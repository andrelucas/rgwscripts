#!/bin/bash

scriptdir="$(dirname "$0")"
source "$scriptdir"/common.sh

timestamp="$(date -u '+%Y%m%dt%H%M%Sz')"
bucketpre="bucket-${timestamp}-"

bigfile="$scriptdir/bigfile"

# set -x
set -e

function s3cmd () {
	# Command prevents this function from calling itself.
	command s3cmd --region=us-east-1 "$@"
}

function banner () {
	set +x
	echo
	echo "===================================================================="
	echo "$@"
	echo "===================================================================="
	set -x
}



function setup_bigfile() {
	if [[ ! -f "$bigfile" ]]; then
		echo "Creating $bigfile"
		dd if=/dev/urandom of="$bigfile" bs=1M count=1000
		split -b 100M --numeric-suffixes=1 "$bigfile" "$bigfile-chunk"
	fi
}

function regular_bucket () {
	local -
	set -u
	n="$1"
	# Regular bucket.
	bucket="${bucketpre}${n}"
	banner "Regular bucket $bucket"

	set -e -x
	"$scriptdir"/racmd.sh bucket rm --bucket "$bucket"
	s3cmd mb s3://"$bucket"

	s3cmd ls s3://"$bucket"
	s3cmd put /etc/hosts s3://"$bucket"/hosts
	s3cmd get --force s3://"$bucket"/hosts

	## Tagging with s3cmd.
	s3cmd settagging s3://"$bucket"/hosts "a=b&c=d"
	s3cmd gettagging s3://"$bucket"/hosts
	s3cmd deltagging s3://"$bucket"/hosts
	s3cmd gettagging s3://"$bucket"/hosts
	## copy is a gen2 strangeness. We need rgw_handoff_authz_reject_filtered_commands=false.
	s3cmd cp s3://"$bucket"/hosts s3://"$bucket"/hosts2
	## get-object-attributes doesn't seem to work here, it gets mapped to a simple get.
	# ./aws.sh s3api get-object-attributes --bucket "$bucket" --key hosts --object-attributes ETag
	
	## Tagging with awscli.
	./aws.sh s3api put-bucket-tagging --bucket "$bucket" --tagging "TagSet=[{Key=a,Value=b},{Key=c,Value=d}]"
	./aws.sh s3api get-bucket-tagging --bucket "$bucket"
	./aws.sh s3api delete-bucket-tagging --bucket "$bucket"
	./aws.sh s3api get-bucket-tagging --bucket "$bucket"
	
	## Bucket policy.
	./aws.sh s3api put-bucket-policy --bucket "$bucket" --policy '{
		"Version": "2012-10-17",
		"Statement": [
			{
				"Sid": "allow-all",
				"Effect": "Allow",
				"Principal": "*",
				"Action": "s3:*",
				"Resource": "arn:aws:s3:::'"$bucket"'/*"
			}
		]
	}'
	./aws.sh s3api get-bucket-policy --bucket "$bucket"
	./aws.sh s3api get-bucket-policy-status --bucket "$bucket"
	./aws.sh s3api delete-bucket-policy --bucket "$bucket"
	./aws.sh s3api get-bucket-policy --bucket "$bucket" || echo "Failure here is good"
	./aws.sh s3api get-bucket-policy-status --bucket "$bucket"
	
	## Lifecycle.
	s3cmd put /etc/hosts s3://"$bucket"/lc
	./aws.sh s3api put-bucket-lifecycle-configuration --bucket "$bucket" --lifecycle-configuration '{
		"Rules": [
			{
				"ID": "rule1",
				"Status": "Enabled",
				"Prefix": "lc",
				"Expiration": { "Days": 1 }
			}
		]
	}'
	./aws.sh s3api get-bucket-lifecycle-configuration --bucket "$bucket"
	./aws.sh s3api delete-bucket-lifecycle --bucket "$bucket"
	./aws.sh s3api get-bucket-lifecycle-configuration --bucket "$bucket" || echo "Failure here is good"
	s3cmd rm s3://"$bucket"/lc
	
	## Encryption.
	./aws.sh s3api put-bucket-encryption --bucket "$bucket" --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
	./aws.sh s3api get-bucket-encryption --bucket "$bucket"
	./aws.sh s3api delete-bucket-encryption --bucket "$bucket"
	
	## Public access.
	./aws.sh s3api put-public-access-block --bucket "$bucket" --public-access-block-configuration '{"BlockPublicAcls": true, "IgnorePublicAcls": true, "BlockPublicPolicy": true, "RestrictPublicBuckets": true}'
	./aws.sh s3api get-public-access-block --bucket "$bucket"
	./aws.sh s3api delete-public-access-block --bucket "$bucket"
	
	## Multipart upload.
	setup_bigfile
	# Simple form. Should just complete.
	./aws.sh s3 cp bigfile "s3://${bucket}/bigfile"
	# More complex form with an abort.
	upload_id="$(./aws.sh s3api create-multipart-upload --bucket "$bucket" --key bigfile2 | jq -r '.UploadId')"
	./aws.sh s3api upload-part --bucket "$bucket" --key bigfile2 --part-number 1 --upload-id "$upload_id" --body bigfile-chunk01
	./aws.sh s3api list-multipart-uploads --bucket "$bucket" | jq '.Uploads[] | .Key + " " + .UploadId'
	./aws.sh s3api list-parts --bucket "$bucket" --key bigfile2 --upload-id "$upload_id" | jq '.Parts | length'
	./aws.sh s3api abort-multipart-upload --bucket "$bucket" --key bigfile2 --upload-id "$upload_id"
	
	## Bucket replication.
	## Can't test put-bucket-replication without a zone setup, and I'm not doing that.
	# ./aws.sh s3api put-bucket-replication --bucket "$bucket" --replication-configuration '{
	# 	"Role": "arn:aws:iam::123456789012:role/replication-role",
	# 	"Rules": [
	# 		{
	# 			"ID": "rule1",
	# 			"Status": "Enabled",
	# 			"Prefix": "",
	# 			"Destination": {
	# 				"Bucket": "destination-bucket",
	# 				"StorageClass": "STANDARD"
	# 			}
	# 		}
	# 	]
	# }'
	./aws.sh s3api get-bucket-replication --bucket "$bucket"
	./aws.sh s3api delete-bucket-replication --bucket "$bucket" || echo "Failure here is good"
	
	## Bucket website.
	./aws.sh s3api put-bucket-website --bucket "$bucket" --website-configuration '{
		"IndexDocument": { "Suffix": "index.html" },
		"ErrorDocument": { "Key": "error.html" }
	}'
	./aws.sh s3api get-bucket-website --bucket "$bucket"
	./aws.sh s3api delete-bucket-website --bucket "$bucket"
	./aws.sh s3api get-bucket-website --bucket "$bucket" || echo "Failure here is good"
	
	## CORS.
	./aws.sh s3api put-bucket-cors --bucket "$bucket" --cors-configuration '{
		"CORSRules": [
			{
				"AllowedHeaders": ["*"],
				"AllowedMethods": ["GET"],
				"AllowedOrigins": ["*"],
				"ExposeHeaders": ["ETag"]
			}
		]
	}'
	./aws.sh s3api get-bucket-cors --bucket "$bucket"
	./aws.sh s3api delete-bucket-cors --bucket "$bucket"
	./aws.sh s3api get-bucket-cors --bucket "$bucket" || echo "Failure here is good"
	
	## Bucket logging (minimal).
	./aws.sh s3api get-bucket-logging --bucket "$bucket"

	## Request payment.
	./aws.sh s3api put-bucket-request-payment --bucket "$bucket" --request-payment-configuration '{"Payer": "Requester"}'
	./aws.sh s3api get-bucket-request-payment --bucket "$bucket"	
	
	s3cmd rm s3://"$bucket"/bigfile
	s3cmd rm s3://"$bucket"/hosts
	s3cmd rm s3://"$bucket"/hosts2
	s3cmd rb s3://"$bucket"
}

