#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Fresh-install finite registration experiment. Installation starts no daemon.
SKIPUNZIP=0
REPLACE=""
REMOVE=""
export SKIPUNZIP REPLACE REMOVE
[ "$BOOTMODE" = true ] || abort '! Install inside Android from SukiSU/KernelSU Manager, not recovery.'
[ "$KSU" = true ] || abort '! SukiSU/KernelSU is required.'
MODDIR=$MODPATH
. "$MODDIR/common.sh"
ui_print '- GT8 Pro RMX5200 / CN01 .501 / exact stock kernel and library checks'
mosey_check_payload install || abort '! Test-package checksum failed.'
mosey_check_target || abort "! Target prerequisite failed: $GT8_FAILURE. Do not bypass it."
for gt8_existing in /data/adb/modules/* /data/adb/modules_update/*; do
    [ -d "$gt8_existing" ] || continue
    [ "$gt8_existing" != "$MODPATH" ] || continue
    case "$gt8_existing" in
        */moseyPLK.service|*/mosey-plk110-cn|*/gt8pro.mosey.loadprobe|*/gt8pro.mosey.servicetest)
            abort '! Existing Mosey/test module found. Disable/uninstall it and reboot first.' ;;
    esac
    for gt8_rel in system/odm/bin/mosey_server system/odm/bin/mosey_load_probe system/vendor/bin/mosey_launcher odm/bin/mosey_server odm/bin/mosey_load_probe vendor/bin/mosey_launcher; do
        [ ! -e "$gt8_existing/$gt8_rel" ] && [ ! -L "$gt8_existing/$gt8_rel" ] \
            || abort '! Another module supplies overlapping Mosey files; stop here.'
    done
done
for gt8_dest in /odm/bin/mosey_server /odm/bin/mosey_load_probe /odm/lib64/libmosey_load_probe.so /vendor/bin/mosey_launcher /odm/lib64/libmosey_daemon_ffi.so /odm/lib64/libmosey_registration_compat.so; do
    [ ! -e "$gt8_dest" ] && [ ! -L "$gt8_dest" ] || abort '! Existing system Mosey/probe file found; no overwrite allowed.'
done
gt8_package=$(timeout -k 1 8 pm path com.google.android.mosey 2>/dev/null)
gt8_package_rc=$?
case "$gt8_package_rc:$gt8_package" in
    0:|1:) ;;
    0:*) abort '! Mosey app already installed; this fresh-install probe is not intended for that state.' ;;
    *) abort '! Package query failed or timed out; cannot establish a clean test state.' ;;
esac
[ -x /data/adb/ksud ] || abort '! Cannot find ksud to check rule syntax.'
/data/adb/ksud sepolicy check "$MODDIR/sepolicy.rule" >"$MODDIR/policy-check.log" 2>&1
gt8_policy_rc=$?
cat "$MODDIR/policy-check.log"
[ "$gt8_policy_rc" = 0 ] || abort '! KernelSU rejected the policy rule syntax.'
set_perm_recursive "$MODDIR" 0 0 0755 0644
set_perm_recursive "$MODDIR/system/odm" 0 0 0755 0644 u:object_r:vendor_file:s0
set_perm_recursive "$MODDIR/system/vendor" 0 0 0755 0644 u:object_r:vendor_file:s0
set_perm "$MODDIR/system/odm/bin/mosey_load_probe" 0 0 0755 u:object_r:mosey_server_exec:s0
set_perm "$MODDIR/system/odm/bin/mosey_server" 0 0 0755 u:object_r:mosey_server_exec:s0
set_perm "$MODDIR/system/vendor/bin/mosey_launcher" 0 0 0755 u:object_r:vendor_file:s0
set_perm "$MODDIR/tools/gt8_service_watchdog" 0 0 0755 u:object_r:system_file:s0
for gt8_script in action.sh stop.sh service-run.sh service-common.sh registration-checks.sh load-probe.sh common.sh namespace-common.sh namespace-service.sh compatibility.sh uninstall.sh; do
    set_perm "$MODDIR/$gt8_script" 0 0 0755
done
case "$(ls -Z "$MODDIR/system/odm/bin/mosey_load_probe")" in
    *u:object_r:mosey_server_exec:s0*) ;;
    *) abort '! Probe SELinux label could not be set.' ;;
esac
if [ ! -d /data/adb/metamodule ] && [ ! -d /data/adb/modules/meta-hybrid ]; then
    ui_print '! No known mount provider directory found. This package does not perform its own mounts.'
fi
ui_print '- Install finished. Reboot using your normal root/mount procedure.'
ui_print '- NOTHING starts automatically. Run the module Action manually after reboot.'
ui_print '- Manual Action runs a REAL Mosey service briefly; it may initialize wireless state.'
ui_print '- The pidfd guardian requests stop after at most 40 seconds; stop confirmation is mandatory.'
ui_print '- This is registration-only, NOT AirDrop. Do not change GMS. Share only Action summary.'
