#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Fixed-path checks only; target-checks.sh is generated from reviewed 0.3.0 gates.
. "$MODDIR/target-checks.sh"
mosey_check_payload() {
    case "${1:-runtime}" in
        install) (cd "$MODDIR" && sha256sum -c install.sha256); return $? ;;
        runtime) ;;
        *) return 1 ;;
    esac
    (
        cd "$MODDIR" || exit 1
        app_root=$(pwd -P) || exit 1
        app_seen='|'; app_count=0
        while read -r app_hash app_rel app_extra; do
            [ -z "$app_extra" ] && [ "${#app_hash}" = 64 ] || exit 1
            case "$app_hash" in *[!0-9a-f]*) exit 1 ;; esac
            app_moved=
            case "$app_rel" in
                system/system_ext/priv-app/MoseyApp/MoseyApp.apk|system/system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml|system/system_ext/etc/default-permissions/default-permissions-com.google.android.mosey.xml)
                    app_moved=${app_rel#system/} ;;
                action.sh|common.sh|target-checks.sh|package-checks.sh|compatibility.sh|module.prop|README.txt|LICENSE|NOTICE|THIRD_PARTY_NOTICES.md|provenance.json) ;;
                *) exit 1 ;;
            esac
            case "$app_seen" in *"|$app_rel|"*) exit 1 ;; esac
            app_seen="$app_seen$app_rel|"; app_count=$((app_count+1)); app_found=false
            for app_file in "$app_rel" "$app_moved"; do
                [ -n "$app_file" ] || continue
                if [ -e "$app_file" ] || [ -L "$app_file" ]; then
                    app_found=true
                    app_real=$(readlink -f "$app_file") || exit 1
                    if [ "$app_real" != "$app_root/$app_rel" ]; then
                        [ -n "$app_moved" ] && [ "$app_real" = "$app_root/$app_moved" ] || exit 1
                    fi
                    gt8_hash "$app_file" "$app_hash" || exit 1
                fi
            done
            [ "$app_found" = true ] || exit 1
        done <payload.sha256
        [ "$app_count" = 14 ]
    )
}
