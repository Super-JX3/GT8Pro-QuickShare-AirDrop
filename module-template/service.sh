#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Boot entry for one exact firmware and user 0; failure stops the supervisor.
PATH=/system/bin:/system/xbin
export PATH
umask 077
set -f
module=/data/adb/modules/gt8pro.mosey.integrated
root=/data/adb/gt8pro-mosey-daily
d=$root/runtime-integrated-v7
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] && [ "$(getenforce)" = Enforcing ] || exit 1
[ "$(getprop ro.product.model)" = RMX5200 ] && [ "$(getprop ro.build.display.id)" = 'RMX5200_16.0.10.501(CN01)' ] || exit 1
[ ! -L "$module" ] && [ -d "$module" ] && [ ! -L "$module/payload" ] && [ -d "$module/payload" ] || exit 1
for flag in disable remove update;do [ ! -e "$module/$flag" ] && [ ! -L "$module/$flag" ] || exit 0;done
[ ! -L "$module/payload.sha256" ] && [ "$(sha256sum "$module/payload.sha256" | cut -d ' ' -f1)" = f25e06a81c663fc4ed0a3a85cb5d84d8543beed03d500246bde50f5d85d035a6 ] || exit 1
[ ! -L "$root" ] || exit 1
mkdir -m 0700 -p "$root" || exit 1
[ "$(stat -c '%u:%a' "$root")" = 0:700 ] && [ "$(readlink -f "$root")" = "$root" ] || exit 1
lock=$root/bootstrap.lock
[ ! -L "$lock" ] || exit 1
if [ ! -e "$lock" ];then (set -C; : >"$lock") || exit 1;fi
[ -f "$lock" ] && [ "$(stat -c '%u:%a' "$lock")" = 0:600 ] || exit 1
exec 8<>"$lock" || exit 1
flock -x -n 8 8>&8 || exit 0
stage=
cleanup(){ [ -z "$stage" ] || rm -rf "$stage"; }
trap cleanup 0
trap 'exit 1' 1 2 15
verify_dir(){
 verify_root=$1
 [ ! -L "$verify_root" ] && [ "$(stat -c '%u:%a' "$verify_root")" = 0:700 ] && [ "$(readlink -f "$verify_root")" = "$verify_root" ] || return 1
 while read digest name extra;do
  case "$digest" in ''|*[!a-f0-9]*)return 1;;esac
  [ "${#digest}" = 64 ] && [ -z "$extra" ] || return 1
  case "$name" in ''|*[!a-zA-Z0-9_.-]*|.*)return 1;;esac
  f=$verify_root/$name
  [ ! -L "$f" ] && [ -f "$f" ] || return 1
  case "$name" in gt8_service_watchdog_soak|outer-watchdog) perms=0:700;; *) perms=0:600;;esac
  [ "$(stat -c '%u:%a' "$f")" = "$perms" ] && [ "$(sha256sum "$f" | cut -d ' ' -f1)" = "$digest" ] || return 1
 done <"$module/payload.sha256"
}
if [ ! -e "$d" ] && [ ! -L "$d" ];then
 stage=$(mktemp -d "$root/.runtime.XXXXXX") || exit 1
 while read digest name extra;do
  case "$digest" in ''|*[!a-f0-9]*)exit 1;;esac
  [ "${#digest}" = 64 ] && [ -z "$extra" ] || exit 1
  case "$name" in ''|*[!a-zA-Z0-9_.-]*|.*)exit 1;;esac
  source=$module/payload/$name
  [ ! -L "$source" ] && [ -f "$source" ] && [ "$(sha256sum "$source" | cut -d ' ' -f1)" = "$digest" ] || exit 1
  (set -C; cat "$source" >"$stage/$name") || exit 1
  case "$name" in gt8_service_watchdog_soak|outer-watchdog) chmod 0700 "$stage/$name" || exit 1;; *) chmod 0600 "$stage/$name" || exit 1;;esac
 done <"$module/payload.sha256"
 verify_dir "$stage" || exit 1
 mv "$stage" "$d" || exit 1
 stage=
fi
verify_dir "$d" || exit 1
status_tmp=$(mktemp "$root/.status.XXXXXX") || exit 1
printf 'WATCHER=WAITING_FOR_UNLOCK\n' >"$status_tmp" && mv -f "$status_tmp" "$root/status" || exit 1
while :;do
 for flag in disable remove update;do [ ! -e "$module/$flag" ] && [ ! -L "$module/$flag" ] || exit 0;done
 [ ! -L "$module" ] && [ -d "$module" ] || exit 0
 boot=$(getprop sys.boot_completed)
 state=$(timeout -k 1 5 am get-started-user-state 0 2>/dev/null) || state=UNKNOWN
 [ "$boot" = 1 ] && [ "$state" = RUNNING_UNLOCKED ] && break
 sleep 5
