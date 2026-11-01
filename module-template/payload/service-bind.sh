#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Deliberately registration-only, not the upstream full-system app integration.
# No init/VINTF/APK/GMS edits; registers one real Binder name temporarily.
MODDIR=/data/adb/modules/gt8pro.mosey.integrated/base-service
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
. "$GT8_BINDDIR/handoff-lock.sh"
locked_service_stop(){
    gt8_handoff_begin "$OUT" || return 1
    gt8_service_stop_request; rc=$?
    gt8_handoff_unlock
    return "$rc"
}
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
"$GT8_BINDDIR/gt8_service_watchdog_soak" probe >"$OUT/pidfd-probe.txt" 2>&1 \
    || sv_finish PIDFD_SELFTEST_FAILED
grep -qx PIDFD_SELFTEST=PASS "$OUT/pidfd-probe.txt" || sv_finish PIDFD_SELFTEST_FAILED
SV_ROOT=/data/adb/gt8pro-mosey-service
gt8_handoff_begin "$OUT" || sv_finish SERVICE_STATE_UNVERIFIED
if [ -e "$SV_ROOT/current" ] || [ -L "$SV_ROOT/current" ]; then
    if [ -L "$SV_ROOT/current" ] || [ ! -f "$SV_ROOT/current" ] || [ "$(stat -c '%u:%a' "$SV_ROOT/current")" != 0:600 ];then gt8_handoff_unlock;sv_finish SERVICE_STATE_UNVERIFIED;fi
    mv "$SV_ROOT/current" "$OUT/previous-current" || { gt8_handoff_unlock;sv_finish SERVICE_STATE_UNVERIFIED; }
fi
(set -C; printf '%s\n' "${OUT##*/}" >"$SV_ROOT/current") || { gt8_handoff_unlock;sv_finish SERVICE_STATE_UNVERIFIED; }
gt8_handoff_unlock
SV_HELPER=
BIND_STREAM=
PROVIDER_GUARD=
PROVIDER_OPEN=false
provider_finish() {
 if [ "$PROVIDER_OPEN" = true ];then
  if sh "$GT8_BINDDIR/provider-control.sh" "$OUT" pause >"$OUT/provider-parent-pause.txt" 2>&1;then
   (set -C; echo PAUSED >"$OUT/provider-pause-done.txt") || return 1
   PROVIDER_OPEN=false
   echo PROVIDER_LEASE_PAUSE=PASS
  else return 1;fi
 fi
 if [ -n "$PROVIDER_GUARD" ];then
  wait "$PROVIDER_GUARD" 2>/dev/null || :
  PROVIDER_GUARD=
  status=$(cat "$OUT/provider-guard-status.txt" 2>/dev/null)
  case "$status" in RELEASED|EXPIRED_PAUSED) echo PROVIDER_LEASE_GUARD=$status;; *) return 1;;esac
 fi
}
stream_finish() {
 if [ -n "$BIND_STREAM" ];then
  (set -C; echo STOP >"$OUT/binding-stream-stop.txt") 2>/dev/null || [ "$(cat "$OUT/binding-stream-stop.txt" 2>/dev/null)" = STOP ] || return 1
  wait "$BIND_STREAM" 2>/dev/null || :
  BIND_STREAM=
  [ "$(cat "$OUT/binding-stream-status.txt" 2>/dev/null)" = COMPLETED ] || return 1
  echo APP_STREAM_GUARD=COMPLETED
 fi
}
sv_cleanup() {
    sv_rc=$?
    : >"$OUT/native-heartbeat-stop"
    trap - 0 1 2 15
    provider_finish || :
    stream_finish || :
    if [ -n "$SV_HELPER" ]; then
        locked_service_stop || :
        # A helper/guardian owns the pidfd; never kill this numeric PID here.
        wait "$SV_HELPER" 2>/dev/null || :
    fi
    exit "$sv_rc"
}
trap sv_cleanup 0
trap 'exit 1' 1 2 15
gt8_handoff_begin "$OUT" || sv_finish SERVICE_STATE_UNVERIFIED
"$GT8_BINDDIR/gt8_service_watchdog_soak" run "${OUT##*/}" >"$OUT/helper-output.txt" 2>&1 &
SV_HELPER=$!
gt8_handoff_unlock
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
if [ "$SV_OBSERVED" = true ]; then
    . "$GT8_BINDDIR/bind-common.sh"
    echo NETWORK_FACTORY_GRANTED=PASS
    # Warm the real receiving broker UI before the app makes its first SDK bind.
    sh "$GT8_BINDDIR/ui-start.sh" "$OUT" >"$OUT/binding-ui-warmup-report.txt" 2>&1 || sv_finish SERVICE_STATE_UNVERIFIED
    setsid sh "$GT8_BINDDIR/app-stream.sh" "$OUT" </dev/null >"$OUT/binding-stream-private.txt" 2>&1 &
    BIND_STREAM=$!
    i=0
    while [ ! -f "$OUT/binding-stream-ready.txt" ] && [ "$i" -lt 20 ];do sleep 0.1;i=$((i+1));done
    [ "$(cat "$OUT/binding-stream-ready.txt" 2>/dev/null)" = READY ] || sv_finish SERVICE_STATE_UNVERIFIED
    sleep 0.1
    [ ! -f "$OUT/binding-stream-status.txt" ] || sv_finish SERVICE_STATE_UNVERIFIED
    setsid sh "$GT8_BINDDIR/provider-guard.sh" "$OUT" </dev/null >"$OUT/provider-guard-private.txt" 2>&1 &
    PROVIDER_GUARD=$!
    i=0
    while [ ! -f "$OUT/provider-guard-ready.txt" ] && [ "$i" -lt 20 ];do sleep 0.1;i=$((i+1));done
    [ "$(cat "$OUT/provider-guard-ready.txt" 2>/dev/null)" = READY ] || sv_finish SERVICE_STATE_UNVERIFIED
    PROVIDER_OPEN=true
    sh "$GT8_BINDDIR/provider-control.sh" "$OUT" enable >"$OUT/provider-enable.txt" 2>&1 || sv_finish SERVICE_STATE_UNVERIFIED
    sh "$GT8_BINDDIR/app-probe.sh" "$OUT" >"$OUT/binding-report.txt" 2>&1
    sv_app_rc=$?
    . "$GT8_BINDDIR/bind-common.sh"
    bind_emit "$OUT/binding-report.txt"
    printf 'APP_CHECK_EXIT_CODE=%s\n' "$sv_app_rc"
    if ! registration_identity "$SV_PID" "$SV_TOKEN"; then
        SV_OBSERVED=false; SV_REASON=SERVICE_REGISTRATION_UNCONFIRMED
    fi
