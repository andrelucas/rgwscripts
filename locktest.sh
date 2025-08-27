#!/bin/bash

timestamp="$(date -u '+%Y%m%dt%H%M%Sz')"
bucketpre="locktest-${timestamp}-"
s3endpoint="http://127.0.0.1:8000"

# set -x
set -e

function s3cmd () {
	# Command prevents this function from calling itself.
	command s3cmd --region=us-east-1 "$@"
}

function aws () {
	command aws --endpoint-url="$s3endpoint" "$@"
}

function banner () {
	set +x
	echo
	echo "===================================================================="
	echo "$@"
	echo "===================================================================="
	set -x
}

function object_lock_bucket() {
	local -
	set -u
	n="$1"
	# Object lock bucket.
	bucket="${bucketpre}${n}l"
	banner "Object lock bucket $bucket"

	set -e -x
	#"$scriptdir"/racmd.sh bucket rm --bucket "$bucket"
	aws s3api create-bucket --bucket "$bucket" --object-lock-enabled-for-bucket
	s3cmd setversioning s3://"$bucket" enable
	s3cmd ls s3://"$bucket"
	# Set 'governance' mode, which can be overridden by empowered users. We'll
	# use this later on when changing retention values.
	aws s3api put-object-lock-configuration --bucket "$bucket" \
		--object-lock-configuration='{ "ObjectLockEnabled": "Enabled", "Rule": { "DefaultRetention": { "Mode": "GOVERNANCE", "Days": 5 }}}'
	aws s3api get-object-lock-configuration --bucket "$bucket"
	
	s3cmd put /etc/hosts s3://"$bucket"/legalhold
	lhversion="$(aws s3api list-object-versions --bucket "$bucket" --prefix legalhold | jq -r '.Versions[0].VersionId')"
	aws s3api put-object-legal-hold --bucket "$bucket" --key legalhold --version-id="$lhversion" --legal-hold '{ "Status": "ON" }'
	aws s3api get-object-legal-hold --bucket "$bucket" --key legalhold --version-id="$lhversion"
	aws s3api delete-object --bucket "$bucket" --key legalhold --version-id="$lhversion" || echo "Expected fail"

	## The object has a legal hold. It should not be deletable.
	s3cmd rm s3://"$bucket"/legalhold && banner "That shouldn't have worked!"
	s3cmd ls s3://"${bucket}/legalhold?versionId=$lhversion"
	s3cmd ls s3://"${bucket}/legalhold"
	echo

	s3cmd put /etc/hosts s3://"$bucket"/retention
	retversion="$(aws s3api list-object-versions --bucket "$bucket" --prefix retention | jq -r '.Versions[0].VersionId')"
	# ISO date for tomorrow, same time as now.
	rud="$(date +"%Y-%m-%dT%H:%M:%S" --utc --date tomorrow)Z"
	aws s3api put-object-retention --bucket "$bucket" --key retention --version-id="$retversion" --retention '{"Mode": "COMPLIANCE", "RetainUntilDate": "'"$rud"'"}' || echo "Expected fail"
	aws s3api put-object-retention --bucket "$bucket" --key retention --version-id="$retversion" --retention '{"Mode": "COMPLIANCE", "RetainUntilDate": "'"$rud"'"}' --bypass-governance-retention
	aws s3api get-object-retention --bucket "$bucket" --key retention --version-id="$retversion"
	## The object is set to be retained until tomorrow. It should not be deletable.
	s3cmd rm s3://"$bucket"/retention && banner "That shouldn't have worked either!"
	s3cmd ls s3://"${bucket}/retention?versionId=${retversion}"
	s3cmd ls s3://"$bucket"/retention
	echo
	
	s3cmd rm s3://"$bucket"/hosts # Should fail.
	s3cmd rb s3://"$bucket" || true # Will probably fail.
}


object_lock_bucket 1

exit 0
