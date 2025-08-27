#!/bin/bash

scriptdir="$(dirname "$0")"
source "$scriptdir"/common.sh

bucket="test"

function usage() {
	echo "Usage: $0 [-eH] bucket"
	echo "  -e: don't add any objects to the bucket"
	echo "  -H: only add versions of /etc/hosts to the bucket"
	exit 1
}

empty_bucket=false
just_hosts=false

while getopts "eH" o; do
    case "${o}" in
		e)
			empty_bucket=true
			;;
		H)
			just_hosts=true
			;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

"$scriptdir"/bucket-delete.sh "$bucket" || true

set -e -x
$awscmd s3api create-bucket --bucket "$bucket"
$awscmd s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled
$awscmd s3api get-bucket-versioning --bucket "$bucket"

if $empty_bucket; then
	echo "Bucket created, not adding any objects"
	exit 0
fi

for _n in $(seq 10); do
    $awscmd s3 cp /etc/hosts s3://"$bucket"/hosts
done

if $just_hosts; then
	echo "Just added hosts"
	exit 0
fi

$awscmd s3 cp /etc/nsswitch.conf s3://"$bucket"/hosts/switch
$awscmd s3 rm s3://"$bucket"/hosts
$awscmd s3api list-object-versions --bucket "$bucket"

# Create a prefix clash.
dd if=/dev/urandom of=rand bs=1K count=1
$awscmd s3 cp rand s3://"$bucket"/rand
$awscmd s3 cp rand s3://"$bucket"/rand/subrand
$awscmd s3 cp rand s3://"$bucket"/rand_subrand
for n in $(seq 0 4); do
	$awscmd s3 cp rand s3://"$bucket"/rand/subrand/$n
done

for n in $(seq 0 10); do
	$awscmd s3 cp rand s3://"$bucket"/bigfile/$n
done


