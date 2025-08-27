#!/bin/bash

scriptdir="$(dirname $0)"
source "$scriptdir"/common.sh

set -e -x

# Make it less than 100MiB so we don't go into multipart upload.
dd if=/dev/urandom bs=1M count=75 | $awscmd s3 cp - s3://testnv/mediumfile
