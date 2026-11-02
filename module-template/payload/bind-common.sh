#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Fixed-component helpers; never executes saved output as code.
BIND_PACKAGE=com.google.android.mosey
BIND_COMPONENT=com.google.android.mosey/.ExternalSharingService
bind_out_ok() {
    case "$OUT" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) return 1 ;; esac
    [ ! -L "$OUT" ] && [ -d "$OUT" ] && [ "$(stat -c '%u:%a' "$OUT")" = 0:700 ] && [ "$(readlink -f "$OUT")" = "$OUT" ]
}
bind_capture() {
    bind_file=$1; bind_seconds=$2; shift 2
    case "$bind_seconds" in 5|6|8) ;; *) return 125 ;; esac
    case "$bind_file" in "$OUT"/binding-*.txt) ;; *) return 125 ;; esac
    case "${bind_file##*/}" in *[!a-z0-9.-]*) return 125 ;; esac
    [ ! -e "$bind_file" ] && [ ! -L "$bind_file" ] && [ ! -e "$bind_file.rc" ] && [ ! -L "$bind_file.rc" ] || return 125
    (
        timeout -k 1 "$bind_seconds" "$@"
        bind_command_rc=$?
        (set -C; printf '%s\n' "$bind_command_rc" >"$bind_file.rc") || exit 125
    ) 2>&1 | (set -C; cat >"$bind_file")
    [ "$?" = 0 ] || return 125
    bind_rc=$(awk 'NR==1&&/^[0-9]+$/&&$0<=255{v=$0;ok=1;next}{bad=1}END{if(NR==1&&ok&&!bad)print v}' "$bind_file.rc" 2>/dev/null)
    case "$bind_rc" in ''|*[!0-9]*) return 125 ;; esac
    return "$bind_rc"
}
bind_services_absent() {
    # Valid header + no target ServiceRecord, in two independently captured views.
    gt8_main_services_view "$1" | awk '
        /^ACTIVITY MANAGER SERVICES/ {headers++}
        /ServiceRecord\{/ && /com[.]google[.]android[.]mosey[\/.]/ {present=1}
        /Permission Denial|SecurityException|Error:|Exception dumping/ {bad=1}
        END {exit !(headers==1&&!present&&!bad)}'
}

bind_services_gms_owned() {
    gt8_main_services_view "$1" | awk '
      /^ACTIVITY MANAGER SERVICES/{h++}
      /ServiceRecord\{/ {records++;if($0~/u0 com[.]google[.]android[.]mosey\/([.]ExternalSharingService|com[.]google[.]android[.]mosey[.]ExternalSharingService)([ }]|$)/)target++}
      /Client AppBindRecord/ {clients++;if($0~/com[.]google[.]android[.]gms\/u0a[0-9]+/)gms++}
      /ConnectionRecord/ {connections++}
      /Permission Denial|Exception dumping|SecurityException|Error:/{bad=1}
      END{exit !(h==1&&records==1&&target==1&&clients==1&&gms==1&&connections>=1&&!bad)}'
}

bind_start_accepted() {
    awk '
        /^Starting service: Intent \{/ && /cmp=com[.]google[.]android[.]mosey\/([.]ExternalSharingService|com[.]google[.]android[.]mosey[.]ExternalSharingService)([ }]|$)/ {n++;next}
        NF {bad=1}
        END {exit !(n==1&&!bad)}' "$1"
}
bind_app_uid() {
    awk '
        /^Packages:/ {pkgs=1;next}
        /^[^ ]/ && !/^Packages:/ {pkgs=0;a=0}
        /^  Package \[/ {a=(pkgs&&$0~/^  Package \[com\.google\.android\.mosey\]/);if(a)n++}
        a && /^[ ]+(userId|appId)=[0-9]+[ ]*$/ {
            line=$0;sub(/^[ ]+(userId|appId)=/,"",line);sub(/[ ]*$/,"",line)
            if(uid!=""&&uid!=line)bad=1;uid=line
        }
        END {if(n==1&&!bad&&(uid+0)>=10000&&(uid+0)<20000)print uid;else exit 1}' "$1"
}
gt8_user0_mosey_uid() {
    (timeout -k 1 5 cmd package list packages -U --user 0 com.google.android.mosey; printf '\n__UID_RC=%s\n' "$?") 2>&1 | awk '
      /^package:com[.]google[.]android[.]mosey uid:[0-9]+$/ { n++;split($2,a,":");uid=a[2];next }
      /^package:/ { next }
      /^__UID_RC=0$/ { rc++;next }
      NF {bad=1}
      END {if(n==1&&rc==1&&!bad&&uid~/^[0-9]+$/&&uid>=10000&&uid<20000)print uid;else exit 1}'
}
bind_core_permissions() {
    awk '
        BEGIN {split("MANAGE_WIFI_INTERFACES BLUETOOTH_PRIVILEGED INTERNET CONNECTIVITY_USE_RESTRICTED_NETWORKS LOCATION_HARDWARE",p," ");for(i=1;i<=5;i++)want["android.permission."p[i]]=1}
        /^Packages:/ {pkgs=1;next}
        /^[^ ]/ && !/^Packages:/ {pkgs=0;a=0;s=0}
        /^  Package \[/ {a=(pkgs&&$0~/^  Package \[com\.google\.android\.mosey\]/);if(a)n++;s=0}
        !a {next}
        /^[ ]+install permissions:/ {s=1;next}
        /^[ ]+User [0-9]+:/ {s=0}
        s && $1~/^android[.]permission[.]/ {
            k=$1;sub(/:$/,"",k)
            if(k in want){seen[k]++;if($0~/(^|[ ,])granted=true([ ,]|$)/)granted[k]++}
        }
        END {ok=(n==1);for(k in want)if(seen[k]!=1||granted[k]!=1)ok=0;exit !ok}' "$1"
}
bind_app_identity() {
    case "$1:$2:$3" in *[!0-9:]*|:*|*:) return 1 ;; esac
    [ "$1" -gt 1 ] && [ "$2" -gt 0 ] && [ "$3" -ge 10000 ] && [ "$3" -lt 100000 ] || return 1
    [ "$(app_process_token "$BIND_PROC_ROOT/$1")" = "$2" ] || return 1
    awk 'NR==1{sub(/^.*[)] /,"");ok=($1~/^[RSDTtIPW]$/)}END{exit !(NR==1&&ok)}' "$BIND_PROC_ROOT/$1/stat" || return 1
    [ "$(tr '\000' '\n' <"$BIND_PROC_ROOT/$1/cmdline" 2>/dev/null)" = "$BIND_PACKAGE" ] || return 1
    awk -v uid="$3" '/^Uid:/{n++;ok=(NF==5&&$2==uid&&$3==uid&&$4==uid&&$5==uid)}END{exit !(n==1&&ok)}' "$BIND_PROC_ROOT/$1/status" || return 1
    tr -d '\000' <"$BIND_PROC_ROOT/$1/attr/current" | awk 'NR==1&&/^u:r:mosey_app:s0(:c[0-9]+(,c[0-9]+)*)?$/{ok=1}END{exit !(NR==1&&ok)}' || return 1
    [ "$(app_process_token "$BIND_PROC_ROOT/$1")" = "$2" ]
}
bind_app_report_ok() {
    awk -F= '
        BEGIN{w["APP_STREAM_GUARD"]="COMPLETED";w["PROVIDER_LEASE_PAUSE"]="PASS";w["NETWORK_FACTORY_GRANTED"]="PASS";w["SHARING_UI_START"]="ADOPTED";w["SHARING_UI_PRESERVED"]="PASS";w["SHARING_UI_VISIBLE"]="PASS";w["APP_PROCESS_IDENTITY"]="PASS";w["APP_BINDER_LOG"]="VERSION_OBSERVED";w["APP_IDENTITY_AFTER_CAPTURE"]="PASS";w["APP_FATAL_LOG"]="NOT_SEEN";w["APP_LOG_CAPTURE"]="CAPTURED";w["APP_CHECK_EXIT_CODE"]="0"}
        $1=="APP_LAUNCH" {launch++;if($2!="PASS"&&$2!="NOT_NEEDED_GMS_BOUND")bad=1;lv=$2}
        $1=="APP_SERVICE_STOPPED" {stops++;sv=$2}
        $1=="APP_TEST" {tests++;tv=$2}
        $1 in w {seen[$1]++;if(NF!=2||$2!=w[$1])bad=1}
        $1=="APP_GUARD" {guard++;if(NF!=2||($2!="RELEASED"&&$2!="REQUESTED"))bad=1}
        END{for(k in w)if(seen[k]!=1)bad=1;lifecycle=(lv=="PASS"&&sv=="PASS"&&tv=="VERSION_OBSERVED_AND_SERVICE_STOPPED")||(lv=="NOT_NEEDED_GMS_BOUND"&&sv=="NOT_OWNED_GMS_BOUND"&&tv=="VERSION_OBSERVED_SERVICE_GMS_OWNED");exit !(guard==1&&launch==1&&stops==1&&tests==1&&lifecycle&&!bad)}' "$1"
}
bind_label_report_ok() {
    awk -F= '$1=="LABEL_VIEWS"{n++;if(NF!=2||$2!="PASS")bad=1}
        $1=="LABEL_VIEW_BINDS"{b++;if(NF!=2||$2!="4")bad=1}
        END{exit !(n==1&&b==1&&!bad)}' "$1"
}
bind_emit() {
    awk -F= '
        /^SOAK_RESULT=(PASS|UNCONFIRMED)$/ || /^SOAK_ABORT_REASON=[A-Z_]+$/ {print;next}
        /^SOAK_MEASURED_SECONDS=[0-9]+$/ {print;next}
        /^SYSTEM_SHARE_ROUTE=CHOOSER_TO_GMS_QUICK_SHARE$/ {print;next}
        /^TRANSFER_FIXTURE_RECEIPT=(VERIFIED|NOT_CONFIRMED)$/ {print;next}
        /^APP_STREAM_GUARD=COMPLETED$/ || /^NETWORK_FACTORY_GRANTED=PASS$/ || /^PROVIDER_LEASE_PAUSE=PASS$/ || /^PROVIDER_LEASE_GUARD=(RELEASED|EXPIRED_PAUSED)$/ {print;next}
        /^SHARING_UI_META=(FOCUS_UNCONFIRMED|CAPTURE_UNCONFIRMED|SHAPE_UNCONFIRMED|CAPTURED)$/ || /^SHARING_UI_(GMS_SURFACE|SYSTEM_PERMISSION_SURFACE|ONBOARDING|BLUETOOTH_PROMPT|WIFI_PROMPT|ACCOUNT_PROMPT|TERMS_PROMPT|DISCOVERY_SURFACE|PERMISSION_PROMPT)=(SEEN|NOT_SEEN)$/ {print;next}
        /^SERVICE_STOP_MODE=(DRAINED|QUIET_BEST_EFFORT|EMERGENCY|UNCONFIRMED)$/ {print;next}
        /^SHARING_UI_START=(ADOPTED|FAILED|PREEXISTING_OR_UNCONFIRMED)$/ || /^SHARING_UI_(PRESERVED|VISIBLE)=(PASS|UNCONFIRMED)$/ {print;next}
        /^APP_(LAUNCH|PROCESS_IDENTITY|SERVICE_STOPPED)=(PASS|UNCONFIRMED|NOT_NEEDED_GMS_BOUND|NOT_OWNED_GMS_BOUND)$/ ||
        /^APP_BINDER_LOG=(VERSION_OBSERVED|NULL_OBSERVED|UNCONFIRMED)$/ ||
        /^APP_GUARD=(RELEASED|REQUESTED|UNCONFIRMED)$/ ||
        /^APP_TEST=(NOT_RUN|UID_UNVERIFIED|ALREADY_RUNNING|GUARD_UNAVAILABLE|CLOCK_UNVERIFIED|STOP_UNCONFIRMED|VERSION_OBSERVED_AND_SERVICE_STOPPED|VERSION_OBSERVED_SERVICE_GMS_OWNED|BINDING_UNCONFIRMED)$/ {print;next}
        /^APP_IDENTITY_AFTER_CAPTURE=(PASS|UNCONFIRMED)$/ ||
        /^APP_LOG_CAPTURE=(NOT_ATTEMPTED|FAILED|CAPTURED|WINDOW_UNVERIFIED)$/ ||
        /^APP_LOG_EVENTS=(EMPTY|PRESENT)$/ ||
        /^APP_(CREATE_LOG|PROVIDER_LOG|FATAL_LOG|UNDECLARED_SERVICE_LOG)=(SEEN|NOT_SEEN)$/ {print;next}
        /^APP_(DISCOVERY_CALLBACK_LOG|ADVERTISING_CALLBACK_LOG|CONTROLLER_START_DONE_LOG|CONTROLLER_LOOP_ERROR_LOG|CONTROLLER_COMMAND_LOG|ACONFIG_DISABLED_LOG|GMS_BROKER_ERROR_LOG|GMS_API_UNAVAILABLE_LOG|ACTOR_CLOSED_LOG|SECURITY_EXCEPTION_LOG|AIDL_LOOKUP_MISS_LOG)=(SEEN|NOT_SEEN)$/ {print;next}
        /^LABEL_VIEWS=PASS$/ || /^LABEL_VIEW_BINDS=4$/ ||
        /^LABEL_VIEW_FILE=(LOAD_PROBE_LIBRARY|DAEMON_LIBRARY|REGISTRATION_LIBRARY|LAUNCHER)$/ ||
        /^LABEL_VIEW_CHECK=(PRIVATE_VIEW_UNVERIFIED|SOURCE_UNVERIFIED|TARGET_UNVERIFIED|RECORD_FAILED|BIND_FAILED|BIND_UNVERIFIED)$/ {print;next}
        $1=="APP_CHECK_EXIT_CODE"&&NF==2&&$2~/^[0-9]+$/&&$2<=255 {print}
    ' "$1"
}
bind_log_classify() {
    # A fresh app PID/start token and bounded wall-clock interval are checked by
    # the caller. Only a complete numeric native-interface version log counts.
    awk -v pid="$2" -v since="$3" -v until="$4" '
        $1~/^[0-9]+[.][0-9]+$/&&$1>=since&&$1<=until&&$2==pid {
            if($4=="I"&&$5=="GT8ProBridge:"&&$6=="GT8BRIDGE_V1"&&$7=="event=APP_NATIVE_VERSION"&&$8=="process=MOSEY"&&NF==11&&$9=="backend=ANDROID"&&$10~/^value=A[1-9][0-9]{0,2}$/&&$11=="outcome=RETURNED"){positive++}
            if($4=="I"&&$5=="MoseyController:"&&$6=="MoseyController"&&$7=="got"&&$8=="interface"&&NF==9&&$9~/^A[1-9][0-9]*$/){positive++}
            if($5=="MoseyController:"&&$0~/Got null mosey binder[.]/)negative++
        }
        END {if(positive&&!negative)print "VERSION_OBSERVED";else if(negative&&!positive)print "NULL_OBSERVED";else print "UNCONFIRMED"}' "$1"
}
bind_observation_classify() {
    # Only same-PID, bounded epoch lines. No message, PID, timestamp or identifier
    # is emitted. Absence is NOT_SEEN, not proof the event never happened.
    awk -v pid="$2" -v since="$3" -v until="$4" '
        $1~/^[0-9]+[.][0-9]+$/&&$1>=since&&$1<=until&&$2==pid {
            events++
            if($5=="MoseyService:"&&$0~/ExternalSharingService doCreate called[.]$/)created=1
            if($5=="MoseyService:"&&$0~/ExternalSharingService getSharingProvider called[.]$/)provider=1
            if($5=="Mosey-ExternalProvider:"&&$0~/Mosey invoking (StartDiscovery|UpdateDiscoveryOptions)$/)discovery=1
            if($5=="Mosey-ExternalProvider:"&&$0~/Mosey invoking (StartAdvertising|UpdateAdvertising)$/)advertising=1
            if($5=="MoseyController:"&&$0~/Event received: /)command=1
            if($5=="MoseyController:"&&$0~/===== MoseyController start: done$/)startdone=1
            if($5=="MoseyController:"&&$0~/MoseyControllerCommandLoop finished with error:/)looperror=1
            if($5=="Mosey-ExternalProvider:"&&$0~/Mosey (startDiscovery|updateDiscoveryOptions|startAdvertising|updateAdvertising) skipped as aconfig feature is disabled$/)disabled=1
            if($0~/Failed to get service from broker|Unknown calling package name|DEVELOPER_ERROR/)broker=1
            if($0~/API_UNAVAILABLE|SERVICE_VERSION_UPDATE_REQUIRED|API: .* is not available/)unavailable=1
            if($5=="Mosey.SendProvider:"&&$0~/Actor channel is likely closed[.]$/)closed=1
            if($0~/java[.]lang[.]SecurityException:/)security=1
            if($5=="MoseyAidl:"&&$0~/Cannot get com[.]google[.]android[.]moseyservice[.]IMoseyService\/default or com[.]google[.]pixel[.]moseyservice[.]IMoseyService\/default$/)aidlmiss=1
            if($5=="AndroidRuntime:"&&$0~/FATAL EXCEPTION:/)fatal=1
            if($5=="libc:"&&$0~/Fatal signal [0-9]+/)fatal=1
            if(($5=="ServiceManager:"||$5=="servicemanager:")&&$0~/com[.]google[.](android|pixel)[.]moseyservice[.]IMoseyService\/default/&&$0~/not declared|isDeclared.*false/)undeclared=1
        }
        END {
            print "APP_LOG_EVENTS="(events?"PRESENT":"EMPTY")
            print "APP_CREATE_LOG="(created?"SEEN":"NOT_SEEN")
            print "APP_PROVIDER_LOG="(provider?"SEEN":"NOT_SEEN")
            print "APP_FATAL_LOG="(fatal?"SEEN":"NOT_SEEN")
            print "APP_UNDECLARED_SERVICE_LOG="(undeclared?"SEEN":"NOT_SEEN")
            print "APP_DISCOVERY_CALLBACK_LOG="(discovery?"SEEN":"NOT_SEEN")
            print "APP_ADVERTISING_CALLBACK_LOG="(advertising?"SEEN":"NOT_SEEN")
            print "APP_CONTROLLER_START_DONE_LOG="(startdone?"SEEN":"NOT_SEEN")
            print "APP_CONTROLLER_LOOP_ERROR_LOG="(looperror?"SEEN":"NOT_SEEN")
            print "APP_CONTROLLER_COMMAND_LOG="(command?"SEEN":"NOT_SEEN")
            print "APP_ACONFIG_DISABLED_LOG="(disabled?"SEEN":"NOT_SEEN")
            print "APP_GMS_BROKER_ERROR_LOG="(broker?"SEEN":"NOT_SEEN")
            print "APP_GMS_API_UNAVAILABLE_LOG="(unavailable?"SEEN":"NOT_SEEN")
            print "APP_ACTOR_CLOSED_LOG="(closed?"SEEN":"NOT_SEEN")
            print "APP_SECURITY_EXCEPTION_LOG="(security?"SEEN":"NOT_SEEN")
            print "APP_AIDL_LOOKUP_MISS_LOG="(aidlmiss?"SEEN":"NOT_SEEN")
        }' "$1"
}

bind_network_factory_granted() {
 awk '
 /^Packages:/{packages=1;next}
 /^[^ ]/&&!/^Packages:/{packages=0;pkg=0;scope=0}
 /^  Package \[/ {pkg=(packages&&$0~/^  Package \[com[.]google[.]android[.]mosey\]/);if(pkg)np++;scope=0}
 !pkg{next}
 /^[ ]+install permissions:/ {scope=1;next}
 /^[ ]+User [0-9]+:/ {scope=($0~/^[ ]+User 0:/?2:0);next}
 scope&&/^[ ]+android[.]permission[.]NETWORK_FACTORY: granted=true([ ,]|$)/{granted++}
 END{exit !(np==1&&granted==1)}' "$1"
}

gt8_mosey_main_pids() {
    gt8_scope_proc=${1:-/proc}
    gt8_scope_target=$(gt8_user0_mosey_uid) || return 1
    gt8_scope_result=
    gt8_scope_seen='|'
    for gt8_scope_pid in $(pidof com.google.android.mosey 2>/dev/null); do
        case "$gt8_scope_pid" in ''|*[!0-9]*) return 1;;esac
        [ "${#gt8_scope_pid}" -le 10 ] && [ "$gt8_scope_pid" -gt 0 ] || return 1
        case "$gt8_scope_seen" in *"|$gt8_scope_pid|"*) continue;;esac
        gt8_scope_seen="$gt8_scope_seen$gt8_scope_pid|"
        [ -d "$gt8_scope_proc/$gt8_scope_pid" ] || continue
        gt8_scope_before=$(awk 'NR==1{sub(/^.*[)] /,"");if($20~/^[0-9]+$/)print $20}' "$gt8_scope_proc/$gt8_scope_pid/stat" 2>/dev/null)
        gt8_scope_uid=$(awk '/^Uid:/{if(NF==5&&$2~/^[0-9]+$/&&$2==$3&&$3==$4&&$4==$5)print $2}' "$gt8_scope_proc/$gt8_scope_pid/status" 2>/dev/null)
        gt8_scope_cmd=$(tr '\000' '\n' <"$gt8_scope_proc/$gt8_scope_pid/cmdline" 2>/dev/null)
        gt8_scope_after=$(awk 'NR==1{sub(/^.*[)] /,"");if($20~/^[0-9]+$/)print $20}' "$gt8_scope_proc/$gt8_scope_pid/stat" 2>/dev/null)
        [ -d "$gt8_scope_proc/$gt8_scope_pid" ] || continue
        [ -n "$gt8_scope_before" ] && [ "$gt8_scope_before" = "$gt8_scope_after" ] && [ "$gt8_scope_cmd" = com.google.android.mosey ] || return 1
        case "$gt8_scope_uid" in ''|*[!0-9]*) return 1;;esac
        if [ "$gt8_scope_uid" = "$gt8_scope_target" ];then
            gt8_scope_result="$gt8_scope_result $gt8_scope_pid"
        elif [ "$gt8_scope_uid" -ge 100000 ] && [ "$((gt8_scope_uid % 100000))" = "$gt8_scope_target" ];then
            : # Another Android user: inspect identity only and leave it untouched.
        else return 1;fi
    done
    [ -z "$gt8_scope_result" ] || printf '%s\n' "${gt8_scope_result# }"
    return 0
}
gt8_main_services_view() {
    awk '
    /^ACTIVITY MANAGER SERVICES/{print;next}
    /Permission Denial|Exception dumping|SecurityException|Error:/{print "Error: MAIN_USER_SERVICE_QUERY_FAILED";bad=1;next}
    /^[[:space:]]*User [0-9]+.*services:/{inside=0;next}
    /^[[:space:]]*[*] ServiceRecord\{/ {
        if($0~/ u0 com[.]google[.]android[.]mosey\/([.]ExternalSharingService|com[.]google[.]android[.]mosey[.]ExternalSharingService)([ }]|$)/)inside=1
        else if($0~/ u[1-9][0-9]* com[.]google[.]android[.]mosey\/([.]ExternalSharingService|com[.]google[.]android[.]mosey[.]ExternalSharingService)([ }]|$)/)inside=0
        else{inside=0;bad=1;print "Error: UNVERIFIED_SERVICE_RECORD"}
        if(inside)print
        next
    }
    /ServiceRecord\{/{print "Error: UNVERIFIED_SERVICE_SHAPE";bad=1;inside=0;next}
    inside{print}
    END{if(bad)exit 1}' "$1"
}