else
    echo APP_TEST=NOT_RUN
fi
provider_finish || sv_finish SERVICE_STOP_UNCONFIRMED
stream_finish || sv_finish SERVICE_STOP_UNCONFIRMED
 : >"$OUT/native-heartbeat-stop"
# Wait for the heartbeat writer to acknowledge the handoff before publishing
# the non-atomic quiet observation. Never publish it on failed cleanup.
i=0
while [ ! -f "$OUT/native-heartbeat-stopped" ] && [ "$i" -lt 100 ];do sleep 0.1;i=$((i+1));done
if [ "$(cat "$OUT/native-heartbeat-stopped" 2>/dev/null)" = STOPPED ] && [ "$(cat "$OUT/quiet-window-observed.txt" 2>/dev/null)" = OBSERVED ];then
 sh "$GT8_BINDDIR/heartbeat.sh" "$OUT" QUIET NATIVE >/dev/null || :
fi
locked_service_stop || SV_REASON=STOP_REQUEST_FAILED
wait "$SV_HELPER"
SV_HELPER_RC=$?
SV_HELPER=
printf 'WATCHDOG_EXIT_CODE=%s\n' "$SV_HELPER_RC"
if [ "$SV_HELPER_RC" != 0 ] || [ "$(cat "$OUT/watchdog.status" 2>/dev/null)" != STOPPED ] \
    || [ "$(cat "$OUT/guard.status" 2>/dev/null)" != STOPPED ] \
    || ! grep -qx CHILD_REAPED=1 "$OUT/watchdog.details"; then
    sv_finish SERVICE_STOP_UNCONFIRMED
fi
case "$(cat "$OUT/guard.reason" 2>/dev/null)" in
 DRAINED) echo SERVICE_STOP_MODE=DRAINED ;;
 QUIET_BEST_EFFORT) echo SERVICE_STOP_MODE=QUIET_BEST_EFFORT ;;
 EMERGENCY) echo SERVICE_STOP_MODE=EMERGENCY;sv_finish SERVICE_STOP_UNCONFIRMED ;;
 *) echo SERVICE_STOP_MODE=UNCONFIRMED;sv_finish SERVICE_STOP_UNCONFIRMED ;;
esac
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
