#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Experimental sidecar; must be bundled with delegate-policy.sh at a pinned hash.
PATH=/system/bin:/system/xbin
export PATH
umask 077
set -f
OUT=$1; PROBE_PID=$2; PROBE_TOKEN=$3; LIMIT=$4
case "$OUT" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) exit 1;;esac
case "$PROBE_PID:$PROBE_TOKEN" in *[!0-9:]*|:*|*:) exit 1;;esac
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] || exit 1
GT8_BINDDIR=$OUT/binding-code
[ ! -L "$OUT" ] && [ "$(stat -c '%u:%a' "$OUT")" = 0:700 ] || exit 1
. /data/adb/modules/gt8pro.mosey.integrated/base-app/package-checks.sh
. "$GT8_BINDDIR/bind-common.sh"
. "$GT8_BINDDIR/handoff-lock.sh"
[ ! -L "$GT8_BINDDIR/delegate-policy.sh" ] && [ "$(stat -c '%u:%a' "$GT8_BINDDIR/delegate-policy.sh" 2>/dev/null)" = 0:600 ] && [ "$(sha256sum "$GT8_BINDDIR/delegate-policy.sh" | cut -d ' ' -f1)" = be01bfd183ce2cdc8de97fdcfcbf4905e6484689741b3e8a2b268f58544d4ca4 ] || exit 1
. "$GT8_BINDDIR/delegate-policy.sh"
BIND_PROC_ROOT=/proc
record=$OUT/binding-app-record.txt
[ ! -L "$record" ] && [ "$(stat -c '%u:%a' "$record")" = 0:600 ] || exit 1
app=$(awk -F= '$1=="PID"&&$2~/^[0-9]+$/{n++;v=$2}END{if(n==1)print v}' "$record")
token=$(awk -F= '$1=="START_TOKEN"&&$2~/^[0-9]+$/{n++;v=$2}END{if(n==1)print v}' "$record")
uid=$(awk -F= '$1=="UID"&&$2~/^[0-9]+$/{n++;v=$2}END{if(n==1)print v}' "$record")
[ "$(gt8_user0_mosey_uid)" = "$uid" ] || exit 1
case "$app:$token" in *[!0-9:]*|:*|*:) exit 1;;esac
stop_requested=0
trap 'stop_requested=1' 1 2 15
probe_alive(){
 [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$PROBE_PID/stat" 2>/dev/null)" = "$PROBE_TOKEN" ] || return 1
 tr '\000' '\n' <"/proc/$PROBE_PID/cmdline" 2>/dev/null | awk -v script="$GT8_BINDDIR/app-probe.sh" -v out="$OUT" '
 NR==1{if($0!="sh"&&$0!="/system/bin/sh")bad=1}
 NR==2{if($0!=script)bad=1} NR==3{if($0!=out)bad=1}
 END{exit !(NR==3&&!bad)}'
}
gt8_delegate_begin(){ gt8_handoff_begin "$OUT"; }
gt8_delegate_unlock(){ gt8_handoff_unlock; }
gt8_delegate_identity(){ bind_app_identity "$app" "$token" "$uid" && [ "$(gt8_mosey_main_pids)" = "$app" ]; }
gt8_delegate_count(){
 (timeout -k 1 5 dumpsys activity services --user 0 com.google.android.mosey;printf '\n__DELEGATE_RC=%s\n' "$?") 2>&1 | awk '
 /^ACTIVITY MANAGER SERVICES/{h++} /isFgsDelegate=true/{n++}
 /^__DELEGATE_RC=0$/{rc++} END{if(h==1&&rc==1)print n+0;else print "UNKNOWN"}'
}
gt8_delegate_mark(){ (set -C; printf '%s %s\n' "$app" "$token" >"$OUT/delegate-owner.record"); }
gt8_delegate_owned(){
 f=$OUT/delegate-owner.record
 [ ! -L "$f" ] && [ "$(stat -c '%u:%a' "$f" 2>/dev/null)" = 0:600 ] && [ "$(cat "$f")" = "$app $token" ]
}
gt8_delegate_start(){ timeout -k 1 5 cmd activity set-foreground-service-delegate --user 0 com.google.android.mosey start >/dev/null 2>&1; }
gt8_delegate_stop(){ timeout -k 1 5 cmd activity set-foreground-service-delegate --user 0 com.google.android.mosey stop >/dev/null 2>&1; }
gt8_delegate_continue(){ [ "$stop_requested" = 0 ] && [ ! -e "$OUT/delegate-stop.request" ] && probe_alive && gt8_delegate_identity; }
gt8_delegate_sleep(){ sleep 1; }
gt8_delegate_sidecar_gone(){
 f=$OUT/delegate-runner.record
 [ ! -L "$f" ] && [ "$(stat -c '%u:%a' "$f" 2>/dev/null)" = 0:600 ] && [ "$(wc -l <"$f")" = 1 ] || return 1
 read side_pid side_token extra <"$f" || return 1
 case "$side_pid:$side_token" in *[!0-9:]*|:*|*:) return 1;;esac
 [ -z "$extra" ] || return 1
 now=$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$side_pid/stat" 2>/dev/null)
 [ "$now" != "$side_token" ]
}
probe_alive || exit 1
if [ "$LIMIT" = recover ];then gt8_delegate_recover;exit $?;fi
# The parent records this exact sidecar before it can enable a delegate.
self_token=$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$$/stat")
i=0
while [ "$i" -lt 50 ];do
 f=$OUT/delegate-runner.record
 if [ ! -L "$f" ] && [ "$(stat -c '%u:%a' "$f" 2>/dev/null)" = 0:600 ] && [ "$(cat "$f")" = "$$ $self_token" ];then break;fi
 probe_alive || exit 1
 sleep 0.1;i=$((i+1))
done
[ "$i" -lt 50 ] || { echo DELEGATE=RUNNER_RECORD_UNCONFIRMED;exit 1; }
gt8_delegate_run "$LIMIT"
