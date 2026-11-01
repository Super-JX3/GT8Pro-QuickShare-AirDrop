#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Natural app startup only; deliberately no hook or declaration/permission bypass.
PATH=/system/bin:/system/xbin
LC_ALL=C
export PATH LC_ALL
umask 077
set -f
OUT=$1
case "$OUT" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) exit 1 ;; esac
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] || exit 1
. /data/adb/modules/gt8pro.mosey.integrated/base-app/package-checks.sh
. "$GT8_BINDDIR/bind-common.sh"
. "$GT8_BINDDIR/ui-common.sh"
. "$GT8_BINDDIR/handoff-lock.sh"

bind_out_ok || exit 1
BIND_PROC_ROOT=/proc
BIND_UID=$(cat "$OUT/binding-app-uid.txt")
case "$BIND_UID" in ''|*[!0-9]*) echo APP_TEST=UID_UNVERIFIED;exit 1 ;; esac
BIND_GUARD=
UI_MONITOR=
stop_ui_monitor(){
 if [ -n "$UI_MONITOR" ];then
  (set -C; echo STOP >"$OUT/ui-monitor-stop.txt") 2>/dev/null || :
  wait "$UI_MONITOR" 2>/dev/null || :
  UI_MONITOR=
 fi
}
DELEGATE_PID=
DELEGATE_TOKEN=
stop_delegate(){
 [ -n "$DELEGATE_PID" ] || return 0
 (set -C; echo STOP >"$OUT/delegate-stop.request") 2>/dev/null || :
 n=0
 while [ "$n" -lt 15 ] && [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$DELEGATE_PID/stat" 2>/dev/null)" = "$DELEGATE_TOKEN" ];do sleep 1;n=$((n+1));done
 if [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$DELEGATE_PID/stat" 2>/dev/null)" = "$DELEGATE_TOKEN" ];then
  echo DELEGATE_PARENT=SIDECAR_NOT_STOPPED
  return 1
 fi
 wait "$DELEGATE_PID" 2>/dev/null || :
 if [ -e "$OUT/delegate-owner.record" ];then
  if sh "$GT8_BINDDIR/delegate-runner.sh" "$OUT" "$$" "$DELEGATE_PARENT_TOKEN" recover >>"$OUT/delegate-parent-report.txt" 2>&1;then
   echo DELEGATE_PARENT=CLEAN
  else echo DELEGATE_PARENT=CLEANUP_UNCONFIRMED;return 1;fi
 fi
 DELEGATE_PID=
 return 0
}
start_delegate(){
 DELEGATE_PARENT_TOKEN=$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$$/stat")
 case "$DELEGATE_PARENT_TOKEN" in ''|*[!0-9]*) return 1;;esac
 delegate_limit=$((GT8_SOAK_SECONDS+90));[ "$delegate_limit" -le 1800 ] || delegate_limit=1800
 sh "$GT8_BINDDIR/delegate-runner.sh" "$OUT" "$$" "$DELEGATE_PARENT_TOKEN" "$delegate_limit" >"$OUT/delegate-sidecar-report.txt" 2>&1 &
 DELEGATE_PID=$!
 DELEGATE_TOKEN=$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$DELEGATE_PID/stat")
 case "$DELEGATE_TOKEN" in ''|*[!0-9]*) return 1;;esac
 (set -C; printf '%s %s\n' "$DELEGATE_PID" "$DELEGATE_TOKEN" >"$OUT/delegate-runner.record") || return 1
 n=0
 while [ "$n" -lt 10 ];do
  grep -qx 'DELEGATE=ACTIVE' "$OUT/delegate-sidecar-report.txt" && { echo DELEGATE_PARENT=ACTIVE;return 0; }
  [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$DELEGATE_PID/stat" 2>/dev/null)" = "$DELEGATE_TOKEN" ] || break
  sleep 1;n=$((n+1))
 done
 echo DELEGATE_PARENT=START_UNCONFIRMED
 stop_delegate || :
 return 1
}
BIND_CLEAN=false
cleanup() {
    cleanup_rc=$?
    trap - 0 1 2 15
    stop_ui_monitor
    stop_delegate || :
    if [ "$BIND_CLEAN" != true ] && [ -f "$OUT/binding-launch-attempt.txt" ]; then
        if gt8_handoff_begin "$OUT";then
            bind_capture "$OUT/binding-emergency-stop.txt" 6 am stop-service --user 0 -n "$BIND_COMPONENT" || :
            gt8_handoff_unlock
        fi
    fi
    if [ -n "$BIND_GUARD" ]; then wait "$BIND_GUARD" 2>/dev/null || :; fi
    exit "$cleanup_rc"
}
trap cleanup 0
trap 'exit 1' 1 2 15
app_existing=$(gt8_mosey_main_pids) || exit 1
BIND_PREEXISTING=false
if [ -n "$app_existing" ];then
    if [ ! -f "$OUT/binding-existing.txt" ];then
        set -- $app_existing
        [ "$#" = 1 ] || exit 1
        existing_pid=$1;existing_token=$(app_process_token "/proc/$1")
        bind_app_identity "$existing_pid" "$existing_token" "$BIND_UID" && bind_capture "$OUT/binding-live-before.txt" 5 dumpsys activity services "$BIND_COMPONENT" && bind_services_gms_owned "$OUT/binding-live-before.txt" || exit 1
        (set -C; printf '%s %s\n' "$existing_pid" "$existing_token" >"$OUT/binding-existing.txt") || exit 1
    fi
    read existing_pid existing_token existing_extra <"$OUT/binding-existing.txt" || exit 1
    [ -z "$existing_extra" ] && [ "$app_existing" = "$existing_pid" ] && bind_app_identity "$existing_pid" "$existing_token" "$BIND_UID" || { echo APP_TEST=ALREADY_RUNNING;exit 1; }
    BIND_PREEXISTING=true
