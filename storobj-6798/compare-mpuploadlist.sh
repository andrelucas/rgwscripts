#!/usr/bin/env bash

set -euo pipefail

if [[ -t 2 ]]; then
    color_info=$'\033[1;32m'
    color_warn=$'\033[1;33m'
    color_error=$'\033[1;31m'
    color_reset=$'\033[0m'
else
    color_info=""
    color_warn=""
    color_error=""
    color_reset=""
fi

function usage() {
    cat <<'EOF' >&2
Usage: compare-mpuploadlist.sh [-f] [-l last_n] [-n max_pages] [-o output_dir] [-p page_size]... [-s] <bucket>

Compare StoreQuery `mpuploadlist` against `aws s3api list-multipart-uploads`
for one bucket, with one or more page sizes.

AWS defines the page boundary for each comparison step: StoreQuery is asked
for exactly the number of uploads AWS actually returned on that page.

Options:
  -f             Follow continuation tokens/markers after the first page
  -l last_n      Show the last N returned uploads in first-difference diagnostics (default: 5)
  -n max_pages   When -f is used, stop after at most max_pages pages
  -o output_dir  Directory for captured JSON and diff artifacts
  -p page_size   Page size to test; repeat to try multiple sizes (default: 1000)
  -s             Stop immediately on the first non-matching page

Artifacts:
  A subdirectory is created per page size, containing raw page JSON, normalized
  ids, per-page metadata, and overall missing/extra reports.

Documentation:
  See README-compare-mpu.md in this directory for workflow and artifact details.
EOF
}

function info() {
    printf '%sINFO:%s %s\n' "$color_info" "$color_reset" "$*" >&2
}

function warn() {
    printf '%sWARN:%s %s\n' "$color_warn" "$color_reset" "$*" >&2
}

function error() {
    printf '%sERROR:%s %s\n' "$color_error" "$color_reset" "$*" >&2
    exit 1
}

function show_cmd() {
    local arg
    printf '%sINFO:%s Running:' "$color_info" "$color_reset" >&2
    for arg in "$@"; do
        printf ' %q' "$arg" >&2
    done
    printf '\n' >&2
}

function decode_storequery_token() {
    local token="$1"

    if [[ -z "$token" ]]; then
        printf '<none>'
        return 0
    fi

    local decoded
    if decoded="$(jq -Rn -r --arg token "$token" '$token | @base64d' 2>/dev/null)"; then
        printf '%s' "$decoded"
    else
        printf '<decode failed>'
    fi
}

function storequery_token_field() {
    local decoded_token="$1"
    local field="$2"

    if [[ -z "$decoded_token" || "$decoded_token" == "<none>" || "$decoded_token" == "<decode failed>" ]]; then
        printf ''
        return 0
    fi

    jq -r --arg field "$field" '.[$field] // empty' <<<"$decoded_token" 2>/dev/null || true
}

function decode_b64_value() {
    local value="$1"

    if [[ -z "$value" ]]; then
        printf '<none>'
        return 0
    fi

    local decoded
    if decoded="$(jq -Rn -r --arg value "$value" '$value | @base64d' 2>/dev/null)"; then
        printf '%s' "$decoded"
    else
        printf '<decode failed>'
    fi
}

function format_decoded_entry_from_line() {
    local line="$1"
    local key_b64 upload_id_b64

    if [[ -z "$line" ]]; then
        printf '<no entry>'
        return 0
    fi

    IFS=$'\t' read -r key_b64 upload_id_b64 <<<"$line"
    printf 'key=%s | upload_id=%s' \
        "$(decode_b64_value "$key_b64")" \
        "$(decode_b64_value "$upload_id_b64")"
}

