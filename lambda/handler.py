import os, json, urllib.parse, boto3, datetime

s3 = boto3.client("s3")
PROCESSED = os.environ["PROCESSED_BUCKET"]
ARCHIVE   = os.environ["ARCHIVE_BUCKET"]

def classify_doc_type(name: str) -> str:
    n = name.lower()
    if "activity" in n: return "daily-activity"
    if "balance"  in n: return "daily-balance"
    return "daily-activity"  # default bucket if unknown

def today():
    return datetime.datetime.utcnow().strftime("%Y-%m-%d")

def main(event, context):
    # SQS batch with embedded S3 events
    for rec in event.get("Records", []):
        body = json.loads(rec["body"])
        for r in body.get("Records", []):
            if r.get("eventSource") != "aws:s3":
                continue
            src_bucket = r["s3"]["bucket"]["name"]
            key = urllib.parse.unquote(r["s3"]["object"]["key"])
            route_object(src_bucket, key)
    return {"ok": True}

def route_object(src_bucket, key):
    # Expect key: uploads/<client>/<filename>
    parts = key.split("/", 2)
    if len(parts) < 3 or parts[0] != "uploads":
        print(f"Skipping non-upload key: {key}")
        return
    client  = parts[1]
    fname   = parts[2]
    doctype = classify_doc_type(fname)

    # Put current file in processed/clients/<client>/<doctype>/current/
    current_prefix = f"clients/{client}/{doctype}/current/"
    dest_key = current_prefix + fname

    # If a current file exists, archive it under date folder
    prior = find_any(current_prefix)
    if prior:
        prior_name = prior["Key"].split("/")[-1]
        archive_key = f"clients/{client}/{doctype}/{today()}/{prior_name}"
        copy_then_delete(PROCESSED, prior["Key"], ARCHIVE, archive_key)

    # Move the new upload into "current"
    copy_then_delete(src_bucket, key, PROCESSED, dest_key)

def find_any(prefix: str):
    resp = s3.list_objects_v2(Bucket=PROCESSED, Prefix=prefix, MaxKeys=1)
    if resp.get("KeyCount", 0) > 0:
        return {"Key": resp["Contents"][0]["Key"]}
    return None

def copy_then_delete(src_bucket, src_key, dst_bucket, dst_key):
    s3.copy_object(Bucket=dst_bucket, Key=dst_key, CopySource={"Bucket": src_bucket, "Key": src_key})
    s3.delete_object(Bucket=src_bucket, Key=src_key)
    print(f"MOVED s3://{src_bucket}/{src_key} -> s3://{dst_bucket}/{dst_key}")