function versioned_bucket() {
	local -
	set -u
	n="$1"
	# Versioned bucket.
	bucket="${bucketpre}${n}v"
	banner "Versioned bucket $bucket"

	set -e -x
	"$scriptdir"/racmd.sh bucket rm --bucket "$bucket"
	s3cmd mb s3://"$bucket"
	s3cmd setversioning s3://"$bucket" enable
	s3cmd ls s3://"$bucket"
	s3cmd put /etc/hosts s3://"$bucket"/hosts
	s3cmd get --force s3://"$bucket"/hosts
	s3cmd put /etc/hosts s3://"$bucket"/hosts

	firstversion="$(./aws.sh s3api list-object-versions --bucket "$bucket" --prefix hosts | jq -r '.Versions[0].VersionId')"
	## copy is a gen2 strangeness. We need rgw_handoff_authz_reject_filtered_commands=false.
	./aws.sh s3api copy-object --copy-source "$bucket/hosts?versionId=${firstversion}" --bucket "$bucket" --key hosts2

	## Versioned tagging.
	s3cmd settagging s3://"$bucket"/hosts "a=b&c=d"
	s3cmd gettagging s3://"$bucket"/hosts
	s3cmd put /etc/hosts s3://"$bucket"/hosts
	secondversion="$(./aws.sh s3api list-object-versions --bucket "$bucket" --prefix hosts | jq -r '.Versions[0].VersionId')"
	s3cmd settagging s3://"$bucket"/hosts "e=f&g=h" # Tag secondversion differently.
	./aws.sh s3api put-object-tagging --bucket "$bucket" --key hosts  --tagging "TagSet=[{Key=i,Value=j},{Key=l,Value=m}]" --version-id "$firstversion"	# Tag firstversion differently.
	# s3cmd gettagging s3://"$bucket"/hosts # Firstversion
	./aws.sh s3api get-object-tagging --bucket "$bucket" --key hosts --version-id "$firstversion" # Firstversion
	./aws.sh s3api get-object-tagging --bucket "$bucket" --key hosts --version-id "$secondversion" # Secondversion
	s3cmd deltagging s3://"$bucket"/hosts
	s3cmd gettagging s3://"$bucket"/hosts
	## get-object-attributes doesn't seem to work here, it gets mapped to a simple get.
	# ./aws.sh s3api get-object-attributes --bucket "$bucket" --key hosts --object-attributes ETag --version-id "$firstversion"
	# ./aws.sh s3api get-object-attributes --bucket "$bucket" --key hosts --object-attributes ETag --version-id "$secondversion"
	./aws.sh s3api get-object-tagging --bucket "$bucket" --key hosts --version-id "$firstversion" # Firstversion
	./aws.sh s3api delete-objects --bucket "${bucket}" --delete \
		"$(./aws.sh s3api list-object-versions --bucket "${bucket}" --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
	num_delete="$(aws s3api list-object-versions --bucket "$bucket" | jq ".DeleteMarkers | length")"
	if [[ $num_delete -ge 1 ]]; then
		./aws.sh s3api delete-objects --bucket "${bucket}" --delete \
			"$(./aws.sh s3api list-object-versions --bucket "${bucket}" --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')"
	fi
	s3cmd rb s3://"$bucket"
}

