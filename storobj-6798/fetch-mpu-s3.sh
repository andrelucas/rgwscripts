#!/usr/bin/env bash

set -euo pipefail

function usage() {
    cat <<'EOF' >&2
Usage: fetch-mpu-s3.sh [-f] [-n max_pages] [-p page_size] [bucket ...]

List in-flight multipart uploads from the configured S3 endpoint.

If one or more bucket names are supplied, only those buckets are queried.
Otherwise, all buckets returned by list-buckets are queried.

Options:
  -f             Follow continuation markers and fetch all pages
  -n max_pages   Maximum number of pages to fetch per bucket when -f is used
  -p page_size   Number of uploads to request per S3 API call (default: 1000, max: 10000)

Output format:
  bucket<TAB>key<TAB>upload_id<TAB>initiated
EOF
}

function info() {
    printf 'INFO: %s\n' "$*" >&2
}

function error() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

function show_cmd() {
    local arg
    printf 'INFO: Running:' >&2
    for arg in "$@"; do
        printf ' %q' "$arg" >&2
    done
    printf '\n' >&2
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    usage
    exit 0
fi

page_size=1000
follow_pages=0
max_pages=""
while getopts ":fn:p:h" opt; do
    case "$opt" in
        f)
            follow_pages=1
            ;;
        n)
            max_pages="$OPTARG"
            ;;
        p)
            page_size="$OPTARG"
            ;;
        h)
            usage
            exit 0
            ;;
        :)
            error "Option -$OPTARG requires an argument."
            ;;
        \?)
            error "Unknown option: -$OPTARG"
            ;;
    esac
done
shift $((OPTIND - 1))

if ! [[ "$page_size" =~ ^[0-9]+$ ]] || (( page_size < 1 || page_size > 10000 )); then
    error "page_size must be an integer between 1 and 10000."
fi
if [[ -n "$max_pages" ]] && { ! [[ "$max_pages" =~ ^[0-9]+$ ]] || (( max_pages < 1 )); }; then
    error "max_pages must be a positive integer."
fi

scriptdir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$scriptdir/../common.sh"

aws_cmd=(aws --endpoint-url="$epurl")

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/fetch-mpu-s3.XXXXXXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

all_uploads="$tmpdir/all-uploads.tsv"
all_objects="$tmpdir/all-objects.tsv"
: >"$all_uploads"
: >"$all_objects"

declare -a buckets
if [[ $# -gt 0 ]]; then
    buckets=("$@")
else
    mapfile -t buckets < <("${aws_cmd[@]}" s3api list-buckets | jq -r '.Buckets[]?.Name')
fi

if [[ ${#buckets[@]} -eq 0 ]]; then
    info "No buckets found."
    info "Total multipart upload entries fetched: 0"
    info "Unique objects fetched: 0"
    exit 0
fi

printf 'bucket\tkey\tupload_id\tinitiated\n'

total_uploads=0
for bucket in "${buckets[@]}"; do
    info "Listing multipart uploads for bucket '$bucket'"

    key_marker=""
    upload_id_marker=""
    prev_key_marker=""
    prev_upload_id_marker=""
    page=0

    while true; do
        page=$((page + 1))
        outfile="$tmpdir/${bucket//[^[:alnum:]._-]/_}.$page.json"
        cmd=("${aws_cmd[@]}" s3api list-multipart-uploads --no-paginate --bucket "$bucket" --max-uploads "$page_size")
        if [[ -n "$key_marker" ]]; then
            cmd+=(--key-marker "$key_marker")
        fi
        if [[ -n "$upload_id_marker" ]]; then
            cmd+=(--upload-id-marker "$upload_id_marker")
        fi

        show_cmd "${cmd[@]}"
        "${cmd[@]}" >"$outfile"

        page_count="$(jq '.Uploads | length // 0' "$outfile")"
        total_uploads=$((total_uploads + page_count))
        info "Bucket '$bucket' page $page fetched $page_count upload(s)"

        jq -r --arg bucket "$bucket" '.Uploads[]? | [$bucket, .Key, .UploadId, .Initiated] | @tsv' "$outfile" \
            | tee -a "$all_uploads"
        jq -r --arg bucket "$bucket" '.Uploads[]? | [$bucket, .Key] | @tsv' "$outfile" >>"$all_objects"

        if [[ "$(jq -r '.IsTruncated // false' "$outfile")" != "true" ]]; then
            break
        fi
        if [[ $follow_pages -ne 1 ]]; then
            info "Bucket '$bucket' page $page was truncated; stopping because -f was not specified"
            break
        fi
        if [[ -n "$max_pages" && $page -ge $max_pages ]]; then
            info "Bucket '$bucket' reached max_pages=$max_pages; stopping pagination"
            break
        fi

        prev_key_marker="$key_marker"
        prev_upload_id_marker="$upload_id_marker"
        key_marker="$(jq -r '.NextKeyMarker // empty' "$outfile")"
        upload_id_marker="$(jq -r '.NextUploadIdMarker // empty' "$outfile")"
        if [[ -z "$key_marker" && -z "$upload_id_marker" ]]; then
            error "Bucket '$bucket' response was truncated but did not include continuation markers."
        fi
        if [[ "$key_marker" == "$prev_key_marker" && "$upload_id_marker" == "$prev_upload_id_marker" ]]; then
            error "Bucket '$bucket' returned the same continuation markers twice; stopping to avoid an infinite loop."
        fi
    done
done

unique_objects="$(sort -u "$all_objects" | wc -l | tr -d '[:space:]')"

info "Total multipart upload entries fetched: $total_uploads"
info "Unique objects fetched: $unique_objects"
