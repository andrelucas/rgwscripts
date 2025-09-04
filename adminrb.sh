#!/bin/bash

scriptdir="$(dirname "$0")"
# shellcheck source=common.sh
source "$scriptdir"/common.sh

ak=0555b35654ad1656d804
sk=h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q==
host="$(hostname -f):8000"

set -e -x
./racmd.sh caps add --uid="testid" --caps="users=*;buckets=*;metadata=*;usage=*" >/dev/null

./admin-rb.py -a "$ak" -s "$sk" --endpoint "$host" "$@"
