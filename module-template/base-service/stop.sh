#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Requests stop through a root-private marker; no PID/name based signalling.
MODDIR=${0%/*}
PATH=/system/bin:/system/xbin
LC_ALL=C
export PATH LC_ALL
unset LD_PRELOAD LD_LIBRARY_PATH MOSEY_REGISTRATION_COMPAT
umask 077
set -f
echo GT8PRO_SERVICE_STOP_REPORT_V1
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] \
    || { echo RESULT=CALLER_UNVERIFIED; exit 1; }
. "$MODDIR/common.sh"
mosey_check_payload >/dev/null 2>&1 || { echo RESULT=PAYLOAD_CHECK_FAILED; exit 1; }
if "$MODDIR/tools/gt8_service_watchdog" stop >/dev/null 2>&1; then
    echo RESULT=STOP_REQUEST_RECORDED
    echo NOTE=WAIT_FOR_ACTION_STOP_CONFIRMATION
else
    echo RESULT=STOP_REQUEST_UNCONFIRMED
    exit 1
fi
