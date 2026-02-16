#!/bin/bash

set -euo pipefail

: "${AWS_ACCESS_KEY_ID:=0555b35654ad1656d804}"
: "${AWS_SECRET_ACCESS_KEY:=h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q==}"
: "${S3_BUCKET:=testnv}"
: "${S3_REGION:=us-east-1}"
: "${S3_KEY:=obj}"
: "${S3_SIZE_BYTES:=100000}"
: "${S3_CHUNK_SIZE:=65536}"
: "${S3_ENDPOINT:=http://$(hostname -f):8000}"

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

BUCKET_URL=$(python3 - "$S3_ENDPOINT" "$S3_BUCKET" <<'PY'
import sys
import urllib.parse

endpoint = urllib.parse.urlparse(sys.argv[1])
bucket = sys.argv[2]
port = f":{endpoint.port}" if endpoint.port else ""
base_path = endpoint.path.rstrip("/")
print(f"{endpoint.scheme}://{endpoint.hostname}{port}{base_path}/{bucket}")
PY
)

if ! HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" "$BUCKET_URL"); then
	echo "Preflight failed: unable to reach $BUCKET_URL" >&2
	exit 2
fi

case "$HTTP_CODE" in
	200|301|302|307|403)
		;;
	404)
		echo "Preflight failed: bucket '$S3_BUCKET' not found at $BUCKET_URL" >&2
		exit 3
		;;
	*)
		echo "Preflight failed: unexpected HTTP $HTTP_CODE from $BUCKET_URL" >&2
		exit 4
		;;
esac

./s3_stream_unsigned_trailer.py \
	--endpoint "$S3_ENDPOINT" \
	-v \
	--chunk-size "$S3_CHUNK_SIZE" \
	"$S3_BUCKET" "$S3_REGION" "$S3_KEY" "$S3_SIZE_BYTES"
