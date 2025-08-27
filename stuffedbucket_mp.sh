#!/bin/bash

scriptdir="$(dirname "$0")"
source "$scriptdir"/common.sh

set -e

abortonly=0
count=100
include_longkey=0
maxjobs=200
versioning=0

bucket="test"
bucketurl="s3://$bucket"

function usage() {
    echo "Usage: $0 [-c count] [-j maxjobs] [-b bucket] [-V]" >&2
    exit 1
}

# Parse command-line options
while getopts "Ab:c:j:lV" opt; do
    case $opt in
    A) abortonly=1 ;;
    c) count=$OPTARG ;;
    j) maxjobs=$OPTARG ;;
    l) include_longkey=1;;
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

dd if=/dev/urandom bs=32 count=1 >smallfile

ids_and_keys="$(aws s3api list-multipart-uploads --bucket "$bucket" |jq -r '.Uploads[]? | .UploadId + " " + .Key')"
ids=""
keys=""
while read -r id key; do
    ids+=" $id"
    keys+=" $key"
done <<<"$ids_and_keys"

function abort() {
    id="$1"
    key="$2"
    echo "Aborting $key id $id" >>/tmp/out
    aws s3api abort-multipart-upload --bucket "$bucket" --key "$key" --upload-id "$id"
}
export -f abort

# shellcheck disable=SC2086
parallel --link -j"$maxjobs" -n2 "abort {1} {2}" ::: $ids ::: $keys

if [[ $abortonly -eq 1 ]]; then
    echo "Stopping after aborting uploads"
    exit 0
fi

function longcreate() {
    # generate a prefix longer than a line to test our base64 encoding.
    pfx="$(head -c 99 </dev/zero | tr '\0' 'X')"
    n="$(printf "$pfx.mp%08i\n" "$1")"
    echo "Creating $n" >>/tmp/out
    id="$($awscmd s3api create-multipart-upload --bucket "$bucket" --key "$n" | jq -r .UploadId)"
}
export -f longcreate

if [[ $include_longkey -eq 1 ]]; then
    parallel -j"$maxjobs" -n0 "longcreate {#}" ::: $(seq 1 "$count")
fi

function create() {
    n="$(printf "mp%08i\n" "$1")"
    echo "Creating $n" >>/tmp/out
    id="$($awscmd s3api create-multipart-upload --bucket "$bucket" --key "$n" | jq -r .UploadId)"
    echo "Uploading part 1 for $n id $id" >>/tmp/out
    dd if=/dev/urandom bs=32 count=1 | $awscmd s3api upload-part --bucket "$bucket" --key "$n" --part-number 1 --upload-id "$id" --body smallfile
}
export -f create

parallel -j"$maxjobs" -n0 "create {#}" ::: $(seq 1 "$count")