function show_first_entry_difference() {
    local sq_ids_file="$1"
    local aws_ids_file="$2"
    local summary_file="$3"
    local -a sq_lines aws_lines
    local sq_len aws_len max_len i sq_line aws_line diff_index

    mapfile -t sq_lines <"$sq_ids_file"
    mapfile -t aws_lines <"$aws_ids_file"
    sq_len=${#sq_lines[@]}
    aws_len=${#aws_lines[@]}
    max_len=$sq_len
    if (( aws_len > max_len )); then
        max_len=$aws_len
    fi

    diff_index=0
    for ((i = 0; i < max_len; i++)); do
        sq_line="${sq_lines[i]:-}"
        aws_line="${aws_lines[i]:-}"
        if [[ "$sq_line" != "$aws_line" ]]; then
            diff_index=$i
            break
        fi
    done

    if (( diff_index == 0 )); then
        warn "Unable to isolate a first differing entry position from the ordered page output"
        printf '*** FIRST DIFFERING ENTRY POSITION: <not found> ***\n' >>"$summary_file"
        return 0
    fi

    sq_line="${sq_lines[diff_index]:-}"
    aws_line="${aws_lines[diff_index]:-}"

    warn "First differing entry position (zero-based): sq_index=$diff_index aws_index=$diff_index"
    warn "  StoreQuery: $(format_decoded_entry_from_line "$sq_line")"
    warn "  AWS:        $(format_decoded_entry_from_line "$aws_line")"

    {
        printf '*** FIRST DIFFERING ENTRY POSITION (ZERO-BASED): sq_index=%s aws_index=%s ***\n' "$diff_index" "$diff_index"
        printf '*** StoreQuery: %s ***\n' "$(format_decoded_entry_from_line "$sq_line")"
        printf '*** AWS:        %s ***\n' "$(format_decoded_entry_from_line "$aws_line")"
    } >>"$summary_file"
}

function write_tail_entries() {
    local infile="$1"
    local outfile="$2"
    local label="$3"
    local tail_count="$4"
    local line_no=0

    : >"$outfile"
    while IFS=$'\t' read -r key_b64 upload_id_b64; do
        line_no=$((line_no + 1))
        printf '%s%02d key=%s | upload_id=%s\n' \
            "$label" "$line_no" \
            "$(decode_b64_value "$key_b64")" \
            "$(decode_b64_value "$upload_id_b64")" \
            >>"$outfile"
    done < <(tail -n "$tail_count" "$infile")
}

function show_tail_comparison() {
    local sq_ids_file="$1"
    local aws_ids_file="$2"
    local summary_file="$3"
    local tail_count="$4"
    local tail_dir
    tail_dir="$(dirname "$summary_file")"
    local sq_tail_file="$tail_dir/.first-diff-sq-tail"
    local aws_tail_file="$tail_dir/.first-diff-aws-tail"
    local compare_file="$tail_dir/.first-diff-tail-compare"

    write_tail_entries "$sq_ids_file" "$sq_tail_file" 'SQ  ' "$tail_count"
    write_tail_entries "$aws_ids_file" "$aws_tail_file" 'AWS ' "$tail_count"
    paste -d $'\t' "$sq_tail_file" "$aws_tail_file" >"$compare_file"

    warn "Last $tail_count returned uploads before/at first difference:"
    while IFS= read -r line; do
        warn "$line"
    done <"$compare_file"

    {
        printf '*** LAST %s RETURNED UPLOADS (STOREQUERY vs AWS) ***\n' "$tail_count"
        cat "$compare_file"
    } >>"$summary_file"
}

function report_first_difference() {
    local page="$1"
    local page_size="$2"
    local page_status="$3"
    local sq_request_count="$4"
    local sq_count="$5"
    local aws_count="$6"
    local missing_count="$7"
    local extra_count="$8"
    local sq_input_token="$9"
    local sq_input_token_decoded="${10}"
    local aws_input_key_marker="${11}"
    local aws_input_upload_id_marker="${12}"
    local sq_nexttoken="${13}"
    local sq_nexttoken_decoded="${14}"
    local sq_nexttoken_key="${15}"
    local sq_nexttoken_upload_id="${16}"
    local aws_next_key_marker="${17}"
    local aws_next_upload_id_marker="${18}"
    local summary_file="${19}"
    local sq_ids_file="${20}"
    local aws_ids_file="${21}"
    local tail_count="${22}"

    warn "================================================================"
    warn "FIRST DIFFERENCE: page=$page page_size=$page_size status=$page_status"
    warn "Counts: sq_req=$sq_request_count sq=$sq_count aws=$aws_count missing_in_storequery=$missing_count extra_in_storequery=$extra_count"
    warn "Request continuation used for this page:"
    warn "  StoreQuery input token=${sq_input_token:-<none>} decoded=${sq_input_token_decoded:-<none>}"
    warn "  AWS input key_marker=${aws_input_key_marker:-<none>} input upload_id_marker=${aws_input_upload_id_marker:-<none>}"
    warn "StoreQuery continuation: token=${sq_nexttoken:-<none>} decoded=${sq_nexttoken_decoded:-<none>}"
    warn "StoreQuery continuation fields: key=${sq_nexttoken_key:-<none>} uploadId=${sq_nexttoken_upload_id:-<none>}"
    warn "AWS continuation: next_key_marker=${aws_next_key_marker:-<none>} next_upload_id_marker=${aws_next_upload_id_marker:-<none>}"
    warn "Artifacts: $summary_file"
    warn "================================================================"

    {
        printf '*** FIRST DIFFERENCE DETECTED HERE ***\n'
        printf '*** page=%s page_size=%s status=%s sq_req=%s sq=%s aws=%s missing_in_storequery=%s extra_in_storequery=%s ***\n' \
            "$page" "$page_size" "$page_status" "$sq_request_count" "$sq_count" "$aws_count" "$missing_count" "$extra_count"
        printf '*** sq_input_token=%s ***\n' "${sq_input_token:-<none>}"
        printf '*** sq_input_token_decoded=%s ***\n' "${sq_input_token_decoded:-<none>}"
        printf '*** aws_input_key_marker=%s ***\n' "${aws_input_key_marker:-<none>}"
        printf '*** aws_input_upload_id_marker=%s ***\n' "${aws_input_upload_id_marker:-<none>}"
        printf '*** storequery_nexttoken=%s ***\n' "${sq_nexttoken:-<none>}"
        printf '*** storequery_nexttoken_decoded=%s ***\n' "${sq_nexttoken_decoded:-<none>}"
        printf '*** storequery_nexttoken_key=%s ***\n' "${sq_nexttoken_key:-<none>}"
        printf '*** storequery_nexttoken_uploadId=%s ***\n' "${sq_nexttoken_upload_id:-<none>}"
        printf '*** aws_next_key_marker=%s ***\n' "${aws_next_key_marker:-<none>}"
        printf '*** aws_next_upload_id_marker=%s ***\n' "${aws_next_upload_id_marker:-<none>}"
    } >>"$summary_file"

    show_first_entry_difference "$sq_ids_file" "$aws_ids_file" "$summary_file"
    show_tail_comparison "$sq_ids_file" "$aws_ids_file" "$summary_file" "$tail_count"
}

function count_lines() {
    wc -l <"$1" | tr -d '[:space:]'
}

function ids_to_jsonl() {
    local infile="$1"
    local outfile="$2"
    jq -Rn '
        inputs
        | split("\t")
        | {
            key: (.[0] | @base64d),
            upload_id: (.[1] | @base64d)
          }
    ' <"$infile" >"$outfile"
}

function summarize_one_size() {
    local bucket="$1"
    local page_size="$2"
    local size_dir="$3"

    local summary_file="$size_dir/summary.txt"
    local sq_all_ids="$size_dir/storequery.all.ids"
    local aws_all_ids="$size_dir/aws.all.ids"
    : >"$summary_file"
    : >"$sq_all_ids"
    : >"$aws_all_ids"

    local page=0
    local sq_token=""
    local aws_key_marker=""
    local aws_upload_id_marker=""
    local first_mismatch_page=0

    printf 'page_size=%s bucket=%s\n' "$page_size" "$bucket" | tee -a "$summary_file"

    while true; do
        page=$((page + 1))

        local page_tag
        printf -v page_tag 'page-%04d' "$page"

        local sq_json="$size_dir/${page_tag}.storequery.json"
        local aws_json="$size_dir/${page_tag}.aws.json"
        local sq_ids="$size_dir/${page_tag}.storequery.ids"
        local aws_ids="$size_dir/${page_tag}.aws.ids"
        local sq_ids_sorted="$size_dir/${page_tag}.storequery.ids.sorted"
        local aws_ids_sorted="$size_dir/${page_tag}.aws.ids.sorted"
        local missing_ids="$size_dir/${page_tag}.missing-in-storequery.ids"
        local extra_ids="$size_dir/${page_tag}.extra-in-storequery.ids"
        local meta_json="$size_dir/${page_tag}.meta.json"

        local sq_input_token="$sq_token"
        local sq_input_token_decoded
        sq_input_token_decoded="$(decode_storequery_token "$sq_input_token")"
        local aws_input_key_marker="$aws_key_marker"
        local aws_input_upload_id_marker="$aws_upload_id_marker"

        local -a aws_cmd=(
            aws
            --endpoint-url="$epurl"
            s3api
            list-multipart-uploads
            --no-paginate
            --bucket "$bucket"
            --max-uploads "$page_size"
        )
        if [[ -n "$aws_input_key_marker" ]]; then
            aws_cmd+=(--key-marker "$aws_input_key_marker")
        fi
        if [[ -n "$aws_input_upload_id_marker" ]]; then
            aws_cmd+=(--upload-id-marker "$aws_input_upload_id_marker")
        fi
        show_cmd "${aws_cmd[@]}"
        "${aws_cmd[@]}" >"$aws_json"
        jq -r '.Uploads[]? | [(.Key | @base64), (.UploadId | @base64)] | @tsv' "$aws_json" >"$aws_ids"
        cat "$aws_ids" >>"$aws_all_ids"

        local aws_count
        aws_count="$(count_lines "$aws_ids")"

        local aws_truncated aws_next_key_marker aws_next_upload_id_marker aws_expectedtoken aws_has_more
        aws_truncated="$(jq -r '.IsTruncated // false' "$aws_json")"
        aws_next_key_marker="$(jq -r '.NextKeyMarker // empty' "$aws_json")"
        aws_next_upload_id_marker="$(jq -r '.NextUploadIdMarker // empty' "$aws_json")"
        aws_expectedtoken="$(jq -r '
            if (.Uploads | length) > 0 then
                ((.Uploads[-1].Key) + "." + (.Uploads[-1].UploadId) + ".meta" | @base64)
            else
                empty
            end
        ' "$aws_json")"
        aws_has_more=0
        if [[ "$aws_truncated" == "true" ]]; then
            aws_has_more=1
            if [[ -z "$aws_next_key_marker" && -z "$aws_next_upload_id_marker" ]]; then
                info "AWS response was truncated without continuation markers on page $page for page_size=$page_size; stopping AWS pagination"
                aws_has_more=0
            elif [[ "$aws_next_key_marker" == "$aws_input_key_marker" && "$aws_next_upload_id_marker" == "$aws_input_upload_id_marker" ]]; then
                info "AWS repeated continuation markers on page $page for page_size=$page_size; stopping AWS pagination"
                aws_has_more=0
            fi
        fi
        if [[ "$aws_count" -eq 0 && "$aws_truncated" == "true" ]]; then
            error "AWS returned a truncated page with zero uploads for page_size=$page_size page=$page; cannot build a like-for-like StoreQuery comparison."
        fi

        local sq_request_count="$aws_count"
        if [[ "$sq_request_count" -gt 0 ]]; then
            local sq_header="x-rgw-storequery: mpuploadlist $sq_request_count"
            if [[ -n "$sq_input_token" ]]; then
                sq_header+=" $sq_input_token"
            fi
            local -a sq_cmd=(
                curl
                --no-progress-meter
                -H 'Accept: application/json'
                -H "$sq_header"
                --
                "$squrl/$bucket"
            )
            show_cmd "${sq_cmd[@]}"
            "${sq_cmd[@]}" >"$sq_json"
            jq -r '.Objects[]? | [.key, .upload_id] | @tsv' "$sq_json" >"$sq_ids"
            cat "$sq_ids" >>"$sq_all_ids"
        else
            jq -n '{Objects: []}' >"$sq_json"
            : >"$sq_ids"
        fi

        sort "$sq_ids" >"$sq_ids_sorted"
        sort "$aws_ids" >"$aws_ids_sorted"
        comm -23 "$aws_ids_sorted" "$sq_ids_sorted" >"$missing_ids"
        comm -13 "$aws_ids_sorted" "$sq_ids_sorted" >"$extra_ids"

        local sq_count missing_count extra_count
        sq_count="$(count_lines "$sq_ids")"
        missing_count="$(count_lines "$missing_ids")"
        extra_count="$(count_lines "$extra_ids")"

        local page_status
        if cmp -s "$sq_ids" "$aws_ids"; then
            page_status="MATCH"
        elif [[ "$missing_count" -eq 0 && "$extra_count" -eq 0 ]]; then
            page_status="ORDER_MISMATCH"
        else
            page_status="CONTENT_MISMATCH"
        fi

        local sq_nexttoken sq_expectedtoken sq_has_more
        sq_nexttoken="$(jq -r '.NextToken // empty' "$sq_json")"
        local sq_nexttoken_decoded
        sq_nexttoken_decoded="$(decode_storequery_token "$sq_nexttoken")"
        local sq_nexttoken_key sq_nexttoken_upload_id
        sq_nexttoken_key="$(storequery_token_field "$sq_nexttoken_decoded" key)"
        sq_nexttoken_upload_id="$(storequery_token_field "$sq_nexttoken_decoded" uploadId)"
        sq_expectedtoken="$(jq -r '
            if (.Objects | length) > 0 then
                ((.Objects[-1].key | @base64d) + "." + (.Objects[-1].upload_id | @base64d) + ".meta" | @base64)
            else
                empty
            end
        ' "$sq_json")"
        sq_has_more=0
        if [[ -n "$sq_nexttoken" ]]; then
            sq_has_more=1
            if [[ "$sq_nexttoken" == "$sq_input_token" ]]; then
                info "StoreQuery repeated NextToken on page $page for page_size=$page_size; stopping StoreQuery pagination"
                sq_has_more=0
            fi
        fi
        local continuation_marker_mismatch=0
        if [[ -n "$sq_nexttoken" || -n "$aws_next_key_marker" || -n "$aws_next_upload_id_marker" ]]; then
            if [[ "$sq_nexttoken_key" != "$aws_next_key_marker" || "$sq_nexttoken_upload_id" != "$aws_next_upload_id_marker" ]]; then
                continuation_marker_mismatch=1
                if [[ "$page_status" == "MATCH" ]]; then
                    page_status="CONTINUATION_MISMATCH"
                fi
            fi
        fi
        if [[ $first_mismatch_page -eq 0 && $page_status != "MATCH" ]]; then
            first_mismatch_page="$page"
            report_first_difference \
                "$page" "$page_size" "$page_status" "$sq_request_count" "$sq_count" "$aws_count" \
                "$missing_count" "$extra_count" \
                "$sq_input_token" "$sq_input_token_decoded" \
                "$aws_input_key_marker" "$aws_input_upload_id_marker" \
                "$sq_nexttoken" "$sq_nexttoken_decoded" \
                "$sq_nexttoken_key" "$sq_nexttoken_upload_id" \
                "$aws_next_key_marker" "$aws_next_upload_id_marker" \
                "$summary_file" "$sq_ids" "$aws_ids" "$last_n"
        fi

        jq -n \
            --arg page "$page" \
            --arg status "$page_status" \
            --arg sq_count "$sq_count" \
            --arg aws_count "$aws_count" \
            --arg sq_request_count "$sq_request_count" \
            --arg missing_count "$missing_count" \
            --arg extra_count "$extra_count" \
            --arg sq_input_token "$sq_input_token" \
            --arg sq_nexttoken "$sq_nexttoken" \
            --arg sq_nexttoken_key "$sq_nexttoken_key" \
            --arg sq_nexttoken_upload_id "$sq_nexttoken_upload_id" \
            --arg sq_expectedtoken "$sq_expectedtoken" \
            --arg aws_input_key_marker "$aws_input_key_marker" \
            --arg aws_input_upload_id_marker "$aws_input_upload_id_marker" \
            --arg aws_truncated "$aws_truncated" \
            --arg aws_next_key_marker "$aws_next_key_marker" \
            --arg aws_next_upload_id_marker "$aws_next_upload_id_marker" \
            --arg aws_expectedtoken "$aws_expectedtoken" \
            --arg continuation_marker_mismatch "$continuation_marker_mismatch" \
            '{
                page: ($page | tonumber),
                status: $status,
                counts: {
                    storequery_requested: ($sq_request_count | tonumber),
                    storequery: ($sq_count | tonumber),
                    aws: ($aws_count | tonumber),
                    missing_in_storequery: ($missing_count | tonumber),
                    extra_in_storequery: ($extra_count | tonumber)
                },
                storequery: {
                    input_token: $sq_input_token,
                    next_token: $sq_nexttoken,
                    next_token_key: $sq_nexttoken_key,
                    next_token_upload_id: $sq_nexttoken_upload_id,
                    expected_next_token_from_last_item: $sq_expectedtoken
                },
                aws: {
                    input_key_marker: $aws_input_key_marker,
                    input_upload_id_marker: $aws_input_upload_id_marker,
                    truncated: ($aws_truncated == "true"),
                    next_key_marker: $aws_next_key_marker,
                    next_upload_id_marker: $aws_next_upload_id_marker,
                    expected_storequery_token_from_last_item: $aws_expectedtoken
                },
                continuation_marker_mismatch: ($continuation_marker_mismatch == "1")
            }' >"$meta_json"

        printf 'page=%d sq_req=%s sq=%s aws=%s status=%s missing_in_storequery=%s extra_in_storequery=%s\n' \
            "$page" "$sq_request_count" "$sq_count" "$aws_count" "$page_status" "$missing_count" "$extra_count" \
            | tee -a "$summary_file"

        if [[ -n "$sq_nexttoken" || "$aws_truncated" == "true" ]]; then
            printf '  sq_nexttoken=%s sq_token_key=%s sq_token_uploadId=%s sq_expected=%s aws_next_key=%s aws_next_upload_id=%s aws_expected_sq_token=%s\n' \
                "${sq_nexttoken:-<none>}" "${sq_nexttoken_key:-<none>}" "${sq_nexttoken_upload_id:-<none>}" \
                "${sq_expectedtoken:-<none>}" \
                "${aws_next_key_marker:-<none>}" "${aws_next_upload_id_marker:-<none>}" \
                "${aws_expectedtoken:-<none>}" \
                | tee -a "$summary_file"
        fi

        if [[ "$missing_count" -gt 0 ]]; then
            ids_to_jsonl "$missing_ids" "$size_dir/${page_tag}.missing-in-storequery.jsonl"
        fi
        if [[ "$extra_count" -gt 0 ]]; then
            ids_to_jsonl "$extra_ids" "$size_dir/${page_tag}.extra-in-storequery.jsonl"
        fi
        if [[ $stop_on_first_diff -eq 1 && $page_status != "MATCH" ]]; then
            warn "Stopping on first difference because -s was specified"
            printf '  stopping on first difference because -s was specified\n' | tee -a "$summary_file"
            return 1
        fi

        if [[ $follow_pages -ne 1 ]]; then
            if [[ $sq_has_more -eq 1 || $aws_has_more -eq 1 ]]; then
                printf '  stopping after first page because -f was not specified\n' | tee -a "$summary_file"
            fi
            break
        fi

        if [[ -n "$max_pages" && "$page" -ge "$max_pages" ]]; then
            if [[ $sq_has_more -eq 1 || $aws_has_more -eq 1 ]]; then
                printf '  stopping at max_pages=%s\n' "$max_pages" | tee -a "$summary_file"
            fi
            break
        fi
        if [[ "$aws_has_more" -ne 1 ]]; then
            if [[ "$sq_has_more" -eq 1 ]]; then
                warn "StoreQuery reports more pages after AWS was exhausted"
                printf '  StoreQuery reports more pages after AWS was exhausted\n' | tee -a "$summary_file"
                return 1
            fi
            break
        fi
        if [[ "$sq_has_more" -ne 1 ]]; then
            warn "StoreQuery stopped paginating before AWS was exhausted"
            printf '  StoreQuery stopped paginating before AWS was exhausted\n' | tee -a "$summary_file"
            return 1
        fi

        sq_token="$sq_nexttoken"
        aws_key_marker="$aws_next_key_marker"
        aws_upload_id_marker="$aws_next_upload_id_marker"
    done

    local sq_unique_ids="$size_dir/storequery.all.unique.ids"
    local aws_unique_ids="$size_dir/aws.all.unique.ids"
    local overall_missing_ids="$size_dir/missing-in-storequery.ids"
    local overall_extra_ids="$size_dir/extra-in-storequery.ids"
    sort -u "$sq_all_ids" >"$sq_unique_ids"
    sort -u "$aws_all_ids" >"$aws_unique_ids"
    comm -23 "$aws_unique_ids" "$sq_unique_ids" >"$overall_missing_ids"
    comm -13 "$aws_unique_ids" "$sq_unique_ids" >"$overall_extra_ids"

    local sq_total aws_total sq_unique aws_unique overall_missing overall_extra overall_status
    sq_total="$(count_lines "$sq_all_ids")"
    aws_total="$(count_lines "$aws_all_ids")"
    sq_unique="$(count_lines "$sq_unique_ids")"
    aws_unique="$(count_lines "$aws_unique_ids")"
    overall_missing="$(count_lines "$overall_missing_ids")"
    overall_extra="$(count_lines "$overall_extra_ids")"

    if [[ $overall_missing -eq 0 && $overall_extra -eq 0 && $first_mismatch_page -eq 0 ]]; then
        overall_status="MATCH"
    else
        overall_status="DIFF"
    fi

    if [[ "$overall_missing" -gt 0 ]]; then
        ids_to_jsonl "$overall_missing_ids" "$size_dir/missing-in-storequery.jsonl"
    fi
    if [[ "$overall_extra" -gt 0 ]]; then
        ids_to_jsonl "$overall_extra_ids" "$size_dir/extra-in-storequery.jsonl"
    fi

    printf 'result page_size=%s status=%s pages=%s sq_total=%s aws_total=%s sq_unique=%s aws_unique=%s missing_in_storequery=%s extra_in_storequery=%s first_mismatch_page=%s artifacts=%s\n' \
        "$page_size" "$overall_status" "$page" "$sq_total" "$aws_total" "$sq_unique" "$aws_unique" \
        "$overall_missing" "$overall_extra" "${first_mismatch_page:-0}" "$size_dir" \
        | tee -a "$summary_file"
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    usage
    exit 0
fi

follow_pages=0
last_n=5
max_pages=""
output_dir=""
stop_on_first_diff=0
declare -a page_sizes=()

while getopts ":fhl:n:o:p:s" opt; do
    case "$opt" in
        f)
            follow_pages=1
            ;;
        h)
            usage
            exit 0
            ;;
        l)
            last_n="$OPTARG"
            ;;
        n)
            max_pages="$OPTARG"
            ;;
        o)
            output_dir="$OPTARG"
            ;;
        p)
            page_sizes+=("$OPTARG")
            ;;
        s)
            stop_on_first_diff=1
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

