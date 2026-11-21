> 0.16.0 / 0.12.5 是本地启动优化候选，需成对安装。0.15.4 的手动恢复曾在指定 GT8 Pro 实测，平板共存仍未实现。

> 0.13.8 动态 UID 实验候选已在原测试设备验证启动及一次 iPhone 接收；其他设备及长期稳定性尚未验证。仍需处理 24 小时桥接到期、历史会话目录累积、升级迁移和从源码重建。

# 安装、使用与回滚

> 0.13.7 / 0.11.6 存在固定测试机 UID `10366` 的已知问题；另一台相同机型和固件的设备也可能无法启动或正确恢复。0.13.8 候选采用动态 UID，但仍未在不同 UID 的真实设备上验证，不建议其他设备安装。

## 准备

确认设备、固件、内核和应用版本与 README 一致；备份可用模块和重要数据，确保具备可用的 KernelSU/SukiSU 与 LSPosed。安装涉及系统应用挂载、SELinux 策略及前台代理，异常可能导致分享功能不可用或需要重启。旧模块保持备份，便于恢复。

从 [0.16.0-rc 实验版](https://github.com/Super-JX3/GT8Pro-QuickShare-AirDrop/releases/tag/v0.16.0-rc) 取得模块 ZIP、桥 APK 和 SHA-256 清单。保留 [0.15.2-rc 整合模块和桥 APK](https://github.com/Super-JX3/GT8Pro-QuickShare-AirDrop/releases/tag/v0.15.2-rc) 作为回滚对。也可按[构建说明](BUILD.md)使用本地输入组装。模块 ZIP 包含外部原厂组件。

## 安装

1. 从主用户安装对应的 0.12.5 桥 APK。如果已有其他签名的同包名应用，Android 会拒绝覆盖；先检查签名和备份，勿直接清除数据。
2. 在 LSPosed 启用 `local.gt8pro.moseybridge`，仅选择主用户的 `com.google.android.gms` 和 `com.google.android.mosey` 两个作用域。
3. 如已使用旧的 `gt8pro.mosey.servicetest`、`gt8pro.mosey.appstage`、`gt8pro.mosey.daily`，在管理器中禁用它们并保留备份。确保没有正在进行的分享。
4. 在 KernelSU/SukiSU 管理器安装与桥 APK 配对的 0.16.0 模块 ZIP。模块 ID 为 `gt8pro.mosey.integrated`，不是刷机包，不要使用系统刷机工具。
5. 正常重启并首次解锁手机；确认管理器中模块已启用、LSPosed 作用域仍正确。

0.13.7 / 0.11.6 是公开版重建候选，已在指定测试机通过一次重启启动与 iPhone→Android 接收；反向、并发和长期稳定性仍未重新验收。在不同设备上操作前请等待对应验证。安装器和运行脚本会针对固定机型、固件、文件哈希及权限进行检查。

桥中的“打开 Quick Share”保留当前无线连接。“检查 AirDrop 状态”和“断开直连并恢复 AirDrop”需要在 KernelSU/SukiSU 中授权 Root。后者会在用户确认后核验当前传输和服务状态，有可能断开 OPPO 平板互联或其他 Wi-Fi 直连设备。

## 验证

打开 Quick Share 分享或接收页，等待服务启动。先测试无敏感内容的小文件，再测试 iPhone→Android 和 Android→iPhone 两个方向；确认对端状态及收到的文件可正常打开。实况照片、多文件、较大视频和持续运行要单独测试。

若发现不到设备，先确认 Quick Share 位于前台、iPhone 已解锁且 AirDrop 为“所有人，10 分钟”，然后关闭并重新打开分享页。故障持续时保留模块状态和时间，收集前检查日志是否含设备名、地址或文件名。

## 回滚

等待传输结束，在 KernelSU/SukiSU 管理器禁用 `gt8pro.mosey.integrated` 并正常重启。若需要恢复原先单独模块，请先核对各模块与当前固件兼容并启用已有备份；同签名的 0.12.5 桥 APK 沿用 0.12.3 的版本代码，便于通过 ADB 保留应用数据替换回 0.12.3；回滚时应同时恢复配套模块。不要通过清除 Google Play 服务、Mosey 或个人应用数据来回滚。
