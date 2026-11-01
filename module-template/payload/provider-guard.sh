#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Bounded provider lease with parent liveness checks and short temporary allowance renewal.
PATH=/system/bin:/system/xbin
export PATH
set -f
OUT=$1
case "$OUT" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) exit 1;;esac
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] && [ ! -L "$OUT" ] && [ "$(stat -c '%u:%a' "$OUT")" = 0:700 ] || exit 1
trap '' 1 2 15
start=$(awk '{print int($1)}' /proc/uptime)
case "$start" in ''|*[!0-9]*) exit 1;;esac
(set -C; echo READY >"$OUT/provider-guard-ready.txt") || exit 1
case "$GT8_SOAK_SECONDS" in 10|70|240|600|1800) ;;*)exit 1;;esac
limit=$((GT8_SOAK_SECONDS+40))
. "$GT8_BINDDIR/lease-gate.sh"
. "$GT8_BINDDIR/handoff-lock.sh"

read controller token extra <"$OUT/soak-controller.record" || exit 1
[ -z "$extra" ] || exit 1
case "$controller:$token" in *[!0-9:]*|:*|*:) exit 1;;esac
next_refresh=0
reason=EMERGENCY
while :;do
 if [ -f "$OUT/provider-pause-done.txt" ] && [ "$(cat "$OUT/provider-pause-done.txt")" = PAUSED ];then
  echo RELEASED >"$OUT/provider-guard-status.txt";exit 0
 fi
 now=$(awk '{print int($1)}' /proc/uptime)
 case "$now" in ''|*[!0-9]*) break;;esac
 [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$controller/stat" 2>/dev/null)" = "$token" ] || break
 if [ "$((now-start))" -ge "$limit" ];then
  ms=$(awk 'NR==1{printf "%.0f",$1*1000}' /proc/uptime)
  gate=$(gt8_lease_gate "$OUT" "$ms") || gate=EMERGENCY
  case "$gate" in HOLD) ;; DRAINED) reason=DRAINED;break;; *) break;; esac
 fi
 if [ "$now" -ge "$next_refresh" ];then
  if timeout -k 1 4 cmd deviceidle tempwhitelist -u 0 -d 120000 com.google.android.mosey >/dev/null 2>&1;then
   next_refresh=$((now+45))
   printf 'TEMP_ALLOWANCE_REFRESH=PASS\n' >>"$OUT/allowance-refresh.txt"
  else
   printf 'TEMP_ALLOWANCE_REFRESH=FAILED\n' >>"$OUT/allowance-refresh.txt"
   break
  fi
 fi
 sleep 1
done
printf '%s\n' "$reason" >"$OUT/provider-guard-reason.txt"
# Always stop this run's pidfd-owned native child when the independent lease expires.
gt8_handoff_begin "$OUT" || { echo OWNER_UNVERIFIED >"$OUT/provider-guard-status.txt";exit 1; }
/data/adb/modules/gt8pro.mosey.integrated/base-service/tools/gt8_service_watchdog stop >"$OUT/soak-emergency-native-stop.txt" 2>&1 || :
gt8_handoff_unlock
if sh "$GT8_BINDDIR/provider-control.sh" "$OUT" pause >"$OUT/provider-guard-pause.txt" 2>&1;then
 echo EXPIRED_PAUSED >"$OUT/provider-guard-status.txt"
else
 echo PAUSE_UNCONFIRMED >"$OUT/provider-guard-status.txt"
 exit 1
fi
