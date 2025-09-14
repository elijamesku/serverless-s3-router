import os, json, boto3

INTAKE = os.environ["INTAKE_BUCKET"]
API_KEY = os.environ.get("API_SHARED_KEY")
s3 = boto3.client("s3")
CORS = {"access-control-allow-origin":"*", "access-control-allow-headers":"x-api-key,content-type"}

def main(event, _):
    # basic header auth
    if API_KEY and (event.get("headers", {}).get("x-api-key") != API_KEY):
        return {"statusCode": 401, "body": "unauthorized"}

    try:
        body = json.loads(event.get("body") or "{}")
        client = body.get("client")
        filename = body.get("filename")
        content_type = body.get("contentType", "application/octet-stream")
        if not client or not filename:
            return {"statusCode": 400, "body": "client and filename required"}

        key = f"uploads/{client}/{filename}"
        url = s3.generate_presigned_url(
            ClientMethod="put_object",
            Params={"Bucket": INTAKE, "Key": key, "ContentType": content_type},
            ExpiresIn=900,
        )
        return {
            "statusCode": 200,
            "headers": {"content-type":"application/json", **CORS},
            "body": json.dumps({"bucket": INTAKE, "key": key, "url": url, "expiresSec": 900})
        }
        
    except Exception as e:
        return {"statusCode": 401, "headers": CORS, "body": "unauthorized"}
