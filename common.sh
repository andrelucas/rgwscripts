# source me
#
# shellcheck shell=bash

#epurl="http://127.0.0.1:8000"
#epurl="http://amygdala-ub01.home.ae-35.com:8000"
#epurl="http://amygdala-fe02.home.ae-35.com:8000"
#epurl="http://ludwig-fe01.home.ae-35.com:8000"
# epurl="http://atl1.objstore.dev:8000"
epurl="http://ludwig-ub01.home.ae-35.com:8000"

## Use this for StoreQuery if talking to a real RGW instance you can directly
## access, i.e. not inside a remote k8s cluster.
#squrl="$epurl"

## Use this for StoreQuery if port-forwarding.
squrl="http://127.0.0.1:8000"

cephbuilddir=~/git/ceph/build
# cephbuilddir=~/git/ceph/build.RelWithDebInfo
#cephbuilddir=~/git/ceph-alt/build
#cephbuilddir=~/git/ceph/build.Debug
cephbindir="$cephbuilddir/bin"
cephconf="$cephbuilddir/ceph.conf"

test -f $cephconf || (echo "ceph.conf not found in $cephconf" >&2; exit 1)

awscmd='aws --endpoint-url='$epurl''
export CEPH_DEV=1
racmd="env CEPH_CONF=$cephconf $cephbindir/radosgw-admin"

: "${sqcurl_verbose:=0}"
: "${sqcurl_silent:=1}"
: "${sqcurl_out:=1}"
: "${sqcmd_showcmd:=0}"

function sqcmd () {
    local cmd cmdopt curl_options out tmpdir uripath
    cmd="$1"
    uripath="$2"
    if [[ $cmd = "" ]]; then
        cmdopt=";"
    else
        cmdopt=": $cmd"
    fi
    tmpdir=$(mktemp -d "sqcmd_XXXXXXXXXX")
    out="$tmpdir/out"
    ## Need to evaluate $tmpdir right away, otherwise it appears to execute
    ## after the local variables are unset. This means it uses $tmpdir as set
    ## in the parent context, which is not what we want.
    # shellcheck disable=SC2064
    trap "rm -rf $tmpdir" RETURN
    set -a curl_options
    if [[ $sqcurl_verbose -eq 1 ]]; then
        curl_options+=(-v)
    fi
    if [[ $sqcurl_silent -eq 1 ]]; then
        curl_options+=(--no-progress-meter)
    fi
    if [[ $sqcmd_showcmd -eq 1 ]]; then
        set -x
    fi
    echo "SQCMD: Run storequery header 'x-rgw-storequery$cmdopt' against URI '$uripath'" >&2
    curl "${curl_options[@]}" -H "Accept: application/json" -H "x-rgw-storequery$cmdopt" -o "$out" -- $squrl/"$uripath"
    if [[ $sqcmd_showcmd -eq 1 ]]; then
        set +x
    fi
    # ls -lart $tmpdir
    # od -xc $out
    # jq -C '.' "$out"
    if [[ $sqcurl_out -eq 1 ]]; then
        cat "$out"
    fi
}

export awscmd racmd
