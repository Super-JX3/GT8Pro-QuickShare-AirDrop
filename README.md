# GT8 Pro Quick Share ↔ AirDrop（实验项目）

让特定固件的真我 GT8 Pro 在 Quick Share 中使用 Mosey/AirDrop 互传。项目提供 KernelSU/SukiSU 整合模块源码、LSPosed 兼容桥、恢复逻辑及本地组包工具。

**状态：实验候选，不是 Google、Apple 或 realme 官方产品。** 已在一台设备上验证重启后的服务启动、iPhone 与 Android 双向传输；接收视频曾出现文件已保存但界面卡住，0.13.6 的回调修复在一个复现样本上使界面最终显示“已接收”。长时间后设备不可发现、采样异常退出、进度短暂停留、多个文件及并发传输仍需进一步验证。

> **已知兼容性问题（0.13.7 / 0.11.6）：** 该旧版本在多处将 Mosey 应用 UID 固定为测试机的 `10366`。即使是相同机型和固件，其他设备的 UID 也可能不同，导致服务无法启动、代理及异常恢复失败。请勿把该旧候选视为支持所有同型号设备；0.13.8 候选已改为动态查询 UID，并在原测试机启动及完成一次 iPhone→Android 文件接收；不同 UID 的真实设备仍未验证。

## 已验证的设备

| 项目 | 范围 |
| --- | --- |
| 机型 | realme GT8 Pro，型号 **RMX5200** |
| 固件 | **RMX5200_16.0.10.501(CN01)**，Android 16 / SDK 36 |
| 平台与内核 | `canoe`；`6.12.23-android16-5-gb2a876903b49-ab14541642-4k` |
| Root / 挂载 | 测试机使用 KernelSU/SukiSU 与 SELinux Enforcing |
| 应用桥 | LSPosed；仅作用于主用户的 Google Play 服务和 `com.google.android.mosey` |
| 软件身份 | Mosey 60715 与固定版本的 Google Play 服务，运行时通过 SHA-256 核对 |

其他机型、固件、内核、Magisk 或其他版本的 GMS/Mosey **未验证**。安装检查会拒绝不匹配环境；不要通过删除检查来宣称已适配。固件或应用更新可能使模块停止工作。

## 使用方式

在系统分享面板中选择 Quick Share，或打开 Quick Share 接收页面。监听器检测到页面处于前台后按需启动原生服务和代理，首次就绪存在延迟。iPhone 的 AirDrop 接收需设为“所有人，10 分钟”以便发现；发送方和接收方均需在附近。退出分享流程后服务会尝试清理，监听器等待下一次打开。

Live Photo 的动态部分和 Android 相册显示兼容性尚未完成验证。接收时以实际文件和两端状态为准；部分大文件的进度可能短暂停留。

## 获取与安装

项目由 **一个 KernelSU/SukiSU 整合模块 ZIP + 一个 LSPosed 桥 APK** 组成，另需系统已安装并正常运行的 LSPosed。整合模块不依赖原来的 0.3.0、0.4.0 或独立 daily 模块；迁移时旧模块应禁用，确认新版本正常后再自行决定如何处理备份。

`releases/GT8Pro-MoseyBridge-0.11.6.apk` 是经过个人信息清理后重建的桥 APK。0.13.7 / 0.11.6 在测试机上通过了重启启动和一次 iPhone→Android 接收：进度短暂停在 25% 后显示“已接收”，日志记录了真实完成回调的补送。该文件未做两端独立哈希比较；反向传输、并发和长期稳定性未在此版本重新验收。不要将主机测试当作手机验收。

从 [0.14.1-rc Release](https://github.com/Super-JX3/GT8Pro-QuickShare-AirDrop/releases/tag/v0.14.1-rc) 下载整合模块 ZIP 和 0.11.9 桥 APK。整合 ZIP 包含 Google 和厂商组件；项目代码的开源许可不覆盖这些外部组件。

也可使用 `python3 build.py --input /path/to/local-verified-inputs` 在本地组装。组包工具按 SHA-256 匹配输入并验证安装清单；从零重建所需的三个固定辅助二进制目前仍未公开，详见 [构建说明](docs/BUILD.md)。请勿提交签名密钥或个人测试日志。

安装步骤、验证、回滚和已知限制见 [安装与使用](docs/INSTALL.md)。模块 ZIP 是管理器安装包，**不是整机刷机包**。

## 源码和许可

- `bridge/`：LSPosed 桥接源码及主机测试。
- `module-template/`：整合模块脚本和校验清单，不含外部二进制输入。
- `native/`、`helpers/`：守护进程和辅助工具的源码。
- `tools/assemble.py`：基于本地输入的组包工具。

项目代码遵循 [Apache-2.0](LICENSE)，并保留 [NOTICE](NOTICE) 与模块内第三方声明。外部 Google/厂商资产不因本项目许可而获得再分发授权。设计参考 [moseyPLK-public](https://github.com/swift-lee/moseyPLK-public) 的 Apache-2.0 代码，以及 [OPAirDrop](https://github.com/Weverses/OPAirDrop) 的 GPL-3.0-only 回调思路；本仓库没有包含其 APK 补丁脚本或厂商固件。详见 [来源和边界](docs/ATTRIBUTION.md)。

0.13.8 是动态 UID 实验候选；旧版 0.13.7 的固定 UID 限制仍适用。候选仍存在会话目录累计、桥接 24 小时到期、升级运行目录及自有组件重建限制，尚不适合宣传为通用稳定版。

0.13.9 / 0.11.8 为重启按钮与异常恢复实验候选。按钮需要在 KernelSU/SukiSU 中授予桥 APK Root；已在 GT8 Pro 待机状态验证点击按钮后启动服务；传输中保护、异常恢复和实际收发仍需验证。历史会话清理、24 小时桥接过期、从源码生成完整校验链及长期稳定性仍未解决。请勿将候选称为通用稳定版。

0.13.9 的一键组装入口为 `python3 build.py`；仍需本地提供匹配的原厂文件和三个尚未公开的固定辅助二进制，详见 [构建说明](docs/BUILD.md)。

0.14.1 / 0.11.9 为界面与挂载布局实验候选：已在测试机检查深浅色界面、开机文件挂载及按钮启动 Binder/代理；该次挂载依赖手动补齐 Hybrid Mount 缓存，自动同步、传输中保护、异常恢复及本版本实际文件收发尚未验证。
