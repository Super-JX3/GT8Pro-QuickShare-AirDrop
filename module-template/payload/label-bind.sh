#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Only four existing, fixed module payloads; called inside verified private ns.
# No relabel, copy, partition writes, driver replacement, or global mount edits.
gt8_label_spec() {
    GT8_LABEL_MODE=644
    case "$1" in
        odm/lib64/libmosey_load_probe.so)
            GT8_LABEL_KEY=LOAD_PROBE_LIBRARY
            GT8_LABEL_HASH=49a82dcf873cadb5f78a01d698b6f6bef5067c07dbd362e5e463b1f583d2d671 ;;
        odm/lib64/libmosey_daemon_ffi.so)
            GT8_LABEL_KEY=DAEMON_LIBRARY
            GT8_LABEL_HASH=89c83ba82930696930968b5aa0d515983be96732697d2bf825e5bfb4ba549ea6 ;;
        odm/lib64/libmosey_registration_compat.so)
            GT8_LABEL_KEY=REGISTRATION_LIBRARY
            GT8_LABEL_HASH=76a5b51899142fc76353f38b2dc200ae001db3b6e72ee2d6324820f0341ad732 ;;
        vendor/bin/mosey_launcher)
            GT8_LABEL_KEY=LAUNCHER
            GT8_LABEL_MODE=755
            GT8_LABEL_HASH=1e9528a3ee0cebf52e8334c487f081a5c351a65c6283f8be8899e2c0801e870b ;;
        *) return 1 ;;
    esac
}
gt8_label_fail() {
    printf 'LABEL_VIEW_FILE=%s\nLABEL_VIEW_CHECK=%s\n' "$GT8_LABEL_KEY" "$1"
    return 1
}
gt8_label_source() {
    gt8_label_spec "$1" || return 1
    gt8_l_root=$(cd "$MODDIR" && pwd -P) || return 1
    GT8_LABEL_SOURCE=
    for gt8_l_file in "$gt8_l_root/$1" "$gt8_l_root/system/$1"; do
        [ -f "$gt8_l_file" ] || continue
        gt8_l_real=$(readlink -f "$gt8_l_file") || return 1
        case "$gt8_l_real" in "$gt8_l_root/$1"|"$gt8_l_root/system/$1") ;; *) return 1 ;; esac
        gt8_hash "$gt8_l_real" "$GT8_LABEL_HASH" || return 1
        [ "$(stat -c '%u:%a' "$gt8_l_real")" = "0:$GT8_LABEL_MODE" ] || return 1
        case "$(ls -Zd "$gt8_l_real")" in u:object_r:vendor_file:s0\ *) ;; *) return 1 ;; esac
        GT8_LABEL_SOURCE=$gt8_l_real
        return 0
    done
    return 1
}
gt8_label_bind_all() {
    # Validate every source/target before adding any of the four new binds.
    for gt8_l_rel in odm/lib64/libmosey_load_probe.so odm/lib64/libmosey_daemon_ffi.so odm/lib64/libmosey_registration_compat.so vendor/bin/mosey_launcher; do
        gt8_label_spec "$gt8_l_rel" || return 1
        gt8_ns_isolated && gt8_private_mountinfo /proc/self/mountinfo || { gt8_label_fail PRIVATE_VIEW_UNVERIFIED; return 1; }
        gt8_label_source "$gt8_l_rel" || { gt8_label_fail SOURCE_UNVERIFIED; return 1; }
        gt8_ns_target "/$gt8_l_rel" "$GT8_LABEL_HASH" || { gt8_label_fail TARGET_UNVERIFIED; return 1; }
        gt8_l_before=$(gt8_ns_fingerprint "/$gt8_l_rel") || { gt8_label_fail TARGET_UNVERIFIED; return 1; }
        (set -C; printf '%s\n' "$gt8_l_before" >"$OUT/label-before.$GT8_LABEL_KEY.txt") || { gt8_label_fail RECORD_FAILED; return 1; }
    done
    for gt8_l_rel in odm/lib64/libmosey_load_probe.so odm/lib64/libmosey_daemon_ffi.so odm/lib64/libmosey_registration_compat.so vendor/bin/mosey_launcher; do
        gt8_label_source "$gt8_l_rel" || { gt8_label_fail SOURCE_UNVERIFIED; return 1; }
        gt8_ns_isolated && gt8_private_mountinfo /proc/self/mountinfo || { gt8_label_fail PRIVATE_VIEW_UNVERIFIED; return 1; }
        "$GT8_BB" mount -n -o bind "$GT8_LABEL_SOURCE" "/$gt8_l_rel" || { gt8_label_fail BIND_FAILED; return 1; }
        GT8_LABEL_BOUND="$gt8_l_rel $GT8_LABEL_BOUND"
        gt8_ns_isolated && gt8_private_mountinfo /proc/self/mountinfo || { gt8_label_fail PRIVATE_VIEW_UNVERIFIED; return 1; }
        [ "$(stat -c '%d:%i' "$GT8_LABEL_SOURCE")" = "$(stat -c '%d:%i' "/$gt8_l_rel")" ] \
            || { gt8_label_fail BIND_UNVERIFIED; return 1; }
        gt8_hash "/$gt8_l_rel" "$GT8_LABEL_HASH" || { gt8_label_fail BIND_UNVERIFIED; return 1; }
        case "$(ls -Zd "/$gt8_l_rel")" in u:object_r:vendor_file:s0\ *) ;; *) gt8_label_fail BIND_UNVERIFIED; return 1 ;; esac
    done
    echo LABEL_VIEW_BINDS=4
    echo LABEL_VIEWS=PASS
}
gt8_label_cleanup_all() {
    gt8_l_clean=true
    for gt8_l_restore in $GT8_LABEL_BOUND; do
        # Reverse mount order; only the exact fixed list is accepted.
        if ! gt8_label_spec "$gt8_l_restore"; then gt8_l_clean=false; continue; fi
        if ! { gt8_ns_isolated && gt8_private_mountinfo /proc/self/mountinfo \
            && "$GT8_BB" umount "/$gt8_l_restore"; }; then gt8_l_clean=false; continue; fi
        gt8_l_expected=$(cat "$OUT/label-before.$GT8_LABEL_KEY.txt") || { gt8_l_clean=false; continue; }
        gt8_l_after=$(gt8_ns_fingerprint "/$gt8_l_restore") || { gt8_l_clean=false; continue; }
        [ "$gt8_l_expected" = "$gt8_l_after" ] || gt8_l_clean=false
    done
    [ "$gt8_l_clean" = true ]
}
