#!/bin/bash

scriptdir="$(dirname "$0")"
source "$scriptdir"/common.sh

fast=0
if [[ $1 -eq -f ]]; then
	fast=1
	shift
fi

bucket=testnv

"$scriptdir"/bucket-delete.sh "$bucket" || true

set -e -x

$awscmd s3api create-bucket --bucket "$bucket"
$awscmd s3api get-bucket-versioning --bucket "$bucket"
$awscmd s3 cp /etc/hosts s3://"$bucket"/hosts
$awscmd s3 cp /etc/hosts s3://"$bucket"/hosts
$awscmd s3 rm s3://"$bucket"/hosts
$awscmd s3api list-object-versions --bucket "$bucket"

# Create a prefix clash.
dd if=/dev/urandom of=rand bs=1K count=1
$awscmd s3 cp rand s3://"$bucket"/rand
$awscmd s3 cp rand s3://"$bucket"/rand/subrand
$awscmd s3 cp rand s3://"$bucket"/rand_subrand

if [[ $fast -eq 1 ]]; then
	exit 0
fi

for n in $(seq 0 4); do
	$awscmd s3 cp rand s3://"$bucket"/rand/subrand/$n
done 

for n in $(seq 0 10); do
	$awscmd s3 cp rand s3://"$bucket"/bigfile/$n
done


