#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

: "${S3_SIZE_BYTES:=${SIZE_BYTES:-100000}}"
: "${S3_CHUNK_SIZE:=${CHUNK_SIZE:-65536}}"
: "${S3_VERBOSE:=${VERBOSE:-0}}"

export S3_SIZE_BYTES
export S3_CHUNK_SIZE
export S3_VERBOSE

TEST_SCRIPTS=(
	"test_s3_stream_unsigned_trailer.sh"
	"test_s3_stream_sha256_trailer.sh"
	"test_s3_stream_sha256_payload.sh"
)

for test_script in "${TEST_SCRIPTS[@]}"; do
	echo "==> Running ${test_script} (S3_SIZE_BYTES=${S3_SIZE_BYTES}, S3_CHUNK_SIZE=${S3_CHUNK_SIZE}, S3_VERBOSE=${S3_VERBOSE})"
	bash "${SCRIPT_DIR}/${test_script}"
done

echo "All tests passed"
