import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, ScanCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';
import { EventBridgeClient, PutEventsCommand } from '@aws-sdk/client-eventbridge';
import { randomUUID } from 'node:crypto';

const dynamo   = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const eventbus = new EventBridgeClient({});

const { TELEMETRY_TABLE, WS_CONNECTIONS_TABLE, WS_ENDPOINT, EVENT_BUS_NAME } = process.env;

export const handler = async (event) => {
  const records = event.Records.map(r =>
    JSON.parse(Buffer.from(r.kinesis.data, 'base64').toString('utf8'))
  );

  const apigw = new ApiGatewayManagementApiClient({ endpoint: WS_ENDPOINT });

  const { Items: connections } = await dynamo.send(
    new ScanCommand({ TableName: WS_CONNECTIONS_TABLE })
  );

  await Promise.all(records.map(async (record) => {
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
