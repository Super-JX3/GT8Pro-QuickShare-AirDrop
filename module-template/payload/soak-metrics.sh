#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Numeric metrics from these three attested processes only.
soak_process_metrics(){
 sp_pid=$1;sp_token=$2;sp_uid=$3;sp_name=$4
 [ "$(app_process_token "/proc/$sp_pid")" = "$sp_token" ] || return 1
 [ "$(tr '\000' '\n' <"/proc/$sp_pid/cmdline")" = "$sp_name" ] || return 1
 awk -v uid="$sp_uid" '/^Uid:/{n++;ok=(NF==5&&$2==uid&&$3==uid&&$4==uid&&$5==uid)}END{exit !(n==1&&ok)}' "/proc/$sp_pid/status" || return 1
 sp_status=$(awk '/^VmRSS:/{r=$2}/^Threads:/{t=$2}END{if(r~/^[0-9]+$/&&t~/^[0-9]+$/)print r,t;else exit 1}' "/proc/$sp_pid/status") || return 1
 sp_ticks=$(awk 'NR==1{sub(/^.*[)] /,"");if($12~/^[0-9]+$/&&$13~/^[0-9]+$/)print $12+$13;else exit 1}' "/proc/$sp_pid/stat") || return 1
 sp_fds=$(find "/proc/$sp_pid/fd" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l) || return 1
 [ "$(app_process_token "/proc/$sp_pid")" = "$sp_token" ] || return 1
 printf '%s %s %s\n' "$sp_status" "$sp_ticks" "$sp_fds"
}
soak_prepare(){
 . /data/adb/modules/gt8pro.mosey.integrated/base-service/common.sh
 . /data/adb/modules/gt8pro.mosey.integrated/base-service/service-common.sh
 . /data/adb/modules/gt8pro.mosey.integrated/base-service/registration-checks.sh
 PROC_ROOT=/proc;BIN=/odm/bin/mosey_server
 gt8_service_record && registration_identity "$SV_PID" "$SV_TOKEN" || return 1
 SOAK_NATIVE_PID=$SV_PID;SOAK_NATIVE_TOKEN=$SV_TOKEN
 gms_record=$( (timeout -k 1 8 dumpsys activity processes;printf '\n__PROCESSES_RC=%s\n' "$?") 2>&1 | awk -f "$GT8_BINDDIR/gms-main-pid.awk") || return 1
 set -- $gms_record
 [ "$#" = 2 ] || return 1
 SOAK_GMS_PID=$1;SOAK_GMS_UID=$2
 case "$SOAK_GMS_PID:$SOAK_GMS_UID" in *[!0-9:]*|:*|*:) return 1;;esac
 [ "$(tr '\000' '\n' <"/proc/$SOAK_GMS_PID/cmdline")" = com.google.android.gms ] || return 1
 u=$(awk '/^Uid:/{if(NF==5&&$2==$3&&$3==$4&&$4==$5)print $2}' "/proc/$SOAK_GMS_PID/status")
 [ "$u" = "$SOAK_GMS_UID" ] || return 1
 SOAK_GMS_TOKEN=$(app_process_token "/proc/$SOAK_GMS_PID")
 case "$SOAK_GMS_TOKEN" in ''|*[!0-9]*) return 1;;esac
 SOAK_BOOT=$(cat /proc/sys/kernel/random/boot_id) || return 1
 SOAK_SYSTEM_PID=$(pidof system_server);case "$SOAK_SYSTEM_PID" in ''|*[!0-9]*)return 1;;esac
 SOAK_SYSTEM_TOKEN=$(app_process_token "/proc/$SOAK_SYSTEM_PID")
 (set -C; : >"$OUT/soak-metrics.txt") || return 1
}
soak_sample(){
 [ "$(cat /proc/sys/kernel/random/boot_id)" = "$SOAK_BOOT" ] && [ "$(getenforce)" = Enforcing ] || return 1
 [ "$(app_process_token "/proc/$SOAK_SYSTEM_PID")" = "$SOAK_SYSTEM_TOKEN" ] || return 1
 bind_app_identity "$BIND_PID" "$BIND_TOKEN" "$BIND_UID" && registration_identity "$SOAK_NATIVE_PID" "$SOAK_NATIVE_TOKEN" || return 1
 n=$(soak_process_metrics "$SOAK_NATIVE_PID" "$SOAK_NATIVE_TOKEN" 1000 /odm/bin/mosey_server) || return 1
 a=$(soak_process_metrics "$BIND_PID" "$BIND_TOKEN" "$BIND_UID" com.google.android.mosey) || return 1
 g=$(soak_process_metrics "$SOAK_GMS_PID" "$SOAK_GMS_TOKEN" "$SOAK_GMS_UID" com.google.android.gms) || return 1
 battery=$(timeout -k 1 2 dumpsys battery | awk '/^[ ]*temperature: [0-9]+$/{t=$2;n++}END{if(n==1)print t;else exit 1}') || return 1
 case "$battery" in ''|*[!0-9]*)return 1;;esac
 if [ "$battery" -ge 450 ];then echo SOAK_ABORT_REASON=BATTERY_TEMPERATURE;return 1;fi
 set -- $n $a $g
 [ "$#" = 12 ] || return 1
 # Conservative catastrophic-memory bound, not a leak verdict.
 [ "$1" -lt 524288 ] && [ "$5" -lt 1048576 ] || { echo SOAK_ABORT_REASON=MEMORY_LIMIT;return 1; }
 printf 'SOAK_SAMPLE elapsed_s=%s native_rss_kb=%s native_threads=%s native_cpu_ticks=%s native_fds=%s app_rss_kb=%s app_threads=%s app_cpu_ticks=%s app_fds=%s gms_rss_kb=%s gms_threads=%s gms_cpu_ticks=%s gms_fds=%s battery_deci_c=%s\n' "$soak_elapsed" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" "$battery" >>"$OUT/soak-metrics.txt"
}
