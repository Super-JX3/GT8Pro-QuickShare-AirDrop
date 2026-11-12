> 当前源码为 0.14.1 / 0.11.9 实验候选。

# 构建与输入边界

## 一键组装实验模块

安装 Python 3，在仓库根目录创建 `local-inputs/`，将有合法使用权的匹配组件文件放入该目录，再执行：

```sh
python3 build.py
```

输出为 `dist/GT8Pro-QuickShare-0.14.1.zip`。也可用 `python3 build.py --input /path/to/local-files` 指定本地目录、ZIP 或单个文件；`--input` 可重复，`--output` 可更改输出路径。脚本不会下载或上传本地输入。

仓库的 `releases/GT8Pro-project-helpers-0.13.9.zip` 提供本项目五个固定版本辅助程序，源码分别位于 `helpers/`、`native/` 和 `module-template/base-service/source/`；它们不再要求从旧整合 ZIP 获取。`external-inputs.json` 仍对所有输入按长度与 SHA-256 匹配，并验证安装清单的完整校验链；缺项会列出后退出。

**输入限制：**仍需另行取得清单中未公开的原厂 APK、服务、库、launcher 和权限 XML；此外，`mosey_load_probe`、`libmosey_load_probe.so` 和 `libmosey_registration_compat.so` 的固定二进制目前也尚未随仓库提供，也没有完整的公开重建路径。这些文件可由用户有权使用的历史模块中提取；因此该入口仍不能让全新用户仅凭仓库构建。不能通过关闭哈希检查来绕过缺项。

辅助程序 ZIP 是已发布的固定构建，不等于可复现构建；下方实验性源码编译尚不能自动更新整个校验链。`dist/`、`local-inputs/` 和签名文件被 `.gitignore` 忽略，请勿上传原厂文件或本机原始模块 ZIP。

## 重建项目辅助程序（实验）

`tools/build-helpers.py` 可以用本地 Android 36 平台、build-tools 的 D8、NDK clang 和 JDK 17 编译两个 Java 辅助 JAR 及三个 arm64 守护程序，并生成这些输出的 SHA-256 清单：

```sh
python3 tools/build-helpers.py --android-jar /path/to/android-36/android.jar --d8-jar /path/to/build-tools/lib/d8.jar --ndk-clang /path/to/ndk/toolchains/llvm/prebuilt/HOST/bin/clang --jdk-bin /path/to/jdk/bin --output dist/helpers
```

此步骤已在本机工具链编译通过，但不会自动更新脚本中逐级固定的哈希、安装清单或桥 APK 签名；产物不能直接替换到发布包中，也尚未验证其与旧版二进制的设备行为一致。完整自建组包及其校验链生成仍待完成。原厂组件仍须另行取得并核验。

## LSPosed 桥

`bridge/build.py` 是当前桥源码的构建入口，要求 Android 36 平台、Android 16 build-tools、Xposed API 82、JDK 17 和已有签名目录；脚本对指定工具包有固定哈希检查。其参数为 `--tools`、`--jdk`、`--out`、`--signing`。不要把签名目录、密钥或密码提交到仓库。

仓库提供的 0.11.9 APK 为发布时本地构建；自己用其他签名或修改源码构建的 APK 会得到不同哈希，而模块模板固定接受发布 APK 的哈希。要使用自编译 APK，必须同步更新 `check-helper.sh`、所有依赖哈希和安装清单，再经过完整测试；不要只改一个检查或禁用校验。

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
