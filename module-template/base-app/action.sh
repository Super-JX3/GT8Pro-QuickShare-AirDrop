#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Read-only app/permission/view checks; private output files are the only writes.
MODDIR=${0%/*}
PATH=/system/bin:/system/xbin
LC_ALL=C
export PATH LC_ALL
unset LD_PRELOAD LD_LIBRARY_PATH MOSEY_REGISTRATION_COMPAT
umask 077
set -f
echo GT8PRO_APP_READINESS_REPORT_V1
echo PACKAGE_VERSION=0.4.0
app_finish() { printf 'RESULT=%s\nNEXT_STAGE=WAIT_FOR_REVIEW\n' "$1"; exit "${2:-1}"; }
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current 2>/dev/null)" = u:r:ksu:s0 ] || app_finish ROOT_OR_CONTEXT_REQUIRED
for app_flag in disable remove update; do [ ! -e "$MODDIR/$app_flag" ] || app_finish MODULE_INACTIVE; done
command -v timeout >/dev/null 2>&1 || app_finish TIMEOUT_UNAVAILABLE
APP_ROOT=/data/adb/gt8pro-mosey-appstage
[ ! -L "$APP_ROOT" ] || app_finish PRIVATE_PATH_UNTRUSTED
mkdir -m 0700 -p "$APP_ROOT" || app_finish PRIVATE_STATE_UNAVAILABLE
[ "$(stat -c '%u:%a' "$APP_ROOT" 2>/dev/null)" = 0:700 ] || app_finish PRIVATE_PATH_UNTRUSTED
OUT=$(mktemp -d "$APP_ROOT/run.XXXXXX") || app_finish PRIVATE_STATE_UNAVAILABLE
. "$MODDIR/common.sh"
. "$MODDIR/package-checks.sh"
mosey_check_payload >"$OUT/payload.txt" 2>&1 || app_finish PAYLOAD_CHECK_FAILED
echo PAYLOAD_CHECK=PASS
mosey_check_target >"$OUT/target.txt" 2>&1 || app_finish TARGET_CHECK_FAILED
echo TARGET_CHECK=PASS
[ "$(getprop sys.boot_completed)" = 1 ] || app_finish BOOT_NOT_COMPLETE
[ "$(timeout -k 1 5 am get-current-user 2>/dev/null)" = 0 ] || app_finish MAIN_USER_REQUIRED
app_system_pids=$(pidof system_server 2>/dev/null)
set -- $app_system_pids
[ "$#" = 1 ] || app_finish SYSTEM_SERVER_UNVERIFIED
APP_SYSTEM_PID=$1
case "$APP_SYSTEM_PID" in ''|*[!0-9]*) app_finish SYSTEM_SERVER_UNVERIFIED ;; esac
APP_SYSTEM_TOKEN=$(app_process_token "/proc/$APP_SYSTEM_PID")
[ -n "$APP_SYSTEM_TOKEN" ] || app_finish SYSTEM_SERVER_UNVERIFIED
for app_view in self 1 "$APP_SYSTEM_PID"; do
    case "$app_view" in self) app_prefix= ;; *) app_prefix=/proc/$app_view/root ;; esac
    app_mounted_files "$app_prefix" || app_finish APP_MOUNT_VIEW_UNVERIFIED
done
echo APP_MOUNT_VIEWS=PASS
timeout -k 1 8 pm path --user 0 com.google.android.mosey >"$OUT/package-path.txt" 2>&1 || app_finish PACKAGE_QUERY_FAILED
app_paths=$(cat "$OUT/package-path.txt")
case "$app_paths" in
    package:/system_ext/priv-app/MoseyApp/MoseyApp.apk|package:/system/system_ext/priv-app/MoseyApp/MoseyApp.apk) ;;
    *) app_finish ACTIVE_APK_PATH_UNVERIFIED ;;
esac
gt8_hash "${app_paths#package:}" "$(awk '$2=="system/system_ext/priv-app/MoseyApp/MoseyApp.apk" {print $1}' "$MODDIR/payload.sha256")" || app_finish ACTIVE_APK_HASH_UNVERIFIED
echo ACTIVE_APK=PASS
timeout -k 1 8 dumpsys package com.google.android.mosey >"$OUT/package.txt" 2>&1 || app_finish PACKAGE_QUERY_FAILED
app_package_check "$OUT/package.txt" || app_finish SYSTEM_PRIVAPP_UNVERIFIED
echo SYSTEM_PRIVAPP=PASS
app_install_count=$(app_permissions_check "$OUT/package.txt" install); app_install_rc=$?
app_runtime_count=$(app_permissions_check "$OUT/package.txt" runtime); app_runtime_rc=$?
case "$app_install_count:$app_runtime_count" in [0-7]:[0-6]) ;; *) app_finish PERMISSION_QUERY_UNVERIFIED ;; esac
printf 'PRIVILEGED_GRANTED=%s/7\nRUNTIME_GRANTED=%s/6\n' "$app_install_count" "$app_runtime_count"
[ "$app_install_rc" = 0 ] || app_finish PRIVILEGED_PERMISSIONS_INCOMPLETE
[ "$app_runtime_rc" = 0 ] || app_finish RUNTIME_PERMISSIONS_INCOMPLETE
timeout -k 1 8 cmd package query-services --components --user 0 -a com.google.android.nearby.SHARING_PROVIDER -p com.google.android.mosey >"$OUT/provider.txt" 2>&1 || app_finish PROVIDER_QUERY_FAILED
app_provider_check "$OUT/provider.txt" || app_finish PROVIDER_NOT_RESOLVED
echo PROVIDER_RESOLVES=PASS
app_after=$(app_process_token "/proc/$APP_SYSTEM_PID")
[ "$(pidof system_server 2>/dev/null)" = "$APP_SYSTEM_PID" ] && [ "$app_after" = "$APP_SYSTEM_TOKEN" ] || app_finish SYSTEM_SERVER_CHANGED
echo SYSTEM_SERVER_STABLE=PASS
echo GMS_HOOK=NOT_CHANGED
echo NATIVE_SERVICE=NOT_STARTED_BY_THIS_TEST
echo APP_BINDING=NOT_TESTED
echo AIRDROP_TRANSFER=NOT_TESTED
app_finish APP_READINESS_CONFIRMED 0
