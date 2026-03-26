#!/usr/bin/env bash

squrl="${SQURL:-http://127.0.0.1:8000}"

decode=0
decode_token=0
follow_nexttoken=0
max_pages=0
pretty=1

function usage() {
    cat <<EOF >&2
Usage: $0 "<command>" [-b][-c] <path>

Run a store query command against the specified path in the RGW.

-b: (for objectlist and mpuploadlist) decode base64-encoded object keys in the output
-c: use 'compact' (not pretty-printed) JSON output
-f: (for objectlist and mpuploadlist) follow NextToken in the output
-n <max_pages>: when following NextToken, stop after max_pages pages (default: no limit)
-t: (for objectlist and mpuploadlist) decode base64-encoded NextToken in the output

Example:
    $0 "ping foo" mybucket
    $0 "objectstatus" mybucket/mykey
    $0 -b "objectlist 100" mybucket
    $0 -f -n 5 "mpuploadlist" mybucket
    
The command must be quoted if it contains spaces.
EOF
    exit 1
}

function info() {
    echo -e "\033[1;32mINFO: $*\033[0m" >&2
}

function error() {
    local noexit
    if [[ $1 = '-n' ]]; then
        shift
        noexit=1
    fi
    echo -e "\033[1;37mERROR: $*\033[0m" >&2
    if [[ $noexit -ne 1 ]]; then
        exit 1
    fi
}

# Parse options
while getopts "bcfn:t" opt; do
  case $opt in
    b)
      decode=1
      ;;
    c)
      pretty=0
      ;;
    f)
      follow_nexttoken=1
      ;;
    n)
      max_pages="$OPTARG"
      ;;
    t)
      decode_token=1
      ;;
    *)
      echo "Usage: $0 [-bcft] [-n <max_pages>] \"<command>\" <path> [<path> ...]" >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

cmd="$1"
path="$2"
shift

if [[ -z "$cmd" || -z "$path" ]]; then
    usage
fi

if [[ $decode -eq 1 || $decode_token -eq 1 ]]; then
    if [[ $cmd =~ ^(objectlist|mpuploadlist) ]]; then
        true
    else
        error "-b and -t options (decode base64) are only valid for 'objectlist' and 'mpuploadlist' commands."
    fi
fi
if [[ $follow_nexttoken -eq 1 ]]; then
    if [[ $cmd =~ ^(objectlist|mpuploadlist) ]]; then
        true
    else
        error "-f option (follow NextToken) is only valid for 'mpobjectlist' and 'mpuploadlist' commands."
    fi
fi

declare -a jqopts
jqscript="."
if [[ $pretty -ne 1 ]]; then
    jqopts+=("-c")
fi
if [[ $decode -eq 1 ]]; then
    jqscript='if (.Objects | length > 0) then .Objects[].key |= @base64d else . end'
fi

tmpdir=$(mktemp -d "sqcmd_XXXXXXXXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

function run() {
    local cmd="$1"
    local path="$2"
    curl --no-progress-meter \
        -H 'Accept: application/json' \
        -H "x-rgw-storequery: $cmd" \
        -- \
        "${squrl}/${path}"
}

function ntdecode() {
    # Decode the NextToken key if it exists.
    if [[ $decode_token -eq 1 ]]; then
        jq 'if (.NextToken != null) then .NextToken |= @base64d else . end'

    else
        cat
    fi
}

token=""
prevtoken=""
count=0
remaining_pages="$max_pages"

objlist_all="$tmpdir/objlist-all"
objlist_uniq="$tmpdir/objlist-uniq"
:>"$objlist_all"
:>"$objlist_uniq"
if [[ $cmd =~ ^(objectlist|mpuploadlist) ]]; then
    wantobjcount=1
else
    wantobjcount=0
fi

while true; do
    outfile="$tmpdir/out.json"
    fullcmd="$cmd"
    if [[ -n "$token" ]]; then
        fullcmd="$fullcmd $token"
    fi
    run "$fullcmd" "$path" >"$outfile"
    count=$((count + 1))
    info "Command $count: '$fullcmd'"
    jq "${jqopts[@]}" "$jqscript" "$outfile" | ntdecode
    if [[ $wantobjcount -eq 1 ]]; then
        # Save a list of objects for later.
        jq -r '.Objects[] | .key' "$outfile" >>"$objlist_all"
    fi

    if [[ $follow_nexttoken -eq 0 ]]; then
        break
    else
        prevtoken=$token
        token=$(jq -r 'if (.NextToken != null) then .NextToken else empty end' "$outfile")
        if [[ -n $token && $token = "$prevtoken" ]]; then
            error "NextToken did not change after $count commands, exiting to avoid loop."
        fi
        if [[ -z "$token" ]]; then
            break
        fi
    fi
    # If max_pages <= 0, there's no limiter.
    if [[ "$max_pages" -gt 0 ]]; then
        remaining_pages=$((remaining_pages - 1))
        if [[ $remaining_pages -le 0 ]]; then
            info "Stopping pagination at page $max_pages"
            break
        fi
    fi
done

info "Done. Ran $count command(s)."
if [[ $wantobjcount -eq 1 ]]; then
    info "Total objects listed: $(cat "$objlist_all" | wc -l)"
    sort "$objlist_all" | uniq >"$objlist_uniq"
    info "Unique objects listed: $(cat "$objlist_uniq" | wc -l)"
fi
