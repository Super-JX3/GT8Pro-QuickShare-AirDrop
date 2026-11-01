#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Parse only the exact active package and user 0; never source package output.
app_package_check_updated() {
    # exit 1 means absent/ambiguous or not the original system privileged package.
    awk '
        /^Packages:/ {packages=1; next}
        /^[^ ]/ && !/^Packages:/ {packages=0; active=0; user=0}
        /^  Package \[/ {
            active=(packages && $0 ~ /^  Package \[com\.google\.android\.mosey\]/)
            if(active) count++
            user=0
        }
        !active {next}
        /^[ ]+codePath=/ {
            paths++; if(index($0,"codePath=/data/app/")>0) path_ok=1
        }
        /^[ ]+versionCode=/ {versions++; if($0 ~ /^[ ]+versionCode=60715([ ]|$)/) version_ok=1}
        /^[ ]+(pkgFlags|flags)=\[/ {
            if($0 ~ /(^|[ |[])SYSTEM([] |]|$)/) is_system=1
            if($0 ~ /(^|[ |[])UPDATED_SYSTEM_APP([] |]|$)/) updated=1
        }
        /^[ ]+(pkgPrivateFlags|privateFlags)=\[/ {
            if($0 ~ /(^|[ |[])PRIVILEGED([] |]|$)/) privileged=1
        }
        /^[ ]+User [0-9]+:/ {
            user=($0 ~ /^[ ]+User 0:/)
            if(user) {
                users++
                if($0 ~ /(^| )installed=true( |$)/) installed=1
                if($0 ~ /(^| )hidden=false( |$)/) visible=1
                if($0 ~ /(^| )suspended=false( |$)/) unsuspended=1
                if($0 ~ /(^| )enabled=[01]( |$)/) enabled=1
            }
        }
        END {exit !(count==1 && paths==1 && path_ok && versions==1 && version_ok && is_system && privileged && updated && users==1 && installed && visible && unsuspended && enabled)}
    ' "$1"
}
updated_code_profile_ok(){
 awk '
 BEGIN{split("NETWORK_FACTORY BLUETOOTH_PRIVILEGED CONNECTIVITY_USE_RESTRICTED_NETWORKS MANAGE_WIFI_INTERFACES LOCATION_HARDWARE INTERNET BLUETOOTH_SCAN BLUETOOTH_ADVERTISE NEARBY_WIFI_DEVICES ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION",want," ");for(i in want)required[want[i]]=1}
 /^CURRENT_CODE_PROFILE=PASS$/{code++}
 /^CURRENT_GOOGLE_SIGNER=PASS$/{signer++}
 /^CURRENT_MOSEY_UID=10366$/{uid++}
 /^CURRENT_PRIVILEGED=true$/{priv++}
 /^CURRENT_PROFILE_RESULT=PASS$/{ok++}
 /^CURRENT_PERMISSION=/{name=$1;sub(/^CURRENT_PERMISSION=/,"",name);if(name in required){seen[name]++;if($2=="REQUESTED=YES"&&$3=="GRANTED=YES")granted[name]++}}
 END{good=(code==1&&signer==1&&uid==1&&priv==1&&ok==1);for(k in required)if(seen[k]!=1||granted[k]!=1)good=0;exit !good}' "$1"
}
