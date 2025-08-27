#!/bin/bash

function usage() {
	echo "Usage: $0 [private|public-read|public-read-write|authenticated-read] BUCKETNAME" >&2
	exit 1
}

acl="$1"
bucket="$2"
if [[ -z "$acl" || -z "$bucket" ]]; then
	usage
fi

set -e -x
./aws.sh s3api put-bucket-acl --bucket "$bucket" --acl $acl
