#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Explicit user action only; stdout is a freshly generated allowlisted summary.
MODDIR=${0%/*}
PATH=/system/bin:/system/xbin
LC_ALL=C
export PATH LC_ALL
unset LD_PRELOAD LD_LIBRARY_PATH MOSEY_REGISTRATION_COMPAT
umask 077
set -f
printf 'GT8PRO_SERVICE_TEST_REPORT_V1\n'
echo PACKAGE_VERSION=0.3.0
[ "$(id -u)" = 0 ] || { echo RESULT=ROOT_REQUIRED; exit 1; }
[ "$(cat /proc/self/attr/current 2>/dev/null)" = u:r:ksu:s0 ] \
    || { echo RESULT=KSU_CONTEXT_REQUIRED; exit 1; }
for gt8_flag in disable remove update; do
    [ ! -e "$MODDIR/$gt8_flag" ] || { echo RESULT=MODULE_INACTIVE; exit 1; }
done
command -v timeout >/dev/null 2>&1 || { echo RESULT=TIMEOUT_UNAVAILABLE; exit 1; }
GT8_ROOT=/data/adb/gt8pro-mosey-service
[ ! -L "$GT8_ROOT" ] || { echo RESULT=PRIVATE_PATH_UNTRUSTED; exit 1; }
mkdir -m 0700 -p "$GT8_ROOT" || { echo RESULT=PRIVATE_STATE_UNAVAILABLE; exit 1; }
[ -d "$GT8_ROOT" ] && [ "$(stat -c '%u:%a' "$GT8_ROOT" 2>/dev/null)" = 0:700 ] \
    || { echo RESULT=PRIVATE_PATH_UNTRUSTED; exit 1; }
GT8_RUN=$(mktemp -d "$GT8_ROOT/run.XXXXXX") || { echo RESULT=PRIVATE_STATE_UNAVAILABLE; exit 1; }
. "$MODDIR/common.sh"
. "$MODDIR/namespace-common.sh"
. "$MODDIR/service-common.sh"
if ! mosey_check_payload >"$GT8_RUN/payload.txt" 2>&1; then
    echo RESULT=PAYLOAD_CHECK_FAILED
    exit 1
fi
echo PAYLOAD_CHECK=PASS
if ! mosey_check_target >"$GT8_RUN/target.txt" 2>&1; then
    case "$GT8_FAILURE" in
        root|selinux|model|sdk|abi|platform|kernel|firmware|wonder_hash|wlan_hash|binder_hash|checker_missing|policy)
            printf 'FAILED_CHECK=%s\n' "$GT8_FAILURE" ;;
    esac
    echo RESULT=TARGET_CHECK_FAILED
    exit 1
fi
echo TARGET_CHECK=PASS
GT8_BB=/data/adb/ksu/bin/busybox
[ -x "$GT8_BB" ] && [ "$(stat -c '%u:%a' "$GT8_BB")" = 0:755 ] \
    || { echo RESULT=NAMESPACE_TOOLS_UNAVAILABLE; exit 1; }
GT8_PARENT_NS=$(readlink /proc/self/ns/mnt)
gt8_namespace_token "$GT8_PARENT_NS" || { echo RESULT=NAMESPACE_UNVERIFIED; exit 1; }
GT8_PARENT_PID=$$
if ! mkdir -m 0700 "$GT8_ROOT/action-lock" 2>/dev/null; then
    echo RESULT=PROBE_BUSY_OR_STALE_LOCK
    exit 1
fi
trap 'rmdir "$GT8_ROOT/action-lock" 2>/dev/null' 0
trap 'exit 1' 1 2 15
gt8_namespace_parent_view >"$GT8_RUN/parent-before.txt" 2>&1 \
    || { echo RESULT=PARENT_VIEW_UNVERIFIED; exit 1; }
timeout -k 2 150 "$GT8_BB" unshare -m /system/bin/sh "$MODDIR/namespace-service.sh" \
    "$GT8_PARENT_NS" "$GT8_PARENT_PID" "$GT8_RUN" >"$GT8_RUN/probe.txt" 2>&1
gt8_rc=$?
case "$gt8_rc" in ''|*[!0-9]*) gt8_rc=255 ;; esac
printf 'PROBE_EXIT_CODE=%s\n' "$gt8_rc"
if ! gt8_namespace_parent_view >"$GT8_RUN/parent-after.txt" 2>&1 \
    || ! "$GT8_BB" cmp -s "$GT8_RUN/parent-before.txt" "$GT8_RUN/parent-after.txt"; then
    echo PARENT_VIEW=CHANGED_OR_UNCONFIRMED
    echo RESULT=PARENT_VIEW_UNVERIFIED
    echo NEXT_STAGE=WAIT_FOR_REVIEW
    exit 1
fi
echo PARENT_VIEW=UNCHANGED
if [ "$gt8_rc" = 0 ] && gt8_service_report_ok "$GT8_RUN/probe.txt"; then
    echo NAMESPACE_ISOLATION=PASS
    echo PRIVATE_BIND=PASS
    echo NAMESPACE_CLEANUP=PASS
    echo SERVICE_IDENTITY=PASS
    echo SHIM_REGISTRATION=PASS
    echo BINDER_OBSERVED=PASS
    echo SERVICE_STOPPED=PASS
    echo BINDER_REMOVED=PASS
    echo RESULT=REGISTRATION_OBSERVED_AND_STOPPED
else
    echo REGISTRATION_TEST=UNCONFIRMED
    gt8_watch_rc=$(awk -F= '$1=="WATCHDOG_EXIT_CODE" {n++;if(NF==2&&$2~/^[0-9]+$/&&$2<=255)v=$2;else bad=1}END{if(n==1&&!bad)print v}' "$GT8_RUN/probe.txt")
    [ -z "$gt8_watch_rc" ] || printf 'WATCHDOG_EXIT_CODE=%s\n' "$gt8_watch_rc"
    gt8_result=$(sed -n 's/^RESULT=//p' "$GT8_RUN/probe.txt" | tail -n 1)
    case "$gt8_result" in
        '')
            case "$gt8_rc" in
                124|137) echo RESULT=PROBE_TIMEOUT ;;
                *) echo RESULT=NAMESPACE_START_FAILED ;;
            esac ;;
        ROOT_REQUIRED|CALLER_CONTEXT_UNVERIFIED|TIMEOUT_UNAVAILABLE|FILES_NOT_READY|PAYLOAD_MISMATCH|PROBE_LABEL_MISMATCH|LIBRARY_LABEL_MISMATCH|LAUNCHER_LABEL_MISMATCH|BASELINE_FAILED|BASELINE_UNVERIFIED|PRELOAD_BLOCKED_AT_SECURE|PRELOAD_UNCONFIRMED|NAMESPACE_ARGUMENT_INVALID|NAMESPACE_CALLER_INVALID|NAMESPACE_UNVERIFIED|NAMESPACE_PRIVATE_FAILED|NAMESPACE_PRIVATE_UNVERIFIED|PAYLOAD_CHECK_FAILED|SOURCE_PROBE_UNVERIFIED|SOURCE_SERVICE_UNVERIFIED|BIND_TARGET_UNVERIFIED|PRIVATE_BIND_FAILED|PRIVATE_BIND_UNVERIFIED|NAMESPACE_CLEANUP_FAILED|SERVICE_STATE_UNVERIFIED|SERVICE_CALLER_UNVERIFIED|SERVICE_PAYLOAD_MISMATCH|SERVICE_LABEL_MISMATCH|EXISTING_SERVICE_PROCESS|EXISTING_BINDER_SERVICE|BINDER_QUERY_UNVERIFIED|PIDFD_SELFTEST_FAILED|SERVICE_REGISTRATION_UNCONFIRMED|SERVICE_EXITED_BEFORE_CONFIRMATION|STOP_REQUEST_FAILED|SERVICE_STOP_UNCONFIRMED|BINDER_STILL_PRESENT)
            printf 'RESULT=%s\n' "$gt8_result" ;;
        *) echo RESULT=PROBE_FAILED_OR_OUTPUT_UNVERIFIED ;;
    esac
    echo NEXT_STAGE=WAIT_FOR_REVIEW
    exit 1
fi
echo NEXT_STAGE=WAIT_FOR_REVIEW
