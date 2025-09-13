import os, json, urllib.parse, boto3, datetime
import time

ddb = boto3.client("dynamodb")
LOG_TABLE = os.environ.get("LOG_TABLE")

def put_log(pk, sk, **fields):
    if not LOG_TABLE: return
    item = {"pk":{"S":pk}, "sk":{"S":sk}, "ts":{"S":str(int(time.time()))}}
    
    for k,v in fields.items():
        if v is None: continue
        item[k] = {"S": str(v)}
    ddb.put_item(TableName=LOG_TABLE, Item=item)

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

def route_object(src_bucket: str, key: str) -> None:
    """
    Expected intake key: uploads/<client>/<filename>
    Promotes to:   processed/clients/<client>/<doc_type>/current/<filename>
    Archives old:  archive/  clients/<client>/<doc_type>/<YYYY-MM-DD>/<oldname>
    """
    # Validate + parse
    parts = key.split("/", 2)
    if len(parts) < 3 or parts[0] != "uploads":
        print(f"Skipping non-upload key: {key}")
        return

    client  = parts[1]
    fname   = parts[2]
    doctype = classify_doc_type(fname)

    current_prefix = f"clients/{client}/{doctype}/current/"
    dest_key       = current_prefix + fname
    pk             = f"s3://{src_bucket}/{key}"

    # Log receipt
    try:
        put_log(pk, today(), status="RECEIVED", client=client, doc_type=doctype, src_bucket=src_bucket, src_key=key)
    except Exception as _:
        pass  # logging should never break routing

    try:
        # If a current file exists (any name) archive it first
        prior = find_any(current_prefix)
        if prior:
            prior_key  = prior["Key"]
            # Avoiding archiving the same object if it already has the exact dest key
            if prior_key != dest_key:
                prior_name = prior_key.rsplit("/", 1)[-1]
                archive_key = f"clients/{client}/{doctype}/{today()}/{prior_name}"
                put_log(pk, today(), status="ARCHIVING", client=client, doc_type=doctype, prior=prior_key, archive=archive_key)
                copy_then_delete(PROCESSED, prior_key, ARCHIVE, archive_key)

        # Promote new upload into "current"
        copy_then_delete(src_bucket, key, PROCESSED, dest_key)

        put_log(pk, today(), status="PROCESSED", client=client, doc_type=doctype, dest=f"s3://{PROCESSED}/{dest_key}")
    except Exception as e:
        # Best-effort failure log, then re-raise so SQS/Lambda retry semantics kick in
        try:
            put_log(pk, today(), status="FAILED", client=client, doc_type=doctype, error=str(e))
        except Exception:
            pass
        raise

    

def find_any(prefix: str):
    resp = s3.list_objects_v2(Bucket=PROCESSED, Prefix=prefix, MaxKeys=1)
    if resp.get("KeyCount", 0) > 0:
        return {"Key": resp["Contents"][0]["Key"]}
    return None

def copy_then_delete(src_bucket, src_key, dst_bucket, dst_key):
    s3.copy_object(Bucket=dst_bucket, Key=dst_key, CopySource={"Bucket": src_bucket, "Key": src_key})
    s3.delete_object(Bucket=src_bucket, Key=src_key)
    print(f"MOVED s3://{src_bucket}/{src_key} -> s3://{dst_bucket}/{dst_key}")