function object_lock_bucket() {
	local -
	set -u
	n="$1"
	# Object lock bucket.
	bucket="${bucketpre}${n}l"
	banner "Object lock bucket $bucket"

	set -e -x
	"$scriptdir"/racmd.sh bucket rm --bucket "$bucket"
	./aws.sh s3api create-bucket --bucket "$bucket" --object-lock-enabled-for-bucket
	s3cmd setversioning s3://"$bucket" enable
	s3cmd ls s3://"$bucket"
	# Set 'governance' mode, which can be overridden by empowered users. We'll
	# use this later on when changing retention values.
	./aws.sh s3api put-object-lock-configuration --bucket "$bucket" \
		--object-lock-configuration='{ "ObjectLockEnabled": "Enabled", "Rule": { "DefaultRetention": { "Mode": "GOVERNANCE", "Days": 5 }}}'
	./aws.sh s3api get-object-lock-configuration --bucket "$bucket"
	
	s3cmd put /etc/hosts s3://"$bucket"/hosts
	s3cmd get --force s3://"$bucket"/hosts
	s3cmd settagging s3://"$bucket"/hosts "a=b&c=d"
	s3cmd gettagging s3://"$bucket"/hosts
	s3cmd deltagging s3://"$bucket"/hosts
	s3cmd gettagging s3://"$bucket"/hosts
	
	s3cmd put /etc/hosts s3://"$bucket"/legalhold
	lhversion="$(./aws.sh s3api list-object-versions --bucket "$bucket" --prefix legalhold | jq -r '.Versions[0].VersionId')"
	./aws.sh s3api put-object-legal-hold --bucket "$bucket" --key legalhold --version-id="$lhversion" --legal-hold '{ "Status": "ON" }'
	./aws.sh s3api get-object-legal-hold --bucket "$bucket" --key legalhold --version-id="$lhversion"
	./aws.sh s3api delete-object --bucket "$bucket" --key legalhold --version-id="$lhversion"
	s3cmd rm s3://"$bucket"/legalhold && banner "That delete should not have worked"
	s3cmd ls s3://"$bucket"/

	s3cmd put /etc/hosts s3://"$bucket"/retention
	# ISO date for tomorrow, same time as now.
	rud="$(date +"%Y-%m-%dT%H:%M:%S" --utc --date tomorrow)Z"
	./aws.sh s3api put-object-retention --bucket "$bucket" --key retention --retention '{"Mode": "COMPLIANCE", "RetainUntilDate": "'"$rud"'"}'
	./aws.sh s3api put-object-retention --bucket "$bucket" --key retention --retention '{"Mode": "COMPLIANCE", "RetainUntilDate": "'"$rud"'"}' --bypass-governance-retention
	./aws.sh s3api get-object-retention --bucket "$bucket" --key retention
	s3cmd rm s3://"$bucket"/retention && banner "That delete should not have worked"
	
	s3cmd rm s3://"$bucket"/hosts && banner "That delete should not have worked"
	s3cmd rb s3://"$bucket"
	# Use the admin REST API to force the issue, as rb won't delete a
	# non-empty bucket.
	./adminrb.sh delete --bucket "$bucket" --uid testid --purge
}

