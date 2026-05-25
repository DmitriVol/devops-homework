import json
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Cached globally — reused across warm Lambda invocations.
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def lambda_handler(event, context):
    logger.info("[%s] Received event: %s", context.aws_request_id, json.dumps(event))

    # Parse body
    try:
        body = json.loads(event.get("body") or "{}")
    except (json.JSONDecodeError, TypeError):
        return _response(400, {"error": "Request body must be valid JSON."})

    # Validate required field — key must exist and must not be None or empty string
    if "payload" not in body:
        return _response(400, {"error": "Missing required field: payload."})
    payload = body["payload"]
    if payload is None or payload == "":
        return _response(400, {"error": "Field 'payload' must not be empty."})

    # Save to DynamoDB
    item = {
        "id": str(uuid.uuid4()),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "payload": payload,
        "source_ip": (event.get("requestContext") or {})
                     .get("http", {})
                     .get("sourceIp", "unknown"),
    }

    try:
        table.put_item(Item=item)
    except ClientError as e:
        logger.error("[%s] DynamoDB error: %s", context.aws_request_id,
                     e.response["Error"]["Message"])
        return _response(500, {"error": "Failed to save request."})

    logger.info("[%s] Saved item id=%s", context.aws_request_id, item["id"])
    return _response(200, {"status": "healthy", "message": "Request processed and saved."})


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
