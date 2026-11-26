# Google 服务缓存路径静态核对

## 检查 GMS 更新

桥接使用已复核的内置配置或 [手机端助手](../../mobile-builder/README.md) 写入模块的配置。每次启动核对实际版本号、Google 签名、base APK 的 SHA-256 和目标类归属。找不到匹配配置时会在日志中记录具体原因。

维护者可以从自己的测试机取得 GMS 的 base APK，在本机扫描候选配置。需要 JDK 17 和与桥接构建相同的已校验 Android SDK 输入。工具默认使用手机端助手的 DEX 读取器。

```sh
python3 tools/gms-gate-proof/inspect-profile.py /path/to/gms-base.apk \
  --tools /path/to/android-tools --jdk /path/to/jdk/bin
```

扫描器按 Quick Share 服务的配置读取链路和 `HomeFeatures` 的布尔字段定位适配点。只有各自找到唯一匹配才输出 JSON。复核后把配置加入桥接，重新构建并在真机从发送页测试能力提示、服务注册和 Apple 设备互传。若 Google 改动配置键、流程或签名，需要重新分析。请勿提交 GMS APK 或设备日志。

## 26.43.30 的缓存证明

`GateProof.java` 只读取本地提供的已校验 GMS APK，验证以下引用链：分享服务中的开关 supplier、缓存包装、两个布尔配置读取及外部服务注册入口。脚本不加载或执行目标应用代码，也不修改系统。它不能证明真实进程里的缓存值、首次调用时序或运行时连接状态。

使用 JDK 17，先编译上面提到的 `GmsDexFile.java` 和 `GateProof.java`，再以匹配的 GMS base APK 为参数运行。脚本对目标 APK 固定 SHA-256。
