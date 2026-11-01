#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
PATH=/system/bin:/system/xbin
export PATH
OUT=$1
. "$GT8_BINDDIR/ui-common.sh"
ui_private_ok || exit 1
[ "$(ui_state)" = TARGET_TOP ] || { echo SHARING_UI_START=PREEXISTING_OR_UNCONFIRMED;exit 1; }
echo SHARING_UI_START=ADOPTED
echo SHARING_UI_VISIBLE=PASS
