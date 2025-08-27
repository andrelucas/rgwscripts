#!/usr/bin/env bash

# Note the python trick in the hashbang. Bash on macOS is old and doesn't
# properly expand arrays using ${array[@]} syntax. Install newer bash using
# Homebrew and make sure it's in your PATH before the system bash.

scriptdir="$(dirname "$0")"
sqcurl_silent=1
source "$scriptdir"/common.sh

debug=0

cmd="$1"
version="$2"
uripath="storequery/$version/$cmd"

declare -a passes failures

reshard=0
stop_on_failure=1

ver_single_single=1
ver_single_multiple=1
ver_paginated_single=1
ver_paginated_multiversion=1
nonver=1

function get_object_counts_for_pagelen() {
    local pagelen="$1"

    objcounts_page10="1 2 9 10 11 19 20 21"
    objcounts_page100="1 2 99 100 101 102 199 200 201"
    objcounts_page1000="1 2 999 1000 1001 1002 1999 2000 2001"

    case "$pagelen" in
        10) echo "$objcounts_page10" ;;
        100) echo "$objcounts_page100" ;;
        1000) echo "$objcounts_page1000" ;;
        *) error "Unsupported page length: $pagelen" ;;
    esac
}

tmpdir=$(mktemp -d "sqtest_XXXXXXXXXX")
out="$tmpdir/out"
trap 'echo "Removing \"$tmpdir\""; rm -rf "$tmpdir"' EXIT

maxjobs=100

capture_out="$out/sqcmd_capture.txt"

function error() {
    echo -e "\e[31mERROR: $*" >&2
    exit 1
}

testname=NOTSET

function testname() {
    if [[ -z "$1" ]]; then
        error "testname function requires a test name argument"
    fi
    testname="$1"
    echo -e "\e[33mTEST: $testname\e[0m" >&2    
}

function pass() {
    passes+=("$*")
    echo -e "\e[32mPASS: $testname: $*\e[0m" >&2
}

function fail() {
    failures+=("$*")
    echo -e "\e[31mFAIL: $testname: $*\e[0m" >&2
    if [[ stop_on_failure -eq 1 ]]; then
        echo -e "\e[31mStopping on failure: $testname: $*\e[0m" >&2
        exit 1
    fi
}

function start() {
    echo -e "\e[36mSTART: $*\e[0m"
}

function info() {
    echo -e "\e[34mINFO: $*\e[0m"
}
function info_err() {
    echo -e "\e[34mINFO: $*\e[0m" >&2
}
function debug() {
    if [[ $debug -eq 1 ]]; then
        echo -e "\e[35mDEBUG: $*"
    fi
}
function debug_err() {
    if [[ $debug -eq 1 ]]; then
        echo -e "\e[35mDEBUG: $*"
    fi
}

function prereq() {
    mkdir -p "$out" || error "Failed to create output directory"
    for n in $(seq 1 10); do
        dd if=/dev/urandom of="$out/infile$n" bs=1024 count=1 2>/dev/null || error "Failed to create input file"
    done
}

