#!/bin/bash

scriptdir="$(dirname $0)"
source "$scriptdir"/common.sh

set -e -x
dd if=/dev/zero bs=100M count=100 | $awscmd s3 cp $* - s3://testnv/bigfile