fi
setsid sh "$GT8_BINDDIR/app-guard.sh" "$OUT" </dev/null >"$OUT/binding-guard-private.txt" 2>&1 &
BIND_GUARD=$!
i=0
while [ ! -f "$OUT/binding-guard-ready.txt" ] && [ "$i" -lt 20 ]; do sleep 0.1;i=$((i+1));done
[ "$(cat "$OUT/binding-guard-ready.txt" 2>/dev/null)" = READY ] || { echo APP_TEST=GUARD_UNAVAILABLE;exit 1; }
if [ ! -L "$OUT/provider-enable-epoch.txt" ] && [ "$(stat -c '%u:%a' "$OUT/provider-enable-epoch.txt")" = 0:600 ];then
    BIND_SINCE=$(awk 'NR==1&&/^[0-9]+$/{v=$0;next}{bad=1}END{if(NR==1&&!bad)print v;else exit 1}' "$OUT/provider-enable-epoch.txt") || exit 1
else exit 1;fi
case "$BIND_SINCE" in ''|*[!0-9]*) echo APP_TEST=CLOCK_UNVERIFIED;exit 1 ;; esac
BIND_LAUNCH=false
if [ "$BIND_PREEXISTING" = true ];then
    BIND_LAUNCH=true
    echo APP_LAUNCH=NOT_NEEDED_GMS_BOUND
else
    gt8_handoff_begin "$OUT" || { echo APP_START=OWNER_UNVERIFIED;exit 1; }
    if (set -C; echo ATTEMPT >"$OUT/binding-launch-attempt.txt") && bind_capture "$OUT/binding-start.txt" 8 am start-service --user 0 -n "$BIND_COMPONENT" -a com.google.android.nearby.SHARING_PROVIDER && bind_start_accepted "$OUT/binding-start.txt";then BIND_LAUNCH=true;fi
    gt8_handoff_unlock
    if [ "$BIND_LAUNCH" = true ];then echo APP_LAUNCH=PASS;else echo APP_LAUNCH=UNCONFIRMED;fi
fi
BIND_IDENTITY=false
BIND_LOG=UNCONFIRMED
BIND_CAPTURE=NOT_ATTEMPTED
BIND_AFTER=false
BIND_FATAL=UNCONFIRMED
i=0
app_pids=$(gt8_mosey_main_pids) || exit 1
while [ -z "$app_pids" ] && [ "$BIND_LAUNCH" = true ] && [ "$i" -lt 20 ]; do
    sleep 0.1;i=$((i+1));app_pids=$(gt8_mosey_main_pids) || exit 1
