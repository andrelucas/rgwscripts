#!/bin/bash

scriptdir="$(dirname "$0")"
source "$scriptdir"/common.sh

set -e

count=10000
delete_some=0
maxjobs=200
versioning=0

bucket=test
bucketurl="s3://$bucket"

function usage() {
    echo "Usage: $0 [-c count] [-d] [-j maxjobs] [-b bucket] [-V]" >&2
    exit 1
}

# Parse command-line options
while getopts "c:dj:b:V" opt; do
    case $opt in
    c) count=$OPTARG ;;
    d) delete_some=1 ;;
    j) maxjobs=$OPTARG ;;
    b) bucket=$OPTARG ;;
    V) versioning=1 ;;
    \?)
        echo "Invalid option -$OPTARG" >&2
        usage
        ;;
    esac
done

export bucket bucketurl

# s3cmd rb $bucketurl || true
s3cmd mb $bucketurl
if [[ $versioning -eq 1 ]]; then
    s3cmd setversioning $bucketurl enable
fi

function put() {
    n="$(printf "%08i\n" "$1")"
    echo "Uploading $n" >>/tmp/out
    dd if=/dev/urandom status=none bs=16 count=1 | $awscmd s3 cp - $bucketurl/"$n"
}
export -f put

parallel -j"$maxjobs" -n0 "put {#}" ::: $(seq 1 "$count")

function rmobj() {
    n="$(printf "%08i\n" "$1")"
    echo "Removing $n" >>/tmp/out
    $awscmd s3 rm $bucketurl/"$n"
}
export -f rmobj

if [[ $delete_some -eq 1 ]]; then
    # Delete (mark as deleted when versioning) every third object
    parallel -j"$maxjobs" "rmobj {}" ::: $(seq 1 3 "$count")
fi
