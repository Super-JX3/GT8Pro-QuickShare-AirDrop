# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Only the ActivityManager canonical user-0 GMS main ProcessRecord is accepted.
/^ACTIVITY MANAGER RUNNING PROCESSES [(]dumpsys activity processes[)]$/ { headers++; next }
/^__PROCESSES_RC=/ { marks++; if ($0 != "__PROCESSES_RC=0") bad=1; next }
/^[ ]*\*APP\* UID [0-9]+ ProcessRecord\{[^}]*:com[.]google[.]android[.]gms\/u0/ {
 if ($0 !~ /^[ ]*\*APP\* UID [0-9]+ ProcessRecord\{[0-9a-f]+ [0-9]+:com[.]google[.]android[.]gms\/u0a[0-9]+\}[ ]*$/) { bad=1; next }
 line=$0; sub(/^[ ]*\*APP\* UID /,"",line); split(line,a," "); uid=a[1]+0
 proc=a[3]; sub(/:.*/,"",proc); pid=proc+0
 suffix=$0; sub(/^.*\/u0a/,"",suffix); sub(/\}.*/,"",suffix)
 if (uid<10000 || uid>=100000 || uid!=10000+suffix || pid<=0) { bad=1; next }
 count++; result=pid " " uid
}
END { if(headers==1 && marks==1 && count==1 && !bad)print result; else exit 1 }
