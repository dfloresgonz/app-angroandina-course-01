const { GCP_PUBSUB_URL } = process.env;

export const handler = async (event) => {
  const message = Buffer.from(JSON.stringify(event)).toString('base64');

  const response = await fetch(GCP_PUBSUB_URL, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify({ message: { data: message } })
  });

  if (!response.ok) {
    throw new Error(`GCP Cloud Function responded ${response.status}`);
  }
};
