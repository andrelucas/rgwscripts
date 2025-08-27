#!/bin/bash

scriptdir="$(dirname "$0")"
source "$scriptdir"/common.sh

$racmd "$@"
