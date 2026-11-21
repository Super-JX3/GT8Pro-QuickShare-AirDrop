> 当前源码为 0.16.0 / 0.12.5 实验候选；自编译产物尚未经过实机验证。

# 构建与输入边界

## 一键组装实验模块

安装 Python 3，在仓库根目录创建 `local-inputs/`，将有合法使用权的匹配组件文件放入该目录，再执行：

```sh
python3 build.py
```

输出为 `dist/GT8Pro-QuickShare-0.16.0.zip`。也可用 `python3 build.py --input /path/to/local-files` 指定本地目录、ZIP 或单个文件；`--input` 可重复，`--output` 可更改输出路径。脚本不会下载或上传本地输入。

仓库的 `releases/GT8Pro-project-helpers-0.13.9.zip` 提供本项目五个固定版本辅助程序，源码分别位于 `helpers/`、`native/` 和 `module-template/base-service/source/`；它们不再要求从旧整合 ZIP 获取。`external-inputs.json` 仍对所有输入按长度与 SHA-256 匹配，并验证安装清单的完整校验链；缺项会列出后退出。

**输入限制：**固定版本组装入口仍需要匹配的原厂文件，以及清单要求的固定版本项目组件。不要绕过哈希检查。`dist/`、`local-inputs/` 和签名文件被 `.gitignore` 忽略，请勿上传原厂文件或签名材料。

## 从源码构建项目组件并组装（实验）

仓库现包含三个上游原生组件的源码及来源说明（见 `native/UPSTREAM.md`），可以连同本项目的辅助程序和桥 APK 一起编译，并自动更新相应的哈希与清单。原厂文件仍须自行合法取得，脚本会按 `external-inputs.json` 的长度和哈希校验，既不下载也不上传文件。

需要 Python 3、JDK 17、Android NDK clang 和桥构建脚本要求的本地 Android SDK 工具包。`--tools` 指向含 `sdk/` 和桥构建所需工具归档的目录；具体要求和固定哈希见 `bridge/build.py`。例如：

```sh
python3 build-from-source.py \
  --tools /path/to/verified-android-tools \
  --jdk-bin /path/to/jdk/bin \
  --ndk-clang /path/to/ndk/toolchains/llvm/prebuilt/HOST/bin/clang \
  --signing /private/path/to/signing \
  --input /path/to/authorized-vendor-files-or-zip \
  --output dist/GT8Pro-source-build.zip
```

输出模块和同名 `.bridge.apk` 必须配套使用；首次构建会在签名目录生成本机私钥和密码，请妥善备份并保密。与设备现有桥 APK 签名不同的构建不能直接覆盖安装，需自行处理 Android 签名及卸载迁移。生成包保留清单校验；若向模板新增文件，需同步维护相应清单，否则构建会拒绝输出。新编译组件与发布二进制不保证字节一致，**尚未在手机上验证**，不要视为稳定发布包。

## 重建项目辅助程序（实验）

`tools/build-helpers.py` 可以用本地 Android 36 平台、build-tools 的 D8、NDK clang 和 JDK 17 编译两个 Java 辅助 JAR 及三个 arm64 守护程序，并生成这些输出的 SHA-256 清单：

```sh
python3 tools/build-helpers.py --android-jar /path/to/android-36/android.jar --d8-jar /path/to/build-tools/lib/d8.jar --ndk-clang /path/to/ndk/toolchains/llvm/prebuilt/HOST/bin/clang --jdk-bin /path/to/jdk/bin --output dist/helpers
```

此单独步骤仅生成辅助程序；使用上面的源码构建入口才能更新完整校验链。编译结果尚未验证其与旧版二进制的设备行为一致。

## LSPosed 桥

`bridge/build.py` 是当前桥源码的构建入口，要求 Android 36 平台、Android 16 build-tools、Xposed API 82、JDK 17 和签名目录；首次使用时会创建签名身份，后续构建应保留同一身份；脚本对指定工具包有固定哈希检查。其参数为 `--tools`、`--jdk`、`--out`、`--signing`。不要把签名目录、密钥或密码提交到仓库。

仓库提供的桥 APK 为候选构建；自编译 APK 的哈希由源码构建入口写入校验链。不同签名不可直接覆盖现有 APK。

主机测试示例：

```sh
python3 bridge/test-host.py
python3 bridge/test-discover.py
python3 bridge/test-route.py
python3 bridge/test-reasons.py
python3 bridge/test-metadata.py
python3 bridge/test-callback.py
python3 tools/test-supervisor-retry.py
python3 tools/test-boot-recovery.py
python3 tools/test-first-run.py
python3 tools/test-runtime-upgrade.py
python3 bridge/test-lifetime.py
```

主机测试不能替代手机开机、发现、收发、清理或长期稳定性验证。
`test-host.py` 为不分发 Google 资源文件，在临时测试副本中将一个固定资源哈希替换为合成夹具的哈希；正式桥源码和发布 APK 中的固定哈希不受影响。
