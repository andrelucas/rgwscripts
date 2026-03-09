#!/bin/bash

s3_test_env_init() {
	local default_key="$1"

	: "${AWS_ACCESS_KEY_ID:=0555b35654ad1656d804}"
	: "${AWS_SECRET_ACCESS_KEY:=h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q==}"
	: "${S3_BUCKET:=testnv}"
	: "${S3_REGION:=us-east-1}"
	: "${S3_KEY:=${default_key}}"
	: "${S3_SIZE_BYTES:=${SIZE_BYTES:-100000}}"
	: "${S3_CHUNK_SIZE:=${CHUNK_SIZE:-65536}}"
	: "${S3_VERBOSE:=${VERBOSE:-1}}"
	: "${S3_ENDPOINT:=http://$(hostname -f):8000}"

	export AWS_ACCESS_KEY_ID
	export AWS_SECRET_ACCESS_KEY
	export S3_SIZE_BYTES
	export S3_CHUNK_SIZE
	export S3_VERBOSE
}

s3_test_verbose_arg() {
	case "${S3_VERBOSE,,}" in
		1|true|yes|on|y)
			echo "-v"
			;;
		0|false|no|off|n)
			echo ""
			;;
		*)
			echo "-v"
			;;
	esac
}

s3_test_preflight_bucket() {
	local bucket_url http_code

	bucket_url=$(python3 - "$S3_ENDPOINT" "$S3_BUCKET" <<'PY'
import sys
import urllib.parse

endpoint = urllib.parse.urlparse(sys.argv[1])
bucket = sys.argv[2]
port = f":{endpoint.port}" if endpoint.port else ""
base_path = endpoint.path.rstrip("/")
print(f"{endpoint.scheme}://{endpoint.hostname}{port}{base_path}/{bucket}")
PY
)

	if ! http_code=$(curl -sS -o /dev/null -w "%{http_code}" "$bucket_url"); then
		echo "Preflight failed: unable to reach $bucket_url" >&2
		return 2
	fi

	case "$http_code" in
		200|301|302|307|403)
			;;
		404)
			echo "Preflight failed: bucket '$S3_BUCKET' not found at $bucket_url" >&2
			return 3
			;;
		*)
			echo "Preflight failed: unexpected HTTP $http_code from $bucket_url" >&2
			return 4
			;;
	esac
}