done
status_tmp=$(mktemp "$root/.status.XXXXXX") || exit 1
printf 'WATCHER=WAITING_FOR_SHARE\n' >"$status_tmp" && mv -f "$status_tmp" "$root/status" || exit 1
GT8_DAILY_MODULE=$module
export GT8_DAILY_MODULE
# The watcher owns its own lock and never manipulates unrelated user processes.
# Only bounded status codes, not app data or device names, enter Android's log.
# Retry a failed watcher only after verifying that its entire user-0 session
# is absent. Blocked checks do not consume the watcher restart budget.
# A bounded retry cannot establish a transfer admission barrier.
. "$d/bind-common.sh"
retry_quiet(){
 r=/data/adb/gt8pro-mosey-service
 [ ! -e "$r/action-lock" ] && [ ! -e "$r/watch-lock" ] && [ -z "$(pidof mosey_server)" ] || return 1
 apps=$(gt8_mosey_main_pids) || return 1
 [ -z "$apps" ] || return 1
 for svc in com.google.android.moseyservice.IMoseyService/default com.google.pixel.moseyservice.IMoseyService/default;do
  [ "$(timeout -k 1 3 service check "$svc" 2>&1)" = "Service $svc: not found" ] || return 1
 done
 [ "$(timeout -k 1 5 cmd package query-services --components --user 0 -a com.google.android.nearby.SHARING_PROVIDER -p com.google.android.mosey 2>&1)" = 'No services found' ] || return 1
 for sample in 1 2 3;do
  [ "$(sh "$d/transfer-idle.sh")" = TRANSFER_CLASS=IDLE ] || return 1
  [ "$sample" = 3 ] || sleep 1
 done
 [ ! -e "$r/action-lock" ] && [ ! -e "$r/watch-lock" ] && [ -z "$(pidof mosey_server)" ]
}
# After the finite retry budget is exhausted, stay dormant until the share
# flow is confirmed closed and all session state is quiescent. This rearms the
# listener; it does not keep restarting a failing visible share page.
module_enabled(){
 [ -d "$module" ] && [ ! -L "$module" ] || return 1
 for flag in disable remove update;do [ ! -e "$module/$flag" ] && [ ! -L "$module/$flag" ] || return 1;done
}
closed_safe(){
 (timeout -k 1 2 dumpsys window displays;printf '\n__RC=%s\n' "$?") 2>&1 | awk '
 /^WINDOW MANAGER DISPLAY CONTENTS [(]dumpsys window displays[)]$/{headers++;inside=1;next}
 /^WINDOW MANAGER DISPLAY CONTENTS [(]EXT[)]$/{inside=0;next}
 /^__RC=0$/{rc++;next}
 inside&&/mCurrentFocus=/{focus++;if(!/ u0 [^ ]+\/[^ ]+/)bad=1;if(/com[.]android[.]intentresolver\/|com[.]android[.]documentsui\/|com[.]google[.]android[.]documentsui\/|com[.]coloros[.]filemanager\/com[.]oplus[.]filemanager[.]picker[.]PickerActivity([ }]|$)/)picker++}
 END{exit !(headers==1&&rc==1&&focus==1&&!picker&&!bad)}'
}
wait_for_rearm(){
 . "$d/ui-common.sh"
 closed_count=0
 while module_enabled;do
  observed=$(ui_state) || observed=UNCONFIRMED
  case "$observed" in ABSENT|PRESENT_OTHER_TOP) if closed_safe;then closed_count=$((closed_count+1));else closed_count=0;fi;;*)closed_count=0;;esac
  if [ "$closed_count" -ge 3 ];then
   if retry_quiet && module_enabled;then echo WATCH_RETRY=REARMED;return 0;fi
   closed_count=0
  fi
  sleep 5
 done
 return 1
}
(
 retries=0
 while :;do
  sh "$d/watch-daily.sh" probe
  rc=$?
  printf 'WATCH_EXIT=%s\n' "$rc"
  while :;do
   if [ "$retries" -ge 3 ];then
    echo WATCH_RETRY=EXHAUSTED
    wait_for_rearm || exit 0
    retries=0
    break
   fi
   sleep 5
   disabled=0
   for flag in disable remove update;do [ ! -e "$module/$flag" ] && [ ! -L "$module/$flag" ] || disabled=1;done
   [ "$disabled" = 0 ] && [ -d "$module" ] && [ ! -L "$module" ] || exit 0
   if retry_quiet;then
    retries=$((retries+1))
    echo WATCH_RETRY=START
    break
   else
    [ "${blocked_reported:-0}" = 1 ] || echo WATCH_RETRY=BLOCKED
    blocked_reported=1
   fi
  done
  blocked_reported=0
 done
) 2>&1 | while IFS= read -r line;do
 case "$line" in
  WATCH_SESSION=BEGIN|WATCH_SESSION_END=UI_CLOSED_AND_CLEAN|WATCH_SESSION_END=MODULE_DISABLED_AND_CLEAN|WATCH_REARM=READY|WATCHER=DISABLED|WATCH_ADMISSION=UNCONFIRMED|WATCH_RETRY=START|WATCH_RETRY=BLOCKED|WATCH_RETRY=EXHAUSTED|WATCH_RETRY=REARMED|WATCH_EXIT=[0-9]*)
   log -t GT8ProDaily "$line" 2>/dev/null || :
   (set -C; printf '%s\n' "$line" >"$root/.status.$$" && mv -f "$root/.status.$$" "$root/status") || :;;
 esac
done
