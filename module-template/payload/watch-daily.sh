#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Candidate only: bounded manual lifecycle trial; not installed on boot.
PATH=/system/bin:/system/xbin
export PATH
umask 077
set -f
case "${1:-probe}" in smoke-once) mode=smoke;once=1;; test-once) mode=probe;once=1;; renew-test) mode=renew-test;once=0;; probe) mode=probe;once=0;; *) exit 1;;esac
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] || exit 1
d=${GT8_RUNTIME_DIR:-}
case "$d" in /data/adb/gt8pro-mosey-daily/runtime-integrated-*) ;; *) exit 1;;esac
name=${d##*/runtime-integrated-}
case "$name" in *[!a-f0-9]*|'') exit 1;;esac
[ "${#name}" = 64 ] && [ "$(readlink -f "$d")" = "$d" ] || exit 1
[ ! -L "$d" ] && [ "$(stat -c '%u:%a' "$d")" = 0:700 ] || exit 1
for pair in 'recover-v9.sh:ca63c55950b1a629a5da0dc76b19da719f48f428fbeb6e31c0fd3e4a53fd9ecf' 'watch-lock.sh:eb10d66c10839e5a5cd5dfbe5a1a952ec4f081484223308f26617b1d51ee2199' 'owner-guard.sh:180a2960f5cc0862ccb6329f92c067612248812f01d23c57641e149dac93bf40' 'watch-policy.sh:b1c9ee10fb33cd5550ec3978f64ecb1873437978da03475f9e3bbdbf89eaf8df' 'ui-common.sh:aa5445b5d5370407cbbc2217c75bc19d320fbc515f4a376fc1658fa8589eee46' 'bind-common.sh:e6a75e680b406e4a18f07ef1e9627e2cc02aeb20046ff44a6b996486d8d3ab7f' 'main.sh:1cfbbcd6e0a1959fd91b4a365ffd5770037ccd8de70d04c0612b7cbba2bdec5e' 'transfer-idle.sh:e156907644bfdaecfd9dbc3e5d5df281d5fe3aeea2a65efd39825c55d3e87db2' 'check-helper.sh:409f3c039abfc5c022192f6ac3fca8612a44389af291caccca6f71809d8b6e7c';do
 f=${pair%%:*};expected=${pair#*:}
 [ ! -L "$d/$f" ] && [ "$(stat -c '%u:%a' "$d/$f")" = 0:600 ] && [ "$(sha256sum "$d/$f" | cut -d ' ' -f1)" = "$expected" ] || exit 1
done
check=$(sh "$d/check-helper.sh") || exit 1
printf '%s\n' "$check" | awk '/^EXTRA_SCOPES=0$/{e++} /^LSPOSED_BRIDGE_STATE (modern|legacy) enabled=1 scopes=2 apkMatches=1$/{s++} END{exit !(e==1&&s==1)}' || exit 1
. "$d/bind-common.sh"
. "$d/ui-common.sh"
. "$d/watch-policy.sh"
. "$d/owner-guard.sh"
. "$d/watch-lock.sh"
# A picker or chooser can temporarily cover the sharing flow. Do not rearm on it.
closed_safe(){
 (timeout -k 1 2 dumpsys window displays;printf '\n__RC=%s\n' "$?") 2>&1 | awk '
 /^WINDOW MANAGER DISPLAY CONTENTS [(]dumpsys window displays[)]$/{headers++;inside=1;next}
 /^WINDOW MANAGER DISPLAY CONTENTS [(]EXT[)]$/{inside=0;next}
 /^__RC=0$/{rc++;next}
 inside&&/^[ ]*Display: mDisplayId=/{displays++;primary=($0~/^[ ]*Display: mDisplayId=0[ ]/);if(primary)primaryCount++;else others[displays]=1;next}
 inside&&/mCurrentFocus=/{if(!displays){bad=1;next}if(primary){focus++;if(!/ u0 [^ ]+\/[^ ]+/)bad=1;if(/com[.]android[.]intentresolver\/|com[.]android[.]documentsui\/|com[.]google[.]android[.]documentsui\/|com[.]coloros[.]filemanager\/com[.]oplus[.]filemanager[.]picker[.]PickerActivity([ }]|$)/)picker++}else{otherFocus[displays]++;if($0!~/^[ ]*mCurrentFocus=null[ ]*$/)bad=1}next}
 inside&&/mFocusedApp=/&&!primary{if(!displays){bad=1;next}otherApp[displays]++;if($0!~/^[ ]*mFocusedApp=null[ ]*$/)bad=1;next}
 END{for(i in others)if(otherFocus[i]!=1||otherApp[i]!=1)bad=1;exit !(headers==1&&rc==1&&primaryCount==1&&focus==1&&!picker&&!bad)}'
}
root=/data/adb/gt8pro-mosey-service
[ ! -L "$root" ] && [ "$(stat -c '%u:%a' "$root")" = 0:700 ] || exit 1
# Only recover a previous lock when every owned service and Binder is absent.
gt8_watch_quiescent(){
 [ ! -e "$root/action-lock" ] && [ -z "$(pidof mosey_server)" ] || return 1
 apps=$(gt8_mosey_main_pids) || return 1
 if [ -n "$apps" ];then
  sh "$d/recover-v9.sh" || return 1
 fi
 apps=$(gt8_mosey_main_pids) || return 1
 [ -z "$apps" ] || return 1
 # Absence of the process alone does not prove the provider is paused.
 (timeout -k 1 4 cmd package query-services --components --user 0 -a com.google.android.nearby.SHARING_PROVIDER -p com.google.android.mosey;printf "\n__QUERY_RC=%s\n" "$?") 2>&1 | awk '
  /^[ ]*No services found[.]?[ ]*$/{n++;next}
  /^__QUERY_RC=0$/{m++;next} NF{bad=1} END{exit !(n==1&&m==1&&!bad)}' || return 1
 for svc in com.google.android.moseyservice.IMoseyService/default com.google.pixel.moseyservice.IMoseyService/default;do
  reply=$(timeout -k 1 3 service check "$svc" 2>&1) || return 1
  [ "$reply" = "Service $svc: not found" ] || return 1
 done
 [ "$(sh "$d/transfer-idle.sh")" = TRANSFER_CLASS=IDLE ]
}
# Reset only a confirmed idle, unbound main-user process started outside a session.
# Fail closed on an ambiguous process, transfer, provider, or service observation.
gt8_prepare_idle_boot_process(){
 apps=$(gt8_mosey_main_pids) || return 1
 [ -n "$apps" ] || return 0
 case "$apps" in *[!0-9]*|'') return 1;;esac
 p=$apps
 profile=$(sh "$d/current-code-profile.sh") || return 1
 printf '%s\n' "$profile" | grep -qx CURRENT_PROFILE_RESULT=PASS || return 1
 uid=$(gt8_user0_mosey_uid) || return 1
 token=$(awk 'NR==1{sub(/^.*[)] /,"");if($20~/^[0-9]+$/)print $20}' "/proc/$p/stat" 2>/dev/null)
 case "$token" in ''|*[!0-9]*) return 1;;esac
 for attempt in 1 2 3;do
  [ "$(ui_state)" = TARGET_TOP ] && [ ! -e "$root/action-lock" ] && [ -z "$(pidof mosey_server)" ] || return 1
  [ "$(gt8_mosey_main_pids)" = "$p" ] && [ "$(gt8_user0_mosey_uid)" = "$uid" ] || return 1
  [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$p/stat" 2>/dev/null)" = "$token" ] || return 1
  tr -d '\000' <"/proc/$p/attr/current" | awk 'NR==1&&/^u:r:mosey_app:s0(:c[0-9]+(,c[0-9]+)*)?$/{ok=1}END{exit !(NR==1&&ok)}' || return 1
  [ "$(sh "$d/transfer-idle.sh")" = TRANSFER_CLASS=IDLE ] || return 1
  query=$(timeout -k 1 4 cmd package query-services --components --user 0 -a com.google.android.nearby.SHARING_PROVIDER -p com.google.android.mosey) || return 1
  [ "$query" = 'No services found' ] || return 1
  for svc in com.google.android.moseyservice.IMoseyService/default com.google.pixel.moseyservice.IMoseyService/default;do
   reply=$(timeout -k 1 3 service check "$svc") || return 1
   [ "$reply" = "Service $svc: not found" ] || return 1
  done
  snapshot=$(timeout -k 1 5 dumpsys activity services com.google.android.mosey/.ExternalSharingService) || return 1
  printf '%s\n' "$snapshot" | gt8_main_services_view | awk '/^ACTIVITY MANAGER SERVICES/{h++} /ServiceRecord\{/{bad=1} /Error:|Permission Denial|Exception dumping/{bad=1} END{exit !(h==1&&!bad)}' || return 1
  [ "$attempt" = 3 ] || sleep 1
 done
 [ "$(gt8_mosey_main_pids)" = "$p" ] && [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$p/stat" 2>/dev/null)" = "$token" ] || return 1
 timeout -k 1 4 am force-stop --user 0 com.google.android.mosey || return 1
 [ -z "$(gt8_mosey_main_pids)" ] || return 1
 echo WATCH_IDLE_BOOT_PROCESS=STOPPED
}
GT8_WATCHER_PID=$$
GT8_WATCHER_TOKEN=$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$$/stat")
export GT8_WATCHER_PID GT8_WATCHER_TOKEN
gt8_owner_alive "$GT8_WATCHER_PID" "$GT8_WATCHER_TOKEN" /proc || exit 1
gt8_watch_lock_acquire "$root" "$GT8_WATCHER_PID" "$GT8_WATCHER_TOKEN" || { echo WATCHER=ALREADY_RUNNING_OR_STALE;exit 1; }
trap 'gt8_watch_lock_release "$root" "$GT8_WATCHER_PID" "$GT8_WATCHER_TOKEN" || :' 0
trap 'exit 1' 1 2 15
phase=ARMED;count=0
while :;do
 if [ "${GT8_DAILY_MODULE:-}" = /data/adb/modules/gt8pro.mosey.integrated ];then
  [ ! -L "$GT8_DAILY_MODULE" ] && [ -d "$GT8_DAILY_MODULE" ] || { echo WATCHER=DISABLED;exit 0; }
  for flag in disable remove update;do [ ! -e "$GT8_DAILY_MODULE/$flag" ] && [ ! -L "$GT8_DAILY_MODULE/$flag" ] || { echo WATCHER=DISABLED;exit 0; };done
 fi
 state=$(ui_state) || state=UNCONFIRMED
 case "$state" in TARGET_TOP) observed=TARGET_TOP;; ABSENT|PRESENT_OTHER_TOP) if closed_safe;then observed=CLOSED_CONFIRMED;else observed=OTHER_OR_UNKNOWN;fi;; *) observed=OTHER_OR_UNKNOWN;;esac
 result=$(gt8_watch_step "$phase" "$count" "$observed") || exit 1
 set -- $result
 [ "$#" = 3 ] || exit 1
 phase=$1;count=$2;action=$3
 case "$action" in
  LAUNCH)
   [ "$(ui_state)" = TARGET_TOP ] && [ "$(sh "$d/transfer-idle.sh")" = TRANSFER_CLASS=IDLE ] || { echo WATCH_ADMISSION=UNCONFIRMED;exit 1; }
   gt8_prepare_idle_boot_process || { echo WATCH_IDLE_BOOT_PROCESS=UNCONFIRMED;exit 1; }
   cmd deviceidle tempwhitelist -u 0 -d 120000 com.google.android.mosey >/dev/null || exit 1
   echo WATCH_SESSION=BEGIN
   sh "$d/main.sh" "$mode"
   rc=$?;printf 'WATCH_SESSION_EXIT=%s\n' "$rc"
   if [ "$rc" != 0 ];then
    completed=$(cat "$root/current" 2>/dev/null)
    case "$completed" in run.??????) ;;*)exit "$rc";;esac
    run_dir=$root/$completed
    [ ! -L "$run_dir" ] && [ "$(stat -c '%u:%a' "$run_dir")" = 0:700 ] || exit "$rc"
    [ "$(cat "$run_dir/watcher-owner.record" 2>/dev/null)" = "$GT8_WATCHER_PID $GT8_WATCHER_TOKEN" ] || exit "$rc"
    case "$(cat "$run_dir/ui-stop-reason.txt" 2>/dev/null)" in UI_CLOSED|MODULE_DISABLED) ;; *) exit "$rc";;esac
    [ "$(cat "$run_dir/ui-monitor-report.txt" 2>/dev/null)" = UI_MONITOR=STOP_REQUESTED ] || exit "$rc"
    [ "$(cat "$run_dir/binding-stream-status.txt" 2>/dev/null)" = COMPLETED ] || exit "$rc"
    [ "$(cat "$run_dir/guard.status" 2>/dev/null)" = STOPPED ] || exit "$rc"
    case "$(cat "$run_dir/guard.reason" 2>/dev/null)" in DRAINED|QUIET_BEST_EFFORT) ;; *) exit "$rc";;esac
    grep -qx 'APP_SERVICE_STOPPED=PASS' "$run_dir/binding-report.txt" || exit "$rc"
    gt8_watch_quiescent || exit "$rc"
    case "$(cat "$run_dir/ui-stop-reason.txt")" in
     UI_CLOSED) echo WATCH_SESSION_END=UI_CLOSED_AND_CLEAN;;
     MODULE_DISABLED) echo WATCH_SESSION_END=MODULE_DISABLED_AND_CLEAN;;
    esac
   fi
   [ "$once" = 0 ] || { echo WATCH_ONCE=COMPLETE;exit 0; }
   # A clean close may complete after the user has reopened the share page.
   # Clean nonzero exits have already passed the ownership and quiescence checks.
   if [ "$(ui_state)" = TARGET_TOP ];then phase=ARMED;count=0;fi;;
  REARM) echo WATCH_REARM=READY;;
  WAIT) ;;
  *) exit 1;;
 esac
 sleep 2
done
