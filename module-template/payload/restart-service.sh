#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Invoked only by the local bridge after the user taps restart.
PATH=/system/bin:/system/xbin
export PATH
umask 077
set -f
[ "$#" = 1 ] && [ "$1" = reclaim ] || { echo MODULE_UNAVAILABLE; exit 1; }
m=/data/adb/modules/gt8pro.mosey.integrated
root=/data/adb/gt8pro-mosey-service
manifest=$m/payload.sha256
[ ! -L "$manifest" ] && [ -f "$manifest" ] || { echo MODULE_UNAVAILABLE; exit 1; }
sum=$(sha256sum "$manifest") || exit 1
sum=${sum%% *}
case "$sum" in *[!a-f0-9]*|'') exit 1;;esac
[ "${#sum}" = 64 ] || exit 1
d=/data/adb/gt8pro-mosey-daily/runtime-integrated-$sum
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] && [ "$(getenforce)" = Enforcing ] || { echo MODULE_UNAVAILABLE; exit 1; }
[ ! -L "$m" ] && [ -d "$m" ] && [ ! -e "$m/disable" ] && [ ! -e "$m/remove" ] && [ ! -e "$m/update" ] || { echo MODULE_UNAVAILABLE; exit 1; }
[ ! -L "$d" ] && [ "$(stat -c '%u:%a' "$d")" = 0:700 ] && [ "$(readlink -f "$d")" = "$d" ] || { echo MODULE_UNAVAILABLE;exit 1; }
for pair in 'transfer-idle.sh:e156907644bfdaecfd9dbc3e5d5df281d5fe3aeea2a65efd39825c55d3e87db2' 'bind-common.sh:e6a75e680b406e4a18f07ef1e9627e2cc02aeb20046ff44a6b996486d8d3ab7f' 'recover-v9.sh:ca63c55950b1a629a5da0dc76b19da719f48f428fbeb6e31c0fd3e4a53fd9ecf';do
 n=${pair%%:*}; expected=${pair#*:}; f=$d/$n
 [ ! -L "$f" ] && [ "$(stat -c '%u:%a' "$f")" = 0:600 ] && [ "$(sha256sum "$f" | cut -d ' ' -f1)" = "$expected" ] || exit 1
done
# A visible transfer may start between observations. These checks cannot provide
# an admission barrier, so do not stop any active session here.
for i in 1 2 3; do
 [ "$(sh "$d/transfer-idle.sh")" = TRANSFER_CLASS=IDLE ] || { echo TRANSFER_BUSY;exit 1; }
 sleep 1
done
for i in 1 2 3 4 5 6 7 8 9 10;do
 [ ! -e "$root/action-lock" ] && [ -z "$(pidof mosey_server)" ] && break
 sleep 1
done
[ ! -e "$root/action-lock" ] && [ -z "$(pidof mosey_server)" ] || { echo SERVICE_ACTIVE;exit 1; }
# A boot-created Mosey process need not belong to an old watcher. The daily
# watcher validates and adopts or safely resets it on the next share page.
# Do not force-stop an unowned process here.
[ "$(sh "$d/transfer-idle.sh")" = TRANSFER_CLASS=IDLE ] || { echo TRANSFER_BUSY;exit 1; }
# The caller explicitly confirms that ending the current Wi-Fi Direct group may
# disconnect another device. Never remove saved groups or toggle Wi-Fi.
p2p_state() {
 (timeout -k 1 4 dumpsys wifip2p; printf '\n__P2P_RC=%s\n' "$?") 2>/dev/null | awk '
 /^mWifiP2pInfo groupFormed: (true|false) / {n++; if ($3=="true") state="ACTIVE"; else if ($3=="false") state="IDLE"; else bad=1; next}
 /^__P2P_RC=0$/ {ok++; next}
 END {if(n==1&&ok==1&&!bad) print state; else exit 1}'
}
state=$(p2p_state) || { echo P2P_RELEASE_FAILED;exit 1; }
if [ "$state" = ACTIVE ];then
 [ "$(sh "$d/transfer-idle.sh")" = TRANSFER_CLASS=IDLE ] || { echo TRANSFER_BUSY;exit 1; }
 timeout -k 1 5 cmd wifip2p init >/dev/null 2>&1 || { echo P2P_RELEASE_FAILED;exit 1; }
 timeout -k 1 8 cmd wifip2p remove-group >/dev/null 2>&1
 result=$?
 timeout -k 1 5 cmd wifip2p deinit >/dev/null 2>&1 || result=1
 [ "$result" = 0 ] || { echo P2P_RELEASE_FAILED;exit 1; }
 released=false
 for i in 1 2 3 4 5 6 7 8;do
  if [ "$(p2p_state)" = IDLE ];then released=true;break;fi
  sleep 1
 done
 [ "$released" = true ] || { echo P2P_RELEASE_FAILED;exit 1; }
fi
[ "$(sh "$d/transfer-idle.sh")" = TRANSFER_CLASS=IDLE ] || { echo TRANSFER_BUSY;exit 1; }
[ "$(cmd package query-services --components --user 0 -a com.google.android.nearby.SHARING_PROVIDER -p com.google.android.mosey)" = 'No services found' ] || exit 1
for s in com.google.android.moseyservice.IMoseyService/default com.google.pixel.moseyservice.IMoseyService/default;do
 [ "$(timeout -k 1 3 service check "$s")" = "Service $s: not found" ] || exit 1
done
echo RESTART_READY
