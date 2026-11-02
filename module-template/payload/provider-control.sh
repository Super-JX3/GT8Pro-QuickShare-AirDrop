#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Original DEFAULT state is restored only inside an already guarded native test.
PATH=/system/bin:/system/xbin
export PATH
set -f
set -o pipefail
provider_control_main() {
OUT=$1
mode=$2
case "$OUT" in /data/adb/gt8pro-mosey-service/run.??????) ;; *) exit 1;;esac
[ "$(id -u)" = 0 ] && [ "$(cat /proc/self/attr/current)" = u:r:ksu:s0 ] && [ "$(getprop ro.product.model)" = RMX5200 ] && [ "$(getprop ro.build.display.id)" = 'RMX5200_16.0.10.501(CN01)' ] && [ "$(getenforce)" = Enforcing ] || exit 1
[ ! -L "$OUT" ] && [ "$(stat -c '%u:%a' "$OUT")" = 0:700 ] && [ "$(readlink -f "$OUT")" = "$OUT" ] || exit 1
. "$GT8_BINDDIR/handoff-lock.sh"
gt8_handoff_begin "$OUT" || { echo PROVIDER_MUTATION=OWNER_UNVERIFIED;exit 1; }
trap 'gt8_handoff_unlock' 0
. "$GT8_BINDDIR/bind-common.sh"
backup=/data/adb/gt8pro-mosey-bridge/provider-gate-before-065.txt
[ ! -L "$backup" ] && [ "$(stat -c '%u:%a' "$backup")" = 0:600 ] || exit 1
sum=$(sha256sum "$backup") || exit 1
[ "${sum%% *}" = 25459f6be305987883435474d59ac40251005d187aacb7ebcb9c5cb9c8347412 ] || exit 1
case "$mode" in
 enable)
  . "$GT8_BINDDIR/updated-package-checks.sh"
  report=$(sh "$GT8_BINDDIR/current-code-profile.sh") || exit 1
  expected_uid=$(gt8_user0_mosey_uid) || exit 1
  uid_record=$OUT/binding-app-uid.txt
  [ ! -L "$uid_record" ] && [ "$(stat -c '%u:%a' "$uid_record" 2>/dev/null)" = 0:600 ] && [ "$(cat "$uid_record")" = "$expected_uid" ] || exit 1
  printf '%s\n' "$report" | updated_code_profile_ok /dev/stdin "$expected_uid" || exit 1
  [ -n "$(pidof mosey_server 2>/dev/null)" ] || exit 1
  (timeout -k 1 3 service check com.google.android.moseyservice.IMoseyService/default;printf '\n__PROVIDER_BINDER_RC=%s\n' "$?") 2>&1 | awk '
  /^Service com[.]google[.]android[.]moseyservice[.]IMoseyService\/default: found$/{n++;next}
  /^__PROVIDER_BINDER_RC=0$/{m++;next} NF{bad=1} END{exit !(n==1&&m==1&&!bad)}' || exit 1
  epoch=$(date +%s)
  case "$epoch" in ''|*[!0-9]*) exit 1;;esac
  (set -C; printf '%s\n' "$epoch" >"$OUT/provider-enable-epoch.txt") || exit 1
  timeout -k 1 4 pm default-state --user 0 com.google.android.mosey/.ExternalSharingService || exit 1
  echo PROVIDER_COMPONENT=DEFAULT_WITH_NATIVE_GUARD
  ;;
 pause)
  timeout -k 1 4 pm disable --user 0 com.google.android.mosey/.ExternalSharingService
  component_rc=$?
  timeout -k 1 4 am force-stop --user 0 com.google.android.mosey || exit 1
  [ "$component_rc" = 0 ] || exit 1
  gt8_pause_left=$(gt8_mosey_main_pids) || exit 1
  [ -z "$gt8_pause_left" ] || exit 1
  (timeout -k 1 4 cmd package query-services --components --user 0 -a com.google.android.nearby.SHARING_PROVIDER -p com.google.android.mosey;printf '\n__PAUSE_QUERY_RC=%s\n' "$?") 2>&1 | awk '
  /^[ ]*No services found[.]?[ ]*$/{n++;next}
  /^__PAUSE_QUERY_RC=0$/{m++;next} NF{bad=1} END{exit !(n==1&&m==1&&!bad)}' || exit 1
  echo PROVIDER_LEASE_PAUSE=PASS
  ;;
 *) exit 1;;
esac

}
# Binder shell commands must receive pipe FDs rather than root-private log FDs.
provider_control_main "$@" 2>&1 | cat
exit "$?"
