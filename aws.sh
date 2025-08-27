#!/bin/bash

set -e -x
#aws --endpoint-url=http://127.0.0.1:8000 $*
aws --endpoint-url=http://ludwig-ub01.home.ae-35.com:8000 "$@"
