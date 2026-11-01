#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# System application staging only. Does not start daemon, package, or hook.
SKIPUNZIP=0
REPLACE=""
REMOVE=""
export SKIPUNZIP REPLACE REMOVE
[ "$BOOTMODE" = true ] && [ "$KSU" = true ] || abort '! Install in Android with SukiSU/KernelSU.'
MODDIR=$MODPATH
. "$MODDIR/common.sh"
mosey_check_payload install || abort '! Package checksum failed.'
mosey_check_target || abort "! Exact target check failed: $GT8_FAILURE"
for app_dir in /data/adb/modules/* /data/adb/modules_update/*; do
    [ -d "$app_dir" ] || continue
    [ "$app_dir" != "$MODPATH" ] || continue
    case "$app_dir" in
        */gt8pro.mosey.appstage|*/moseyPLK.service|*/mosey-plk110-cn) abort '! Another Mosey app/provider module exists; stop.' ;;
    esac
    for app_rel in system/system_ext/priv-app/MoseyApp/MoseyApp.apk system_ext/priv-app/MoseyApp/MoseyApp.apk system/system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml system/system_ext/etc/default-permissions/default-permissions-com.google.android.mosey.xml system_ext/etc/default-permissions/default-permissions-com.google.android.mosey.xml; do
        [ ! -e "$app_dir/$app_rel" ] && [ ! -L "$app_dir/$app_rel" ] || abort '! Another module supplies overlapping app/config files.'
    done
done
for app_path in /system_ext/priv-app/MoseyApp/MoseyApp.apk /system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml /system_ext/etc/default-permissions/default-permissions-com.google.android.mosey.xml; do
    [ ! -e "$app_path" ] && [ ! -L "$app_path" ] || abort '! Existing system app/config found; no replacement permitted.'
done
app_package=$(timeout -k 1 8 pm path com.google.android.mosey 2>/dev/null)
app_rc=$?
case "$app_rc:$app_package" in 0:|1:) ;; *) abort '! Existing Mosey package or package query failure; stop.' ;; esac
[ -d /data/adb/modules/gt8pro.mosey.servicetest ] || abort '! Keep the 0.3.0 service test installed; this is an independent companion.'
app_pids=$(pidof mosey_server 2>/dev/null)
[ -z "$app_pids" ] || abort '! A Mosey daemon is running; wait for the owned test to finish first.'
for app_flag in disable remove update; do
    [ ! -e "/data/adb/modules/gt8pro.mosey.servicetest/$app_flag" ] || abort '! Companion service test module is inactive or pending changes.'
done
[ -d /data/adb/modules/meta-hybrid ] || [ -d /data/adb/metamodule ] || abort '! No expected mount provider found.'
set_perm_recursive "$MODDIR" 0 0 0755 0644
set_perm_recursive "$MODDIR/system/system_ext" 0 0 0755 0644 u:object_r:system_file:s0
set_perm "$MODDIR/action.sh" 0 0 0755
ui_print '- Original signed Mosey app and scoped permission XML staged.'
ui_print '- Reboot normally, then run this module Action for READ-ONLY readiness checks.'
ui_print '- No native service or GMS hook starts here. GMS may naturally discover the installed app.'
ui_print '- No guarantee of app grants/binding or AirDrop until device testing.'
