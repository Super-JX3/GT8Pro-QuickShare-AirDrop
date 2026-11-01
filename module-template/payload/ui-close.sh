#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
PATH=/system/bin:/system/xbin
export PATH
OUT=$1
. "$GT8_BINDDIR/ui-common.sh"
ui_private_ok || exit 1
# This test never closes the user-owned page.
exit 0
