#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Invoked only by the local bridge after the user taps restart.
PATH=/system/bin:/system/xbin
export PATH
umask 077
set -f
m=/data/adb/modules/gt8pro.mosey.integrated
root=/data/adb/gt8pro-mosey-service
d=/data/adb/gt8pro-mosey-daily/runtime-integrated-v9
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
. "$d/bind-common.sh"
apps=$(gt8_mosey_main_pids) || exit 1
if [ -n "$apps" ];then sh "$d/recover-v9.sh" supervisor || exit 1;fi
[ -z "$(gt8_mosey_main_pids)" ] || exit 1
[ "$(sh "$d/transfer-idle.sh")" = TRANSFER_CLASS=IDLE ] || { echo TRANSFER_BUSY;exit 1; }
[ "$(cmd package query-services --components --user 0 -a com.google.android.nearby.SHARING_PROVIDER -p com.google.android.mosey)" = 'No services found' ] || exit 1
for s in com.google.android.moseyservice.IMoseyService/default com.google.pixel.moseyservice.IMoseyService/default;do
 [ "$(timeout -k 1 3 service check "$s")" = "Service $s: not found" ] || exit 1
done
echo RESTART_READY
