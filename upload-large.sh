#!/bin/bash

scriptdir="$(dirname "$0")"
source "$scriptdir"/common.sh

set -e -x
dd if=/dev/urandom bs=1M count=1000 | $awscmd s3 cp - s3://test/bigfile
