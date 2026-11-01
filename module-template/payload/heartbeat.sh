#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Atomic heartbeat; DRAINED is intentionally unavailable until admission gating is verified.
PATH=/system/bin:/system/xbin
export PATH
umask 077
set -f
[ "$#" = 2 ] || [ "$#" = 3 ] || exit 2
out=$1;state=$2
case "${3:-OUTER}" in OUTER) leaf=transfer-heartbeat;; NATIVE) leaf=native-transfer-heartbeat;; *) exit 2;;esac
case "$out" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) exit 2;;esac
suffix=${out##*/};case "$suffix" in *[!a-zA-Z0-9.]*) exit 2;;esac
case "$state:$leaf" in ACTIVE:*|UNKNOWN:*|QUIET:native-transfer-heartbeat) ;; *) exit 2;;esac
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] || exit 1
[ ! -L "$out" ] && [ "$(stat -c '%u:%a' "$out")" = 0:700 ] || exit 1
if [ -e "$out/$leaf" ] || [ -L "$out/$leaf" ]; then
 [ ! -L "$out/$leaf" ] && [ -f "$out/$leaf" ] && [ "$(stat -c '%u:%a' "$out/$leaf")" = 0:600 ] || exit 1
fi
stamp=$(awk 'NR==1 && $1~/^[0-9]+([.][0-9]+)?$/ {printf "%.0f",$1*1000;ok=1} END{if(!ok)exit 1}' /proc/uptime) || exit 1
case "$stamp" in ''|*[!0-9]*) exit 1;;esac
tmp=$(mktemp "$out/.heartbeat.XXXXXX") || exit 1
trap 'rm -f "$tmp"' 0 1 2 15
[ ! -L "$tmp" ] && [ "$(stat -c '%u:%a' "$tmp")" = 0:600 ] || exit 1
printf '%s %s\n' "$stamp" "$state" >"$tmp" || exit 1
mv -f "$tmp" "$out/$leaf" || exit 1
trap - 0 1 2 15
printf 'HEARTBEAT_WRITE=PASS\n'
