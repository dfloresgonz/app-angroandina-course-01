import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import { createSign } from 'node:crypto';

const sm = new SecretsManagerClient({});
const { GCP_SA_SECRET_ARN, GCP_PROJECT_ID, GCP_PUBSUB_TOPIC } = process.env;

const PUBSUB_ENDPOINT =
  `https://pubsub.googleapis.com/v1/projects/${GCP_PROJECT_ID}/topics/${GCP_PUBSUB_TOPIC}:publish`;

// Cached in module scope — reused across warm invocations
let cachedToken = null;
let tokenExpiry  = 0;

async function getSaKey() {
  const res = await sm.send(new GetSecretValueCommand({ SecretId: GCP_SA_SECRET_ARN }));
  return JSON.parse(res.SecretString);
}

async function getAccessToken() {
  if (cachedToken && Date.now() < tokenExpiry) return cachedToken;

  const sa  = await getSaKey();
  const now = Math.floor(Date.now() / 1000);

  const header  = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({
    iss:   sa.client_email,
    scope: 'https://www.googleapis.com/auth/pubsub',
    aud:   'https://oauth2.googleapis.com/token',
    iat:   now,
    exp:   now + 3600
  })).toString('base64url');

  const sign = createSign('RSA-SHA256');
  sign.update(`${header}.${payload}`);
  const signature = sign.sign(sa.private_key, 'base64url');

  const jwt = `${header}.${payload}.${signature}`;

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion:  jwt
    })
  });

  const tokenData = await tokenRes.json();
  if (!tokenRes.ok) throw new Error(`OAuth2 error: ${JSON.stringify(tokenData)}`);

  cachedToken = tokenData.access_token;
  tokenExpiry = Date.now() + (tokenData.expires_in - 60) * 1000;
  return cachedToken;
}

export const handler = async (event) => {
  const token = await getAccessToken();
  const failures = [];

  for (const record of event.Records) {
    try {
      // SQS wraps the EventBridge envelope in record.body
      const ebEvent = JSON.parse(record.body);
      const data = Buffer.from(JSON.stringify(ebEvent.detail)).toString('base64');

      const res = await fetch(PUBSUB_ENDPOINT, {
        method:  'POST',
        headers: {
          'Content-Type':  'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({ messages: [{ data }] })
      });

      if (!res.ok) {
        const body = await res.text();
        throw new Error(`Pub/Sub publish failed ${res.status}: ${body}`);
      }
    } catch (err) {
      console.error(`Failed record ${record.messageId}:`, err);
      failures.push({ itemIdentifier: record.messageId });
    }
  }

  // ReportBatchItemFailures — solo los fallidos vuelven a la queue / DLQ
  return { batchItemFailures: failures };
};
