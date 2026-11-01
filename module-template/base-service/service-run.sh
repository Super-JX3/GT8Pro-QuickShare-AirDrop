#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Deliberately registration-only, not the upstream full-system app integration.
# No init/VINTF/APK/GMS edits; registers one real Binder name temporarily.
MODDIR=${0%/*}
PATH=/system/bin:/system/xbin
LC_ALL=C
export PATH LC_ALL
unset LD_PRELOAD LD_LIBRARY_PATH MOSEY_REGISTRATION_COMPAT
umask 077
set -f
OUT=$1
case "$OUT" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) echo RESULT=SERVICE_STATE_UNVERIFIED; exit 1 ;; esac
[ ! -L "$OUT" ] && [ -d "$OUT" ] && [ "$(stat -c '%u:%a' "$OUT")" = 0:700 ] \
    || { echo RESULT=SERVICE_STATE_UNVERIFIED; exit 1; }
PROC_ROOT=/proc
BIN=/odm/bin/mosey_server
SERVICE_NAME=com.google.android.moseyservice.IMoseyService/default
. "$MODDIR/common.sh"
. "$MODDIR/namespace-common.sh"
. "$MODDIR/service-common.sh"
. "$MODDIR/registration-checks.sh"
sv_finish() { printf 'RESULT=%s\n' "$1"; exit 1; }
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] \
    && [ "$(getenforce)" = Enforcing ] || sv_finish SERVICE_CALLER_UNVERIFIED
gt8_private_mountinfo /proc/self/mountinfo || sv_finish NAMESPACE_PRIVATE_UNVERIFIED
for sv_rel in odm/bin/mosey_server odm/lib64/libmosey_daemon_ffi.so odm/lib64/libmosey_registration_compat.so; do
    sv_expected=$(awk -v p="system/$sv_rel" '$2==p {n++;v=$1}END{if(n==1)print v}' "$MODDIR/payload.sha256")
    [ "${#sv_expected}" = 64 ] && gt8_hash "/$sv_rel" "$sv_expected" || sv_finish SERVICE_PAYLOAD_MISMATCH
    case "$sv_rel:$(ls -Zd "/$sv_rel")" in
        odm/bin/*:u:object_r:mosey_server_exec:s0\ *|odm/lib64/*:u:object_r:vendor_file:s0\ *) ;;
        *) sv_finish SERVICE_LABEL_MISMATCH ;;
    esac
done
sv_existing=$(pidof mosey_server 2>/dev/null)
[ -z "$sv_existing" ] || sv_finish EXISTING_SERVICE_PROCESS
registration_binder before
case "$?" in 1) ;; 0) sv_finish EXISTING_BINDER_SERVICE ;; *) sv_finish BINDER_QUERY_UNVERIFIED ;; esac
# Refuse a pre-existing alternate-vendor instance as well.
SERVICE_NAME=com.google.pixel.moseyservice.IMoseyService/default
registration_binder alternate
case "$?" in 1) ;; 0) sv_finish EXISTING_BINDER_SERVICE ;; *) sv_finish BINDER_QUERY_UNVERIFIED ;; esac
SERVICE_NAME=com.google.android.moseyservice.IMoseyService/default
"$MODDIR/tools/gt8_service_watchdog" probe >"$OUT/pidfd-probe.txt" 2>&1 \
    || sv_finish PIDFD_SELFTEST_FAILED
grep -qx PIDFD_SELFTEST=PASS "$OUT/pidfd-probe.txt" || sv_finish PIDFD_SELFTEST_FAILED
SV_ROOT=/data/adb/gt8pro-mosey-service
if [ -e "$SV_ROOT/current" ] || [ -L "$SV_ROOT/current" ]; then
    [ ! -L "$SV_ROOT/current" ] && [ -f "$SV_ROOT/current" ] \
        && [ "$(stat -c '%u:%a' "$SV_ROOT/current")" = 0:600 ] || sv_finish SERVICE_STATE_UNVERIFIED
    mv "$SV_ROOT/current" "$OUT/previous-current" || sv_finish SERVICE_STATE_UNVERIFIED
fi
(set -C; printf '%s\n' "${OUT##*/}" >"$SV_ROOT/current") || sv_finish SERVICE_STATE_UNVERIFIED
SV_HELPER=
sv_cleanup() {
    sv_rc=$?
    trap - 0 1 2 15
    if [ -n "$SV_HELPER" ]; then
        gt8_service_stop_request || :
        # A helper/guardian owns the pidfd; never kill this numeric PID here.
        wait "$SV_HELPER" 2>/dev/null || :
    fi
    exit "$sv_rc"
}
trap sv_cleanup 0
trap 'exit 1' 1 2 15
"$MODDIR/tools/gt8_service_watchdog" run "${OUT##*/}" >"$OUT/helper-output.txt" 2>&1 &
SV_HELPER=$!
SV_OBSERVED=false
SV_REASON=SERVICE_REGISTRATION_UNCONFIRMED
sv_i=0
while [ "$sv_i" -lt 20 ]; do
    if [ -r "$OUT/watchdog.status" ]; then SV_REASON=SERVICE_EXITED_BEFORE_CONFIRMATION; break; fi
    if gt8_service_record && registration_identity "$SV_PID" "$SV_TOKEN" \
        && registration_shim_success "$OUT/daemon.log" "$SV_PID"; then
        registration_binder observed
        case "$?" in
            0)
                sleep 2
                if registration_identity "$SV_PID" "$SV_TOKEN" \
                    && registration_shim_success "$OUT/daemon.log" "$SV_PID"; then
                    registration_binder confirmed
                    case "$?" in
                        0) SV_OBSERVED=true; break ;;
                        2) SV_REASON=BINDER_QUERY_UNVERIFIED; break ;;
                    esac
                fi ;;
            2) SV_REASON=BINDER_QUERY_UNVERIFIED; break ;;
        esac
    fi
    sv_i=$((sv_i+1))
    sleep 1
done
gt8_service_stop_request || SV_REASON=STOP_REQUEST_FAILED
wait "$SV_HELPER"
SV_HELPER_RC=$?
SV_HELPER=
printf 'WATCHDOG_EXIT_CODE=%s\n' "$SV_HELPER_RC"
if [ "$SV_HELPER_RC" != 0 ] || [ "$(cat "$OUT/watchdog.status" 2>/dev/null)" != STOPPED ] \
    || [ "$(cat "$OUT/guard.status" 2>/dev/null)" != STOPPED ] \
    || ! grep -qx CHILD_REAPED=1 "$OUT/watchdog.details"; then
    sv_finish SERVICE_STOP_UNCONFIRMED
fi
echo SERVICE_STOPPED=PASS
registration_binder stopped
case "$?" in 1) ;; 0) sv_finish BINDER_STILL_PRESENT ;; *) sv_finish BINDER_QUERY_UNVERIFIED ;; esac
sleep 1
registration_binder removed
case "$?" in 1) ;; 0) sv_finish BINDER_STILL_PRESENT ;; *) sv_finish BINDER_QUERY_UNVERIFIED ;; esac
echo BINDER_REMOVED=PASS
[ "$SV_REASON" != STOP_REQUEST_FAILED ] || sv_finish STOP_REQUEST_FAILED
[ "$SV_OBSERVED" = true ] || sv_finish "$SV_REASON"
echo SERVICE_IDENTITY=PASS
echo SHIM_REGISTRATION=PASS
echo BINDER_OBSERVED=PASS
echo RESULT=REGISTRATION_OBSERVED_AND_STOPPED
