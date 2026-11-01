#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Caller provides gt8_read_transfer_state, returning exactly IDLE or UNKNOWN.
# This is an observation window, not a lock or proof of admission closure.
# Return 0 after 3 consecutive IDLE observations; all else resets the count.
gt8_wait_quiet() {
 [ "$#" = 1 ] || return 2
 case "$1" in ''|*[!0-9]*) return 2;;esac
 [ "$1" -ge 3 ] && [ "$1" -le 300 ] || return 2
 count=0;attempt=0
 while [ "$attempt" -lt "$1" ];do
  observed=$(gt8_read_transfer_state) || observed=UNKNOWN
  case "$observed" in IDLE) count=$((count+1));; *) count=0;;esac
  [ "$count" -lt 3 ] || { echo QUIET_WINDOW=OBSERVED;return 0; }
  attempt=$((attempt+1))
  [ "$attempt" -ge "$1" ] || gt8_quiet_sleep || return 2
 done
 echo QUIET_WINDOW=UNCONFIRMED
 return 1
}
