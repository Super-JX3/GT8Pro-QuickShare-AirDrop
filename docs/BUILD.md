# 构建与输入边界

## 组装已固定的整合包

`external-inputs.json` 列出构建 0.13.8 所需但未提交的文件路径、长度与 SHA-256。输入包括原厂 Mosey APK、vendor/launcher 文件、权限 XML 和项目生成的守护及辅助二进制。由于重定位和重复挂载，清单中的多个目标可能对应同一内容哈希。

在本机准备拥有合法使用权的文件；可通过重复 `--input` 传入目录、单文件或 ZIP：

```sh
python3 tools/assemble.py --input /path/to/local-inputs --input /path/to/older-local-module.zip --output dist/module.zip
```

工具按固定内容哈希匹配，不依赖输入文件名；缺项会列出哈希并停止。模板脚本携带改动声明，组装时移除固定的声明行，再验证 `install.sha256` 和安装脚本中的清单哈希。公开模板仅将安装器里桥版本提示为 0.11.7；该提示不在安装清单内。它不会生成缺少的二进制，也不会把不同版本的文件冒充兼容文件。

辅助源码在 `native/` 和 `helpers/`，可用下述实验脚本编译，但目前尚无经验证的一键重建和组包流程；即使功能等效，重编译二进制哈希不同也会被当前组包器拒绝。先前本机生成的整合 ZIP 可作为固定二进制来源。此限制意味着新的使用者不能仅凭公开仓库完成组装。

`dist/`、`local-inputs/` 和签名文件被 `.gitignore` 忽略。请不要上传原厂文件或本机原始模块 ZIP。

## 重建项目辅助程序（实验）

`tools/build-helpers.py` 可以用本地 Android 36 平台、build-tools 的 D8、NDK clang 和 JDK 17 编译两个 Java 辅助 JAR 及三个 arm64 守护程序，并生成这些输出的 SHA-256 清单：

```sh
python3 tools/build-helpers.py --android-jar /path/to/android-36/android.jar --d8-jar /path/to/build-tools/lib/d8.jar --ndk-clang /path/to/ndk/toolchains/llvm/prebuilt/HOST/bin/clang --jdk-bin /path/to/jdk/bin --output dist/helpers
```

此步骤已在本机工具链编译通过，但不会自动更新脚本中逐级固定的哈希、安装清单或桥 APK 签名；产物不能直接替换到发布包中，也尚未验证其与旧版二进制的设备行为一致。完整自建组包及其校验链生成仍待完成。原厂组件仍须另行取得并核验。

## LSPosed 桥

`bridge/build.py` 是当前桥源码的构建入口，要求 Android 36 平台、Android 16 build-tools、Xposed API 82、JDK 17 和已有签名目录；脚本对指定工具包有固定哈希检查。其参数为 `--tools`、`--jdk`、`--out`、`--signing`。不要把签名目录、密钥或密码提交到仓库。

仓库提供的 0.11.7 APK 为发布时本地构建；自己用其他签名或修改源码构建的 APK 会得到不同哈希，而模块模板固定接受发布 APK 的哈希。要使用自编译 APK，必须同步更新 `check-helper.sh`、所有依赖哈希和安装清单，再经过完整测试；不要只改一个检查或禁用校验。

主机测试示例：

```sh
python3 bridge/test-host.py
python3 bridge/test-discover.py
python3 bridge/test-route.py
python3 bridge/test-reasons.py
python3 bridge/test-metadata.py
python3 bridge/test-callback.py
python3 tools/test-supervisor-retry.py
```

主机测试不能替代手机开机、发现、收发、清理或长期稳定性验证。
`test-host.py` 为不分发 Google 资源文件，在临时测试副本中将一个固定资源哈希替换为合成夹具的哈希；正式桥源码和发布 APK 中的固定哈希不受影响。
