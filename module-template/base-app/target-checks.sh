#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# GT8 Pro host-reviewed prerequisites. No device mutation in these helpers.
# Modified 2026-10-22; upstream compatibility checks remain unchanged.
gt8_fail() { GT8_FAILURE=$1; printf 'CHECK_FAIL=%s\n' "$1"; return 1; }
gt8_hash() {
    gt8_sum=$(sha256sum "$1" 2>/dev/null)
    gt8_sum=${gt8_sum%% *}
    [ "$gt8_sum" = "$2" ]
}
mosey_check_target() {
    GT8_FAILURE=none
    [ "$(id -u)" = 0 ] || { gt8_fail root; return 1; }
    [ "$(getenforce 2>/dev/null)" = Enforcing ] || { gt8_fail selinux; return 1; }
    [ "$(getprop ro.product.model)" = RMX5200 ] || { gt8_fail model; return 1; }
    [ "$(getprop ro.build.version.sdk)" = 36 ] || { gt8_fail sdk; return 1; }
    [ "$(getprop ro.product.cpu.abi)" = arm64-v8a ] || { gt8_fail abi; return 1; }
    [ "$(getprop ro.board.platform)" = canoe ] || { gt8_fail platform; return 1; }
    [ "$(uname -r)" = 6.12.23-android16-5-gb2a876903b49-ab14541642-4k ] || { gt8_fail kernel; return 1; }
    gt8_firmware_ok=false
    for gt8_prop in ro.build.version.ota ro.build.display.id ro.build.display.id.show ro.build.version.incremental; do
        gt8_value=$(getprop "$gt8_prop")
        case "$gt8_value" in
            'RMX5200_16.0.10.501(CN01)'|'16.0.10.501(CN01)') gt8_firmware_ok=true ;;
        esac
    done
    [ "$gt8_firmware_ok" = true ] || { gt8_fail firmware; return 1; }
    gt8_hash /vendor_dlkm/lib/modules/wonder.ko 533cfc36b5bb015f0949b02319a4307cfa8baba4c3872a8a5a7630f811823c4e \
        || { gt8_fail wonder_hash; return 1; }
    gt8_hash /vendor_dlkm/lib/modules/qca_cld3_peach_v2.ko eb19a7cfe73dd00e697a88d4cad02bc8118e349485b1bd2b43ed912e2ed3aa46 \
        || { gt8_fail wlan_hash; return 1; }
    gt8_hash /system/lib64/libbinder_ndk.so 0ef7b4a9844df4084f4b4e87a661224b4ca3de7d527a109a893c328aae03f100 \
        || { gt8_fail binder_hash; return 1; }
    [ -r "$MODDIR/compatibility.sh" ] || { gt8_fail checker_missing; return 1; }
    . "$MODDIR/compatibility.sh"
    mosey_check_compatibility || { gt8_fail policy; return 1; }
    printf 'TARGET_CHECK=PASS\n'
}
