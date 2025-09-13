import os, json, boto3

ddb = boto3.client("dynamodb")
s3  = boto3.client("s3")
sqs = boto3.client("sqs")

TABLE   = os.environ["LOG_TABLE"]
INTAKE  = os.environ["INTAKE_BUCKET"]
ARCHIVE = os.environ["ARCHIVE_BUCKET"]
QUEUE   = os.environ["QUEUE_URL"]
API_KEY = os.environ.get("API_SHARED_KEY")

def ok(data, code=200): return {"statusCode": code, "headers":{"content-type":"application/json"}, "body": json.dumps(data)}
def fail(code, msg):    return {"statusCode": code, "body": msg}

def authed(headers):
    return (API_KEY is None) or (headers.get("x-api-key") == API_KEY)

def list_logs(params):
    if params and "client" in params:
        resp = ddb.query(
            TableName=TABLE, IndexName="client-index",
            KeyConditionExpression="client = :c",
            ExpressionAttributeValues={":c":{"S":params["client"]}},
            ScanIndexForward=False, Limit=200
        )
    elif params and "status" in params:
        resp = ddb.query(
            TableName=TABLE, IndexName="status-index",
            KeyConditionExpression="status = :s",
            ExpressionAttributeValues={":s":{"S":params["status"]}},
            ScanIndexForward=False, Limit=200
        )
    else:
        return []
    def _un(m): return {k: list(v.values())[0] for k,v in m.items()}
    return list(map(_un, resp.get("Items", [])))

def reenqueue(bucket, key):
    sqs.send_message(
        QueueUrl=QUEUE,
        MessageBody=json.dumps({"Records":[{"eventSource":"aws:s3","s3":{"bucket":{"name":bucket},"object":{"key":key}}}]})
    )

def restore_from_archive(client, doc_type, date, filename):
    src = f"clients/{client}/{doc_type}/{date}/{filename}"
    dst = f"uploads/{client}/{filename}"
    s3.copy_object(Bucket=INTAKE, Key=dst, CopySource={"Bucket":ARCHIVE,"Key":src})
    return dst

def main(event, _):
    if not authed(event.get("headers", {})):
        return fail(401, "unauthorized")

    route  = event["requestContext"]["http"]["path"]
    method = event["requestContext"]["http"]["method"]
    params = event.get("queryStringParameters") or {}
    body   = json.loads(event.get("body") or "{}")

    if route == "/logs" and method == "GET":
        return ok(list_logs(params))

    if route == "/retry" and method == "POST":
        reenqueue(body["bucket"], body["key"])
        return ok({"status":"enqueued"})

    if route == "/restore" and method == "POST":
        new_key = restore_from_archive(body["client"], body["doc_type"], body["date"], body["filename"])
        if body.get("retry"): reenqueue(INTAKE, new_key)
        return ok({"restored_key": new_key})

    if route == "/force-route" and method == "POST":
        reenqueue(INTAKE, body["key"])
        return ok({"status":"enqueued"})

    return fail(404, "not found")
