#!/bin/bash

scriptdir="$(dirname "$0")"
source "$scriptdir"/common.sh

tmpdir="$(mktemp -d)"
trap 'test -n "$tmpdir" && rm -rf "$tmpdir"' EXIT

bucket="test"

pfile="$tmpdir/lc.xml"
cat >"$pfile" <<'EOF'
{
        "Rules": [
        {
                    "Filter": {
                            "Prefix": ""
                    },
                    "Status": "Enabled",
                    "Expiration": {
                            "Days": 1
                    },
                    "ID": "1"
            }
    ]
}
EOF

$awscmd s3api put-bucket-lifecycle-configuration --bucket $bucket --lifecycle-configuration=file:///"$pfile"

$awscmd s3api get-bucket-lifecycle-configuration --bucket $bucket
