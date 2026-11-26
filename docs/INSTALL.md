> 0.16.6 模块搭配 0.12.7 桥 APK。模块生成助手可为当前安装的 Google Play 服务生成配置。

> 0.13.8 动态 UID 实验候选已在原测试设备验证启动及一次 iPhone 接收；其他设备及长期稳定性尚未验证。仍需处理 24 小时桥接到期、历史会话目录累积、升级迁移和从源码重建。

# 安装、使用与回滚

> 0.13.7 / 0.11.6 存在固定测试机 UID `10366` 的已知问题；另一台相同机型和固件的设备也可能无法启动或正确恢复。0.13.8 候选采用动态 UID，但仍未在不同 UID 的真实设备上验证，不建议其他设备安装。

## 准备

确认设备、固件、内核和应用版本与 README 一致；备份可用模块和重要数据，确保具备可用的 KernelSU/SukiSU 与 LSPosed。安装涉及系统应用挂载、SELinux 策略及前台代理，异常可能导致分享功能不可用或需要重启。旧模块保持备份，便于恢复。

从 [v0.16.6-rc 实验版](https://github.com/Super-JX3/GT8Pro-QuickShare-AirDrop/releases/tag/v0.16.6-rc) 取得模块生成助手、配套桥 APK、实机生成的模块 ZIP 和 SHA-256 清单。Release 内的 ZIP 已在 GMS 26.45.31（`264531035`）上验证启动。也可按[构建说明](BUILD.md)使用合法取得的本地输入组装。整合 ZIP 和内嵌同一模板的助手包含外部原厂组件。

## 安装

1. 从主用户安装对应的 0.12.7 桥 APK。如果已有其他签名的同包名应用，Android 会拒绝覆盖。先检查签名和备份。
2. 在 LSPosed 启用 `local.gt8pro.moseybridge`，仅选择主用户的 `com.google.android.gms` 和 `com.google.android.mosey` 两个作用域。
3. 如已使用旧的 `gt8pro.mosey.servicetest`、`gt8pro.mosey.appstage`、`gt8pro.mosey.daily`，在管理器中禁用它们并保留备份。确保没有正在进行的分享。
4. 在 KernelSU/SukiSU 管理器安装与桥 APK 配对的 0.16.6 模块 ZIP。模块 ID 为 `gt8pro.mosey.integrated`，请通过管理器安装。
5. 正常重启并首次解锁手机；确认管理器中模块已启用、LSPosed 作用域仍正确。

0.13.7 / 0.11.6 是公开版重建候选，已在指定测试机通过一次重启启动与 iPhone→Android 接收；反向、并发和长期稳定性仍未重新验收。在不同设备上操作前请等待对应验证。安装器和运行脚本会针对固定机型、固件、文件哈希及权限进行检查。

桥中的“打开 Quick Share”保留当前无线连接。“检查 AirDrop 状态”和“断开直连并恢复 AirDrop”需要在 KernelSU/SukiSU 中授权 Root。后者会在用户确认后核验当前传输和服务状态，有可能断开 OPPO 平板互联或其他 Wi-Fi 直连设备。

## Google Play 服务更新后

打开[模块生成助手](../mobile-builder/README.md)，点「重新检查 Google Play 服务」。识别成功后点「生成适配模块」并保存 ZIP。确认传输结束后，用管理器安装新 ZIP 并重启。已安装同一份 0.12.7 桥 APK 时，可以沿用现有桥和 LSPosed 作用域。若新 GMS 的签名或适配点无法确认，请保留现有包并等待复核。

## 验证

打开 Quick Share 分享或接收页，等待服务启动。先测试无敏感内容的小文件，再测试 iPhone→Android 和 Android→iPhone 两个方向；确认对端状态及收到的文件可正常打开。实况照片、多文件、较大视频和持续运行要单独测试。

若发现不到设备，先确认 Quick Share 位于前台、iPhone 已解锁且 AirDrop 为“所有人，10 分钟”，然后关闭并重新打开分享页。故障持续时保留模块状态和时间，收集前检查日志是否含设备名、地址或文件名。

测试发往 Apple 设备时，先选好内容，再从系统分享菜单进入 Google Quick Share。发送页有活动的前台发送时可以启动 AirDrop，普通设置页保持待命。完成传输并退出 Quick Share 后，等服务自动回收，再重开发送页验证能否再次发现并发送。

0.16.4 已在指定 GT8 Pro 上通过两次向同一台 Mac 发送约 96 MiB ZIP 的实测。两份文件的字节数及 SHA-256 均与源文件一致，关页后服务均正常回收。iPhone 的同一大文件连续发送用例待维护者验证。

0.16.6 已在同一型号和指定固件上验证重启后读取生成的 GMS 配置、报告 iOS 能力、发送页注册服务和退回待命。本轮文件传输待单独复测。

## 回滚

上一公开版是 [v0.16.4-rc](https://github.com/Super-JX3/GT8Pro-QuickShare-AirDrop/releases/tag/v0.16.4-rc)。回滚前核对手机现有 GMS 是否匹配该版。也可从 [v0.16.3-rc](https://github.com/Super-JX3/GT8Pro-QuickShare-AirDrop/releases/tag/v0.16.3-rc) 或 [v0.16.2-rc](https://github.com/Super-JX3/GT8Pro-QuickShare-AirDrop/releases/tag/v0.16.2-rc) 下载历史版本。请使用同一个 Release 中的整合模块和桥 APK。

等待传输结束，在 KernelSU/SukiSU 管理器禁用 `gt8pro.mosey.integrated` 并正常重启。若需回到上一套配置，恢复配套模块和同签名的桥 APK。0.12.7 沿用 0.12.5 的桥接版本代码，可以通过 ADB 保留应用数据覆盖安装。保留 Google Play 服务、Mosey 和个人应用数据。
