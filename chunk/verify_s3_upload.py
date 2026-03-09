#!/usr/bin/env python3

import hashlib
import pathlib
import sys

import boto3
from botocore.config import Config


def main() -> None:
    if len(sys.argv) not in (6, 7):
        raise SystemExit(
            "Usage: verify_s3_upload.py <endpoint> <region> <bucket> <key> <expected_size> [local_file_path]"
        )

    endpoint, region, bucket, key, expected_size, local_file_path = (
        sys.argv[1],
        sys.argv[2],
        sys.argv[3],
        sys.argv[4],
        int(sys.argv[5]),
        sys.argv[6] if len(sys.argv) == 7 else "upload.bin",
    )

    s3 = boto3.client(
        "s3",
        endpoint_url=endpoint,
        region_name=region,
        config=Config(s3={"addressing_style": "virtual"}),
    )

    head = s3.head_object(Bucket=bucket, Key=key)
    if int(head.get("ContentLength", -1)) != expected_size:
        raise SystemExit(
            f"Verification failed: expected size {expected_size}, got {head.get('ContentLength')} for {bucket}/{key}"
        )

    remote_data = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    local_data = pathlib.Path(local_file_path).read_bytes()

    remote_sha = hashlib.sha256(remote_data).hexdigest()
    local_sha = hashlib.sha256(local_data).hexdigest()

    if remote_sha != local_sha:
        raise SystemExit(
            f"Verification failed: SHA256 mismatch local={local_sha} remote={remote_sha} for {bucket}/{key}"
        )

    print(f"Verified upload for s3://{bucket}/{key} size={expected_size} sha256={local_sha}")


if __name__ == "__main__":
    main()
