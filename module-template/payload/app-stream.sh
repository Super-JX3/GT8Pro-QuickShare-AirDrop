#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Retain startup evidence before the global log buffer can evict it.
PATH=/system/bin:/system/xbin
export PATH
umask 077
set -f
OUT=$1
case "$OUT" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) exit 1;;esac
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] && [ ! -L "$OUT" ] && [ "$(stat -c '%u:%a' "$OUT")" = 0:700 ] && [ "$(readlink -f "$OUT")" = "$OUT" ] || exit 1
[ ! -L "$OUT/binding-app-uid.txt" ] && [ "$(stat -c '%u:%a' "$OUT/binding-app-uid.txt")" = 0:600 ] || exit 1
uid=$(cat "$OUT/binding-app-uid.txt")
. "$GT8_BINDDIR/bind-common.sh"
[ "$(gt8_user0_mosey_uid)" = "$uid" ] || exit 1
case "$GT8_SOAK_SECONDS" in 10|70|240|600|1800) ;;*)exit 1;;esac
stream_seconds=$((GT8_SOAK_SECONDS+15))
start=$(date +%s)
case "$start" in ''|*[!0-9]*) exit 1;;esac
(set -C; : >"$OUT/binding-stream.txt") || exit 1
(
 logcat -b main -b system -b crash -v epoch --uid="$uid" -T "$start.000" '*:V' &
 collector=$!
 token=$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$collector/stat" 2>/dev/null)
 case "$token" in ''|*[!0-9]*) wait "$collector"; exit 1;;esac
 (set -C; echo READY >"$OUT/binding-stream-ready.txt") || { kill "$collector" 2>/dev/null; wait "$collector"; exit 1; }
 began=$(awk '{print int($1)}' /proc/uptime)
 case "$began" in ''|*[!0-9]*) kill "$collector" 2>/dev/null; wait "$collector"; exit 1;;esac
 reason=UNEXPECTED
 while :;do
  stat=$(awk 'NR==1{sub(/^.*[)] /,"");print $1, $20}' "/proc/$collector/stat" 2>/dev/null)
  [ "$stat" = "Z $token" ] && break
  case "$stat" in ""|*" $token") ;; *) break;;esac
  [ -n "$stat" ] || break
  now=$(awk '{print int($1)}' /proc/uptime)
  case "$now" in ''|*[!0-9]*) break;;esac
  if [ -f "$OUT/binding-stream-stop.txt" ] && [ ! -L "$OUT/binding-stream-stop.txt" ] && [ "$(cat "$OUT/binding-stream-stop.txt")" = STOP ];then reason=STOP;fi
  [ "$((now-began))" -lt "$stream_seconds" ] || reason=TIMEOUT
  if [ "$reason" != UNEXPECTED ];then
   [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$collector/stat" 2>/dev/null)" = "$token" ] || { reason=UNEXPECTED;break; }
   if kill -TERM "$collector" 2>/dev/null;then
    n=0
    while [ "$n" -lt 3 ];do
     state=$(awk 'NR==1{sub(/^.*[)] /,"");print $1, $20}' "/proc/$collector/stat" 2>/dev/null)
     case "$state" in "Z $token"|"") break;; *" $token") ;; *) reason=UNEXPECTED;break;;esac
     sleep 1;n=$((n+1))
    done
    if [ "$n" = 3 ];then
     [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$collector/stat" 2>/dev/null)" = "$token" ] && kill -KILL "$collector" 2>/dev/null && reason="${reason}_KILL" || reason=UNEXPECTED
    fi
   else reason=UNEXPECTED;fi
   break
  fi
  sleep 1
 done
 wait "$collector"; rc=$?
 (set -C; printf '%s %s\n' "$reason" "$rc" >"$OUT/binding-stream-rc.txt") || exit 1
) 2>&1 | head -c 1048576 >>"$OUT/binding-stream.txt"
read reason rc extra <"$OUT/binding-stream-rc.txt" 2>/dev/null || exit 1
case "$reason:$rc:$extra" in STOP:143:|TIMEOUT:143:|STOP_KILL:137:|TIMEOUT_KILL:137:) ;; *) echo UNCONFIRMED >"$OUT/binding-stream-status.txt";exit 1;;esac
if [ "$(wc -c <"$OUT/binding-stream.txt")" -lt 1048576 ];then
 echo COMPLETED >"$OUT/binding-stream-status.txt"
else
 echo UNCONFIRMED >"$OUT/binding-stream-status.txt"
 exit 1
fi
