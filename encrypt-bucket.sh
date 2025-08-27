#!/bin/bash

scriptdir="$(dirname "$0")"
source "$scriptdir"/common.sh

set -e -x

bucket="$1"
if [ -z "$bucket" ]; then
  echo "Usage: $0 <bucket-name>"
  exit 1
fi

./aws.sh s3api put-bucket-encryption --bucket "$bucket" --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
./aws.sh s3api get-bucket-encryption --bucket "$bucket"
