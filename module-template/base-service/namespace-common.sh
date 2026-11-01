#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Original adaptation helpers. No command runs when sourced.
gt8_namespace_token() {
    printf '%s\n' "$1" | grep -Eq '^mnt:\[[0-9]+\]$'
}
gt8_namespace_separate() {
    gt8_namespace_token "$1" && gt8_namespace_token "$2" && [ "$1" != "$2" ]
}
gt8_private_mountinfo() {
    # A private tree must have no outgoing shared or incoming master relationship.
    # Validate each complete line before accepting absence of optional fields.
    awk '
        NF < 10 || $1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+$/ {bad=1;next}
        {
            sep=0
            for(i=7;i<=NF;i++) {
                if($i=="-"){sep=i;break}
                if($i ~ /^(shared:|master:|propagate_from:)/) bad=1
            }
            if(!sep || NF!=sep+3) bad=1
            if($5=="/") root++
            n++
        }
        END {exit !(n>0 && root==1 && !bad)}' "$1"
}
gt8_namespace_parent_view() {
    readlink /proc/self/ns/mnt || return 1
    cat /proc/self/mountinfo || return 1
    stat -c '%d:%i:%s:%a:%u' /odm/bin/mosey_load_probe || return 1
    ls -Zd /odm/bin/mosey_load_probe || return 1
}
gt8_namespace_source() {
    # Only the module-owned original probe, never the repaired staging copy.
    gt8_source_root=$(cd "$MODDIR" && pwd -P) || return 1
    GT8_PROBE_SOURCE=
    for gt8_candidate in "$gt8_source_root/odm/bin/mosey_load_probe" "$gt8_source_root/system/odm/bin/mosey_load_probe"; do
        [ -f "$gt8_candidate" ] || continue
        gt8_real=$(readlink -f "$gt8_candidate") || return 1
        case "$gt8_real" in
            "$gt8_source_root/odm/bin/mosey_load_probe"|"$gt8_source_root/system/odm/bin/mosey_load_probe") ;;
            *) return 1 ;;
        esac
        gt8_hash "$gt8_real" f736d6e9048ed0d80c3211fed3d2d159c347a017d5666be6104472596fb8ed9d || return 1
        [ "$(stat -c '%u:%a' "$gt8_real")" = 0:755 ] || return 1
        case "$(ls -Zd "$gt8_real")" in
            u:object_r:mosey_server_exec:s0\ *) ;;
            *) return 1 ;;
        esac
        GT8_PROBE_SOURCE=$gt8_real
        return 0
    done
    return 1
}
gt8_namespace_report_ok() {
    awk -F= '
        BEGIN {w[1]="BASELINE_IDENTITY_OK";w[2]="PRELOAD_OK";w[3]="PROBE_PRELOAD_CONFIRMED"}
        $1=="RESULT" {n++;if(NF!=2||$2!=w[n])bad=1}
        $1=="NAMESPACE_ISOLATION" {iso++;if(NF!=2||$2!="PASS")bad=1}
        $1=="PRIVATE_BIND" {binds++;if(NF!=2||$2!="PASS")bad=1}
        $1=="NAMESPACE_CLEANUP" {clean++;if(NF!=2||$2!="PASS")bad=1}
        END {exit !(n==3 && iso==1 && binds==1 && clean==1 && !bad)}' "$1"
}
