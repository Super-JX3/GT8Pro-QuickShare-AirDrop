#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
PATH=/system/bin:/system/xbin
export PATH
LC_ALL=C
export LC_ALL
set -f
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] && [ "$(getprop ro.product.model)" = RMX5200 ] && [ "$(getprop ro.build.display.id)" = 'RMX5200_16.0.10.501(CN01)' ] && [ "$(getenforce)" = Enforcing ] || exit 1
[ "$(timeout -k 1 5 am get-current-user)" = 0 ] || exit 1
(
 timeout -k 1 8 dumpsys activity --user 0 service com.google.android.gms/.chimera.PersistentApiServiceNoInstantApps
 printf '\n__IDLE_RC=%s\n' "$?"
) 2>&1 | awk '
# Recognize only complete, paired table rows; do not output values or identifiers.
function trim(x){gsub(/^[[:space:]]+|[[:space:]]+$/,"",x);return x}
function terminal(x){return x=="COMPLETE"||x=="MEDIA_UNAVAILABLE"||x=="FAILED"||x=="REJECTED"||x=="CANCELLED"||x=="CANCELED"||x=="TIMED_OUT"||x=="TIMEDOUT"}
/^SERVICE / {heads++;if($2!="com.google.android.gms/.chimera.PersistentApiServiceNoInstantApps"||$NF!="user=0")bad=1;next}
/^__IDLE_RC=/ {marks++;if($0!="__IDLE_RC=0")bad=1;next}
/Permission Denial|Exception dumping|Error dumping|RemoteException|Dump was interrupted/ {bad=1}
/^[ ]*com[.]google[.]android[.]gms[.]nearby[.]sharing[.]NearbySharingService[ ]*$/ {sharing++;inside=1;next}
!inside {next}
/^[ ]*Outgoing Transfers:[ ]*$/ {if(phase||pending)bad=1;out++;phase=1;next}
/^[ ]*Incoming Transfers:[ ]*$/ {if(phase!=1||pending)bad=1;inc++;phase=2;next}
/^[ ]*Registered providers:[ ]*$/ {if(phase!=2||pending)bad=1;phase=3;next}
/^[ ]*com[.]google[.]android[.]gms[.]nearby[.]sharing[.]discovery[.]FastInitiation[ ]*$/ {checkpoint++;inside=0;next}
(phase==1||phase==2)&&NF {
 x=$0;gsub(/[[:space:]]/,"",x)
 if(x~/^[+|-]+$/)next
 if(x=="|Key|Value|Status|StartTime|EndTime|Duration|"){table[phase]++;next}
 n=split($0,c,"|");key=trim(c[2]);rows++
 if(pending==0){
  if(key!~/^[0-9]+$/){bad=1;next}
  if(n==8&&trim(c[4])=="COMPLETE")pending=1
  else if(n==9&&trim(c[4])==""&&trim(c[5])=="COMPLETE")pending=2
  else bad=1
 } else if(pending==1){
  if(n==9&&key==""&&trim(c[3])!=""&&trim(c[4])==""){
   for(i=5;i<=8;i++)if(trim(c[i])!="")bad=1
   wraps++;if(wraps>4)bad=1
   next
  } else if(n==9&&key==""&&trim(c[3])!=""&&terminal(trim(c[4]))){
   for(i=5;i<=8;i++)if(trim(c[i])!="")bad=1
  } else if(n==8&&key==""&&terminal(trim(c[3]))){
   for(i=4;i<=7;i++)if(trim(c[i])!="")bad=1
  } else bad=1
  pending=0;wraps=0
 } else {
  if(n!=8||key!=""||!terminal(trim(c[3])))bad=1
  for(i=4;i<=7;i++)if(trim(c[i])!="")bad=1
  pending=0
 }
}
END {
 ok=heads==1&&marks==1&&!bad&&sharing==1&&out==1&&inc==1&&checkpoint==1&&table[1]==1&&table[2]==1&&pending==0
 print "TRANSFER_CLASS="(ok?"IDLE":"UNKNOWN")
 exit !ok
}

' || exit 1