done
set -- $app_pids
if [ "$BIND_LAUNCH" = true ] && [ "$#" = 1 ]; then
    BIND_PID=$1
    BIND_TOKEN=$(app_process_token "$BIND_PROC_ROOT/$BIND_PID")
    if bind_app_identity "$BIND_PID" "$BIND_TOKEN" "$BIND_UID"; then
        BIND_IDENTITY=true
        (set -C; printf 'PID=%s\nSTART_TOKEN=%s\nUID=%s\nSINCE=%s\n' "$BIND_PID" "$BIND_TOKEN" "$BIND_UID" "$BIND_SINCE" >"$OUT/binding-app-record.txt") || exit 1
        if [ -f "$OUT/binding-ui-warmup-report.txt" ];then
            [ "$(ui_state)" = TARGET_TOP ] || exit 1
            bind_emit "$OUT/binding-ui-warmup-report.txt"
        elif ! sh "$GT8_BINDDIR/ui-start.sh" "$OUT";then exit 1;fi
        monitor_token=$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$$/stat")
        case "$monitor_token" in ''|*[!0-9]*) exit 1;;esac
        sh "$GT8_BINDDIR/ui-lease-monitor.sh" "$OUT" "$$" "$monitor_token" >"$OUT/ui-monitor-report.txt" 2>&1 &
        UI_MONITOR=$!
        i=0
        while [ ! -f "$OUT/ui-monitor-ready.txt" ] && [ "$i" -lt 20 ];do sleep 0.1;i=$((i+1));done
        [ "$(cat "$OUT/ui-monitor-ready.txt" 2>/dev/null)" = READY ] || exit 1
        case "$GT8_SOAK_SECONDS" in 10|70|240|600|1800) ;;*)exit 1;;esac
        start_delegate || echo DELEGATE_PARENT=UNAVAILABLE
        . "$GT8_BINDDIR/soak-metrics.sh"
        soak_start=$(awk '{print int($1)}' /proc/uptime);last_sample=-15;soak_ok=true
        if ! soak_prepare;then soak_ok=false;fi
        while [ "$soak_ok" = true ];do
            now=$(awk '{print int($1)}' /proc/uptime);soak_elapsed=$((now-soak_start))
            if [ "$((soak_elapsed-last_sample))" -ge 15 ] || [ "$soak_elapsed" -ge "$GT8_SOAK_SECONDS" ];then
                if ! soak_sample;then echo SOAK_ABORT_REASON=IDENTITY_OR_METRICS_UNCONFIRMED;soak_ok=false;break;fi
                last_sample=$soak_elapsed
            fi
            [ "$soak_elapsed" -lt "$GT8_SOAK_SECONDS" ] || break
            [ ! -e "$OUT/soak-stop.request" ] || { echo SOAK_ABORT_REASON=STOP_REQUESTED;soak_ok=false;break; }
            sleep 1
        done
        stop_ui_monitor
        echo SOAK_MEASURED_SECONDS=$soak_elapsed
        if [ "$soak_ok" = true ] && [ "$soak_elapsed" -ge "$GT8_SOAK_SECONDS" ];then echo SOAK_RESULT=PASS;else echo SOAK_RESULT=UNCONFIRMED;fi
        if bind_app_identity "$BIND_PID" "$BIND_TOKEN" "$BIND_UID"; then
            BIND_CAPTURE=FAILED
            if [ ! -L "$OUT/binding-stream.txt" ] && [ "$(stat -c '%u:%a' "$OUT/binding-stream.txt")" = 0:600 ] && [ "$(wc -c <"$OUT/binding-stream.txt")" -lt 1048576 ] && bind_capture "$OUT/binding-log.txt" 5 cat "$OUT/binding-stream.txt"; then
            BIND_UNTIL=$(date +%s)
            case "$BIND_UNTIL" in ''|*[!0-9]*) BIND_UNTIL=0 ;; esac
            if [ "$BIND_UNTIL" -ge "$BIND_SINCE" ] && [ "$((BIND_UNTIL-BIND_SINCE))" -le "$((GT8_SOAK_SECONDS+36))" ] && [ "$(wc -l <"$OUT/binding-log.txt")" -lt 16384 ]; then
                BIND_LOG=$(bind_log_classify "$OUT/binding-log.txt" "$BIND_PID" "$BIND_SINCE" "$((BIND_UNTIL+1))")
                if bind_observation_classify "$OUT/binding-log.txt" "$BIND_PID" "$BIND_SINCE" "$((BIND_UNTIL+1))" >"$OUT/binding-observation.txt"; then
                    BIND_CAPTURE=CAPTURED
                    BIND_FATAL=$(awk -F= '$1=="APP_FATAL_LOG"&&NF==2{print $2}' "$OUT/binding-observation.txt")
                    bind_emit "$OUT/binding-observation.txt"
                fi
            else
                BIND_CAPTURE=WINDOW_UNVERIFIED
            fi
            fi
        fi
        if bind_app_identity "$BIND_PID" "$BIND_TOKEN" "$BIND_UID"; then BIND_AFTER=true;fi
    fi
