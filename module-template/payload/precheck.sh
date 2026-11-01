#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
PATH=/system/bin:/system/xbin
LC_ALL=C
export PATH LC_ALL
umask 077
set -f
OUT=$1
MODDIR=/data/adb/modules/gt8pro.mosey.integrated/base-app
. "$MODDIR/common.sh"
. "$MODDIR/package-checks.sh"
. "$GT8_BINDDIR/bind-common.sh"
. "$GT8_BINDDIR/updated-package-checks.sh"
fail() { printf 'BIND_PRECHECK=%s\n' "$1"; exit 1; }
bind_out_ok || fail PRIVATE_STATE_UNVERIFIED
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] || fail CALLER_UNVERIFIED
for flag in disable remove update; do [ ! -e "$MODDIR/$flag" ] || fail MODULE_INACTIVE; done
mosey_check_payload >"$OUT/binding-app-payload.txt" 2>&1 || fail APP_PAYLOAD_FAILED
[ "$(timeout -k 1 5 am get-current-user 2>/dev/null)" = 0 ] || fail MAIN_USER_REQUIRED
[ "$(getprop sys.boot_completed)" = 1 ] || fail BOOT_NOT_COMPLETE
command -v setsid >/dev/null 2>&1 || fail GUARD_TOOL_UNAVAILABLE
app_pids=$(pidof system_server 2>/dev/null);set -- $app_pids
[ "$#" = 1 ] || fail SYSTEM_SERVER_UNVERIFIED
app_token=$(app_process_token "/proc/$1");app_system=$1
[ -n "$app_token" ] || fail SYSTEM_SERVER_UNVERIFIED
for view in self 1 "$app_system"; do
    case "$view" in self) prefix= ;; *) prefix=/proc/$view/root ;; esac
    app_mounted_files "$prefix" || fail APP_MOUNT_UNVERIFIED
done
bind_capture "$OUT/binding-pre-package.txt" 8 dumpsys package "$BIND_PACKAGE" || fail PACKAGE_QUERY_FAILED
bind_capture "$OUT/binding-current-code-profile.txt" 8 sh "$GT8_BINDDIR/current-code-profile.sh" || fail APP_IDENTITY_UNVERIFIED
updated_code_profile_ok "$OUT/binding-current-code-profile.txt" && app_package_check_updated "$OUT/binding-pre-package.txt" || fail APP_IDENTITY_UNVERIFIED
BIND_UID=$(bind_app_uid "$OUT/binding-pre-package.txt") || fail APP_UID_UNVERIFIED
bind_core_permissions "$OUT/binding-pre-package.txt" || fail CORE_PRIVILEGES_MISSING
app_permissions_check "$OUT/binding-pre-package.txt" runtime >/dev/null || fail RUNTIME_PERMISSIONS_MISSING
bind_capture "$OUT/binding-pre-provider.txt" 8 cmd package query-services --components --query-flags 512 --user 0 -a com.google.android.nearby.SHARING_PROVIDER -p "$BIND_PACKAGE" || fail PROVIDER_QUERY_FAILED
app_provider_check "$OUT/binding-pre-provider.txt" || fail PROVIDER_UNVERIFIED
sh "$GT8_BINDDIR/transfer-idle.sh" >/dev/null 2>&1 || fail APP_STATE_QUERY_FAILED
bind_network_factory_granted "$OUT/binding-pre-package.txt" || fail CORE_PRIVILEGES_MISSING
app_existing=$(gt8_mosey_main_pids) || fail APP_ALREADY_RUNNING
[ -z "$app_existing" ] || fail APP_ALREADY_RUNNING
bind_capture "$OUT/binding-before.txt" 5 dumpsys activity services "$BIND_COMPONENT" || fail APP_STATE_QUERY_FAILED
bind_services_absent "$OUT/binding-before.txt" || fail APP_SERVICE_ALREADY_PRESENT
[ "$(pidof system_server 2>/dev/null)" = "$app_system" ] && [ "$(app_process_token "/proc/$app_system")" = "$app_token" ] || fail SYSTEM_SERVER_CHANGED
(set -C; printf '%s\n' "$BIND_UID" >"$OUT/binding-app-uid.txt") || fail PRIVATE_STATE_FAILED
echo CORE_PRIVILEGES=PASS
echo RUNTIME_PERMISSIONS=PASS
echo NETWORK_PERMISSION_GAP=UNRESOLVED
echo NETWORK_FACTORY_GRANTED=PASS
echo BIND_PRECHECK=PASS
