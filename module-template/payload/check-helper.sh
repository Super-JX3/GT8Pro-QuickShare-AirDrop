#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
PATH=/system/bin:/system/xbin
export PATH
set -f
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] && [ "$(getprop ro.product.model)" = RMX5200 ] && [ "$(getprop ro.build.display.id)" = 'RMX5200_16.0.10.501(CN01)' ] || exit 1
# The supervisor stages this private runtime directory by payload digest.
runtime=${0%/*}
[ -d "$runtime" ] && [ ! -L "$runtime" ] && [ "$(readlink -f "$runtime")" = "$runtime" ] || exit 1
[ "$(stat -c '%u:%a' "$runtime")" = 0:700 ] || exit 1
helper=$runtime/activation-helper.jar
[ -f "$helper" ] && [ ! -L "$helper" ] && [ "$(stat -c '%u:%a' "$helper")" = 0:600 ] || exit 1
sum=$(sha256sum "$helper") || exit 1
[ "${sum%% *}" = 5d65c5d7c6bd5d608a534ba0df5f30e056b39af57e2c9cb5babf0a637c03ee57 ] || exit 1
apk=$( (
 timeout -k 1 5 pm path --user 0 local.gt8pro.moseybridge
 rc=$?
 printf '\n__APK_PATH_RC=%s\n' "$rc"
) 2>&1 | awk '
 /^__APK_PATH_RC=/{markers++;split($0,r,"=");rc=r[2];next}
 index($0,"package:/data/app/")==1{
  p=substr($0,9);t=p;gsub("/","",t)
  if(t!~/^[a-zA-Z0-9_.+~=-]+$/||substr(p,length(p)-8)!="/base.apk")bad=1
  n++;v=p;next
 }
 NF{bad=1}
 END{if(markers==1&&rc==0&&n==1&&!bad)print v;else exit 1}') || exit 1

sum=$(sha256sum "$apk") || exit 1
[ "${sum%% *}" = 35735e517e07adc668cfa580ae70af873b2c6b9a7ba86570316b85a80cc7c3c3 ] || exit 1
CLASSPATH="$helper" timeout -k 1 12 /system/bin/app_process /system/bin GT8ProLSPosedSetup --check /data/adb/lspd/config/modules_config.db "$apk"
