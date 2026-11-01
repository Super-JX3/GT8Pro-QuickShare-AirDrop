#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Candidate only: caller validates controller and run-directory identity.
# Root-private heartbeat is an advisory state, never proof of transfer gating.
# Output HOLD, DRAINED, or EMERGENCY. No filesystem writes or process signals.
gt8_lease_gate() {
 [ "$#" = 2 ] || { echo EMERGENCY;return 1; }
 dir=$1;now=$2
 case "$now" in ''|*[!0-9]*) echo EMERGENCY;return 1;;esac
 [ ! -L "$dir" ] && [ "$(stat -c '%u:%a' "$dir" 2>/dev/null)" = 0:700 ] || { echo EMERGENCY;return 1; }
 f=$dir/transfer-heartbeat
 [ ! -L "$f" ] && [ -f "$f" ] && [ "$(stat -c '%u:%a' "$f" 2>/dev/null)" = 0:600 ] || { echo EMERGENCY;return 1; }
 snapshot=$(cat "$f" && printf '__GT8_SNAPSHOT_END__\n') || { echo EMERGENCY;return 1; }
 after=$(awk 'NR==1{printf "%.0f",$1*1000}' /proc/uptime) || { echo EMERGENCY;return 1; }
 case "$after" in ''|*[!0-9]*) echo EMERGENCY;return 1;;esac
 [ "$after" -ge "$now" ] || { echo EMERGENCY;return 1; }
 printf '%s\n' "$snapshot" | awk -v now="$after" '
 NR==1 && NF==2 && $1~/^[0-9]+$/ && $1<=now && now-$1<=5000 {
  if($2=="DRAINED") result="DRAINED";
  else if($2=="ACTIVE"||$2=="UNKNOWN") result="HOLD";
 }
 NR==2 && $0=="__GT8_SNAPSHOT_END__" {end_marker=1;next}
 NR>1 {bad=1}
 END { if(NR!=2 || !end_marker || bad || result==""){print "EMERGENCY";exit 1} print result }
 '
}
