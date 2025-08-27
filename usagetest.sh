#!/bin/bash
scriptdir="$(dirname "$0")"

# shellcheck source=common.sh
source "$scriptdir"/common.sh

./racmd.sh usage show --show-log-entries=true
s3cmd mb s3://test
s3cmd put /etc/hosts s3://test/hosts
s3cmd get s3://test/hosts
./racmd.sh usage show --show-log-entries=true