bucket="${1:-}"
if [[ -z "$bucket" ]]; then
    usage
    exit 1
fi
if [[ $# -ne 1 ]]; then
    error "Exactly one bucket name is required."
fi

if [[ ${#page_sizes[@]} -eq 0 ]]; then
    page_sizes=(1000)
fi

for page_size in "${page_sizes[@]}"; do
    if ! [[ "$page_size" =~ ^[0-9]+$ ]] || (( page_size < 1 || page_size > 10000 )); then
        error "Each page_size must be an integer between 1 and 10000."
    fi
done

if [[ -n "$max_pages" ]] && { ! [[ "$max_pages" =~ ^[0-9]+$ ]] || (( max_pages < 1 )); }; then
    error "max_pages must be a positive integer."
fi
if ! [[ "$last_n" =~ ^[0-9]+$ ]] || (( last_n < 1 )); then
    error "last_n must be a positive integer."
fi

scriptdir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$scriptdir/../common.sh"

if [[ -z "$output_dir" ]]; then
    output_dir="$(mktemp -d "${TMPDIR:-/tmp}/compare-mpuploadlist.XXXXXXXXXX")"
else
    mkdir -p "$output_dir"
fi

info "Writing artifacts to '$output_dir'"

for page_size in "${page_sizes[@]}"; do
    size_dir="$output_dir/page-size-$page_size"
    mkdir -p "$size_dir"
    if ! summarize_one_size "$bucket" "$page_size" "$size_dir"; then
        exit 1
    fi
done
