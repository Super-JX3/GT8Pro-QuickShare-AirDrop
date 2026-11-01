# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Fixed metadata only; non-empty or unfamiliar service dumps are unknown.
/^SERVICE / {headers++;if($2!~/^com[.]google[.]android[.]mosey\//||$NF!="user=0")bad=1;next}
/^__DUMP_RC=/ {marks++;if($0!="__DUMP_RC=0")bad=1;next}
/Permission Denial|Exception dumping|Error dumping|RemoteException|Dump was interrupted/ {bad=1}
/ExternalSharingService state:/ {service++}
/Active Transfers \(0\)/ {empty++}
/Active Transfers \([1-9][0-9]*\)/ {active++}
/Receive provider transferring: false/ {recv_idle++}
/Receive provider transferring: true/ {recv_active++}
/isTransferFinished=false/ {unfinished++}
/activeTransfers=/ {list_count++;if($0~/activeTransfers=\[\]/)list_empty++;else list_busy++}
END {
 ok=headers==1&&marks==1&&!bad&&service==1&&empty==1&&recv_idle==1&&list_empty>=1&&list_count==list_empty&&active==0&&recv_active==0&&unfinished==0&&list_busy==0
 print "PROVIDER_TRANSFER_CLASS="(ok?"IDLE_SNAPSHOT":"UNKNOWN")
 exit !ok
}
