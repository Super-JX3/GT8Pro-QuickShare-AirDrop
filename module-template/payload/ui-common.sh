#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# UI metadata only; no screenshot, recipient selection or setting change.
ui_private_ok(){
 case "$OUT" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) return 1;; esac
 [ ! -L "$OUT" ] && [ "$(stat -c '%u:%a' "$OUT")" = 0:700 ] && [ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ]
}
ui_state(){
 local state
 state=$( (
  timeout -k 1 2 dumpsys activity activities
  printf '\n__UI_QUERY_RC=%s\n' "$?"
  timeout -k 1 2 dumpsys window displays
  printf '\n__WIN_QUERY_RC=%s\n' "$?"
 ) 2>&1 | awk '
 function target_kind(line){
  if(line~/ u0 com[.]google[.]android[.]gms[\/](com[.]google[.]android[.]gms[.]|[.])nearby[.]sharing[.](main[.]MainActivity|receive[.]ReceiveActivity)[ }]/)return "classic"
  if(line~/ u0 com[.]google[.]android[.]gms[\/](com[.]google[.]android[.]gms[.]|[.])nearby[.]sharing[.]main[.]SettingsMainActivity[ }]/)return "settings"
  return ""
 }
 /^ACTIVITY MANAGER ACTIVITIES/{headers++}
 /^__UI_QUERY_RC=/{markers++;if($0!~/^__UI_QUERY_RC=[0-9]+$/)bad=1;split($0,r,"=");rc=r[2];next}
 /^WINDOW MANAGER DISPLAY CONTENTS [(]dumpsys window displays[)]$/{windows++;w=1;next}
 /^WINDOW MANAGER DISPLAY CONTENTS [(]EXT[)]$/{w=0;next}
 /^__WIN_QUERY_RC=/{wm++;if($0!="__WIN_QUERY_RC=0")bad=1;next}
 w&&/^[ ]*Display: mDisplayId=/{displays++;display0=($0~/^[ ]*Display: mDisplayId=0[ ]/);if(display0)primary++;else other[displays]=1;next}
 w&&/mCurrentFocus=|mFocusedApp=/ {
  target=target_kind($0)
  if(!displays){bad=1;next}
  if(display0){
   if($0~/mCurrentFocus=/){focus++;tfocus=target}
   if($0~/mFocusedApp=/){app++;tapp=target}
  }else{
   if($0~/mCurrentFocus=/){otherFocus[displays]++;if($0!~/^[ ]*mCurrentFocus=null[ ]*$/)bad=1}
   if($0~/mFocusedApp=/){otherApp[displays]++;if($0!~/^[ ]*mFocusedApp=null[ ]*$/)bad=1}
  }
  next
 }
 !w&&/ActivityRecord\{/ {
  target=target_kind($0)
  if(target=="classic"&&($0~/Hist #[0-9]+:/||$0~/topResumedActivity=|mResumedActivity:/))present=1
  if(target!=""&&$0~/topResumedActivity=|mResumedActivity:/)targettops[target]++
 }
 END{
  for(i in other)if(otherFocus[i]!=1||otherApp[i]!=1)bad=1
  if(headers!=1||markers!=1||windows!=1||wm!=1||bad||rc!=0||primary!=1){print "UNCONFIRMED";exit 1}
  if(focus==1&&app==1&&tfocus==tapp&&targettops[tfocus]>=1)print (tfocus=="settings"?"SETTINGS_TOP":"TARGET_TOP")
  else print (present?"PRESENT_OTHER_TOP":"ABSENT")
 }') || { printf '%s\n' "$state"; return 1; }
 if [ "$state" = SETTINGS_TOP ];then
  state=$(ui_settings_send_state) || { echo UNCONFIRMED; return 1; }
 fi
 printf '%s\n' "$state"
}
# SettingsMainActivity hosts ordinary settings as well as the live send surface.
# GMS exposes the active foreground send registration without UI text or payload.
ui_settings_send_state(){
 (
  timeout -k 1 2 dumpsys activity --user 0 service com.google.android.gms/.chimera.PersistentApiServiceNoInstantApps
  printf '\n__SEND_SURFACE_RC=%s\n' "$?"
 ) 2>&1 | awk '
 function trim(s){sub(/^[[:space:]]+/,"",s);sub(/[[:space:]]+$/,"",s);return s}
 /^SERVICE / {services++;if($2!="com.google.android.gms/.chimera.PersistentApiServiceNoInstantApps"||$NF!="user=0")bad=1;next}
 /^__SEND_SURFACE_RC=/ {markers++;if($0!="__SEND_SURFACE_RC=0")bad=1;next}
 /Permission Denial|Exception dumping|Error dumping|RemoteException|Dump was interrupted/ {bad=1}
 trim($0)=="com.google.android.gms.nearby.sharing.NearbySharingService" {sharing++;inside=1;next}
 !inside {next}
 trim($0)=="Scanning: true" || trim($0)=="Scanning: false" {scan_rows++;scanning=(trim($0)=="Scanning: true");next}
 trim($0)=="Registered Send Surfaces:" {tables++;table=1;next}
 /^[ ]*Fast Init Advertising:/ {if(table)closed++;table=0;inside=0;next}
 table&&NF {
  line=trim($0)
  if(line~/^[+|-]+$/)next
  gsub(/[[:space:]]/,"",line)
  if(line=="|Key|Value|Status|StartTime|EndTime|Duration|"){headers++;next}
  n=split($0,c,"|")
  if(n!=8||trim(c[1])!=""||trim(c[8])!=""||trim(c[2])!~/^[0-9]+$/){bad=1;next}
  if(trim(c[3])=="FOREGROUND"&&trim(c[4])=="ACTIVE")active++
 }
 END{
  if(bad||services!=1||markers!=1||sharing!=1||scan_rows!=1||tables!=1||headers!=1||closed!=1)exit 1
  print (scanning&&active?"TARGET_TOP":"ABSENT")
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
