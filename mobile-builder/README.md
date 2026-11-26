# 手机端模块构建助手 0.3.0-dev

助手在 RMX5200 的 `RMX5200_16.0.10.501(CN01)` 固件上读取当前安装的 Google Play 服务。它会核对 Google 签名与 APK 的 SHA‑256，离线扫描 AirDrop 开关和 Quick Share 横幅。两个位置都能唯一匹配时，可以生成带当前 GMS 配置的模块 ZIP，并导出配套的 0.12.7 桥接 APK。

安装时，用 KernelSU 安装生成的模块，用同签名的配套桥接 APK 覆盖旧版，在 LSPosed 确认 GMS 和 Mosey 作用域，再正常重启。模块安装器核验配置文件与原有清单。每次启动时，模块会发布一份由 root 持有、仅向 GMS 开放读取权限的临时配置。桥接同时核对 GMS 签名、版本代码、文件哈希和目标类归属。

GMS 更新后，在助手点「重新检查 Google Play 服务」并生成新 ZIP。只改版本名或调整混淆类名时，只要扫描仍匹配同一行为，就能生成新配置。若已安装同一份 0.12.7 桥接 APK，只需更新 ZIP 并重启。扫描找不到唯一匹配时，助手会停在检查阶段。发现和传输还需实机验证。

助手无网络权限，文件保存在用户选择的位置。生成和导出无需 root，也不会安装模块或重启手机。不同机型、固件、Mosey 组件和驱动需要各自适配。

## 构建助手 APK

需要 Python 3、JDK 17、经校验的 Android SDK 输入、生成助手的原签名目录、与当前源码模板逐文件匹配的 0.16.6 ZIP，以及该 ZIP 配套的已签名 0.12.7 桥接 APK。模板可通过仓库根目录的 `build.py` 和合法取得的原厂输入组装。

```sh
python3 mobile-builder/build.py \
  --tools /path/to/verified-android-tools \
  --jdk-bin /path/to/jdk/bin \
  --signing /private/path/to/builder-signing \
  --reference /path/to/GT8Pro-QuickShare-0.16.6.zip \
  --bridge /path/to/GT8Pro-MoseyBridge-0.12.7-transfer-test.apk \
  --output dist/GT8Pro-Builder-0.3.0-dev.apk
```

脚本从已校验归档提取工具，逐项校验参考包，检查配套桥接 APK 的签名和哈希。签名目录首次使用时会生成密钥。请妥善备份签名材料，覆盖安装助手时需沿用相同签名。

## DEX 读取器

解析器源于 moseyPLK-public 的 Apache-2.0 实现，使用本项目根目录的许可证。为控制手机端内存，扫描时逐个解析类并丢弃无需复查的方法数据。[上游 GmsDexFile.java](https://github.com/swift-lee/moseyPLK-public/blob/afc3c38/client-compat/src/main/java/moseyPLK/client/GmsDexFile.java)
