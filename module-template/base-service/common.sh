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
mosey_check_payload() {
    case "${1:-runtime}" in
        install) (cd "$MODDIR" && sha256sum -c install.sha256); return $? ;;
        runtime) ;;
        *) return 1 ;;
    esac
    # Keep canonical manifest paths for load-probe.sh's mounted-file checks.
    # Installers may relocate partition trees, with or without compatibility links.
    (
        cd "$MODDIR" || exit 1
        gt8_module_root=$(pwd -P) || exit 1
        gt8_seen='|'
        gt8_count=0
        while read -r gt8_expected gt8_relative gt8_extra; do
            [ -z "$gt8_extra" ] && [ "${#gt8_expected}" = 64 ] || exit 1
            case "$gt8_expected" in *[!0-9a-f]*) exit 1 ;; esac
            gt8_relocated=
            case "$gt8_relative" in
                system/odm/bin/mosey_load_probe|system/odm/bin/mosey_server|system/odm/lib64/libmosey_daemon_ffi.so|system/odm/lib64/libmosey_registration_compat.so|system/odm/lib64/libmosey_load_probe.so|system/vendor/bin/mosey_launcher)
                    gt8_relocated=${gt8_relative#system/} ;;
                action.sh|stop.sh|service-run.sh|service-common.sh|registration-checks.sh|tools/gt8_service_watchdog|source/watchdog.c|MUSL-COPYRIGHT|common.sh|namespace-common.sh|namespace-service.sh|compatibility.sh|LICENSE|load-probe.sh|module.prop|NOTICE|provenance.json|README.txt|sepolicy.rule|THIRD_PARTY_NOTICES.md|uninstall.sh) ;;
                *) exit 1 ;;
            esac
            case "$gt8_seen" in *"|$gt8_relative|"*) exit 1 ;; esac
            gt8_seen="$gt8_seen$gt8_relative|"
            gt8_count=$((gt8_count + 1))
            gt8_found=false
            for gt8_candidate in "$gt8_relative" "$gt8_relocated"; do
                [ -n "$gt8_candidate" ] || continue
                if [ -e "$gt8_candidate" ] || [ -L "$gt8_candidate" ]; then
                    gt8_found=true
                    gt8_resolved=$(readlink -f "$gt8_candidate") || exit 1
                    # Never accept an external target through a rewritten link.
                    if [ "$gt8_resolved" != "$gt8_module_root/$gt8_relative" ]; then
                        [ -n "$gt8_relocated" ] && [ "$gt8_resolved" = "$gt8_module_root/$gt8_relocated" ] || exit 1
                    fi
                    gt8_hash "$gt8_candidate" "$gt8_expected" || exit 1
                fi
            done
            [ "$gt8_found" = true ] || exit 1
        done < payload.sha256
        [ "$gt8_count" = 27 ] || exit 1
    )
}
