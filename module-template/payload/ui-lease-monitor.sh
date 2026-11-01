#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Test-only monitor. No UI input; unknown focus and system pickers keep the lease.
PATH=/system/bin:/system/xbin
export PATH
umask 077
set -f
OUT=$1
parent=$2
token=$3
case "$OUT" in /data/adb/gt8pro-mosey-service/run.??????) ;;*)exit 1;;esac
case "$parent:$token" in *[!0-9:]*|:*|*:)exit 1;;esac
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] && [ ! -L "$OUT" ] && [ "$(stat -c '%u:%a' "$OUT")" = 0:700 ] || exit 1
. "$GT8_BINDDIR/ui-common.sh"
. "$GT8_BINDDIR/handoff-lock.sh"
parent_alive(){ [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$parent/stat" 2>/dev/null)" = "$token" ]; }
closed_safe(){
 (timeout -k 1 3 dumpsys window displays;printf '\n__RC=%s\n' "$?") 2>&1 | awk '
 /^WINDOW MANAGER DISPLAY CONTENTS [(]dumpsys window displays[)]$/{headers++;inside=1;next}
 /^WINDOW MANAGER DISPLAY CONTENTS [(]EXT[)]$/{inside=0;next}
 /^__RC=0$/{rc++;next}
 inside&&/mCurrentFocus=/{focus++;if(!/ u0 [^ ]+\/[^ ]+/)bad=1;if(/com[.]android[.]intentresolver\/|com[.]android[.]documentsui\/|com[.]google[.]android[.]documentsui\/|com[.]coloros[.]filemanager\/com[.]oplus[.]filemanager[.]picker[.]PickerActivity([ }]|$)|com[.]google[.]android[.]gms\/[^ ]*nearby[.]sharing[.]/)protected++}
 END{exit !(headers==1&&rc==1&&focus==1&&!protected&&!bad)}'
}
daily=0
if [ -e "$OUT/daily-module-session" ] || [ -L "$OUT/daily-module-session" ];then
 [ ! -L "$OUT/daily-module-session" ] && [ "$(stat -c '%u:%a' "$OUT/daily-module-session")" = 0:600 ] && [ "$(cat "$OUT/daily-module-session")" = DAILY_V5 ] || exit 1
 daily=1
fi
count=0
(set -C; echo READY >"$OUT/ui-monitor-ready.txt") || exit 1
while parent_alive;do
 [ ! -e "$OUT/ui-monitor-stop.txt" ] || { echo UI_MONITOR=RELEASED;exit 0; }
 if [ "$daily" = 1 ];then
  module=/data/adb/modules/gt8pro.mosey.integrated
  daily_off=0
  [ ! -L "$module" ] && [ -d "$module" ] || daily_off=1
  for flag in disable remove update;do [ ! -e "$module/$flag" ] && [ ! -L "$module/$flag" ] || daily_off=1;done
  if [ "$daily_off" = 1 ];then
   gt8_handoff_begin "$OUT" || { echo UI_MONITOR=OWNER_UNVERIFIED;exit 1; }
   if [ ! -e "$OUT/soak-stop.request" ];then
    (set -C; echo MODULE_DISABLED >"$OUT/ui-stop-reason.txt") && (set -C; echo STOP >"$OUT/soak-stop.request") || { gt8_handoff_unlock;exit 1; }
   fi
   gt8_handoff_unlock
   echo UI_MONITOR=STOP_REQUESTED
   exit 0
  fi
 fi
 state=$(ui_state) || state=UNCONFIRMED
 case "$state" in
  ABSENT|PRESENT_OTHER_TOP) if closed_safe;then count=$((count+1));else count=0;fi;;
  *) count=0;;
 esac
 if [ "$count" -ge 3 ];then
  gt8_handoff_begin "$OUT" || { echo UI_MONITOR=OWNER_UNVERIFIED;exit 1; }
  state=$(ui_state) || state=UNCONFIRMED
  case "$state" in ABSENT|PRESENT_OTHER_TOP) ;; *) gt8_handoff_unlock;count=0;sleep 2;continue;;esac
  if ! closed_safe;then gt8_handoff_unlock;count=0;sleep 2;continue;fi
  if [ ! -e "$OUT/soak-stop.request" ];then
   (set -C; echo UI_CLOSED >"$OUT/ui-stop-reason.txt") && (set -C; echo STOP >"$OUT/soak-stop.request") || { gt8_handoff_unlock;exit 1; }
  fi
  gt8_handoff_unlock
  echo UI_MONITOR=STOP_REQUESTED
  exit 0
 fi
 sleep 2
done
echo UI_MONITOR=PARENT_GONE
exit 1
