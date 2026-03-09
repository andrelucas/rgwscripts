#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/s3_test_env.sh"
s3_test_env_init "obj-sha256-payload-$(date +%s)-$$"
s3_test_enable_object_cleanup
s3_test_preflight_bucket
VERBOSE_ARG=$(s3_test_verbose_arg)

./s3_stream_sha256_payload.py \
	--endpoint "$S3_ENDPOINT" \
	${VERBOSE_ARG:+$VERBOSE_ARG} \
	--chunk-size "$S3_CHUNK_SIZE" \
	"$S3_BUCKET" "$S3_REGION" "$S3_KEY" "$S3_SIZE_BYTES"

python3 "${SCRIPT_DIR}/verify_s3_upload.py" \
	"$S3_ENDPOINT" "$S3_REGION" "$S3_BUCKET" "$S3_KEY" "$S3_SIZE_BYTES"
