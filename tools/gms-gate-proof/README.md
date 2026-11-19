# Google 服务缓存路径静态核对

`GateProof.java` 只读取本地提供的已校验 GMS APK，验证以下引用链：分享服务中的开关 supplier、缓存包装、两个布尔配置读取及外部服务注册入口。脚本不加载或执行目标应用代码，也不修改系统。它不能证明真实进程里的缓存值、首次调用时序或运行时连接状态。

使用 JDK 17，先编译本仓库 `mobile-builder/src/moseyPLK/client/GmsDexFile.java` 和本文件，再以用户有权使用的匹配 GMS base APK 为参数运行。脚本对目标 APK 固定 SHA-256，未知版本会退出。请勿把 APK、私有日志或账号信息提交到仓库。
