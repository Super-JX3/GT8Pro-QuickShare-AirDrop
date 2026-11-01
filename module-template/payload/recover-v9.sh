#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
PATH=/system/bin:/system/xbin
export PATH
umask 077
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] && [ "$(getenforce)" = Enforcing ] || exit 1
r=/data/adb/gt8pro-mosey-service;run=$(cat "$r/current");case "$run" in run.??????) ;;*)exit 1;;esac
d=$r/$run;b=$d/binding-code
[ ! -L "$d" ] && [ "$(stat -c '%u:%a' "$d")" = 0:700 ] || exit 1
w=$r/watch-lock/owner
[ ! -L "$w" ] && [ "$(stat -c '%u:%a' "$w" 2>/dev/null)" = 0:600 ] || exit 1
read wp wt wx <"$w" || exit 1
case "$wp:$wt" in *[!0-9:]*|:*|*:) exit 1;;esac
[ -z "$wx" ] && [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$wp/stat" 2>/dev/null)" != "$wt" ] || exit 1
wr=$d/watcher-owner.record
[ ! -L "$wr" ] && [ "$(stat -c '%u:%a' "$wr" 2>/dev/null)" = 0:600 ] && [ "$(cat "$wr")" = "$wp $wt" ] || exit 1
[ "$(sha256sum "$b/bind-common.sh" | cut -d ' ' -f1)" = c9a1a8f66bedefcfed873f0052a3f9a3006b8157c96bf43b4eb685153da7fe0f ] || exit 1
[ "$(sha256sum "$b/handoff-lock.sh" | cut -d ' ' -f1)" = b30ce8a43d9d6ab7390ff8d221bcb9cd0a03d666a3ac3b4d5dffe91a100ba892 ] || exit 1
. "$b/handoff-lock.sh"
gt8_handoff_lock "$r/mutation.lock" || exit 1
trap 'gt8_handoff_unlock' 0
read ctrl tok extra <"$d/soak-controller.record" || exit 1
case "$ctrl:$tok" in *[!0-9:]*|:*|*:)exit 1;;esac
[ -z "$extra" ] && [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$ctrl/stat" 2>/dev/null)" != "$tok" ] || exit 1
[ "$(cat "$r/session-owner")" = "$run $ctrl $tok" ] && [ ! -e "$r/action-lock" ] && [ -z "$(pidof mosey_server)" ] || exit 1
packages=/data/adb/modules/gt8pro.mosey.integrated/base-app/package-checks.sh
[ ! -L "$packages" ] && [ "$(sha256sum "$packages" | cut -d ' ' -f1)" = 839c474d335817d7eff1354b77d1f65b44681bd59ad193b5b2e143b65ee90183 ] || exit 1
. "$packages"
. "$b/bind-common.sh"
record=$d/binding-app-record.txt
[ ! -L "$record" ] && [ "$(stat -c '%u:%a' "$record" 2>/dev/null)" = 0:600 ] || exit 1
ap=$(awk -F= '$1=="PID"&&$2~/^[0-9]+$/{n++;v=$2}END{if(n==1)print v}' "$record")
at=$(awk -F= '$1=="START_TOKEN"&&$2~/^[0-9]+$/{n++;v=$2}END{if(n==1)print v}' "$record")
case "$ap:$at" in *[!0-9:]*|:*|*:)exit 1;;esac
BIND_PROC_ROOT=/proc
bind_app_identity "$ap" "$at" 10366 || exit 1
[ "$(gt8_mosey_main_pids)" = "$ap" ] || exit 1

for svc in com.google.android.moseyservice.IMoseyService/default com.google.pixel.moseyservice.IMoseyService/default;do
 reply=$(timeout -k 1 3 service check "$svc") || exit 1
 [ "$reply" = "Service $svc: not found" ] || exit 1
done
for i in 1 2 3;do
 a=$( (timeout -k 1 8 dumpsys activity --user 0 service com.google.android.gms/.chimera.PersistentApiServiceNoInstantApps;printf '\n__IDLE_RC=%s\n' "$?") 2>&1 | awk -f "$b/gms-transfer-state.awk") || exit 1
 x=$( (timeout -k 1 8 dumpsys activity --user 0 service com.google.android.mosey/.ExternalSharingService;printf '\n__DUMP_RC=%s\n' "$?") 2>&1 | awk -f "$b/provider-state.awk") || exit 1
 [ "$a" = TRANSFER_CLASS=IDLE ] && [ "$x" = PROVIDER_TRANSFER_CLASS=IDLE_SNAPSHOT ] || exit 1
 [ "$i" = 3 ] || sleep 1
done
[ "$(cat "$r/session-owner")" = "$run $ctrl $tok" ] && [ ! -e "$r/action-lock" ] && bind_app_identity "$ap" "$at" 10366 && [ "$(gt8_mosey_main_pids)" = "$ap" ] || exit 1
timeout -k 1 4 pm disable --user 0 com.google.android.mosey/.ExternalSharingService >/dev/null || exit 1
timeout -k 1 4 am force-stop --user 0 com.google.android.mosey || exit 1
echo STALE_PROVIDER_RECOVERY=REQUESTED
