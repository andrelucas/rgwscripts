#!/bin/bash

bucket=testsse
key=hosts
file=/etc/hosts

set -e -x
s3cmd mb s3://testsse || true
s3cmd put "$file" "s3://${bucket}/${key}" --add-header=x-amz-server-side-encryption-customer-algorithm:AES256 --add-header=x-amz-server-side-encryption-customer-key:pO3upElrwuEXSoFwCfnZPdSsmt/xWeFa0N9KgDijwVs= --add-header=x-amz-server-side-encryption-customer-key-MD5:DWygnHRtgiJ77HCm+1rvHw==
