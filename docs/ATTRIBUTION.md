# 来源、修改与分发边界

整合模块基于 [swift-lee/moseyPLK-public](https://github.com/swift-lee/moseyPLK-public) 中 Apache-2.0 代码与本项目针对 RMX5200 的改动，包含按需启动、会话监督、设备核验和 LSPosed 桥。模块内保留上游 `NOTICE`、`LICENSE`、第三方声明及 musl 许可。

接收完成回调的设计参考 [Weverses/OPAirDrop](https://github.com/Weverses/OPAirDrop) 的 per-transfer callback 机制。OPAirDrop 项目代码默认 GPL-3.0-only；本仓库实现为基于运行时观察独立编写的 LSPosed 路径，没有包含其补丁构建器或补丁源码。该参考不改变 OPAirDrop 的许可。

Google 和设备厂商应用、二进制、配置、驱动及其他外部输入各自受原权利人条款约束，不包含在本仓库的 Apache-2.0 授权中。仓库仅提供识别输入所需的公开哈希与路径；这些哈希不代表取得原厂文件的分发权。
