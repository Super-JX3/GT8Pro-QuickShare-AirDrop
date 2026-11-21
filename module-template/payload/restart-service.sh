#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
PATH=/system/bin:/system/xbin
LC_ALL=C
export PATH LC_ALL
umask 077
set -f

p2p_state() {
    (timeout -k 1 4 dumpsys wifip2p; printf '\n__P2P_RC=%s\n' "$?") 2>/dev/null | awk '
        /^[[:space:]]*mWifiP2pInfo groupFormed:/ {
            rows++
            if ($4!="isGroupOwner:" || ($5!="true" && $5!="false")) bad=1
            if ($3=="true") state="ACTIVE"
            else if ($3=="false") state="IDLE"
            else bad=1
        }
        /^__P2P_RC=/ {markers++; if ($0!="__P2P_RC=0") bad=1}
        /Permission Denial|Exception dumping|Error dumping|Dump was interrupted/ {bad=1}
        END {if (rows==1 && markers==1 && !bad) print state; else exit 1}'
}

binder_state() {
    local reply
    reply=$(timeout -k 1 3 service check "$1" 2>/dev/null) || return 1
    case "$reply" in
        "Service $1: found") echo PRESENT ;;
        "Service $1: not found") echo ABSENT ;;
        *) return 1 ;;
    esac
}

radio_state() {
    (timeout -k 1 3 ip -o link show; printf '\n__LINK_RC=%s\n' "$?") 2>/dev/null | awk '
        /^[0-9]+: [^ ]+: </ {
            links++
            if ($2=="wonder0:" || $2~/^wonder0@[^ ]+:$/) {
                matches++
                flags=$3
                sub(/^</,"",flags); sub(/>$/,"",flags)
                state=(("," flags ",")~/,UP,/ ? "UP" : "DOWN")
            }
        }
        /^__LINK_RC=/ {markers++; if ($0!="__LINK_RC=0") bad=1}
        END {
            if (!links || matches>1 || markers!=1 || bad) exit 1
            print (matches ? state : "ABSENT")
        }'
}

android_binder=com.google.android.moseyservice.IMoseyService/default
pixel_binder=com.google.pixel.moseyservice.IMoseyService/default

snapshot() {
    local p2p binder radio
    p2p=$(p2p_state) || p2p=UNKNOWN
    binder=$(binder_state "$android_binder") || binder=UNKNOWN
    radio=$(radio_state) || radio=UNKNOWN
    printf 'STATUS P2P=%s BINDER=%s RADIO=%s\n' "$p2p" "$binder" "$radio"
}

transfer_idle() {
    [ "$(sh "$d/transfer-idle.sh")" = TRANSFER_CLASS=IDLE ]
}

service_idle() {
    local provider
    [ ! -e "$root/action-lock" ] && [ -z "$(pidof mosey_server)" ] || return 1
    provider=$(timeout -k 1 4 cmd package query-services --components --user 0         -a com.google.android.nearby.SHARING_PROVIDER -p com.google.android.mosey) || return 1
    [ "$provider" = 'No services found' ] || return 1
    [ "$(binder_state "$android_binder")" = ABSENT ] && [ "$(binder_state "$pixel_binder")" = ABSENT ]
}

reclaim() {
    local i state outcome
    # Repeated samples reduce races but do not provide a transfer admission barrier.
    for i in 1 2 3; do
        transfer_idle || { echo TRANSFER_BUSY; return 1; }
        [ "$i" = 3 ] || sleep 1
    done
    for i in 1 2 3 4 5 6 7 8 9 10; do
        [ ! -e "$root/action-lock" ] && [ -z "$(pidof mosey_server)" ] && break
        sleep 1
    done
    service_idle || { echo SERVICE_ACTIVE; return 1; }
    state=$(p2p_state) || { echo P2P_RELEASE_FAILED; return 1; }
    if [ "$state" = ACTIVE ]; then
        # The positive UI action explicitly authorizes release of the current group.
        timeout -k 1 5 cmd wifip2p init >/dev/null 2>&1 || { echo P2P_RELEASE_FAILED; return 1; }
        outcome=RESTART_READY
        state=$(p2p_state) || outcome=P2P_RELEASE_FAILED
        if [ "$outcome" = RESTART_READY ] && [ "$state" = ACTIVE ]; then
            if ! service_idle; then
                outcome=SERVICE_ACTIVE
            elif ! transfer_idle; then
                outcome=TRANSFER_BUSY
            elif ! timeout -k 1 8 cmd wifip2p remove-group >/dev/null 2>&1; then
                outcome=P2P_RELEASE_FAILED
            fi
        fi
        timeout -k 1 5 cmd wifip2p deinit >/dev/null 2>&1 || outcome=P2P_RELEASE_FAILED
        [ "$outcome" = RESTART_READY ] || { echo "$outcome"; return 1; }
        for i in 1 2 3 4 5; do
            state=$(p2p_state) || state=UNKNOWN
            [ "$state" = IDLE ] && break
            [ "$i" = 5 ] || sleep 1
        done
        [ "$state" = IDLE ] || { echo P2P_RELEASE_FAILED; return 1; }
    fi
    service_idle || { echo SERVICE_ACTIVE; return 1; }
    transfer_idle || { echo TRANSFER_BUSY; return 1; }
    [ "$(p2p_state)" = IDLE ] || { echo P2P_RELEASE_FAILED; return 1; }
    echo RESTART_READY
}

[ "$#" = 1 ] || { echo MODULE_UNAVAILABLE; exit 1; }
case "$1" in status|reclaim) ;; *) echo MODULE_UNAVAILABLE; exit 1 ;; esac
m=/data/adb/modules/gt8pro.mosey.integrated
root=/data/adb/gt8pro-mosey-service
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] && [ "$(getenforce)" = Enforcing ] || { echo MODULE_UNAVAILABLE; exit 1; }
[ ! -L "$m" ] && [ -d "$m" ] || { echo MODULE_UNAVAILABLE; exit 1; }
for flag in disable remove update; do
    [ ! -e "$m/$flag" ] && [ ! -L "$m/$flag" ] || { echo MODULE_UNAVAILABLE; exit 1; }
done
if [ "$1" = status ]; then
    snapshot
    exit
fi

manifest=$m/payload.sha256
[ ! -L "$manifest" ] && [ -f "$manifest" ] || { echo MODULE_UNAVAILABLE; exit 1; }
sum=$(sha256sum "$manifest") || exit 1
sum=${sum%% *}
case "$sum" in *[!a-f0-9]*|'') exit 1;; esac
[ "${#sum}" = 64 ] || exit 1
d=/data/adb/gt8pro-mosey-daily/runtime-integrated-$sum
[ ! -L "$d" ] && [ "$(stat -c '%u:%a' "$d")" = 0:700 ] && [ "$(readlink -f "$d")" = "$d" ] || { echo MODULE_UNAVAILABLE; exit 1; }
for pair in 'transfer-idle.sh:e156907644bfdaecfd9dbc3e5d5df281d5fe3aeea2a65efd39825c55d3e87db2' \
            'bind-common.sh:e6a75e680b406e4a18f07ef1e9627e2cc02aeb20046ff44a6b996486d8d3ab7f' \
            'recover-v9.sh:ca63c55950b1a629a5da0dc76b19da719f48f428fbeb6e31c0fd3e4a53fd9ecf'; do
    f=$d/${pair%%:*}
    expected=${pair#*:}
    [ ! -L "$f" ] && [ "$(stat -c '%u:%a' "$f")" = 0:600 ] && \
        [ "$(sha256sum "$f" | cut -d ' ' -f1)" = "$expected" ] || exit 1
done
reclaim
