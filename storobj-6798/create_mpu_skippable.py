#!/usr/bin/env python3
"""Create a bucket designed to trigger complete object skipping in store-query.
Mix of objects with many MPUs (padding) and objects with few MPUs (targets)."""

import time
import threading
import botocore.session
from botocore.config import Config

ENDPOINT = "http://127.0.0.1:8000/"
ACCESS_KEY = "0555b35654ad1656d804"
SECRET_KEY = "h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q=="
REGION = "us-east-1"
BUCKET = "ty-mpu-skip-test"
THREADS = 20
print_lock = threading.Lock()

# 600 "padding" objects with 1000 MPUs each = 600K MPUs
# 200 "target" objects with 50 MPUs each = 10K MPUs
# Total = 610K. Target objects have few enough MPUs (50/3 ≈ 17 per cluster)
# to potentially fall entirely within a single gap (~3000 entries)
PADDING_OBJECTS = 600
PADDING_MPUS = 1000
TARGET_OBJECTS = 200
TARGET_MPUS = 50


def make_client():
    session = botocore.session.get_session()
    return session.create_client(
        "s3",
        endpoint_url=ENDPOINT,
        aws_access_key_id=ACCESS_KEY,
        aws_secret_access_key=SECRET_KEY,
        region_name=REGION,
        config=Config(s3={"addressing_style": "path"}, max_pool_connections=50),
    )


def log(msg):
    with print_lock:
        print(msg, flush=True)


def create_mpus(bucket, prefix, obj_start, obj_end, mpus_per_obj):
    client = make_client()
    t0 = time.time()
    count = 0
    for obj_idx in range(obj_start, obj_end):
        key = f"{prefix}-{obj_idx:04d}"
        for _ in range(mpus_per_obj):
            client.create_multipart_upload(Bucket=bucket, Key=key)
            count += 1
            if count % 1000 == 0:
                elapsed = time.time() - t0
                rate = count / elapsed
                log(f"  {prefix} {obj_start}-{obj_end}: {count} MPUs ({rate:.0f}/s)")
    elapsed = time.time() - t0
    log(f"  {prefix} {obj_start}-{obj_end}: done, {count} MPUs in {elapsed:.1f}s")


def main():
    client = make_client()

    try:
        client.head_bucket(Bucket=BUCKET)
        log(f"Bucket {BUCKET} already exists")
    except Exception:
        log(f"Creating bucket {BUCKET}...")
        client.create_bucket(Bucket=BUCKET)

    total = PADDING_OBJECTS * PADDING_MPUS + TARGET_OBJECTS * TARGET_MPUS
    log(f"Creating {PADDING_OBJECTS} padding objects × {PADDING_MPUS} MPUs = {PADDING_OBJECTS * PADDING_MPUS}")
    log(f"Creating {TARGET_OBJECTS} target objects × {TARGET_MPUS} MPUs = {TARGET_OBJECTS * TARGET_MPUS}")
    log(f"Total: {total} MPUs")

    threads = []

    # Padding objects across THREADS
    per_thread = PADDING_OBJECTS // THREADS
    for t in range(THREADS):
        start = t * per_thread
        end = start + per_thread if t < THREADS - 1 else PADDING_OBJECTS
        th = threading.Thread(target=create_mpus, args=(BUCKET, "padding", start, end, PADDING_MPUS))
        th.start()
        threads.append(th)

    # Target objects across 4 threads
    for t in range(4):
        start = t * 50
        end = start + 50 if t < 3 else TARGET_OBJECTS
        th = threading.Thread(target=create_mpus, args=(BUCKET, "target", start, end, TARGET_MPUS))
        th.start()
        threads.append(th)

    for th in threads:
        th.join()

    log(f"Done! {BUCKET}: {total} total MPUs")


if __name__ == "__main__":
    main()
