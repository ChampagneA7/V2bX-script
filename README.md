# ChampagneA7 V2bX 安装与升级脚本

基于 [wyx2685/V2bX-script](https://github.com/wyx2685/V2bX-script) 维护，保留原提交历史与 MPL-2.0 许可证。
主程序源码与 Release：[ChampagneA7/V2bX](https://github.com/ChampagneA7/V2bX)。

## 从原作者版本切换，或升级现有安装

在服务器 SSH 中使用 root 执行：

```bash
wget -O upgrade.sh https://raw.githubusercontent.com/ChampagneA7/V2bX-script/master/upgrade.sh && bash upgrade.sh
```

升级成功后，以后直接执行：

```bash
V2bX update
```

指定自己仓库的某个 Release：

```bash
V2bX update v2026.10.27
```

旧管理脚本里的 V2bX update 仍指向原作者；必须先执行上面的一次性切换命令。

升级只替换主程序和管理脚本，保留 /etc/V2bX 中的配置、证书、路由、DNS、自定义文件，以及原 geo 数据、systemd/OpenRC 定义和自启设置。
不会生成新配置，不会要求重新输入面板地址、密钥或节点 ID。升级前已停止的服务继续保持停止。

执行顺序为下载、校验 SHA256、检查程序与脚本、备份、停止原服务、替换、启动检查。下载和校验失败时不停止服务；检测到启动失败时尝试自动恢复旧程序和管理脚本。
备份保存在 /usr/local/V2bX/backups/时间.随机值/，包含原程序、管理脚本和只读配置快照 config.tar；权限仅对 root 开放。
升级需要短暂重启，服务存活检查不能代替真实业务连通验证。此脚本用于现有 systemd/OpenRC 安装，不适用于 Docker。

当前提供 Linux x86_64、arm64、s390x Release。需要 curl、unzip、sha256sum、tar、timeout；缺少依赖会在替换前退出。
所有升级只从 ChampagneA7/V2bX 下载，失败时不会回退到原作者的程序。

## 全新安装

```bash
wget -N https://raw.githubusercontent.com/ChampagneA7/V2bX-script/master/install.sh && bash install.sh
```

全新安装从自己的 Release 获取主程序，并提供原有配置向导。已有程序时会自动走上面的配置保留升级流程。

## 面板开发对接

见主程序仓库中的 [Xboard 多订阅对接文档](https://github.com/ChampagneA7/V2bX/blob/dev_new/docs/XBOARD_SUBSCRIPTIONS.md)。
新版节点保留原 UniProxy 协议；多订阅由面板把每条订阅的 node_user_id 输出为原 id 字段实现，旧面板无需跟随节点升级。
新版面板也必须继续保留兼容接口，才能支持尚未升级的旧节点。

## 开发验证

```bash
for file in upgrade.sh V2bX.sh install.sh tests/*.sh; do bash -n "$file"; done
bash tests/upgrade_test.sh
```

模拟测试使用临时目录和假服务，覆盖升级成功、原服务已停止、下载失败、校验失败、启动失败恢复、并发升级锁和符号链接管理脚本；不会操作真实服务。
Windows Git Bash 不支持真实符号链接时跳过该项，Linux CI 继续验证。
