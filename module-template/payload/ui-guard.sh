#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
PATH=/system/bin:/system/xbin
export PATH
set -f
OUT=$1
. "$GT8_BINDDIR/ui-common.sh"
ui_private_ok || exit 1
case "$GT8_SOAK_SECONDS" in 10|70|240|600|1800) ;;*)exit 1;;esac
limit=$((GT8_SOAK_SECONDS+25));i=0
while [ "$i" -lt "$limit" ];do
 [ ! -e "$OUT/ui-close-done.txt" ] || exit 0
 sleep 1;i=$((i+1))
done
[ ! -e "$OUT/ui-close-done.txt" ] || exit 0
if ui_close;then echo SHARING_UI_GUARD=CLOSED;else echo SHARING_UI_GUARD=UNCONFIRMED;fi
