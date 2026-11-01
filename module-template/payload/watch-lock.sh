#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Candidate lock protocol; caller supplies verified root, quiet/system checks and owner function.
# An absent or malformed record is never silently removed.
gt8_watch_lock_acquire(){
 root=$1; pid=$2; token=$3
 case "$pid:$token" in *[!0-9:]*|:*|*:) return 1;;esac
 [ ! -L "$root" ] && [ "$(stat -c '%u:%a' "$root")" = 0:700 ] || return 1
 mkdir -m 700 "$root/watch-recovery-lock" 2>/dev/null || return 1
 if [ -e "$root/watch-lock" ];then
  lock=$root/watch-lock;rec=$lock/owner
  if [ -L "$lock" ] || [ "$(stat -c '%u:%a' "$lock")" != 0:700 ] || [ -L "$rec" ] || [ "$(stat -c '%u:%a' "$rec" 2>/dev/null)" != 0:600 ];then rmdir "$root/watch-recovery-lock";return 1;fi
  read oldpid oldtoken extra <"$rec" || { rmdir "$root/watch-recovery-lock";return 1; }
  case "$oldpid:$oldtoken" in *[!0-9:]*|:*|*:) rmdir "$root/watch-recovery-lock";return 1;;esac
  if [ -n "$extra" ] || gt8_owner_alive "$oldpid" "$oldtoken" /proc || ! gt8_watch_quiescent;then rmdir "$root/watch-recovery-lock";return 1;fi
  rm -f "$rec" && rmdir "$lock" || { rmdir "$root/watch-recovery-lock";return 1; }
 fi
 if ! mkdir -m 700 "$root/watch-lock";then rmdir "$root/watch-recovery-lock";return 1;fi
 if ! (set -C; umask 077; printf '%s %s\n' "$pid" "$token" >"$root/watch-lock/owner");then rmdir "$root/watch-recovery-lock";return 1;fi
 rmdir "$root/watch-recovery-lock"
}
gt8_watch_lock_release(){
 root=$1;pid=$2;token=$3;rec=$root/watch-lock/owner
 [ ! -L "$rec" ] && [ "$(stat -c '%u:%a' "$rec" 2>/dev/null)" = 0:600 ] || return 1
 read oldpid oldtoken extra <"$rec" || return 1
 [ "$oldpid" = "$pid" ] && [ "$oldtoken" = "$token" ] && [ -z "$extra" ] || return 1
 rm -f "$rec" && rmdir "$root/watch-lock"
}
