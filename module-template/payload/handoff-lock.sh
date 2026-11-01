#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Candidate primitive: hold across both ownership check and state mutation.
# A private stable lock file must already exist and must never be replaced.
gt8_handoff_lock(){
 [ "$#" = 1 ] || return 1
 lock_path=$1
 [ ! -L "$lock_path" ] && [ -f "$lock_path" ] && [ "$(stat -c '%u:%a' "$lock_path" 2>/dev/null)" = 0:600 ] || return 1
 exec 9<>"$lock_path" || return 1
 flock -x -n 9 9>&9 || { exec 9>&-;return 2; }
 # Caller must validate the current run's ownership while still holding fd 9.
}
gt8_handoff_unlock(){ flock -u 9 9>&9; exec 9>&-; }
# Invoke only while holding the handoff lock. File contains exactly one
# run name, controller PID and process start token from the same admission.
gt8_handoff_is_owner(){
 [ "$#" = 4 ] || return 1
 root=$1; run=$2; controller=$3; token=$4
 case "$run" in run.??????) ;; *) return 1;;esac
 case "$run" in *[!a-zA-Z0-9.]*) return 1;;esac
 case "$controller:$token" in *[!0-9:]*|:*|*:) return 1;;esac
 f=$root/session-owner
 [ ! -L "$f" ] && [ -f "$f" ] && [ "$(stat -c '%u:%a' "$f" 2>/dev/null)" = 0:600 ] && [ "$(wc -l <"$f")" = 1 ] || return 1
 read seen_run seen_pid seen_token extra <"$f" || return 1
 [ -z "$extra" ] && [ "$seen_run" = "$run" ] && [ "$seen_pid" = "$controller" ] && [ "$seen_token" = "$token" ] || return 1
 [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "/proc/$controller/stat" 2>/dev/null)" = "$token" ]
}
# Return 2 on contention and 1 on stale/unverified ownership.
gt8_handoff_begin(){
 [ "$#" = 1 ] || return 1
 case "$1" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) return 1;;esac
 gt8_handoff_lock /data/adb/gt8pro-mosey-service/mutation.lock;rc=$?
 [ "$rc" = 0 ] || return "$rc"
 if ! (
  run_dir=$1
  [ ! -L "$run_dir" ] && [ "$(stat -c '%u:%a' "$run_dir" 2>/dev/null)" = 0:700 ] || exit 1
  read ctrl tok extra <"$run_dir/soak-controller.record" || exit 1
  [ -z "$extra" ] && gt8_handoff_is_owner /data/adb/gt8pro-mosey-service "${run_dir##*/}" "$ctrl" "$tok"
 );then gt8_handoff_unlock;return 1;fi
}
