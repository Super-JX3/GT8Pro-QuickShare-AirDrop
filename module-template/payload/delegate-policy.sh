#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Backend callbacks must hold the session mutation lock while doing the
# ownership checks and start/stop operations. Never stop a pre-existing delegate.
gt8_delegate_run() {
    [ "$#" = 1 ] || return 2
    case "$1" in ''|*[!0-9]*) return 2;;esac
    [ "$1" -ge 1 ] && [ "$1" -le 1800 ] || return 2
    gt8_delegate_begin || { echo DELEGATE=NOT_STARTED; return 1; }
    case "$(gt8_delegate_count)" in
        0) ;;
        *) gt8_delegate_unlock; echo DELEGATE=PREEXISTING_OR_UNKNOWN; return 1;;
    esac
    if ! gt8_delegate_identity; then
        gt8_delegate_unlock; echo DELEGATE=IDENTITY_UNCONFIRMED; return 1
    fi
    if ! gt8_delegate_mark; then
        gt8_delegate_unlock; echo DELEGATE=MARK_FAILED; return 1
    fi
    # Start may have succeeded even if its response was lost. The backend
    # makes a scoped stop request while ownership is still held in that case.
    if ! gt8_delegate_start; then
        if gt8_delegate_stop; then echo DELEGATE=START_FAILED_STOP_REQUESTED; else echo DELEGATE=START_FAILED_STOP_UNCONFIRMED; fi
        gt8_delegate_unlock; return 1
    fi
    case "$(gt8_delegate_count)" in
        1) ;;
        *)
            if gt8_delegate_stop; then echo DELEGATE=VERIFY_FAILED_STOP_REQUESTED; else echo DELEGATE=VERIFY_FAILED_STOP_UNCONFIRMED; fi
            gt8_delegate_unlock; return 1;;
    esac
    gt8_delegate_unlock
    echo DELEGATE=ACTIVE
    i=0
    while [ "$i" -lt "$1" ]; do
        gt8_delegate_continue || break
        gt8_delegate_sleep || break
        i=$((i+1))
    done
    printf 'DELEGATE_OBSERVED_SECONDS=%s\n' "$i"
    gt8_delegate_begin || { echo DELEGATE=CLEANUP_OWNER_UNCONFIRMED;return 1; }
    # A replacement app process must not be touched. If the original is gone,
    # do not assume that the delegate belongs to a new process.
    if ! gt8_delegate_identity; then
        gt8_delegate_unlock; echo DELEGATE=CLEANUP_IDENTITY_UNCONFIRMED; return 1
    fi
    if ! gt8_delegate_owned; then
        gt8_delegate_unlock; echo DELEGATE=CLEANUP_NOT_OWNED; return 1
    fi
    if ! gt8_delegate_stop; then
        gt8_delegate_unlock; echo DELEGATE=STOP_UNCONFIRMED; return 1
    fi
    case "$(gt8_delegate_count)" in
        0) gt8_delegate_unlock; echo DELEGATE=STOPPED; return 0;;
        *) gt8_delegate_unlock; echo DELEGATE=STOP_UNCONFIRMED; return 1;;
    esac
}

# Called by the owner only after the sidecar is proven dead. The backend must
# verify its recorded PID/start token and hold the same session mutation lock.
gt8_delegate_recover() {
    [ "$#" = 0 ] || return 2
    gt8_delegate_begin || { echo DELEGATE_RECOVERY=OWNER_UNCONFIRMED;return 1; }
    if ! gt8_delegate_sidecar_gone; then
        gt8_delegate_unlock;echo DELEGATE_RECOVERY=SIDECAR_NOT_CONFIRMED_DEAD;return 1
    fi
    if ! gt8_delegate_identity || ! gt8_delegate_owned; then
        gt8_delegate_unlock;echo DELEGATE_RECOVERY=IDENTITY_OR_OWNERSHIP_UNCONFIRMED;return 1
    fi
    case "$(gt8_delegate_count)" in
        0) gt8_delegate_unlock;echo DELEGATE_RECOVERY=ALREADY_STOPPED;return 0;;
        1) ;;
        *) gt8_delegate_unlock;echo DELEGATE_RECOVERY=COUNT_UNCONFIRMED;return 1;;
    esac
    if ! gt8_delegate_stop; then
        gt8_delegate_unlock;echo DELEGATE_RECOVERY=STOP_UNCONFIRMED;return 1
    fi
    case "$(gt8_delegate_count)" in
        0) gt8_delegate_unlock;echo DELEGATE_RECOVERY=STOPPED;return 0;;
        *) gt8_delegate_unlock;echo DELEGATE_RECOVERY=STOP_UNCONFIRMED;return 1;;
    esac
}
