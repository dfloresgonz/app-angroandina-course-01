const { BigQuery } = require('@google-cloud/bigquery');

const bigquery = new BigQuery({ projectId: process.env.PROJECT_ID });

exports.ingestTelemetry = async (req, res) => {
  const message = req.body?.message;
  if (!message?.data) {
    res.status(400).send('no message data');
    return;
  }

  const raw = JSON.parse(Buffer.from(message.data, 'base64').toString('utf8'));

  const row = {
    sensor_id:       raw.sensor_id,
    timestamp:       new Date(Number(raw.timestamp) || raw.timestamp).toISOString(),
    temperature:     raw.temperature ?? null,
    humidity:        raw.humidity ?? null,
    soil_moisture:   raw.soil_moisture ?? null,
    light_intensity: raw.light_intensity ?? null,
    wind_speed:      raw.wind_speed ?? null,
    battery_level:   raw.battery_level ?? null,
    received_at:     new Date().toISOString()
  };

  await bigquery
    .dataset(process.env.BIGQUERY_DATASET)
    .table(process.env.BIGQUERY_TABLE)
    .insert([row]);

  res.status(204).send();
};
