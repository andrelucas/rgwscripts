#!/usr/bin/env bash

awscmd=aws
bucket=andre-testv
files=100
versions=10

function info() {
    echo -e "\033[1;32mINFO: $*\033[0m"
}
function warn() {
    echo -e "\033[1;33mWARN: $*\033[0m"
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

if [[ "$1" = -d ]]; then
    delete=1
    shift
fi

if [[ $delete -eq 1 ]]; then
    info "Delete bucket $bucket if it exists"
    if ./bucket-delete-boto.py --bucket $bucket; then
        info "Waiting..."
        sleep 10
    else
        warn "Failed to delete bucket $bucket"
    fi
fi

set -e
info "Create versioned bucket $bucket"
$awscmd s3api create-bucket --bucket "$bucket"
$awscmd s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled

smallfile="$tmpdir/smallfile"
dd if=/dev/random of="$smallfile" bs=1K count=1

for f in $(seq -w $files); do
    file="file-$f"
    info "Adding $versions versions of $file"
    # for _ in $(seq -w$versions); do
    #     $awscmd s3 cp "$smallfile" "s3://$bucket/$file"
    # done
    seq -w 1 $versions | parallel $awscmd s3 cp "$smallfile" "s3://$bucket/$file" \#
done

primes="002 003 005 007 011 013 017 019 023 029 031 037 041 043 047 053 059 061 067 071 073 079 083 089 097"

for f in $primes; do
    info "Deleting file-$f"
    aws --no-cli-pager s3api delete-object --bucket $bucket --key file-$f
done
