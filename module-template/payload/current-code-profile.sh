#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
PATH=/system/bin:/system/xbin
export PATH
umask 077
set -f
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] && [ "$(getenforce)" = Enforcing ] || exit 1
root=/data/adb/gt8pro-mosey-daily/runtime-integrated-v7
[ ! -L "$root" ] || exit 1
[ "$(stat -c '%u:%a' "$root")" = 0:700 ] && [ "$(readlink -f "$root")" = "$root" ] || exit 1
jar=$root/profile-helper.jar
[ ! -L "$jar" ] || exit 1
[ "$(stat -c '%u:%a' "$jar")" = 0:600 ] || exit 1
sum=$(sha256sum "$jar") || exit 1
[ "${sum%% *}" = a73ada1aa57ab77c4bb7826261225f17b8ce00387c70ff97704554f612c714a7 ] || exit 1
CLASSPATH="$jar" exec timeout -k 1 6 /system/bin/app_process /system/bin GT8ProMosey60715Profile
