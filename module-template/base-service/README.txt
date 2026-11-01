GT8 Pro Mosey 服务注册短时测试 0.3.0 / 2026-10-23

用途：继 0.2.0 的独立命名空间身份/preload 探针通过后，真实运行一次供体服务，
观察它是否能注册 Binder，再停止本次服务并确认该 Binder 名称消失。
这不是可日常使用的 AirDrop 模块，也不是完整应用集成。

支持范围
- RMX5200 / RMX5200_16.0.10.501(CN01) / Android16 API36 / arm64-v8a / canoe。
- 内核须为 6.12.23-android16-5-gb2a876903b49-ab14541642-4k。
- 仍精确核对原厂 Wonder、WLAN、Binder 库哈希及上游 68 项静态配置。
- SukiSU/KernelSU，Enforcing 模式，root 调用者必须是 u:r:ksu:s0。
- 依赖已有的挂载提供者和 /data/adb/ksu/bin/busybox；不刷内核或无线驱动。

重要变化与风险
- 只有手动 Action 才会启动真实 mosey_server，安装、开机不自动运行服务。
- 真实服务可能初始化 Wi-Fi/AWDL 或影响连接；即使文件挂载隔离，注册的 Binder
  名称也短暂对系统可见，其他系统客户端可能发现它。不要在重要网络任务中测试。
- 不装 Mosey APK，不改 GMS，不装 init/VINTF 声明，也不进行文件收发测试。
- 这是不带应用集成的独立注册实验，不能当作原项目全部系统就绪检查通过。
  不要求 PID1/system_server 看到私有 bind；不是完整系统移植的验收。
- 新增一条仅 ksu -> mosey_server 的 signal/sigkill 规则，用于本次进程收尾。
  其余三条域转换规则及目标检查保持；不关闭 SELinux，不加通配 allow。
- 沿用原始注册兼容库，仅对目标 Binder 对象进行其既有的 system stability
  兼容操作；不修改整个 Binder 驱动或其他服务对象。
- 注册稳定观察到后立即请求停止。独立 pidfd 守护进程最多等待 40 秒，然后请求
  SIGTERM；2 秒未退出再对同一 pidfd 请求 SIGKILL，另等 3 秒。停止失败不报告成功。
- 不接受任意 PID，不按名字 kill，不接管已有服务；已存在进程或 Binder 时拒绝启动。
- 任何软件都不能保证内核故障/不可中断状态下停止一定成功。STOP_UNCONFIRMED
  时停止重试并反馈短报告；不要自行按名字杀进程或删除记录。

安装
1. 备份数据，保留当前系统匹配的救援材料及 ADB/root 授权。
2. 在管理器卸载旧的 gt8pro.mosey.loadprobe 或其他 Mosey 测试模块，然后重启。
   不要与原版 moseyPLK/OPAirDrop 或其他提供相同路径的模块叠加。
3. 在 SukiSU/KernelSU 模块页安装此 ZIP。安装报错就停止，不删检查强装。
4. 安装无报错后按常用 root/挂载流程重启。
5. 手动点击“GT8 Pro Mosey Registration Test”的操作/Action；只点一次。
   没有按钮时在 Windows PowerShell 执行：
   .\adb shell "su -c 'sh /data/adb/modules/gt8pro.mosey.servicetest/action.sh'"
6. 前置检查可能另需时间；之后隔离子流程预算 150 秒，加 2 秒终止宽限。
   在预算内等最终报告，不要反复点击、卸载模块或清理记录。
7. 只分享 GT8PRO_SERVICE_TEST_REPORT_V1 短报告，不发送原始日志。

提前停止
在另一终端执行（只给本次运行写停止请求，不按 PID 发信号）：
.\adb shell "su -c 'sh /data/adb/modules/gt8pro.mosey.servicetest/stop.sh'"
STOP_REQUEST_RECORDED 仅表示请求已写入，仍需等待 Action 的 SERVICE_STOPPED 和
BINDER_REMOVED 确认。服务尚未进入启动阶段时，该请求可能无法记录。

成功条件
PAYLOAD_CHECK=PASS
TARGET_CHECK=PASS
PROBE_EXIT_CODE=0
PARENT_VIEW=UNCHANGED
NAMESPACE_ISOLATION=PASS
PRIVATE_BIND=PASS
NAMESPACE_CLEANUP=PASS
SERVICE_IDENTITY=PASS
SHIM_REGISTRATION=PASS
BINDER_OBSERVED=PASS
SERVICE_STOPPED=PASS
BINDER_REMOVED=PASS
RESULT=REGISTRATION_OBSERVED_AND_STOPPED

结果只说明一次短时注册与停止被观察到，不说明无线收发、GMS hook 或应用集成可用。
PARENT_VIEW 是 Action 外层命名空间/mountinfo/探针 inode 与标签的前后观察，不是对
全系统所有状态的绝对证明；无关并发挂载变化也会导致 UNVERIFIED。

错误处理
- PAYLOAD/TARGET/SOURCE/LABEL/BIND/NAMESPACE_*：停止，不改标签、不切全局挂载。
- EXISTING_SERVICE_PROCESS / EXISTING_BINDER_SERVICE：拒绝接管已有实例。
- PIDFD_SELFTEST_FAILED / WATCHDOG_EXIT_CODE 非零：控制工具或内核前提未通过。
- SERVICE_REGISTRATION_UNCONFIRMED / SERVICE_EXITED_BEFORE_CONFIRMATION：尚未确认
  注册。仍会请求停止并核对退出，不把供体退出状态当 Binder 错误码。
- SERVICE_STOP_UNCONFIRMED / BINDER_STILL_PRESENT：停止重试，先反馈短报告。
- 超时或界面关闭时，外层可能未能给出完整报告；守护进程仍尝试停止它持有 pidfd
  的那一个子进程，不自动接管其他进程。没有完整停止结果就不视作成功。

卸载与隐私
待当前测试结束并确认停止后，正常在管理器禁用/卸载 gt8pro.mosey.servicetest 并重启。
若系统进不去，不重新锁 BL 或乱刷镜像，按当前 SukiSU 版本的救援方式处理。
记录保留在 /data/adb/gt8pro-mosey-service/，root 私有，卸载不删除。
原始日志可能含 PID、启动标识、设备或网络运行细节，不应直接分享。
包内校验是完整性校验，不是数字签名，不能防止恶意重打包。

来源与重建
- 供体/launcher/探针/注册兼容库来自 swift-lee/moseyPLK-public v0.7.0 原服务 ZIP，
  逐件核对其 payload.sha256；未修改这些二进制及原 registration-checks.sh。
  https://github.com/swift-lee/moseyPLK-public/releases/tag/v0.7.0
- 新 watchdog 的完整 C 源码随包 source/watchdog.c 提供，Apache-2.0。
  使用 clang13 针对 aarch64-linux-musl 编译，musl1.2.5 静态链接，LLD13；
  无动态解释器/运行时下载。musl 的许可见 MUSL-COPYRIGHT。
- 主机生命周期测试、shell 模拟和静态校验不等于真实 Android 验收。
  外部供体载荷不因脚本开源而自动获得开源许可，见 THIRD_PARTY_NOTICES.md。
