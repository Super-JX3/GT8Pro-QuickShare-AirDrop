#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Explicit user action only; stdout is a freshly generated allowlisted summary.
MODDIR=/data/adb/modules/gt8pro.mosey.integrated/base-service
GT8_INPUT_DIR=$(cd "${0%/*}" && pwd -P) || exit 1
PATH=/system/bin:/system/xbin
LC_ALL=C
export PATH LC_ALL
unset LD_PRELOAD LD_LIBRARY_PATH MOSEY_REGISTRATION_COMPAT
umask 077
set -f
printf 'GT8PRO_APP_BINDING_REPORT_V1\n'
echo PACKAGE_VERSION=0.13.7-public-candidate
echo TEST_TRIGGER=BOUNDED_CONTINUOUS_SOAK
[ "$(id -u)" = 0 ] || { echo RESULT=ROOT_REQUIRED; exit 1; }
[ "$(cat /proc/self/attr/current 2>/dev/null)" = u:r:ksu:s0 ] \
    || { echo RESULT=KSU_CONTEXT_REQUIRED; exit 1; }
for gt8_flag in disable remove update; do
    [ ! -e "$MODDIR/$gt8_flag" ] || { echo RESULT=MODULE_INACTIVE; exit 1; }
done
command -v timeout >/dev/null 2>&1 || { echo RESULT=TIMEOUT_UNAVAILABLE; exit 1; }
case "$1" in smoke) GT8_SOAK_SECONDS=10;; renew-test) GT8_SOAK_SECONDS=70;; probe) GT8_SOAK_SECONDS=600;; diagnostic) GT8_SOAK_SECONDS=600;; soak) GT8_SOAK_SECONDS=1800;; *) echo RESULT=SOAK_MODE_REQUIRED;exit 1;;esac
export GT8_SOAK_SECONDS
GT8_ROOT=/data/adb/gt8pro-mosey-service
[ ! -L "$GT8_ROOT" ] || { echo RESULT=PRIVATE_PATH_UNTRUSTED; exit 1; }
mkdir -m 0700 -p "$GT8_ROOT" || { echo RESULT=PRIVATE_STATE_UNAVAILABLE; exit 1; }
[ -d "$GT8_ROOT" ] && [ "$(stat -c '%u:%a' "$GT8_ROOT" 2>/dev/null)" = 0:700 ] \
    || { echo RESULT=PRIVATE_PATH_UNTRUSTED; exit 1; }
