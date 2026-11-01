#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Independent, fixed-component stop request; no process-name or PID killing.
PATH=/system/bin:/system/xbin
LC_ALL=C
export PATH LC_ALL
umask 077
set -f
OUT=$1
case "$OUT" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) exit 1 ;; esac
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] || exit 1
. "$GT8_BINDDIR/bind-common.sh"
. "$GT8_BINDDIR/handoff-lock.sh"

bind_out_ok || exit 1
trap '' 1 2 15
start=$(awk '{print int($1)}' /proc/uptime)
case "$start" in ''|*[!0-9]*) exit 1 ;; esac
(set -C; echo READY >"$OUT/binding-guard-ready.txt") || exit 1
case "$GT8_SOAK_SECONDS" in 10|70|240|600|1800) ;;*)exit 1;;esac
limit=$((GT8_SOAK_SECONDS+30))
. "$GT8_BINDDIR/lease-gate.sh"
read controller token extra <"$OUT/soak-controller.record" || exit 1
case "$controller:$token" in *[!0-9:]*|:*|*:) exit 1;;esac
[ -z "$extra" ] || exit 1
reason=EMERGENCY
while :; do
    if [ -f "$OUT/binding-guard-release.txt" ] && [ "$(cat "$OUT/binding-guard-release.txt")" = RELEASE ]; then
        echo RELEASED >"$OUT/binding-guard-status.txt";exit 0
    fi
    now=$(awk '{print int($1)}' /proc/uptime)
    case "$now" in ''|*[!0-9]*) break ;; esac
    [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$controller/stat" 2>/dev/null)" = "$token" ] || break
    if [ "$((now-start))" -ge "$limit" ]; then
      ms=$(awk 'NR==1{printf "%.0f",$1*1000}' /proc/uptime)
      gate=$(gt8_lease_gate "$OUT" "$ms") || gate=EMERGENCY
      case "$gate" in HOLD) ;; DRAINED) reason=DRAINED;break;; *) break;; esac
    fi
    sleep 1
done
printf '%s\n' "$reason" >"$OUT/binding-guard-reason.txt"
if [ -f "$OUT/binding-launch-attempt.txt" ]; then
    gt8_handoff_begin "$OUT" || { echo OWNER_UNVERIFIED >"$OUT/binding-guard-status.txt";exit 1; }
    trap 'gt8_handoff_unlock' 0
    bind_capture "$OUT/binding-guard-stop.txt" 6 am stop-service --user 0 -n "$BIND_COMPONENT"
    # AOSP16 may return 255 even for "Service stopped". This is only a request;
    # parent requires two separate service-absence snapshots, not this code.
    echo REQUESTED >"$OUT/binding-guard-status.txt"
else
    echo NOT_STARTED >"$OUT/binding-guard-status.txt"
fi
