<h1 align="center">appctl starter</h1>

[appctl](https://github.com/QingCloudAppcenter/ansible-roles/tree/master/appctl) 是一套约定优于配置（Convention over Configuration）的框架，封装并提供了集群启动、关闭、健康检查等一系列基本命令与默认配置，使应用开发者不必重复开发一些通用的功能，而只需要关注应用的核心功能，从而提高开发效率。appctl 以 Ansible Role 的形式提供。

本仓库基于 appctl 实现了一个最基本的应用，涵盖了应用开发过程中涉及到的大部分常用概念，可以帮助开发者快速上手。本仓库也可以用作仓库模板来快速创建一个新应用。

# 前置条件

- 学习并掌握 [AppCenter 开发文档](https://docs.qingcloud.com/appcenter/)

# 制作虚机映像

本仓库使用 [Ansible](https://docs.ansible.com/ansible/2.9/user_guide/quickstart.html) 制作虚机映像。`ansible/` 目录包含制作虚拟机映像的全部文件。

## 运行时目录结构

制作映像前，我们先了解一下最终运行起来后虚机里面的目录结构。

```shell
/
├─ opt/
│  ├─ app/
│  │  ├─ 1.0.0/
│  │  │  ├─ bin/
│  │  │  │  ├─ envs/       # 环境变量文件
│  │  │  │  ├─ node/       # 主力 Shell 脚本
│  │  │  │  ├─ tmpl/       # confd 生成的中间文件，用来生成最终的配置文件
│  │  │  │  └─ ctl.sh      # appctl 本体，包含开箱即用的一系列函数
│  │  │  └─ conf/
│  │  │     ├─ systemd/    # systemd 文件
│  │  │     ├─ confd/      # confd 文件
│  │  │     └─ .../        # 其他需要的文件，按服务名命名
│  │  └─ current -> 1.0.0/ # 软链接，方便版本升级后不改动命令路径
│  │─ caddy/               # 应用里安装的服务
│  │  ├─ 1.0.4/            # 服务版本
│  │  │  └─ caddy
│  │  └─ current -> 1.0.4/ # 软链接，方便版本升级后不改动命令路径
│  └─ qingcloud/
│     └─ app-agent/
│        │─ bin/
│        │  └─ confd
│        └─ log/
│        │  │─ app.log           # confd 执行 AppCenter 框架命令时的输出日志
│        │  │─ cmd.info          # AppCenter 框架下发的命令
│        │  │─ cmd.log           # AppCenter 框架命令的执行结果（成功/失败码）
│        │  │─ confd-onetime.log # 框架启动 confd 前执行的输出日志
│        │  └─ cmd.log           # confd 后台进程的输出日志
```

## 运行时服务组件

appctl 根据 AppCenter 框架要求，封装了常用的命令入口，应用开发者只需要定义好服务组件即可。同时也允许应用开发者添加自定义操作。

### 环境变量与配置文件

应用中用到的环境变量、配置文件等一般需要通过 [confd](https://github.com/yunify/confd) 模板动态生成。confd 模板基于 Golang 的 [text template](https://golang.org/pkg/text/template/) 格式，并扩展了一些函数，详细说明可以参考 [快速入门](https://github.com/yunify/confd/blob/master/docs/quick-start-guide.md) 和 [函数](https://github.com/yunify/confd/blob/master/docs/templates.md)。

模板的动态信息来自于 [metadata 服务](https://docs.qingcloud.com/appcenter/docs/metadata-service.html)，在集群主机上可以通过命令 `curl metadata/self` 查看 metadata 服务里包含的所有信息。

### 执行命令前的强制检查

根据长期运行过程中总结的经验，在执行命令前会有一些强制检查来确保底层 IaaS/AppCenter 已经准备就续，需要在环境变量文件（`/opt/app/current/bin/envs/*.env`）中定义以下字段：

```
# DATA_MOUNTS=""
# DATA_MOUNTS="/data /data2 /data3"
DATA_MOUNTS=/data           # 如有多个可用空格分隔，如不需要挂盘可以赋值为空（""）
MY_IP={{ getv "/host/ip" }} # 确保节点已经分配到了 IP，如果没分配到，立即退出，不再执行后续步骤
```

### 服务组件定义

服务组件需要在环境变量文件中定义，每个服务由三部分组成，以反斜线（`/`）分隔，多个服务之间以空格分隔，格式如下：

```
# SERVICES="$SERVICES ssh/true/tcp:22 redis/true/tcp:6379,tcp:26379"
SERVICES="$SERVICES starter/true/http:80"
```

- 服务名：如 starter，与 systemd 服务名一致
- 是否开启：在一些复杂的应用里，可能会在同一个节点上安装很多服务组件，并允许用户按需开启，可填 true 或 false
- 端口：用作健康检查的端口，每个端口由协议和端口号组成，之间以冒号（`:`）分隔，多个端口之间以逗号（`,`）分隔，可以支持 TCP 和 HTTP

### 自定义生命周期命令

appctl 的默认命令支持继承或重写，应用开发者可以把需要自定义的函数写在 `/opt/app/current/bin/node/{NODE_CTL}.sh` 里，比如本仓库的 `starter.sh` 中的 `initNode` 函数。需要把文件名定义在环境变量中供 appctl 加载：

```
NODE_CTL=starter
```

框架命令 | appctl 命令 | 说明
-- | -- | --
\- | initNode | 对节点进行初始化，比如创建目录等
init | initCluster | 对新创建的集群或新添加的节点执行初始化操作，依赖 initNode
start | start | 按服务组件定义时的顺序依次启动，依赖 initNode
stop | stop | 按服务组件定义时的逆序依次关闭
restart | restart | 按服务组件定义时的顺序依次重启
check_cmd | check | 健康检查
action_cmd | revive | 健康检查连续失败后，调用此命令自动修复

### 初始化

应用开发者需要关注的部分主要是挂盘上服务目录的创建，每个服务一般包括 `data` 和 `logs` 两个子目录，分别存放数据和日志文件：

```
├─ /data/
│  ├─ appctl/
│  │  ├─ data/
│  │  └─ logs/
│  ├─ caddy/
│  │  ├─ data/
│  │  └─ logs/
│  └─ .../  # 其他服务组件
```

> 注意：启动服务前一定要确保挂盘已经挂载，并且上面的目录已经创建完毕，否则可能导致服务组件把数据写到系统盘上，导致数据丢失或者数据不一致的情况。

### systemd

运行于操作系统上的服务组件采用 [systemd](https://github.com/systemd/systemd) 进行管理。

> 注意：请确保所有服务是 `disabled` 状态，避免虚机开机后自动启动服务组件。AppCenter 框架会在合适的时机调度服务组件进行启动，比如挂盘准备好、IP 分配到位、并且所有节点都准备好以后再启动。

### 健康检查与自动恢复

AppCenter 框架会通过 `appctl check` 对运行在虚机上的服务组件进行健康检查，并且在必要时候通过 `appctl revive` 对不健康的服务进行修复。

默认情况下，健康检查会根据服务定义里指定的顺序，依次检查每个服务的运行状态（`systemctl is-active`）以及服务定义的每个端口是否可达。如果需要更多操作，可以通过继承的方式进行扩展：

```
check() {
  _check # 进行默认检查

  # 其他额外检查
  # ...
}
```

# 制作应用配置文件包

`app/` 目录包含制作 AppCenter 应用的全部配置文件。应用版本名遵守 [Semantic Versioning 2.0.0](https://semver.org/) 规范。
