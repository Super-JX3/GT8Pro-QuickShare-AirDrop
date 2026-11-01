#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Manual-only private namespace, two fixed binds, then a finite real registration.
MODDIR=/data/adb/modules/gt8pro.mosey.integrated/base-service
PATH=/system/bin:/system/xbin
LC_ALL=C
export PATH LC_ALL
unset LD_PRELOAD LD_LIBRARY_PATH MOSEY_REGISTRATION_COMPAT
umask 077
set -f
GT8_BB=/data/adb/ksu/bin/busybox
. "$MODDIR/common.sh"
. "$MODDIR/namespace-common.sh"
. "$MODDIR/service-common.sh"
. "$GT8_BINDDIR/label-bind.sh"
GT8_LABEL_BOUND=
gt8_ns_finish() { printf 'RESULT=%s\n' "$1"; exit 1; }
[ "$#" = 3 ] || gt8_ns_finish NAMESPACE_ARGUMENT_INVALID
GT8_PARENT_NS=$1
GT8_PARENT_PID=$2
OUT=$3
case "$GT8_PARENT_PID" in ''|*[!0-9]*) gt8_ns_finish NAMESPACE_ARGUMENT_INVALID ;; esac
case "$OUT" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) gt8_ns_finish SERVICE_STATE_UNVERIFIED ;; esac
[ ! -L "$OUT" ] && [ -d "$OUT" ] && [ "$(stat -c '%u:%a' "$OUT")" = 0:700 ] \
    && [ "$(readlink -f "$OUT")" = "$OUT" ] || gt8_ns_finish SERVICE_STATE_UNVERIFIED
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] \
    && [ "$(getenforce)" = Enforcing ] || gt8_ns_finish NAMESPACE_CALLER_INVALID
GT8_CHILD_NS=$(readlink /proc/self/ns/mnt) || gt8_ns_finish NAMESPACE_UNVERIFIED
gt8_ns_isolated() {
    [ "$(readlink "/proc/$GT8_PARENT_PID/ns/mnt")" = "$GT8_PARENT_NS" ] \
        && [ "$(readlink /proc/self/ns/mnt)" = "$GT8_CHILD_NS" ] \
        && gt8_namespace_separate "$GT8_CHILD_NS" "$GT8_PARENT_NS"
}
gt8_ns_isolated || gt8_ns_finish NAMESPACE_UNVERIFIED
"$GT8_BB" mount -n --make-rprivate / || gt8_ns_finish NAMESPACE_PRIVATE_FAILED
gt8_ns_isolated && gt8_private_mountinfo /proc/self/mountinfo \
    || gt8_ns_finish NAMESPACE_PRIVATE_UNVERIFIED
echo NAMESPACE_ISOLATION=PASS
mosey_check_payload || gt8_ns_finish PAYLOAD_CHECK_FAILED
gt8_service_exact_source mosey_load_probe || gt8_ns_finish SOURCE_PROBE_UNVERIFIED
GT8_SOURCE_PROBE=$GT8_SERVICE_SOURCE
gt8_service_exact_source mosey_server || gt8_ns_finish SOURCE_SERVICE_UNVERIFIED
GT8_SOURCE_SERVER=$GT8_SERVICE_SOURCE
gt8_ns_target() {
    [ -f "$1" ] && [ ! -L "$1" ] && [ "$(readlink -f "$1")" = "$1" ] && gt8_hash "$1" "$2"
}
gt8_ns_target /odm/bin/mosey_load_probe f736d6e9048ed0d80c3211fed3d2d159c347a017d5666be6104472596fb8ed9d \
    && gt8_ns_target /odm/bin/mosey_server 53aa112866da41f32de05efd91730a27f0f1a40a79ebe61be95bd8d1944a0326 \
    || gt8_ns_finish BIND_TARGET_UNVERIFIED
gt8_ns_fingerprint() { stat -c '%d:%i' "$1" && ls -Zd "$1"; }
GT8_PROBE_BEFORE=$(gt8_ns_fingerprint /odm/bin/mosey_load_probe) || gt8_ns_finish BIND_TARGET_UNVERIFIED
GT8_SERVER_BEFORE=$(gt8_ns_fingerprint /odm/bin/mosey_server) || gt8_ns_finish BIND_TARGET_UNVERIFIED
GT8_BOUND_PROBE=false
GT8_BOUND_SERVER=false
gt8_ns_cleanup() {
    gt8_cleanup_rc=$?
    trap - 0 1 2 15
    gt8_clean=true
    gt8_label_cleanup_all || gt8_clean=false
    if [ "$GT8_BOUND_SERVER" = true ]; then
        if ! { gt8_ns_isolated && gt8_private_mountinfo /proc/self/mountinfo \
            && "$GT8_BB" umount /odm/bin/mosey_server \
            && [ "$(gt8_ns_fingerprint /odm/bin/mosey_server)" = "$GT8_SERVER_BEFORE" ]; }; then gt8_clean=false; fi
    fi
    if [ "$GT8_BOUND_PROBE" = true ]; then
        if ! { gt8_ns_isolated && gt8_private_mountinfo /proc/self/mountinfo \
            && "$GT8_BB" umount /odm/bin/mosey_load_probe \
            && [ "$(gt8_ns_fingerprint /odm/bin/mosey_load_probe)" = "$GT8_PROBE_BEFORE" ]; }; then gt8_clean=false; fi
    fi
    if [ "$gt8_clean" = true ] && gt8_ns_isolated && gt8_private_mountinfo /proc/self/mountinfo; then
        echo NAMESPACE_CLEANUP=PASS
    else
        echo RESULT=NAMESPACE_CLEANUP_FAILED
        gt8_cleanup_rc=1
    fi
    exit "$gt8_cleanup_rc"
}
trap gt8_ns_cleanup 0
trap 'exit 1' 1 2 15
for gt8_binary in mosey_load_probe mosey_server; do
    case "$gt8_binary" in mosey_load_probe) gt8_source=$GT8_SOURCE_PROBE ;; mosey_server) gt8_source=$GT8_SOURCE_SERVER ;; esac
    gt8_ns_isolated && gt8_private_mountinfo /proc/self/mountinfo \
        || gt8_ns_finish NAMESPACE_PRIVATE_UNVERIFIED
    "$GT8_BB" mount -n -o bind "$gt8_source" "/odm/bin/$gt8_binary" || gt8_ns_finish PRIVATE_BIND_FAILED
    case "$gt8_binary" in mosey_load_probe) GT8_BOUND_PROBE=true ;; mosey_server) GT8_BOUND_SERVER=true ;; esac
    gt8_ns_isolated && gt8_private_mountinfo /proc/self/mountinfo \
        || gt8_ns_finish NAMESPACE_PRIVATE_UNVERIFIED
    [ "$(stat -c '%d:%i' "$gt8_source")" = "$(stat -c '%d:%i' "/odm/bin/$gt8_binary")" ] \
        || gt8_ns_finish PRIVATE_BIND_UNVERIFIED
    case "$(ls -Zd "/odm/bin/$gt8_binary")" in u:object_r:mosey_server_exec:s0\ *) ;; *) gt8_ns_finish SERVICE_LABEL_MISMATCH ;; esac
done
gt8_label_bind_all || gt8_ns_finish LABEL_VIEW_UNVERIFIED
echo PRIVATE_BIND=PASS
sh "$MODDIR/load-probe.sh" action || exit $?
sh "$GT8_BINDDIR/service-bind.sh" "$OUT"
exit $?
