#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Restore the canonical module system/system_ext view before Hybrid Mount scans.
PATH=/system/bin:/system/xbin
export PATH
umask 077
set -f
m=/data/adb/modules/gt8pro.mosey.integrated
[ "$(id -u)" = 0 ] && [ "$(getprop ro.product.model)" = RMX5200 ] && [ "$(getprop ro.build.display.id)" = 'RMX5200_16.0.10.501(CN01)' ] || exit 1
[ ! -L "$m" ] && [ -d "$m" ] || exit 1
for flag in disable remove update skip_mount;do [ ! -e "$m/$flag" ] && [ ! -L "$m/$flag" ] || exit 0;done
[ ! -e "$m/system" ] && [ ! -L "$m/system" ] || exit 0
source=$m/system_ext
[ ! -L "$source" ] && [ -d "$source" ] || exit 1
for pair in 'priv-app/MoseyApp/MoseyApp.apk:8ddb871f9a4df13181de71a89dcbec9f05ff7a2c9c0519f88e5851e6e7765d14' 'etc/permissions/privapp-permissions-com.google.android.mosey.xml:1add90954c70167b5d6fcd3089031aba370c83cfa435bf5728ad1f75834a77dd' 'etc/default-permissions/default-permissions-com.google.android.mosey.xml:b25fbf4d59df5fb794234c473cdb0c36fb4d76d3cd746545e665446b59b93e86';do
 name=${pair%%:*};expected=${pair#*:};file=$source/$name
 [ ! -L "$file" ] && [ -f "$file" ] && [ "$(sha256sum "$file" | cut -d ' ' -f1)" = "$expected" ] || exit 1
done
tmp=$(mktemp -d "$m/.gt8-system.XXXXXX") || exit 1
cleanup(){ [ -z "$tmp" ] || rm -rf "$tmp"; }
trap cleanup 0
mkdir -p "$tmp/system_ext/priv-app/MoseyApp" "$tmp/system_ext/etc/permissions" "$tmp/system_ext/etc/default-permissions" || exit 1
for name in priv-app/MoseyApp/MoseyApp.apk etc/permissions/privapp-permissions-com.google.android.mosey.xml etc/default-permissions/default-permissions-com.google.android.mosey.xml;do
 cp "$source/$name" "$tmp/system_ext/$name" || exit 1
 [ "$(sha256sum "$source/$name" | cut -d ' ' -f1)" = "$(sha256sum "$tmp/system_ext/$name" | cut -d ' ' -f1)" ] || exit 1
done
chmod 0755 "$tmp" "$tmp/system_ext" "$tmp/system_ext/priv-app" "$tmp/system_ext/priv-app/MoseyApp" "$tmp/system_ext/etc" "$tmp/system_ext/etc/permissions" "$tmp/system_ext/etc/default-permissions" || exit 1
chmod 0644 "$tmp/system_ext/priv-app/MoseyApp/MoseyApp.apk" "$tmp/system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml" "$tmp/system_ext/etc/default-permissions/default-permissions-com.google.android.mosey.xml" || exit 1
chcon -R u:object_r:system_file:s0 "$tmp" || exit 1
[ ! -e "$m/system" ] && [ ! -L "$m/system" ] || exit 1
mv "$tmp" "$m/system" || exit 1
tmp=
