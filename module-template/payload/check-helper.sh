#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
PATH=/system/bin:/system/xbin
export PATH
set -f
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] && [ "$(getprop ro.product.model)" = RMX5200 ] && [ "$(getprop ro.build.display.id)" = 'RMX5200_16.0.10.501(CN01)' ] || exit 1
ROOT=/data/adb/gt8pro-mosey-bridge
[ ! -L "$ROOT" ] || exit 1
mkdir -m 0700 -p "$ROOT" || exit 1
[ "$(stat -c '%u:%a' "$ROOT")" = 0:700 ] && [ "$(readlink -f "$ROOT")" = "$ROOT" ] || exit 1
[ ! -L "$ROOT/activation-helper.jar" ] || exit 1
if [ ! -e "$ROOT/activation-helper.jar" ];then
 source=${0%/*}/activation-helper.jar
 [ ! -L "$source" ] || exit 1
 sum=$(sha256sum "$source") || exit 1
 [ "${sum%% *}" = 5d65c5d7c6bd5d608a534ba0df5f30e056b39af57e2c9cb5babf0a637c03ee57 ] || exit 1
 (set -C; cat "$source" >"$ROOT/activation-helper.jar") || exit 1
 chmod 0600 "$ROOT/activation-helper.jar" || exit 1
fi
[ "$(stat -c '%u:%a' "$ROOT/activation-helper.jar")" = 0:600 ] || exit 1
sum=$(sha256sum "$ROOT/activation-helper.jar") || exit 1
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
[ "${sum%% *}" = dd2cc51bbe8738fcb8adc1a6bd81fc08694276610719c65a5ed5f629800707a5 ] || exit 1
CLASSPATH="$ROOT/activation-helper.jar" timeout -k 1 12 /system/bin/app_process /system/bin GT8ProLSPosedSetup --check /data/adb/lspd/config/modules_config.db "$apk"
