#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Fixed-path service experiment helpers; never source saved state as shell code.
gt8_service_exact_source() {
    case "$1" in
        mosey_load_probe) gt8_s_hash=f736d6e9048ed0d80c3211fed3d2d159c347a017d5666be6104472596fb8ed9d ;;
        mosey_server) gt8_s_hash=53aa112866da41f32de05efd91730a27f0f1a40a79ebe61be95bd8d1944a0326 ;;
        *) return 1 ;;
    esac
    gt8_s_root=$(cd "$MODDIR" && pwd -P) || return 1
    GT8_SERVICE_SOURCE=
    for gt8_s_file in "$gt8_s_root/odm/bin/$1" "$gt8_s_root/system/odm/bin/$1"; do
        [ -f "$gt8_s_file" ] || continue
        gt8_s_real=$(readlink -f "$gt8_s_file") || return 1
        case "$gt8_s_real" in "$gt8_s_root/odm/bin/$1"|"$gt8_s_root/system/odm/bin/$1") ;; *) return 1 ;; esac
        gt8_hash "$gt8_s_real" "$gt8_s_hash" || return 1
        [ "$(stat -c '%u:%a' "$gt8_s_real")" = 0:755 ] || return 1
        case "$(ls -Zd "$gt8_s_real")" in u:object_r:mosey_server_exec:s0\ *) ;; *) return 1 ;; esac
        GT8_SERVICE_SOURCE=$gt8_s_real
        return 0
    done
    return 1
}
gt8_service_record() {
    [ ! -L "$OUT/child.record" ] && [ -f "$OUT/child.record" ] \
        && [ "$(stat -c '%u:%a' "$OUT/child.record")" = 0:600 ] || return 1
    read -r SV_PID SV_TOKEN SV_EXTRA <"$OUT/child.record"
    [ -z "$SV_EXTRA" ] || return 1
    case "$SV_PID:$SV_TOKEN" in *[!0-9:]*|:*|*:) return 1 ;; esac
    [ "$SV_PID" -gt 1 ] && [ "$SV_TOKEN" -gt 0 ]
}
gt8_service_stop_request() {
    "$MODDIR/tools/gt8_service_watchdog" stop >/dev/null 2>&1
}
gt8_service_report_ok() {
    awk -F= '
        BEGIN {w[1]="BASELINE_IDENTITY_OK";w[2]="PRELOAD_OK";w[3]="PROBE_PRELOAD_CONFIRMED";w[4]="REGISTRATION_OBSERVED_AND_STOPPED"}
        $1=="RESULT" {n++;if(NF!=2||$2!=w[n])bad=1}
        $1=="NAMESPACE_ISOLATION" || $1=="PRIVATE_BIND" || $1=="NAMESPACE_CLEANUP" ||
        $1=="SERVICE_IDENTITY" || $1=="SHIM_REGISTRATION" || $1=="BINDER_OBSERVED" ||
        $1=="SERVICE_STOPPED" || $1=="BINDER_REMOVED" {
            seen[$1]++; if(NF!=2||$2!="PASS")bad=1
        }
        END {
            split("NAMESPACE_ISOLATION PRIVATE_BIND NAMESPACE_CLEANUP SERVICE_IDENTITY SHIM_REGISTRATION BINDER_OBSERVED SERVICE_STOPPED BINDER_REMOVED",keys," ")
            for(i=1;i<=8;i++) if(seen[keys[i]]!=1)bad=1
            exit !(n==4&&!bad)
        }' "$1"
}
