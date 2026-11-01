#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Parse only the exact active package and user 0; never source package output.
app_package_check() {
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
            paths++; if($0 ~ /^[ ]+codePath=\/(system\/)?system_ext\/priv-app\/MoseyApp$/) path_ok=1
        }
        /^[ ]+versionCode=/ {versions++; if($0 ~ /^[ ]+versionCode=13120([ ]|$)/) version_ok=1}
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
        END {exit !(count==1 && paths==1 && path_ok && versions==1 && version_ok && is_system && privileged && !updated && users==1 && installed && visible && unsuspended && enabled)}
    ' "$1"
}
app_permissions_check() {
    # $2 is install or runtime. Report counts only, never raw grant lines.
    awk -v mode="$2" '
        BEGIN {
            if(mode=="install") split("BLUETOOTH_PRIVILEGED LOCAL_MAC_ADDRESS MANAGE_WIFI_INTERFACES NETWORK_FACTORY CREATE_APP_SPECIFIC_NETWORK CONNECTIVITY_USE_RESTRICTED_NETWORKS LOCATION_HARDWARE",want," ")
            else if(mode=="runtime") split("BLUETOOTH_SCAN BLUETOOTH_ADVERTISE NEARBY_WIFI_DEVICES ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION",want," ")
            else bad=1
            total=(mode=="runtime"?6:7)
            for(i=1;i<=total;i++) required["android.permission."want[i]]=1
        }
        /^Packages:/ {packages=1; next}
        /^[^ ]/ && !/^Packages:/ {packages=0; active=0; section=0; user=0}
        /^  Package \[/ {active=(packages && $0 ~ /^  Package \[com\.google\.android\.mosey\]/); if(active)count++;section=0;user=0}
        !active {next}
        /^[ ]+User [0-9]+:/ {user=($0 ~ /^[ ]+User 0:/); section=0}
        /^[ ]+install permissions:/ {section=(mode=="install"); next}
        /^[ ]+runtime permissions:/ {section=(mode=="runtime" && user); next}
        /^[ ]*[a-zA-Z][^:]*:$/ && !/permissions:$/ {section=0}
        section && $1 ~ /^android[.]permission[.]/ {
            name=$1; sub(/:$/,"",name)
            if(required[name]) {
                seen[name]++
                if($0 ~ /(^|[ ,])granted=true([ ,]|$)/) grants[name]++
            }
        }
        END {
            n=0
            for(name in required) if(seen[name]==1 && grants[name]==1)n++
            if(count!=1 || bad)exit 2
            print n
            exit(n==total?0:1)
        }
    ' "$1"
}
app_provider_check() {
    # cmd package query-services --components output: exactly one component.
    awk '
        NF {n++;if($0!="com.google.android.mosey/com.google.android.mosey.ExternalSharingService" && $0!="com.google.android.mosey/.ExternalSharingService")bad=1}
        END {exit !(n==1&&!bad)}' "$1"
}
app_process_token() {
    sed 's/^.*) //' "$1/stat" 2>/dev/null | awk '{if(NF>=20 && $20~/^[0-9]+$/)print $20}'
}
app_mounted_files() {
    app_prefix=$1
    for app_rel in system_ext/priv-app/MoseyApp/MoseyApp.apk system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml system_ext/etc/default-permissions/default-permissions-com.google.android.mosey.xml; do
        app_expected=$(awk -v p="system/$app_rel" '$2==p{n++;h=$1}END{if(n==1)print h}' "$MODDIR/payload.sha256")
        [ "${#app_expected}" = 64 ] && gt8_hash "$app_prefix/$app_rel" "$app_expected" || return 1
        case "$(ls -Zd "$app_prefix/$app_rel" 2>/dev/null)" in u:object_r:system_file:s0\ *) ;; *) return 1 ;; esac
    done
}
