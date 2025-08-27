#!/bin/bash

scriptdir="$(dirname "$0")"
source "$scriptdir"/common.sh

set -e -x

delete_bucket=true

function usage() {
  echo "Usage: $0 [-Dh] <bucket-name>"
  echo "  -D: Do not delete the bucket after the test"
  echo "  -h: Show this help message"
  exit 1
}

while getopts "Dh" opt; do
  case $opt in
    D)
      delete_bucket=false
      ;;
    h)
      usage
      ;;
    *)
      echo "Invalid option: -$OPTARG" >&2
      usage
      ;;
  esac
done

shift $((OPTIND - 1))

bucket="$1"
if [ -z "$bucket" ]; then
  echo "Usage: $0 <bucket-name>"
  exit 1
fi

dd if=/dev/urandom of=test.txt bs=1M count=1

./aws.sh s3api create-bucket --bucket "$bucket"
./aws.sh s3api put-bucket-encryption --bucket "$bucket" --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
./aws.sh s3api put-object --bucket "$bucket" --key "test-object" --body "$scriptdir"/test.txt
./aws.sh s3api get-object --bucket "$bucket" --key "test-object" "test-object.txt"
if [[ $delete_bucket == true ]]; then
  ./aws.sh s3api delete-object --bucket "$bucket" --key "test-object"
  ./aws.sh s3api delete-bucket --bucket "$bucket"
fi
