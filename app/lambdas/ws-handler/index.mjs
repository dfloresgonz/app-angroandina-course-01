import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import AWSXRay from 'aws-xray-sdk-core';

const dynamo = DynamoDBDocumentClient.from(AWSXRay.captureAWSv3Client(new DynamoDBClient({})));

const { WS_CONNECTIONS_TABLE } = process.env;

export const handler = async (event) => {
  const { connectionId, eventType } = event.requestContext;

  if (eventType === 'CONNECT') {
    await dynamo.send(new PutCommand({
      TableName: WS_CONNECTIONS_TABLE,
      Item: { connectionId }
    }));
  } else if (eventType === 'DISCONNECT') {
    await dynamo.send(new DeleteCommand({
      TableName: WS_CONNECTIONS_TABLE,
      Key: { connectionId }
    }));
  }

  return { statusCode: 200 };
};
