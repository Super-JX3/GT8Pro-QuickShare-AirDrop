#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Pure transition; caller validates observations and performs actions.
# Arguments: phase, consecutive count, observation. A launch must return before WAIT_CLOSED.
gt8_watch_step() {
 [ "$#" = 3 ] || { echo INVALID; return 1; }
 case "$1" in ARMED|WAIT_CLOSED) ;; *) echo INVALID; return 1;; esac
 case "$2" in 0|1|2|3) ;; *) echo INVALID; return 1;; esac
 case "$3" in TARGET_TOP|CLOSED_CONFIRMED|OTHER_OR_UNKNOWN) ;; *) echo INVALID; return 1;; esac
 if [ "$1" = ARMED ]; then
  if [ "$3" = TARGET_TOP ]; then
   n=$(($2+1)); [ "$n" -lt 2 ] && echo "ARMED $n WAIT" || echo 'WAIT_CLOSED 0 LAUNCH'
  else echo 'ARMED 0 WAIT'; fi
 else
  if [ "$3" = CLOSED_CONFIRMED ]; then
   n=$(($2+1)); [ "$n" -lt 3 ] && echo "WAIT_CLOSED $n WAIT" || echo 'ARMED 0 REARM'
  else echo 'WAIT_CLOSED 0 WAIT'; fi
 fi
}
