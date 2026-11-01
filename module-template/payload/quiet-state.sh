#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
PATH=/system/bin:/system/xbin
export PATH
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] || exit 1
. "$GT8_BINDDIR/quiet-window.sh"
. "$GT8_BINDDIR/handoff-lock.sh"
OUT=${GT8_BINDDIR%/binding-code}

gt8_read_transfer_state(){
 a=$( (timeout -k 1 8 dumpsys activity --user 0 service com.google.android.gms/.chimera.PersistentApiServiceNoInstantApps;printf "\n__IDLE_RC=%s\n" "$?") 2>&1 | awk -f "$GT8_BINDDIR/gms-transfer-state.awk") || { echo UNKNOWN;return 0; }
 b=$( (timeout -k 1 8 dumpsys activity --user 0 service com.google.android.mosey/.ExternalSharingService;printf "\n__DUMP_RC=%s\n" "$?") 2>&1 | awk -f "$GT8_BINDDIR/provider-state.awk") || { echo UNKNOWN;return 0; }
 [ "$a" = TRANSFER_CLASS=IDLE ] && [ "$b" = PROVIDER_TRANSFER_CLASS=IDLE_SNAPSHOT ] && echo IDLE || echo UNKNOWN
}
gt8_quiet_owner(){
 gt8_handoff_begin "$OUT";rc=$?
 case "$rc" in 0) gt8_handoff_unlock;return 0;;2) return 0;;*) return 1;;esac
}
gt8_quiet_sleep(){ sleep 1;gt8_quiet_owner; }
while :;do
 gt8_quiet_owner || { echo QUIET_OWNER=LOST;exit 1; }
 gt8_wait_quiet 300 && exit 0
done
