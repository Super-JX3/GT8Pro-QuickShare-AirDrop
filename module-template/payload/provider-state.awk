# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Fixed metadata only. The provider may keep finished records in Active Transfers.
/^SERVICE / {headers++;if($2!~/^com[.]google[.]android[.]mosey\//||$NF!="user=0")bad=1;next}
/^__DUMP_RC=/ {marks++;if($0!="__DUMP_RC=0")bad=1;next}
/Permission Denial|Exception dumping|Error dumping|RemoteException|Dump was interrupted/ {bad=1}
/ExternalSharingService state:/ {service++}
/^[[:space:]]*--- Active Transfers \([0-9]+\) ---[[:space:]]*$/ {
 section_count++
 count=$0;sub(/^.*\(/,"",count);sub(/\).*$/,"",count)
 expected=count+0
 in_transfers=1
 next
}
/^[[:space:]]*Receive provider BLE scanning:/ && in_transfers {
 section_end++
 in_transfers=0
}
in_transfers && NF {
 if($0~/^[[:space:]]*#+[[:space:]]*$/)next
 rows++
 if($0!~/^[[:space:]]*TransferState[(]/){bad=1;next}
 fields=$0
 if(gsub(/transferJob=/,"",fields)!=1 || gsub(/isTransferFinished=/,"",fields)!=1 ||
    gsub(/shareContentDeferred=/,"",fields)!=1){bad=1;next}
 if($0!~/,[[:space:]]*transferJob=[A-Za-z0-9_.$]+[{]Completed[}]@[0-9a-fA-F]+,[[:space:]]*transferId=/ ||
    $0!~/,[[:space:]]*isTransferFinished=true,[[:space:]]*shareContentDeferred=(null|[A-Za-z0-9_.$]+[{]Completed[}]@[0-9a-fA-F]+)[)][[:space:]]*$/)bad=1
}
/Receive provider transferring: false/ {recv_idle++}
/Receive provider transferring: true/ {recv_active++}
/isTransferFinished=false/ {unfinished++}
/activeTransfers=/ {list_count++;if($0~/activeTransfers=\[\]/)list_empty++;else list_busy++}
END {
 ok=headers==1&&marks==1&&!bad&&service==1&&section_count==1&&section_end==1&&!in_transfers&&rows+0==expected&&recv_idle==1&&list_empty>=1&&list_count==list_empty&&recv_active==0&&unfinished==0&&list_busy==0
 print "PROVIDER_TRANSFER_CLASS="(ok?"IDLE_SNAPSHOT":"UNKNOWN")
 exit !ok
}