GT8_RUN=$(mktemp -d "$GT8_ROOT/run.XXXXXX") || { echo RESULT=PRIVATE_STATE_UNAVAILABLE; exit 1; }
GT8_BINDDIR="$GT8_RUN/binding-code"
mkdir -m 0700 "$GT8_BINDDIR" || exit 1
export GT8_BINDDIR
cp "$GT8_INPUT_DIR/bind-common.sh" "$GT8_BINDDIR/bind-common.sh" || exit 1
cp "$GT8_INPUT_DIR/precheck.sh" "$GT8_BINDDIR/precheck.sh" || exit 1
cp "$GT8_INPUT_DIR/ui-lease-monitor.sh" "$GT8_BINDDIR/ui-lease-monitor.sh" || exit 1
cp "$GT8_INPUT_DIR/app-probe.sh" "$GT8_BINDDIR/app-probe.sh" || exit 1
cp "$GT8_INPUT_DIR/delegate-policy.sh" "$GT8_BINDDIR/delegate-policy.sh" || exit 1
cp "$GT8_INPUT_DIR/delegate-runner.sh" "$GT8_BINDDIR/delegate-runner.sh" || exit 1
cp "$GT8_INPUT_DIR/app-guard.sh" "$GT8_BINDDIR/app-guard.sh" || exit 1
cp "$GT8_INPUT_DIR/label-bind.sh" "$GT8_BINDDIR/label-bind.sh" || exit 1
cp "$GT8_INPUT_DIR/service-bind.sh" "$GT8_BINDDIR/service-bind.sh" || exit 1
cp "$GT8_INPUT_DIR/namespace-bind.sh" "$GT8_BINDDIR/namespace-bind.sh" || exit 1
cp "$GT8_INPUT_DIR/ui-common.sh" "$GT8_BINDDIR/ui-common.sh" || exit 1
cp "$GT8_INPUT_DIR/ui-start.sh" "$GT8_BINDDIR/ui-start.sh" || exit 1
cp "$GT8_INPUT_DIR/ui-close.sh" "$GT8_BINDDIR/ui-close.sh" || exit 1
cp "$GT8_INPUT_DIR/ui-guard.sh" "$GT8_BINDDIR/ui-guard.sh" || exit 1
cp "$GT8_INPUT_DIR/ui-meta.sh" "$GT8_BINDDIR/ui-meta.sh" || exit 1
cp "$GT8_INPUT_DIR/transfer-idle.sh" "$GT8_BINDDIR/transfer-idle.sh" || exit 1
cp "$GT8_INPUT_DIR/provider-control.sh" "$GT8_BINDDIR/provider-control.sh" || exit 1
cp "$GT8_INPUT_DIR/provider-guard.sh" "$GT8_BINDDIR/provider-guard.sh" || exit 1
cp "$GT8_INPUT_DIR/current-code-profile.sh" "$GT8_BINDDIR/current-code-profile.sh" || exit 1
cp "$GT8_INPUT_DIR/updated-package-checks.sh" "$GT8_BINDDIR/updated-package-checks.sh" || exit 1
cp "$GT8_INPUT_DIR/app-stream.sh" "$GT8_BINDDIR/app-stream.sh" || exit 1
cp "$GT8_INPUT_DIR/soak-metrics.sh" "$GT8_BINDDIR/soak-metrics.sh" || exit 1
cp "$GT8_INPUT_DIR/gms-main-pid.awk" "$GT8_BINDDIR/gms-main-pid.awk" || exit 1
cp "$GT8_INPUT_DIR/lease-gate.sh" "$GT8_BINDDIR/lease-gate.sh" || exit 1
cp "$GT8_INPUT_DIR/handoff-lock.sh" "$GT8_BINDDIR/handoff-lock.sh" || exit 1
cp "$GT8_INPUT_DIR/owner-guard.sh" "$GT8_BINDDIR/owner-guard.sh" || exit 1
cp "$GT8_INPUT_DIR/heartbeat.sh" "$GT8_BINDDIR/heartbeat.sh" || exit 1
cp "$GT8_INPUT_DIR/quiet-window.sh" "$GT8_BINDDIR/quiet-window.sh" || exit 1
cp "$GT8_INPUT_DIR/provider-state.awk" "$GT8_BINDDIR/provider-state.awk" || exit 1
cp "$GT8_INPUT_DIR/gms-transfer-state.awk" "$GT8_BINDDIR/gms-transfer-state.awk" || exit 1
cp "$GT8_INPUT_DIR/quiet-state.sh" "$GT8_BINDDIR/quiet-state.sh" || exit 1
cp "$GT8_INPUT_DIR/outer-watchdog" "$GT8_BINDDIR/outer-watchdog" || exit 1
chmod 0700 "$GT8_BINDDIR/outer-watchdog" || exit 1
cp "$GT8_INPUT_DIR/gt8_service_watchdog_soak" "$GT8_BINDDIR/gt8_service_watchdog_soak" || exit 1
chmod 0700 "$GT8_BINDDIR/gt8_service_watchdog_soak" || exit 1
bind_bootstrap_ok() {
    b_sum=$(sha256sum "$GT8_BINDDIR/ui-lease-monitor.sh") || return 1
    [ "${b_sum%% *}" = 86895bae929c389ee173c879bff9026a5c39fbcd08fd51fd944bd72f683b3ac5 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/handoff-lock.sh") || return 1
    [ "${b_sum%% *}" = b30ce8a43d9d6ab7390ff8d221bcb9cd0a03d666a3ac3b4d5dffe91a100ba892 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/owner-guard.sh") || return 1
    [ "${b_sum%% *}" = 180a2960f5cc0862ccb6329f92c067612248812f01d23c57641e149dac93bf40 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/quiet-window.sh") || return 1
    [ "${b_sum%% *}" = a895f8d0aaf0fd731099e42bff3eebd5860f8b8a70da3bb1e2a11f8b162e3023 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/provider-state.awk") || return 1
    [ "${b_sum%% *}" = 96533a64020ea934e9556bf950a2c50fcfdadfade8be7e5ab88ad8a88febddeb ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/gms-transfer-state.awk") || return 1
    [ "${b_sum%% *}" = dcb506cdc7394534a84b15f7defffc40ffd070db9d0cd8084d5876df62fc60b7 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/quiet-state.sh") || return 1
    [ "${b_sum%% *}" = f658a7511df976329fef4349364f8200451f9a163ef59e46735f9ca7af687116 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/heartbeat.sh") || return 1
    [ "${b_sum%% *}" = 306077f58b97ccb9d5a14764982e97170425222a691b3718241245e21f6f793f ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/lease-gate.sh") || return 1
    [ "${b_sum%% *}" = e48ed1610c628e55ac10bcf576b17d0d7017921cfd331943de12577ca25020e2 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/outer-watchdog") || return 1
    [ "${b_sum%% *}" = 883c7527aa8ee2bdf7e7da963f30da79e5d846525bcdc4bd685bb276b1e8266a ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/gms-main-pid.awk") || return 1
    [ "${b_sum%% *}" = 9439b659a188e5ded196d4d45ba3b51053eb9f046da0da0c87be2cf73a6f6df7 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/soak-metrics.sh") || return 1
    [ "${b_sum%% *}" = 8ad94e746f13c83af740ea1fbd9ef3bfd197e37e6bb075dbc62cd59024b00c68 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/gt8_service_watchdog_soak") || return 1
    [ "${b_sum%% *}" = ff319e66b79a00a6ec3a9605ac7b60b24071c684393c98719f8729d39143c24a ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/current-code-profile.sh") || return 1
    [ "${b_sum%% *}" = 06eda872c7d4f5d1d31df9f5e218bf8314c7c1f9a0dd4329e00bac7fcdf4a8c0 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/updated-package-checks.sh") || return 1
    [ "${b_sum%% *}" = 187cbb2e943e680a694b081b4c1c64b77bd5d2ed796d6cab86468c6f69d13538 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/app-stream.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = df6dafdc081a64f5692c098e00f588fc6ee06e07c1683fe6efdf9e88d5304b47 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/provider-guard.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 8351ae8ea68a9231734fe9e78847d6c788ac9d11e132a80ca6025b5e60e1f6b7 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/provider-control.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = f139ed82507211bb995443320d017f2fbe374539c80d5d5ec653b3fe4ee0963a ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/transfer-idle.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = e156907644bfdaecfd9dbc3e5d5df281d5fe3aeea2a65efd39825c55d3e87db2 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/ui-meta.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = e495d4f8afba64fb9d93ce8a68a5c51db4c1e172e17e941179eb03d832419412 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/ui-close.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = e9256785996b5fb083c38cf5234662e9ec8fe6e69fb66f5807e27b0cb5beb2a7 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/ui-common.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 84c07d259b74fcda4ea9946617193deb7b3382712a220413ebfc58c3fde0eeb8 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/ui-start.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = a0e9fb384a483c271fc4284af0600cc931dfc54da800e2f939ac61c5f88377c5 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/ui-guard.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 61d891907545d681033d34ee1fa3d406247d95bf2299b31fa105c17380673868 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/bind-common.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = c9a1a8f66bedefcfed873f0052a3f9a3006b8157c96bf43b4eb685153da7fe0f ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/precheck.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = e89ed6610f8d13f6ae7552692e7975e82a764dc186a4a664662d19efe7574b27 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/delegate-policy.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = be01bfd183ce2cdc8de97fdcfcbf4905e6484689741b3e8a2b268f58544d4ca4 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/delegate-runner.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 291f5d8322c0eb6a7c8fe4a63aaae4f6364e594dbf5b1d289d1260d004ecb260 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/app-probe.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = c7f3c42aa62e940b45ec088130185febfedce6926eca71d50005428f80ed55ac ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/app-guard.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 25ac47a02fbe8448d637dd0bd8499971bbf8f8ad3b204e25bb60c8147bc50cf9 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/label-bind.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 54baa145b00cad3d3bb99b602096768fd022df44bf476aa47635dbe2c7eac721 ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/service-bind.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 3ea30e18942a5ffa98f246c809e1356846a75c4f7a31ff613add5b02204fd35e ] || return 1
    b_sum=$(sha256sum "$GT8_BINDDIR/namespace-bind.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = df7dcc31f9775dcd29a53492b3465bf4aea644269bcb4e3a987a5de296dc795e ] || return 1
    b_sum=$(sha256sum "$MODDIR/common.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = d52cc0d31e62d3260b8b0a5ccc03387aeb12a72ecd8faa1fc235702649f1cfdb ] || return 1
    b_sum=$(sha256sum "$MODDIR/namespace-common.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 5dd1a283ccd75d33e6f2ba6ce6409a0f22f5776720e3415137baf5773d95feba ] || return 1
    b_sum=$(sha256sum "$MODDIR/service-common.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = d613e77c30af5cb4be681fce1d35d557e4891848071262de5aa0d272a4ebfd59 ] || return 1
    b_sum=$(sha256sum "$MODDIR/registration-checks.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 8969e478df223ddda6a3f54e179cfd52e240ffe70ee4bea7441cb65e0a66a3fd ] || return 1
    b_sum=$(sha256sum "$MODDIR/payload.sha256" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 45f9b82761465398ecba0237eb06824f96e3e76b53e1d1a0c552f15a21660c9c ] || return 1
    b_sum=$(sha256sum "$MODDIR/tools/gt8_service_watchdog" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = da72d9f756cfe06795b0b84567fa5e6ad45c35ca6a8c21b58bb9c0d0a6fa6cc6 ] || return 1
    b_sum=$(sha256sum "/data/adb/modules/gt8pro.mosey.integrated/base-app/common.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = d59e795b326a989289e72f27dcd0b9e89eed687d45a60748c04c9ff079d8c6ac ] || return 1
    b_sum=$(sha256sum "/data/adb/modules/gt8pro.mosey.integrated/base-app/target-checks.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 4d4835877fbaf38f97eec537ef74c6bfcb940d07fc40cebe906e9c5bff1141b0 ] || return 1
    b_sum=$(sha256sum "/data/adb/modules/gt8pro.mosey.integrated/base-app/package-checks.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 839c474d335817d7eff1354b77d1f65b44681bd59ad193b5b2e143b65ee90183 ] || return 1
    b_sum=$(sha256sum "/data/adb/modules/gt8pro.mosey.integrated/base-app/compatibility.sh" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = 8fa064a913ae36f08cef228ce9c1849491298439824f8c087a9fdcc343cb0dc9 ] || return 1
    b_sum=$(sha256sum "/data/adb/modules/gt8pro.mosey.integrated/base-app/payload.sha256" 2>/dev/null) || return 1
    [ "${b_sum%% *}" = e37ee7846c3857dc0186b3269960eac89cc394dcde0f024cf53405fa253bb255 ] || return 1
}
bind_bootstrap_ok || { echo RESULT=BASE_OR_BUNDLE_UNVERIFIED; exit 1; }
. "$GT8_BINDDIR/owner-guard.sh"
. "$GT8_BINDDIR/handoff-lock.sh"
case "${GT8_WATCHER_PID:-}:${GT8_WATCHER_TOKEN:-}" in
 :) GT8_HAS_OWNER=0;;
 *)
  gt8_ppid=$(awk '/^PPid:/{print $2}' "/proc/$$/status")
  [ "$gt8_ppid" = "$GT8_WATCHER_PID" ] && gt8_owner_alive "$GT8_WATCHER_PID" "$GT8_WATCHER_TOKEN" /proc || { echo RESULT=WATCHER_IDENTITY_UNVERIFIED;exit 1; }
  GT8_HAS_OWNER=1;;
esac

. "$GT8_BINDDIR/bind-common.sh"
. "$MODDIR/common.sh"
. "$MODDIR/namespace-common.sh"
. "$MODDIR/service-common.sh"
if ! mosey_check_payload >"$GT8_RUN/payload.txt" 2>&1; then
    echo RESULT=PAYLOAD_CHECK_FAILED
    exit 1
fi
echo PAYLOAD_CHECK=PASS
if ! mosey_check_target >"$GT8_RUN/target.txt" 2>&1; then
    case "$GT8_FAILURE" in
        root|selinux|model|sdk|abi|platform|kernel|firmware|wonder_hash|wlan_hash|binder_hash|checker_missing|policy)
            printf 'FAILED_CHECK=%s\n' "$GT8_FAILURE" ;;
    esac
    echo RESULT=TARGET_CHECK_FAILED
    exit 1
fi
echo TARGET_CHECK=PASS
if ! sh "$GT8_BINDDIR/precheck.sh" "$GT8_RUN" >"$GT8_RUN/binding-precheck.txt" 2>&1; then
    awk '/^BIND_PRECHECK=(CALLER_UNVERIFIED|PRIVATE_STATE_UNVERIFIED|MODULE_INACTIVE|APP_PAYLOAD_FAILED|MAIN_USER_REQUIRED|BOOT_NOT_COMPLETE|GUARD_TOOL_UNAVAILABLE|SYSTEM_SERVER_UNVERIFIED|APP_MOUNT_UNVERIFIED|PACKAGE_QUERY_FAILED|APP_IDENTITY_UNVERIFIED|APP_UID_UNVERIFIED|CORE_PRIVILEGES_MISSING|RUNTIME_PERMISSIONS_MISSING|PROVIDER_QUERY_FAILED|PROVIDER_UNVERIFIED|APP_ALREADY_RUNNING|APP_STATE_QUERY_FAILED|APP_SERVICE_ALREADY_PRESENT|SYSTEM_SERVER_CHANGED|PRIVATE_STATE_FAILED)$/ {print}' "$GT8_RUN/binding-precheck.txt"
    echo RESULT=APP_BINDING_PRECHECK_FAILED
    exit 1
fi
echo CORE_PRIVILEGES=PASS
echo RUNTIME_PERMISSIONS=PASS
echo NETWORK_PERMISSION_GAP=UNRESOLVED
GT8_BB=/data/adb/ksu/bin/busybox
[ -x "$GT8_BB" ] && [ "$(stat -c '%u:%a' "$GT8_BB")" = 0:755 ] \
    || { echo RESULT=NAMESPACE_TOOLS_UNAVAILABLE; exit 1; }
GT8_PARENT_NS=$(readlink /proc/self/ns/mnt)
gt8_namespace_token "$GT8_PARENT_NS" || { echo RESULT=NAMESPACE_UNVERIFIED; exit 1; }
GT8_PARENT_PID=$$
lock=$GT8_ROOT/mutation.lock
if [ ! -e "$lock" ] && [ ! -L "$lock" ];then (set -C; : >"$lock") 2>/dev/null || :;fi
gt8_handoff_lock "$lock" || { echo RESULT=HANDOFF_LOCK_UNAVAILABLE;exit 1; }
if ! mkdir -m 0700 "$GT8_ROOT/action-lock" 2>/dev/null;then
    gt8_handoff_unlock;echo RESULT=PROBE_BUSY_OR_STALE_LOCK;exit 1
fi
control_token=$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$$/stat")
case "$control_token" in ''|*[!0-9]*) rmdir "$GT8_ROOT/action-lock";gt8_handoff_unlock;exit 1;;esac
printf '%s %s\n' "$$" "$control_token" >"$GT8_RUN/soak-controller.record" || { rmdir "$GT8_ROOT/action-lock";gt8_handoff_unlock;exit 1; }
owner=$GT8_ROOT/session-owner
if [ -L "$owner" ] || { [ -e "$owner" ] && [ "$(stat -c '%u:%a' "$owner")" != 0:600 ]; };then rmdir "$GT8_ROOT/action-lock";gt8_handoff_unlock;exit 1;fi
tmp=$(mktemp "$GT8_ROOT/.session-owner.XXXXXX") || { rmdir "$GT8_ROOT/action-lock";gt8_handoff_unlock;exit 1; }
printf '%s %s %s\n' "${GT8_RUN##*/}" "$$" "$control_token" >"$tmp" && mv -f "$tmp" "$owner" || { rm -f "$tmp";rmdir "$GT8_ROOT/action-lock";gt8_handoff_unlock;exit 1; }
if [ "$GT8_HAS_OWNER" = 1 ];then
 (set -C; printf '%s %s\n' "$GT8_WATCHER_PID" "$GT8_WATCHER_TOKEN" >"$GT8_RUN/watcher-owner.record") || { rmdir "$GT8_ROOT/action-lock";gt8_handoff_unlock;exit 1; }
fi
if [ "${GT8_DAILY_MODULE:-}" = /data/adb/modules/gt8pro.mosey.integrated ];then
 [ ! -L "$GT8_DAILY_MODULE" ] && [ -d "$GT8_DAILY_MODULE" ] || { rmdir "$GT8_ROOT/action-lock";gt8_handoff_unlock;exit 1; }
 for flag in disable remove update;do [ ! -e "$GT8_DAILY_MODULE/$flag" ] && [ ! -L "$GT8_DAILY_MODULE/$flag" ] || { rmdir "$GT8_ROOT/action-lock";gt8_handoff_unlock;exit 1; };done
 (set -C; echo DAILY_V5 >"$GT8_RUN/daily-module-session") || { rmdir "$GT8_ROOT/action-lock";gt8_handoff_unlock;exit 1; }
fi
gt8_handoff_unlock
heartbeat_loop() {
 while [ ! -f "$GT8_RUN/heartbeat-stop" ];do
  if [ "$GT8_HAS_OWNER" = 1 ];then gt8_owner_alive "$GT8_WATCHER_PID" "$GT8_WATCHER_TOKEN" /proc || exit 1;fi
  [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$GT8_PARENT_PID/stat" 2>/dev/null)" = "$control_token" ] || exit 1
  sh "$GT8_BINDDIR/heartbeat.sh" "$GT8_RUN" UNKNOWN >/dev/null || exit 1
  if [ ! -f "$GT8_RUN/native-heartbeat-stop" ];then
   sh "$GT8_BINDDIR/heartbeat.sh" "$GT8_RUN" UNKNOWN NATIVE >/dev/null || exit 1
  elif [ ! -f "$GT8_RUN/native-heartbeat-stopped" ];then
   (set -C; echo STOPPED >"$GT8_RUN/native-heartbeat-stopped") || exit 1
  fi
  sleep 2
 done
}
GT8_PARENT_PID=$$
heartbeat_loop >"$GT8_RUN/heartbeat-private.txt" 2>&1 & heartbeat_pid=$!
trap ': >"$GT8_RUN/heartbeat-stop"; wait "$heartbeat_pid" 2>/dev/null; if gt8_handoff_begin "$GT8_RUN";then rmdir "$GT8_ROOT/action-lock" 2>/dev/null; gt8_handoff_unlock;fi' 0
trap 'exit 1' 1 2 15
gt8_namespace_parent_view >"$GT8_RUN/parent-before.txt" 2>&1 \
    || { echo RESULT=PARENT_VIEW_UNVERIFIED; exit 1; }
"$GT8_BINDDIR/outer-watchdog" run "${GT8_RUN##*/}" "$GT8_PARENT_NS" "$GT8_PARENT_PID" >"$GT8_RUN/probe.txt" 2>&1
gt8_rc=$?
case "$gt8_rc" in ''|*[!0-9]*) gt8_rc=255 ;; esac
printf 'PROBE_EXIT_CODE=%s\n' "$gt8_rc"
if ! gt8_namespace_parent_view >"$GT8_RUN/parent-after.txt" 2>&1 \
    || ! "$GT8_BB" cmp -s "$GT8_RUN/parent-before.txt" "$GT8_RUN/parent-after.txt"; then
    echo PARENT_VIEW=CHANGED_OR_UNCONFIRMED
    echo RESULT=PARENT_VIEW_UNVERIFIED
    echo NEXT_STAGE=WAIT_FOR_REVIEW
    exit 1
fi
echo PARENT_VIEW=UNCHANGED
bind_emit "$GT8_RUN/probe.txt"
if [ "$gt8_rc" = 0 ] && gt8_service_report_ok "$GT8_RUN/probe.txt" && bind_label_report_ok "$GT8_RUN/probe.txt"; then
    echo NAMESPACE_ISOLATION=PASS
    echo PRIVATE_BIND=PASS
    echo NAMESPACE_CLEANUP=PASS
    echo SERVICE_IDENTITY=PASS
    echo SHIM_REGISTRATION=PASS
    echo BINDER_OBSERVED=PASS
    echo SERVICE_STOPPED=PASS
    echo BINDER_REMOVED=PASS
    if bind_app_report_ok "$GT8_RUN/probe.txt"; then
        echo RESULT=APP_BINDING_VERSION_OBSERVED_LIFECYCLE_VERIFIED
    else
        echo RESULT=APP_BINDING_UNCONFIRMED
        echo NEXT_STAGE=WAIT_FOR_REVIEW
        exit 1
    fi
else
    echo REGISTRATION_TEST=UNCONFIRMED
    gt8_watch_rc=$(awk -F= '$1=="WATCHDOG_EXIT_CODE" {n++;if(NF==2&&$2~/^[0-9]+$/&&$2<=255)v=$2;else bad=1}END{if(n==1&&!bad)print v}' "$GT8_RUN/probe.txt")
    [ -z "$gt8_watch_rc" ] || printf 'WATCHDOG_EXIT_CODE=%s\n' "$gt8_watch_rc"
    gt8_result=$(sed -n 's/^RESULT=//p' "$GT8_RUN/probe.txt" | tail -n 1)
    case "$gt8_result" in
        '')
            case "$gt8_rc" in
                124|137) echo RESULT=PROBE_TIMEOUT ;;
                *) echo RESULT=NAMESPACE_START_FAILED ;;
            esac ;;
        ROOT_REQUIRED|CALLER_CONTEXT_UNVERIFIED|TIMEOUT_UNAVAILABLE|FILES_NOT_READY|PAYLOAD_MISMATCH|PROBE_LABEL_MISMATCH|LIBRARY_LABEL_MISMATCH|LAUNCHER_LABEL_MISMATCH|BASELINE_FAILED|BASELINE_UNVERIFIED|PRELOAD_BLOCKED_AT_SECURE|PRELOAD_UNCONFIRMED|NAMESPACE_ARGUMENT_INVALID|NAMESPACE_CALLER_INVALID|NAMESPACE_UNVERIFIED|NAMESPACE_PRIVATE_FAILED|NAMESPACE_PRIVATE_UNVERIFIED|PAYLOAD_CHECK_FAILED|SOURCE_PROBE_UNVERIFIED|SOURCE_SERVICE_UNVERIFIED|BIND_TARGET_UNVERIFIED|PRIVATE_BIND_FAILED|PRIVATE_BIND_UNVERIFIED|NAMESPACE_CLEANUP_FAILED|SERVICE_STATE_UNVERIFIED|SERVICE_CALLER_UNVERIFIED|SERVICE_PAYLOAD_MISMATCH|SERVICE_LABEL_MISMATCH|EXISTING_SERVICE_PROCESS|EXISTING_BINDER_SERVICE|BINDER_QUERY_UNVERIFIED|PIDFD_SELFTEST_FAILED|SERVICE_REGISTRATION_UNCONFIRMED|SERVICE_EXITED_BEFORE_CONFIRMATION|STOP_REQUEST_FAILED|SERVICE_STOP_UNCONFIRMED|BINDER_STILL_PRESENT|LABEL_VIEW_UNVERIFIED)
            printf 'RESULT=%s\n' "$gt8_result" ;;
        *) echo RESULT=PROBE_FAILED_OR_OUTPUT_UNVERIFIED ;;
    esac
    echo NEXT_STAGE=WAIT_FOR_REVIEW
    exit 1
fi
echo NEXT_STAGE=WAIT_FOR_REVIEW