function delete_bucket() {
    local bucket="$1"
    if [[ -z "$bucket" ]]; then
        error "Bucket name is required for deletion."
    fi
    info "Deleting bucket: $bucket"
    
    ./bucket-delete-boto.py --bucket "$bucket" --i-mean-it
        
    # $racmd bucket rm --bucket "$bucket" --purge-objects
    
    # $racmd bucket list --bucket "$bucket" > allfiles.json || error "Failed to list bucket $bucket"
    # # # Filter on the exists: true field, to omit deletion markers.
    # # jq '.[] | select( .exists ) | {name, instance}' >"$out/name_instance.json" < allfiles.json || error "Failed filter $bucket object list"
    # jq '.[] | {name, instance}' >"$out/name_instance.json" < allfiles.json || error "Failed filter $bucket object list"
    # # base64 encode name and instance.
    # jq '{name: .name | @base64, instance: .instance | @base64}' < "$out/name_instance.json" > "$out/name_instance_base64.json" || error "Failed to encode bucket name and instance to base64"
    # # Just 'b64(name) b64(instance)' as one line.
    # jq -r '"\(.name) \(.instance)"' < "$out/name_instance_base64.json" > "$out/name_instance.txt" || error "Failed to format bucket name and instance"
    # cat "$out/name_instance.txt"

    # cat "$out/name_instance.txt" | while read -r name_b64 instance_b64; do
    #     name="$(echo "$name_b64" | base64 -d)"
    #     instance="$(echo "$instance_b64" | base64 -d)"
    #     info "Deleting object: $name version $instance"
    #     echo aws s3api delete-object --bucket "$bucket" --key "$name" --version-id \'"$instance"\' || error "Failed to delete object $name from instance $instance"
    #     aws s3api delete-object --bucket "$bucket" --key "$name" --version-id \'"$instance"\' || error "Failed to delete object $name from instance $instance"
    # done

    # s3cmd rb s3://"$bucket" || error "Failed to remove bucket $bucket"
}

function sqcmd_capture() {
    local cmd="$1"
    local bucket="$2"
    if [[ -z "$cmd" ]]; then
        error "Command is required for sqcmd_capture."
    fi
    if [[ -z "$bucket" ]]; then
        error "Bucket name is required for sqcmd_capture."
    fi
    sqcmd "$cmd" "$bucket" >"$capture_out" || error "Failed to run sqcmd: $cmd on bucket: $bucket"
}

function put_same_file_many_times() {
    local bucket="$1"
    local bucketuri="$2"
    local infile="$3"
    local count="$4"

    ## Earlier implementations:
        # for n in $(seq 1 $t); do
        #     tgtfile="tgt$n"
        #     s3cmd -q put "$out/infile1" "$bucketuri/$tgtfile" || error "Failed to upload $tgtfile"
        # done

        # Do up to 100 puts in parallel.
        # parallel -j"$maxjobs" -n0 "s3cmd -q put $out/infile1 $bucketuri/tgtfile{#}" ::: $(seq 1 "$t")


    if [[ -z "$bucket" ]]; then
        error "Bucket name is required for put_same_file_many_times"
    fi
    if [[ -z "$bucketuri" ]]; then
        error "Bucket URI is required for put_same_file_many_times"
    fi
    if [[ -z "$infile" ]]; then
        error "Input file is required for put_same_file_many_times"
    fi
    if [[ -z "$count" ]]; then
        error "Count is required for put_same_file_many_times"
    fi

    # Do up to maxjobs puts in parallel.
    debug_err "Begin parallel put"
    parallel -j"$maxjobs" -n0 "s3cmd -q put $infile $bucketuri/tgtfile{#}" ::: $(seq 1 "$count")
}

function delete_files() {
    local bucket="$1"
    local bucketuri="$2"
    local count="$3"

    if [[ -z "$bucket" ]]; then
        error "Bucket name is required for delete_file."
    fi
    if [[ -z "$bucketuri" ]]; then
        error "Bucket URI is required for delete_file."
    fi
    if [[ -z "$count" ]]; then
        error "Count is required for delete_file."
    fi

    # Do up to maxjobs deletes in parallel.
    debug_err "Begin parallel delete"
    parallel -j"$maxjobs" -n0 "s3cmd -q rm $bucketuri/tgtfile{#}" ::: $(seq 1 "$count")
}

function maybe_reshard() {
    if [[ reshard -ne 1 ]]; then
        return
    fi
    local bucket="$1"
    if [[ -z "$bucket" ]]; then
        error "Bucket name is required for maybe_reshard."
    fi
    ./racmd.sh reshard add --bucket "$bucket" --num-shards 100
    ./racmd.sh reshard list --bucket "$bucket"    
}

