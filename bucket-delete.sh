#!/bin/bash

set -e -x

scriptdir="$(dirname $0)"
source "$scriptdir"/common.sh
bucket="${1:-unspecifiedbucket}"

$racmd bucket rm --bucket "$bucket" --purge-objects
