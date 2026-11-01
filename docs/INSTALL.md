# 安装、使用与回滚

## 准备

确认设备、固件、内核和应用版本与 README 一致；备份可用模块和重要数据，确保具备可用的 KernelSU/SukiSU 与 LSPosed。安装涉及系统应用挂载、SELinux 策略及前台代理，异常可能导致分享功能不可用或需要重启。旧模块保持备份，便于恢复。

本仓库公开的是候选版本源码及桥 APK，整合模块 ZIP 必须按 [构建说明](BUILD.md) 由已授权的本地输入组装。项目没有提供外部原厂组件下载链接或镜像。

## 安装

1. 从主用户安装 `releases/GT8Pro-MoseyBridge-0.11.6.apk`。如果已有其他签名的同包名应用，Android 会拒绝覆盖；先检查签名和备份，勿直接清除数据。
2. 在 LSPosed 启用 `local.gt8pro.moseybridge`，仅选择主用户的 `com.google.android.gms` 和 `com.google.android.mosey` 两个作用域。
3. 如已使用旧的 `gt8pro.mosey.servicetest`、`gt8pro.mosey.appstage`、`gt8pro.mosey.daily`，在管理器中禁用它们并保留备份。确保没有正在进行的分享。
4. 在 KernelSU/SukiSU 管理器选择本地组装的 `GT8Pro-QuickShare-0.13.7.zip` 安装。模块 ID 为 `gt8pro.mosey.integrated`，不是刷机包，不要使用系统刷机工具。
5. 正常重启并首次解锁手机；确认管理器中模块已启用、LSPosed 作用域仍正确。

0.13.7 / 0.11.6 是公开版重建候选，已在指定测试机通过一次重启启动与 iPhone→Android 接收；反向、并发和长期稳定性仍未重新验收。在不同设备上操作前请等待对应验证。安装器和运行脚本会针对固定机型、固件、文件哈希及权限进行检查。

## 验证

打开 Quick Share 分享或接收页，等待服务启动。先测试无敏感内容的小文件，再测试 iPhone→Android 和 Android→iPhone 两个方向；确认对端状态及收到的文件可正常打开。实况照片、多文件、较大视频和持续运行要单独测试。

若发现不到设备，先确认 Quick Share 位于前台、iPhone 已解锁且 AirDrop 为“所有人，10 分钟”，然后关闭并重新打开分享页。故障持续时保留模块状态和时间，收集前检查日志是否含设备名、地址或文件名。

## 回滚

等待传输结束，在 KernelSU/SukiSU 管理器禁用 `gt8pro.mosey.integrated` 并正常重启。若需要恢复原先单独模块，请先核对各模块与当前固件兼容并启用已有备份；桥 APK 可恢复为与旧模块配套的同签名版本。不要通过清除 Google Play 服务、Mosey 或个人应用数据来回滚。
