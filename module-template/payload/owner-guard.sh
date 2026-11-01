#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Optional watcher ownership: match both the process and its kernel start token.
gt8_owner_alive() {
 [ "$#" = 3 ] || return 1
 case "$1:$2" in *[!0-9:]*|:*|*:) return 1;;esac
 [ "$1" -gt 1 ] 2>/dev/null && [ "$2" -gt 0 ] 2>/dev/null || return 1
 state=$(awk '/^State:/{print $2}' "$3/$1/status" 2>/dev/null)
 case "$state" in R|S|D|I|T|t) ;; *) return 1;;esac
 [ "$(awk 'NR==1{sub(/^.*[)] /,"");print $20}' "$3/$1/stat" 2>/dev/null)" = "$2" ]
}