function paginated_list_count() {
    local bucket="$1"
    local pagelen="$2"
    if [[ -z "$bucket" ]]; then
        error "Bucket name is required for paginated_list."
    fi
    if [[ -z "$pagelen" ]]; then
        error "Page length is required for paginated_list."
    fi

    local list_done=0
    local cont=""
    local total_len=0
    local page=0
    
    while [[ $list_done != 1 ]]; do
        page=$((page + 1))
        info_err "Fetching page $page with $pagelen objects from bucket '$bucket' using token '$cont'"

        sqopt="$pagelen"
        if [[ -n "$cont" ]]; then
            sqopt="$sqopt $cont"
        fi
        sqcmd_capture "objectlist $sqopt" "$bucket"
        local len
        len="$(jq -r '.Objects | length' "$capture_out")"
        cont="$(jq -r '.NextToken' "$capture_out")"
        if [[ $len -eq 0 ]]; then
            info_err "No more objects found in bucket '$bucket'."
            list_done=1
        fi
        if [[ $cont == "null" ]]; then
            info_err "No continuation token found, ending pagination."
            list_done=1
        fi
        total_len=$((total_len + len))
    done
    
    echo "$total_len"
}

function versioned() {
    local bucket=testv
    local bucketuri=s3://"$bucket"

    if [[ ver_single_single -eq 1 ]]; then
        testname "Single file, single version"
        
        local pagelen=100
        for t in $(get_object_counts_for_pagelen $pagelen); do

            start "Testing with $t object(s) in versioned bucket"
            
            delete_bucket "$bucket" || true
            info "Creating versioned bucket: $bucket"
            s3cmd mb $bucketuri || error "Failed to create bucket $bucket"
            maybe_reshard "$bucket"
            s3cmd setversioning $bucketuri enable || error "Failed to enable versioning on $bucket"

            info "Uploading $t object(s) to versioned bucket: $bucket"

            put_same_file_many_times "$bucket" "$bucketuri" "$out/infile1" "$t"

            # s3cmd ls $bucketuri
            sqcmd_capture "objectlist $pagelen" $bucket
            local len
            # jq -r -C '.Objects | length' "$capture_out"
            len="$(jq -r '.Objects | length' "$capture_out")"

            testlen=$t
            if [[ $testlen -gt $pagelen ]]; then
                testlen=$pagelen
            fi

            if [[ "$len" -ne $testlen ]]; then
                fail "t=$t expected $testlen object(s) in versioned bucket, found $len"
            else
                pass "t=$t $testlen object(s) counted"
            fi
        done
    fi
    
    if [[ ver_single_multiple -eq 1 ]]; then
        testname "Single file, multiple versions"
        
        local pagelen=100
        for v in 2 5; do
            for t in $(get_object_counts_for_pagelen $pagelen); do

                delete_bucket "$bucket" || true
                info "Creating versioned bucket: $bucket"
                s3cmd mb $bucketuri || error "Failed to create bucket $bucket"
                s3cmd setversioning $bucketuri enable || error "Failed to enable versioning on $bucket"

                info "Uploading $t object(s) $v times to versioned bucket: $bucket"
                for rep in $(seq 1 "$v"); do
                    debug "Uploading version $rep of $t object(s)"
                    # Upload the same file $t times, each time creating a new version.
                    # This will create $v versions of each object.
                    put_same_file_many_times "$bucket" "$bucketuri" "$out/infile1" "$t"
                done

                # s3cmd ls $bucketuri
                sqcmd_capture "objectlist $pagelen" $bucket
                local len
                # jq -r -C '.Objects | length' "$capture_out"
                len="$(jq -r '.Objects | length' "$capture_out")"

                testlen=$t
                if [[ $testlen -gt $pagelen ]]; then
                    testlen=$pagelen
                fi

                if [ "$len" -ne $testlen ]; then
                    fail "t=$t v=$v expected $testlen object(s) in versioned bucket, found $len"
                else
                    pass "t=$t v=$v $testlen object(s) counted"
                fi
            done
        done
    fi

    if [[ ver_paginated_single -eq 1 ]]; then
        testname "Paginated lists of single-version objects in versioned bucket"
        
        local pagelen=10
        for t in $(get_object_counts_for_pagelen $pagelen); do
            delete_bucket "$bucket" || true
            info "Creating versioned bucket: $bucket"
            s3cmd mb $bucketuri || error "Failed to create bucket $bucket"
            s3cmd setversioning $bucketuri enable || error "Failed to enable versioning on $bucket"
            
            info "Uploading $t object(s) to versioned bucket: $bucket"
            put_same_file_many_times "$bucket" "$bucketuri" "$out/infile1" "$t"
            
            len="$(paginated_list_count "$bucket" "$pagelen")"
            if [[ $len -ne $t ]]; then
                fail "t=$t expected $t object(s) in paginated versioned bucket, found $len"
            else
                pass "$len object(s) counted"
            fi
            
        done
    fi

    if [[ ver_paginated_multiversion -eq 1 ]]; then
        testname "Paginated lists of deleted multiply-versioned objects in versioned bucket"
        
        local pagelen=10
        for v in 2 5; do
            for t in $(get_object_counts_for_pagelen $pagelen); do
                delete_bucket "$bucket" || true
                info "Creating versioned bucket: $bucket"
                s3cmd mb $bucketuri || error "Failed to create bucket $bucket"
                s3cmd setversioning $bucketuri enable || error "Failed to enable versioning on $bucket"
                
                info "Uploading $t object(s) $v times to versioned bucket: $bucket"
                for rep in $(seq 1 "$v"); do
                    debug "Uploading version $rep of $t object(s)"
                    # Upload the same file $t times, each time creating a new version.
                    # This will create $v versions of each object.
                    put_same_file_many_times "$bucket" "$bucketuri" "$out/infile1" "$t"
                done
                delete_files "$bucket" "$bucketuri" "$t"

                info "Begin list (should be empty)"
                s3cmd ls "$bucketuri" || error "Failed to list bucket $bucket"
                info "End list"
                
                len="$(paginated_list_count "$bucket" "$pagelen")"
                if [[ $len -ne $t ]]; then
                    fail "t=$t v=$v expected $t object(s) in paginated multiply-versioned bucket, found $len"
                else
                    pass "t=$t v=$v $len object(s) counted"
                fi
                
            done
        done
    fi
}

