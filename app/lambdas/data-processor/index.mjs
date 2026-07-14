import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, ScanCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';
import { EventBridgeClient, PutEventsCommand } from '@aws-sdk/client-eventbridge';
import { AppConfigDataClient, StartConfigurationSessionCommand, GetLatestConfigurationCommand } from '@aws-sdk/client-appconfigdata';
import { randomUUID } from 'node:crypto';
import AWSXRay from 'aws-xray-sdk-core';

const dynamo      = DynamoDBDocumentClient.from(AWSXRay.captureAWSv3Client(new DynamoDBClient({})));
const eventbus    = AWSXRay.captureAWSv3Client(new EventBridgeClient({}));
const appcfgData  = AWSXRay.captureAWSv3Client(new AppConfigDataClient({}));

const { TELEMETRY_TABLE, WS_CONNECTIONS_TABLE, WS_ENDPOINT, EVENT_BUS_NAME,
        APPCONFIG_APP_ID, APPCONFIG_ENV_ID, APPCONFIG_PROFILE_ID } = process.env;

// Cache del flag en scope del módulo — se refresca cada 30s
let flagCache       = { disabled_sensors: [] };
let flagCacheExpiry = 0;
let sessionToken    = null;

async function getDisabledSensors() {
  const now = Date.now();
  if (now < flagCacheExpiry) return flagCache.disabled_sensors;

  if (!sessionToken) {
    const session = await appcfgData.send(new StartConfigurationSessionCommand({
      ApplicationIdentifier:          APPCONFIG_APP_ID,
      EnvironmentIdentifier:          APPCONFIG_ENV_ID,
      ConfigurationProfileIdentifier: APPCONFIG_PROFILE_ID,
      RequiredMinimumPollIntervalInSeconds: 30,
    }));
    sessionToken = session.InitialConfigurationToken;
  }

  const res = await appcfgData.send(new GetLatestConfigurationCommand({
    ConfigurationToken: sessionToken,
  }));

  // NextPollConfigurationToken debe usarse en la próxima llamada
  sessionToken = res.NextPollConfigurationToken;

  // Si ContentType está presente, hubo cambio — actualizar cache
  if (res.ContentType) {
    const text = new TextDecoder().decode(res.Configuration);
    flagCache = JSON.parse(text);
  }

  flagCacheExpiry = now + 30_000;
  return flagCache.disabled_sensors;
}

export const handler = async (event) => {
  const records = event.Records.map(r =>
    JSON.parse(Buffer.from(r.kinesis.data, 'base64').toString('utf8'))
  );

  const apigw = new ApiGatewayManagementApiClient({ endpoint: WS_ENDPOINT });

  const [{ Items: connections }, disabledSensors] = await Promise.all([
    dynamo.send(new ScanCommand({ TableName: WS_CONNECTIONS_TABLE })),
    getDisabledSensors(),
  ]);

  await Promise.all(records.map(async (record) => {
    const isDisabled = disabledSensors.includes(record.sensor_id);

    if (isDisabled) {
      // Avisa al dashboard sin persistir ni reenviar a GCP
      if (connections?.length) {
        await Promise.all(connections.map(async ({ connectionId }) => {
          try {
            await apigw.send(new PostToConnectionCommand({
              ConnectionId: connectionId,
              Data:         JSON.stringify({ sensor_id: record.sensor_id, status: 'disabled' })
            }));
          } catch (err) {
            if (err.$metadata?.httpStatusCode === 410) {
              await dynamo.send(new DeleteCommand({
                TableName: WS_CONNECTIONS_TABLE,
                Key: { connectionId }
              }));
            }
          }
        }));
      }
      return;
    }

    const expiresAt = Math.floor(Date.now() / 1000) + 10800;

    await dynamo.send(new PutCommand({
      TableName: TELEMETRY_TABLE,
      Item: { ...record, id: randomUUID(), expiresAt }
    }));

    await eventbus.send(new PutEventsCommand({
      Entries: [{
        EventBusName: EVENT_BUS_NAME,
        Source:       'angroandina.telemetry',
        DetailType:   'SensorReading',
        Detail:       JSON.stringify(record)
      }]
    }));

    if (!connections?.length) return;

    await Promise.all(connections.map(async ({ connectionId }) => {
      try {
        await apigw.send(new PostToConnectionCommand({
          ConnectionId: connectionId,
          Data:         JSON.stringify(record)
        }));
      } catch (err) {
        if (err.$metadata?.httpStatusCode === 410) {
          await dynamo.send(new DeleteCommand({
            TableName: WS_CONNECTIONS_TABLE,
            Key: { connectionId }
          }));
        }
      }
    }));
  }));
};
