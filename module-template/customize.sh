#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
SKIPUNZIP=0
REPLACE=""
REMOVE=""
export SKIPUNZIP REPLACE REMOVE
[ "$BOOTMODE" = true ] && [ "$KSU" = true ] || abort '! 请在 KernelSU/SukiSU 中安装，不支持 recovery 安装。'
[ -f "$MODPATH/install.sha256" ] && [ "$(sha256sum "$MODPATH/install.sha256" | cut -d ' ' -f1)" = a697c40e7a1d8e2bb27c244ce06d9520c8f4164eab3a08aa9239e09b965647f6 ] || abort '! 安装清单不匹配。'
(cd "$MODPATH" && sha256sum -c install.sha256 >/dev/null) || abort '! 安装文件校验失败。'
MODDIR=$MODPATH/base-service
. "$MODDIR/common.sh"
mosey_check_payload runtime || abort '! 原生组件校验失败。'
mosey_check_target || abort '! 设备或固件不匹配。'
MODDIR=$MODPATH/base-app
. "$MODDIR/common.sh"
mosey_check_payload runtime || abort '! 系统应用组件校验失败。'
for old in gt8pro.mosey.daily gt8pro.mosey.appstage gt8pro.mosey.servicetest;do
 for parent in /data/adb/modules /data/adb/modules_update;do
  legacy=$parent/$old
  if [ -d "$legacy" ];then [ -f "$legacy/disable" ] && [ ! -L "$legacy/disable" ] || abort '! 旧模块仍启用；请使用受控迁移流程。';fi
 done
done
for other in /data/adb/modules/moseyPLK.service /data/adb/modules/mosey-plk110-cn /data/adb/modules/gt8pro.mosey.loadprobe;do
 [ ! -d "$other" ] || [ -f "$other/disable" ] || abort '! 发现其他活动的 Mosey 模块。'
done
[ -d /data/adb/modules/meta-hybrid ] || [ -d /data/adb/metamodule ] || abort '! 未找到挂载提供者。'
[ -x /data/adb/ksud ] || abort '! 找不到 KernelSU 策略检查工具。'
/data/adb/ksud sepolicy check "$MODPATH/sepolicy.rule" >/dev/null 2>&1 || abort '! SELinux 策略检查失败。'
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/system_ext" 0 0 0755 0644 u:object_r:system_file:s0
set_perm_recursive "$MODPATH/system/odm" 0 0 0755 0644 u:object_r:vendor_file:s0
set_perm_recursive "$MODPATH/system/vendor" 0 0 0755 0644 u:object_r:vendor_file:s0
# Private bind sources are checked separately from mounted partition files.
set_perm_recursive "$MODPATH/base-service/system/odm" 0 0 0755 0644 u:object_r:vendor_file:s0
set_perm_recursive "$MODPATH/base-service/system/vendor" 0 0 0755 0644 u:object_r:vendor_file:s0
for prefix in "$MODPATH/system" "$MODPATH/base-service/system";do
 set_perm "$prefix/odm/bin/mosey_load_probe" 0 0 0755 u:object_r:mosey_server_exec:s0
 set_perm "$prefix/odm/bin/mosey_server" 0 0 0755 u:object_r:mosey_server_exec:s0
 set_perm "$prefix/vendor/bin/mosey_launcher" 0 0 0755 u:object_r:vendor_file:s0
done
set_perm "$MODPATH/base-service/tools/gt8_service_watchdog" 0 0 0755 u:object_r:system_file:s0
set_perm "$MODPATH/service.sh" 0 0 0755
ui_print '- 已整合原生服务、Mosey 系统应用和按需监听。'
ui_print '- 使用现有 MoseyBridge 0.11.7，LSPosed 作用域维持 GMS 与 Mosey。'
ui_print '- 重启后由系统加载整合模块。'
