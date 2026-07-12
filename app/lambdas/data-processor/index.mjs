import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, ScanCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';

const dynamo = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const lambda = new LambdaClient({});

const { TELEMETRY_TABLE, WS_CONNECTIONS_TABLE, WS_ENDPOINT, GCP_FORWARDER_ARN } = process.env;

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
      Item: { ...record, expiresAt }
    }));

    await lambda.send(new InvokeCommand({
      FunctionName:   GCP_FORWARDER_ARN,
      InvocationType: 'Event',
      Payload:        JSON.stringify(record)
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