function nonversioned() {
    local bucket=testnv
    local bucketuri=s3://"$bucket"

    if [[ nonver -eq 1 ]]; then
        testname "Single file, non-versioned bucket"
        local pagelen=100
        for t in $(get_object_counts_for_pagelen $pagelen); do

            delete_bucket "$bucket" || true
            info "Creating versioned bucket: $bucket"
            s3cmd mb $bucketuri || error "Failed to create bucket $bucket"
            s3cmd setversioning $bucketuri disable || error "Failed to disable versioning on $bucket"

            info "Uploading $t object(s) to nonversioned bucket: $bucket"

            put_same_file_many_times "$bucket" "$bucketuri" "$out/infile1" "$t"

            # s3cmd ls $bucketuri
            sqcmd_capture "objectlist $pagelen" $bucket
            local len
            # jq -r -C '.Objects | length' "$capture_out"
            len="$(jq -r '.Objects | length' "$capture_out")"

            testlen=$t
            if [[ $testlen -gt $pagelen ]]; then
                testlen=$pagelen
            fi

            if [ "$len" -ne $testlen ]; then
                fail "t=$t expected $testlen object(s) in versioned bucket, found $len"
            else
                pass "t=$t $testlen object(s) counted"
            fi
        done
    fi
}

prereq
versioned
nonversioned

if [[ ${#failures[@]} -gt 0 ]]; then
    echo -e "\nSummary of failures:"
    for f in "${failures[@]}"; do
        echo "$f"
    done
    exit 1
else
    echo -e "\nAll tests passed."
fi