fi
if [ "$BIND_IDENTITY" = true ]; then echo APP_PROCESS_IDENTITY=PASS;else echo APP_PROCESS_IDENTITY=UNCONFIRMED;fi
case "$BIND_LOG" in VERSION_OBSERVED|NULL_OBSERVED|UNCONFIRMED) ;; *) BIND_LOG=UNCONFIRMED ;; esac
printf 'APP_BINDER_LOG=%s\n' "$BIND_LOG"
printf 'APP_LOG_CAPTURE=%s\n' "$BIND_CAPTURE"
if [ "$BIND_AFTER" = true ]; then echo APP_IDENTITY_AFTER_CAPTURE=PASS;else echo APP_IDENTITY_AFTER_CAPTURE=UNCONFIRMED;fi
# Test-only, best-effort snapshots; this is not an admission barrier.
sh "$GT8_BINDDIR/quiet-state.sh" >"$OUT/quiet-state-private.txt" 2>&1 || exit 1
(set -C; echo OBSERVED >"$OUT/quiet-window-observed.txt") || exit 1
echo QUIET_WINDOW=OBSERVED
stop_delegate || { echo DELEGATE_PARENT=STOP_UNCONFIRMED;exit 1; }
echo SHARING_UI_PRESERVED=PASS
if [ "$BIND_PREEXISTING" = true ];then
    if bind_app_identity "$BIND_PID" "$BIND_TOKEN" "$BIND_UID" && bind_capture "$OUT/binding-owned-after.txt" 5 dumpsys activity services "$BIND_COMPONENT" && bind_services_gms_owned "$OUT/binding-owned-after.txt";then BIND_CLEAN=true;fi
else
# End the test's existing provider lease before confirming our started service stops.
# This also releases a GMS bind established after our explicit start.
if sh "$GT8_BINDDIR/provider-control.sh" "$OUT" pause >"$OUT/provider-app-cleanup.txt" 2>&1;then
 echo APP_PROVIDER_PAUSE_BEFORE_STOP=PASS
else echo APP_PROVIDER_PAUSE_BEFORE_STOP=UNCONFIRMED;exit 1;fi
gt8_handoff_begin "$OUT" || { echo APP_STOP=OWNER_UNVERIFIED;exit 1; }
bind_capture "$OUT/binding-stop.txt" 6 am stop-service --user 0 -n "$BIND_COMPONENT" || :
gt8_handoff_unlock
if bind_capture "$OUT/binding-after1.txt" 5 dumpsys activity services "$BIND_COMPONENT" \
    && bind_services_absent "$OUT/binding-after1.txt"; then
    sleep 1
    if bind_capture "$OUT/binding-after2.txt" 5 dumpsys activity services "$BIND_COMPONENT" \
        && bind_services_absent "$OUT/binding-after2.txt"; then BIND_CLEAN=true;fi
fi
fi
if [ "$BIND_CLEAN" = true ]; then
    (set -C; echo RELEASE >"$OUT/binding-guard-release.txt") || exit 1
fi
wait "$BIND_GUARD" 2>/dev/null || :
BIND_GUARD=
guard_status=$(cat "$OUT/binding-guard-status.txt" 2>/dev/null)
case "$guard_status" in RELEASED|REQUESTED) printf 'APP_GUARD=%s\n' "$guard_status" ;; *) echo APP_GUARD=UNCONFIRMED;BIND_CLEAN=false ;; esac
if [ "$BIND_CLEAN" = true ]; then
    if [ "$BIND_PREEXISTING" = true ];then echo APP_SERVICE_STOPPED=NOT_OWNED_GMS_BOUND;else echo APP_SERVICE_STOPPED=PASS;fi;else echo APP_SERVICE_STOPPED=UNCONFIRMED;echo APP_TEST=STOP_UNCONFIRMED;exit 1;fi
if [ "$BIND_LAUNCH" = true ] && [ "$BIND_IDENTITY" = true ] && [ "$BIND_AFTER" = true ] \
    && [ "$soak_ok" = true ] && [ "$soak_elapsed" -ge "$GT8_SOAK_SECONDS" ] \
    && [ "$BIND_FATAL" = NOT_SEEN ] && [ "$BIND_LOG" = VERSION_OBSERVED ]; then
    if [ "$BIND_PREEXISTING" = true ];then echo APP_TEST=VERSION_OBSERVED_SERVICE_GMS_OWNED;else echo APP_TEST=VERSION_OBSERVED_AND_SERVICE_STOPPED;fi;exit 0
fi
echo APP_TEST=BINDING_UNCONFIRMED
exit 1
