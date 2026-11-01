GT8 Pro Mosey 应用接入前置测试 0.4.0

本包是 0.3.0 ServiceTest 的独立配套模块，不替换原测试模块。
仅限 RMX5200 / RMX5200_16.0.10.501(CN01) / 原精确内核、库及策略前提。
其他成员的测试截图不能代替自己手机的测试结果。

做什么
- 由现有挂载器提供原始 Google 签名 Mosey 应用及两份仅针对该应用的权限 XML。
- 重启后手动 Action 只核查：应用及配置在本进程、init 和 system_server 视图的
  原字节/标签，活动 APK、系统特权身份、主用户权限、分享 provider 能否解析。
- 保留精确设备、原厂模块/Binder 库哈希、原 68 项静态检查，不为通过检查改驱动。
- 不启用 GMS/LSPosed hook、不写 Phenotype、不刷内核、不启动原生服务、不绑新 mount。

注意
- 本包把外部供体应用加入系统特权应用并配置蓝牙、附近设备、位置、网络等权限，
  不是普通只读 APK。这些权限只针对 com.google.android.mosey。
- 没有开机脚本或主动启动命令，但安装后 GMS 或系统可能自然发现/绑定该应用，
  应用自己的运行行为并非由本测试完整控制。不要理解为绝不产生后台活动。
- 特权权限是否授予、应用是否能查询真实 Binder、GMS 是否绑定、发现/收发是否
  可用是分开的验证层。Action 通过只说明应用接入前置条件，不说明 AirDrop 可用。
- 系统特权应用/权限配置有启动风险。先保留已授权 ADB 及当前 root 版本的模块
  救援方式、重要数据备份。不清数据、不刷别的机型镜像、不重新锁 BL。
- 未在真实手机安装验收；主机静态/模拟测试不等于运行验证。

安装及测试
1. 自己的 0.3.0 Action 确认服务已停止且 Binder 已移除；当前没有测试正在运行。
2. 保留 GT8 Pro Mosey Registration Test 0.3.0，不卸载它。
3. SukiSU/KernelSU 模块页安装此 ZIP；不能叠加另一份 Mosey APK/权限模块或更新包。
   安装报错停止，不删除检查强装。
4. 正常重启，在 GT8 Pro Mosey App Readiness 模块点击 Action 一次。
   或 Windows PowerShell：
   .\adb shell "su -c 'sh /data/adb/modules/gt8pro.mosey.appstage/action.sh'"
5. 分享 GT8PRO_APP_READINESS_REPORT_V1 短报告；不要发原始 dumpsys 或日志。
   本轮不用再点 0.3.0，不启用其他客户端/桥接模块，不测试发送私人文件。

可能结果
- APP_READINESS_CONFIRMED：应用接入前置通过，下一轮再接应用 Binder 查询和 GMS。
- APP_MOUNT_VIEW_UNVERIFIED：挂载视图/标签尚未确认，不执行软重启或全局挂载修复。
- SYSTEM_PRIVAPP_UNVERIFIED：不是预期原始活动特权包，或主用户状态不符。
- PRIVILEGED_PERMISSIONS_INCOMPLETE / RUNTIME_PERMISSIONS_INCOMPLETE：反馈计数，
  不自动 pm grant、不改 XML 增加更多权限，不用清数据解决。
- PROVIDER_NOT_RESOLVED：服务解析未确认，不自动启动/恢复组件。
- 其他错误也先发短报告。解析格式不兼容可能拒绝通过，不代表已证明系统故障。

退出与恢复
- 测试结束后正常禁用/卸载 gt8pro.mosey.appstage 并重启可移除模块挂载的应用和 XML。
  已产生的应用数据/系统授权记录不主动清除，不保证卸载即恢复全部系统状态。
- 若不能正常启动，按当前 SukiSU/KernelSU 的模块救援方式禁用此模块。
- 原始检查记录在 /data/adb/gt8pro-mosey-appstage，仅 root 可读；卸载不删记录。

来源与许可
- 三件应用/配置原件来自 swift-lee/moseyPLK-public v0.7.0 服务 ZIP，逐件原哈希校验。
- 原签名未改、未重签应用。原 APK v3 签名通过 apksigner 验证，证书 SHA-256：
  82f90326951d14e08010b2a26cce329be2b09e74752158b7640e04a544676878。
- 新检查脚本为本地适配；原项目代码许可见 LICENSE/NOTICE，外部供体不是因脚本
  开源而获得同样许可，见 THIRD_PARTY_NOTICES.md。
- SHA-256 是完整性检查，不是防恶意重打包的签名。