function list_buckets() {
	banner "List buckets"
	set -e -x
	./aws.sh s3api list-buckets
}

function usage() {
	echo "Usage: $0 [-h] [-r] [-v] [-o] [NUMBER ...]"
	echo "Options:"
	echo "  -h  Show help message"
	echo "  -r  Run regular bucket setup"
	echo "  -v  Run versioned bucket setup"
	echo "  -o  Run object lock bucket setup"
}

opt_regular=0
opt_versioned=0
opt_object_lock=0
list_buckets=0

# Parse command line options
while getopts ":hlorv" opt; do
	case $opt in
		h)
			usage
			exit 1
			;;
		l)
			list_buckets=1
			;;
		o)
			opt_object_lock=1
			;;
		r)
			opt_regular=1
			;;
		v)
			opt_versioned=1
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			usage
			exit 1
			;;
	esac
done

# Shift the command line arguments so that $1 refers to the first non-option argument
shift $((OPTIND - 1))

if [[ $list_buckets -eq 1 ]]; then
	list_buckets
	exit 0
fi

if [[ $opt_regular -eq 0 && $opt_versioned -eq 0 && $opt_object_lock -eq 0 ]]; then
	# If no options are provided, run all bucket setups.
	opt_regular=1
	opt_versioned=1
	opt_object_lock=1
fi

if [[ -z "$*" ]]; then
	numbers="$(seq 1 4)"
else
	numbers="$*"
fi

echo "Running bucket setup for numbers: $(echo $numbers | paste -sd ' ')"

for n in $numbers; do
	if [[ $opt_regular -eq 1 ]]; then
		regular_bucket "$n" || echo "** Regular $bucket failed"
		echo
	fi

	if [[ $opt_versioned -eq 1 ]]; then
		versioned_bucket "$n" || echo "** Versioned $bucket failed"
		echo
	fi

	if [[ $opt_object_lock -eq 1 ]]; then
		object_lock_bucket "$n" || echo "** Object lock $bucket failed"
		echo
	fi
done

exit 0
