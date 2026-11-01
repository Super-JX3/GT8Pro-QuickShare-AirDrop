#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# UI metadata only; no screenshot, recipient selection or setting change.
ui_private_ok(){
 case "$OUT" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) return 1;; esac
 [ ! -L "$OUT" ] && [ "$(stat -c '%u:%a' "$OUT")" = 0:700 ] && [ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ]
}
ui_state(){
 (
  timeout -k 1 2 dumpsys activity activities
  printf '\n__UI_QUERY_RC=%s\n' "$?"
  timeout -k 1 2 dumpsys window displays
  printf '\n__WIN_QUERY_RC=%s\n' "$?"
 ) 2>&1 | awk '
 /^ACTIVITY MANAGER ACTIVITIES/{headers++}
 /^__UI_QUERY_RC=/{markers++;if($0!~/^__UI_QUERY_RC=[0-9]+$/)bad=1;split($0,r,"=");rc=r[2];next}
 /^WINDOW MANAGER DISPLAY CONTENTS [(]dumpsys window displays[)]$/{windows++;w=1;next}
 /^WINDOW MANAGER DISPLAY CONTENTS [(]EXT[)]$/{w=0;next}
 /^__WIN_QUERY_RC=/{wm++;if($0!="__WIN_QUERY_RC=0")bad=1;next}
 w&&/^[ ]*Display: mDisplayId=/{displays++;display0=($0~/^[ ]*Display: mDisplayId=0[ ]/);if(!display0)bad=1;next}
 w&&/mCurrentFocus=|mFocusedApp=/ {
  target=($0~/ u0 com[.]google[.]android[.]gms[\/](com[.]google[.]android[.]gms[.]|[.])nearby[.]sharing[.](main[.]MainActivity|receive[.]ReceiveActivity)[ }]/)
  if($0~/mCurrentFocus=/){focus++;if(display0&&target)tfocus++}
  if($0~/mFocusedApp=/){app++;if(display0&&target)tapp++}
  next
 }
 !w&&/ActivityRecord\{/ {
  target=($0~/ u0 com[.]google[.]android[.]gms[\/](com[.]google[.]android[.]gms[.]|[.])nearby[.]sharing[.](main[.]MainActivity|receive[.]ReceiveActivity) /)
  if(target&&($0~/Hist #[0-9]+:/||$0~/topResumedActivity=|mResumedActivity:/))present=1
  if(target&&$0~/topResumedActivity=|mResumedActivity:/)targettops++
 }
 END{
  if(headers!=1||markers!=1||windows!=1||wm!=1||bad||rc!=0||displays!=1){print "UNCONFIRMED";exit 1}
  if(!present)print "ABSENT"
  else if(targettops>=1&&focus==1&&tfocus==1&&app==1&&tapp==1)print "TARGET_TOP"
  else print "PRESENT_OTHER_TOP"
 }'
}
ui_close(){
 ui_private_ok || return 1
 i=0
 while [ "$i" -lt 3 ];do
  state=$(ui_state) || return 1
  if [ "$state" = ABSENT ];then
   [ -e "$OUT/ui-close-done.txt" ] || (set -C; echo CLOSED >"$OUT/ui-close-done.txt")
   return 0
  fi
  [ "$state" = TARGET_TOP ] || return 1
  timeout -k 1 2 input keyevent KEYCODE_BACK >/dev/null 2>&1 || return 1
  sleep 0.2
  i=$((i+1))
 done
 [ "$(ui_state)" = ABSENT ] || return 1
 [ -e "$OUT/ui-close-done.txt" ] || (set -C; echo CLOSED >"$OUT/ui-close-done.txt")
}
