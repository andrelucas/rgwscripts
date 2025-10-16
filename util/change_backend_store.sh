#!/bin/bash

# Usage: ./change_backend_store.sh [-u] ceph.conf
#   -u : Uncomment lines matching 'rgw_backend_store = mdoffload'
#   (default) : Comment out lines matching 'rgw_backend_store = mdoffload'

set -e

UNCOMMENT=0

while getopts "u" opt; do
    case $opt in
        u) UNCOMMENT=1 ;;
        *) echo "Usage: $0 [-u] ceph.conf"; exit 1 ;;
    esac
done

shift $((OPTIND -1))

if [ $# -ne 1 ]; then
    echo "Usage: $0 [-u] ceph.conf"
    exit 1
fi

CONF_FILE="$1"
TMP_FILE="${CONF_FILE}.tmp"

if [ $UNCOMMENT -eq 1 ]; then
    # Uncomment matching lines
    sed 's/^\(\s*\)*#\(rgw_backend_store = mdoffload\)/\1\2/' "$CONF_FILE" > "$TMP_FILE"
else
    # Comment out matching lines
    sed 's/^\(\s*\)\(rgw_backend_store = mdoffload\)/\1#\2/' "$CONF_FILE" > "$TMP_FILE"
fi

mv "$TMP_FILE" "$CONF_FILE"
