#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
PATH=/system/bin:/system/xbin
export PATH
set -f
OUT=$1
. "$GT8_BINDDIR/ui-common.sh"
ui_private_ok || exit 1
[ "$(ui_state)" = TARGET_TOP ] || { echo SHARING_UI_META=FOCUS_UNCONFIRMED;exit 1; }
f="$OUT/binding-ui-view.xml"
[ ! -e "$f" ] && [ ! -L "$f" ] || exit 1
# Keep the XML on the phone in the private test directory. Only fixed flags leave.
(timeout -k 1 3 uiautomator dump --compressed "$f") 2>&1 | cat >"$OUT/binding-ui-meta-private.txt"
[ "$(ui_state)" = TARGET_TOP ] && [ -f "$f" ] && [ ! -L "$f" ] || { echo SHARING_UI_META=CAPTURE_UNCONFIRMED;exit 1; }
chmod 0600 "$f" || exit 1
[ "$(stat -c '%u:%a' "$f")" = 0:600 ] || exit 1
size=$(stat -c '%s' "$f") || exit 1
case "$size" in ''|*[!0-9]*) exit 1;;esac
[ "$size" -le 1048576 ] || exit 1
awk '
{data=data $0}
END{
 if(data!~/^<\?xml/||data!~/<hierarchy /||data!~/<\/hierarchy>$/){print "SHARING_UI_META=SHAPE_UNCONFIRMED";exit 1}
 print "SHARING_UI_META=CAPTURED"
 print "RECEIVE_UI_SEND_TAB="(data~/text="(发送|Send)"/?"SEEN":"NOT_SEEN")
 print "RECEIVE_UI_RECEIVE_TAB="(data~/text="(接收|Receive)"/?"SEEN":"NOT_SEEN")
 print "RECEIVE_UI_ACTIVE="(data~/text="[^\"]*(可以向您分享|可向你分享|可向您分享|正在接收|准备接收|Ready to receive|Receiving|visible to everyone|Anyone nearby)[^\"]*"/?"SEEN":"NOT_SEEN")
 print "SHARING_UI_GMS_SURFACE="(data~/package="com[.]google[.]android[.]gms"/?"SEEN":"NOT_SEEN")
 print "SHARING_UI_SYSTEM_PERMISSION_SURFACE="(data~/package="(com[.]android[.]permissioncontroller|com[.]google[.]android[.]permissioncontroller|com[.]oplus[.]safecenter)"/?"SEEN":"NOT_SEEN")
 print "SHARING_UI_ONBOARDING="(data~/text="(开始使用|Get started|设置快速分享|设置 Quick Share|Set up Quick Share)"/?"SEEN":"NOT_SEEN")
 print "SHARING_UI_BLUETOOTH_PROMPT="(data~/text="(开启蓝牙|打开蓝牙|Turn on Bluetooth|Enable Bluetooth)"/?"SEEN":"NOT_SEEN")
 print "SHARING_UI_WIFI_PROMPT="(data~/text="(开启 WLAN|打开 WLAN|打开 Wi-Fi|Turn on Wi-Fi)"/?"SEEN":"NOT_SEEN")
 print "SHARING_UI_ACCOUNT_PROMPT="(data~/text="(登录|Sign in|选择账号|选择帐号|Choose an account)"/?"SEEN":"NOT_SEEN")
 print "SHARING_UI_TERMS_PROMPT="(data~/text="[^"]*(服务条款|使用条款|Terms of Service)[^"]*"/?"SEEN":"NOT_SEEN")
 print "SHARING_UI_DISCOVERY_SURFACE="(data~/text="(查找设备|正在搜索附近的设备|正在查找附近的设备|Looking for nearby devices|Searching for nearby devices|未找到任何设备|No devices found)"/?"SEEN":"NOT_SEEN")
 print "SHARING_UI_PERMISSION_PROMPT="(data~/text="(允许|Allow|仅在使用该应用时允许|使用应用时|While using the app)"/?"SEEN":"NOT_SEEN")
}' "$f"
