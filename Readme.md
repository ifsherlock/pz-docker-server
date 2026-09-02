# 🧟 Project Zomboid Docker Server (With Web Management)

这是一个可持久化、带 Web 管理面板的《僵尸毁灭工程》(Project Zomboid) Docker 服务端方案。

当前仓库：<https://github.com/ifsherlock/pz-docker-server><br>
配套面板：<https://github.com/ifsherlock/pz-web-backend>

> ⚠️ 注意：
> 
> 如果你想在`Windows`上面跑，请参考[我的博文查看Windows下更好的糊糊工程](https://blog.astro777.cfd/posts/games/windows-project-zomboid-server-automation/)
> 
> 不要在`WSL2`+Docker跑该方案，WSL2收发UDP简直就是场灾难。
>
> 网络模式我从`Mirrored`->`NAT`->`Host`->`Bridge`->`Mirrored`试了一圈，将容器的MTU往下调整（默认1500，我自己是1452，给的是1350），关掉容器内网卡的`tx-checksumming`（`WSL2`低于`12字节`的`UDP`包会被忽略），但都毫无效果。
>
> 只要公网一有流量进来大家就会一起被踢出服务器，看什么时候能`Debug`出问题给`WSL`那边提个`Issue`吧……

## ✨ 1. 功能

* 🐳 全功能 Docker 化: 基于 Ubuntu 构建，内置 SteamCMD、Java 环境及中文语言环境支持。
* 🖥️ Web 可视化配置: 内置 Go 语言编写的 Web 后台，支持在线修改 servertest.ini (服务器设置) 和 sandbox.lua (沙盒设置)，支持热重载。
* 📂 网页文件管理: 集成 FileBrowser，无需 SSH/FTP 即可在网页端管理模组、地图存档及日志文件。
* 🔒 安全网关: 内置 Nginx 反向代理
* 🔐 自动 HTTPS: 集成 acme.sh，支持通过 Cloudflare DNS API 自动申请并续期 SSL 证书，亦支持自定义证书挂载。
* 🔄 自动更新:
  * 游戏更新: 容器启动/重启时自动检测并更新 PZ 服务端，默认跟随 Steam `public` 分支。
  * 面板更新: Web 面板支持在线一键检查更新并热重启。
* 💾 备份与恢复:
  * Web 面板“监控维护”支持手动备份、按小时定时备份、备注、保留数量上限、删除和恢复。
  * 备份包含存档、`Server` 配置、服务器数据库、Workshop 元数据和面板运行设置，不包含 `/opt/pzserver` 游戏程序。
  * 恢复时会停止游戏服务、覆盖数据、修正文件属主后再启动，避免在线写入造成不一致。
* 🎮 版本管理:
  * Web 面板“服务器配置”提供 `public`、`42.19`、`legacy41` 和自定义 Steam 分支选择。
  * 当前 Steam `public` 稳定版为 **42.20.4**（buildid `24909836`）；面板仪表盘显示实际运行版本。
  * 选择 `public` 或其他分支后，保存并重启会执行 `app_update 380870 -beta <分支> validate` 自动拉取最新内容。
  * 自定义项填写 Steam 官方分支名；版本号不能直接当分支名使用。精确锁定历史构建需要 depot manifest ID。
* 🔐 权限修复:
  * Dockerfile 支持 `PZ_UID` / `PZ_GID`（默认 `1000:1000`），创建容器 `steam` 用户时固定 UID/GID。
  * 容器启动时自动校正 bind mount 内部文件属主和读写权限，避免 Steam 更新、日志和存档出现 `Permission denied`。
* 🔑 服务端安全配置:
  * Web 面板底部“服务端安全”分组支持玩家入服密码、管理员账户和管理员密码。
  * 点击“保存并重启”后，玩家密码写入 `servertest.ini`，管理员账户名同步到 Build 42 的服务器数据库，管理员密码通过游戏原生 `-adminpassword` 参数生效。
* 🧱 持久化：游戏本体、存档、配置、面板数据与容器分离，方便改动以及保存。

### 当前版本与配置行为

* 默认游戏分支是 Steam `public`，当前稳定版为 **42.20.4**（buildid `24909836`）。`public` 是分支名，不是固定版本号；Steam 发布新稳定版后会自动跟随。
* 面板“服务器配置”中保存的游戏分支会写入 `data/web-backend/panel_settings.json`，启动时优先于 `.env` 的 `PZ_BRANCH`。切换后点击“保存并重启”即可拉取并运行目标分支。
* 下拉框中的 `42.19`、`legacy41` 也是 Steam 分支。要锁定某个历史构建，必须使用 Steam Depot 的 manifest ID；不能把任意版本号直接填成分支名。
* `PZ_UID` / `PZ_GID` 只负责容器内 `steam` 用户和宿主机 bind mount 的属主映射，默认 `1000:1000`。容器每次启动还会修正挂载目录中的属主和读写权限。
* 面板中的管理员账户/密码是游戏管理员凭据；`PZ_WEB_ACCOUNT` / `PZ_WEB_PASSWORD` 是 Nginx 面板登录凭据，`FILEBROWSER_ADMIN_*` 是 FileBrowser 首次初始化凭据，三者用途不同。
* 面板 favicon 使用官方 Project Zomboid 图标，随面板二进制内嵌发布，不需要额外挂载。

## 🚀 2. 快速开始

### 2.1 环境要求：

* Docker
* Docker Compose
* Linux (No WSL2!)

### 2.2 获取项目

```bash
git clone https://github.com/ifsherlock/pz-docker-server.git
# windows下直接打开目录即可
cd pz-docker-server
```

### 2.3 配置环境文件

> ⚠️ 注意: 请务必修改 `.env` 文件中的密码配置（`FILEBROWSER_ADMIN_PASSWORD`、`PZ_WEB_PASSWORD` 等），切勿使用默认密码！

打开项目目录下的`.env`文件，可选配置如下：

#### ⚙️ 环境变量配置 (.env)

请在首次启动前创建或编辑项目根目录的 `.env`（仓库未提供可直接提交的 `.env.example`），并至少修改所有密码和域名相关配置。`.env` 包含凭据，不要提交到 GitHub。
#### 📦 基础配置 (Basic)

| 变量名                       | 默认值                | 说明                                                         |
| :--------------------------- | :-------------------- | :----------------------------------------------------------- |
| `CONTAINER_NAME`             | `pz-automated-server` | Docker 容器的名称。                                          |
| `PORT_GAME_UDP`              | `16261`               | **主游戏端口 (UDP)**。玩家连接服务器时填写的端口。           |
| `PORT_GAME_HANDSHAKE`        | `16262`               | **握手端口 (UDP)**。用于 Steam 查询和直连。                  |
| `PORT_GAME_SETTING_EXT`      | `10888`               | **Web 面板端口**，默认为游戏配置，/filebrowser路径为文件管理。 |
| `FILEBROWSER_ADMIN_USERNAME` | （自行设置）         | **FileBrowser** 首次初始化的管理员用户名；已有数据库时修改此项不会自动改现有账号。 |
| `FILEBROWSER_ADMIN_PASSWORD` | （自行设置）         | **FileBrowser** 首次初始化的管理员密码；建议使用至少 12 位的强密码。 |

#### 🛠️ 构建与网络 (Build & Network)

| 变量名                  | 默认值                             | 说明                                                         |
| :---------------------- | :--------------------------------- | :----------------------------------------------------------- |
| `PROXY_URL`             | 空                             | **HTTP 代理地址**。用于加速 Docker 构建和 SteamCMD 下载；不用代理时留空。Linux 请填写宿主机局域网 IP（如 `http://192.168.1.5:7890`）。 |
| `USE_CN_MIRROR`         | `true`                             | 是否使用国内镜像源加速 `apt-get` 安装。<br>`true` = 使用阿里云源；`false` = 使用官方源。 |
| `GITHUB_PROXY_URL`      | 空                              | GitHub 下载加速前缀；网络可直连时留空。 |
| `DNS_SERVER_1`          | `223.5.5.5`                        | 容器内使用的DNS组1，此为阿里云的DNS，非国内构建无需填写。    |
| `DNS_SERVER_2`          | `119.29.29.29`                     | 容器内使用的DNS组2，此为腾讯云的DNS，非国内构建无需填写。    |
| `STEAMCMD_CN_MIRROR_ID` | `44`                               | Steam 下载节点 `cellid`；上海 `44`、北京 `23`、成都 `45`、广州 `43`、天津 `47`、新加坡 `10`、香港 `11`。连接异常时可更换或留空。 |

#### 🔒 安全与 HTTPS (SSL/TLS)

设置`HTTPS`之后，脚本会自动帮你申请证书，并把申请到的`cert`以及`key`持久化到项目底下的`cert`文件夹中。

> ⚠️注意，请确定你提供的参数**正确无误**，申请证书是有频率限制的！
>
> 如果查看服务器启动日志时发现被证书机构拒绝，请你自行在你的电脑上面通过`win.acme`或者`acme.sh`之类的工具自行解决后把申请到的证书扔在`cert`文件夹内即可。
>
> **如果你没有公网IP，这一段可以略过，直接走内网穿透即可。**

| 变量名          | 默认值      | 说明                                                         |
| :-------------- | :---------- | :----------------------------------------------------------- |
| `SSL_MODE`      | `off`       | **HTTPS 模式选择**。<br>• `off`: 关闭 HTTPS (仅 HTTP)。<br>• `custom`: 使用自定义证书 (需挂载 `./certs` 目录)。<br>• `cloudflare`: 使用 Cloudflare API 自动申请证书。 |
| `DOMAIN_NAME`   | `localhost` | 你的服务器域名 (如 `pz.example.com`)。<br>仅当 SSL 模式开启时必须填写。 |
| `EMAIL`         | -           | 申请 SSL 证书时的联系邮箱 (用于到期通知)。<br>仅 `cloudflare` 模式需要。 |
| `SSL_CERT`      | `cert.pem`  | 自定义证书文件名 (位于 `./certs` 目录下)。<br>仅 `custom` 模式需要。 |
| `SSL_KEY`       | `key.pem`   | 自定义私钥文件名 (位于 `./certs` 目录下)。<br>仅 `custom` 模式需要。 |
| `CF_TOKEN`      | -           | Cloudflare API Token (需拥有 DNS 编辑权限)。                 |
| `CF_ACCOUNT_ID` | -           | Cloudflare Account ID。                                      |

#### 🎮 游戏配置 (Game Settings)

| 变量名                    | 默认值                          | 说明                                                         |
| :------------------------ | :------------------------------ | :----------------------------------------------------------- |
| `PZ_BRANCH`               | `public`                        | **Steam 游戏分支**。`public` 当前为 42.20.4 并自动跟随稳定版；也可填写 Steam 官方分支名，如 `42.19`、`legacy41`。 |
| `PZ_UID` / `PZ_GID`       | `1000` / `1000`                 | 宿主机挂载目录属主 UID/GID；需与 NAS 上目录属主一致。 |
| `PZ_WEB_ACCOUNT`          | （自行设置）                 | **Nginx Basic Auth 用户名**，用于保护 Web 管理面板入口。 |
| `PZ_WEB_PASSWORD`         | （自行设置）                 | **Nginx Basic Auth 密码**；修改后重启容器重新生成认证文件。 |
| `PZ_SETTING_WEB_REPO`     | `Asteroid77/pz-web-backend`     | 面板依赖的仓库，你可以自行fork然后在此基础上修改，使用自己的Web面板。 |
| `PZ_WEB_BACKEND_FILENAME` | `pz-web-backend-linux-amd64` | 面板 Release 二进制文件名；必须与面板仓库发布的资产名一致。 |

`PZ_SETTING_WEB_REPO` 只影响镜像构建时下载的面板 Release；如果要使用本仓库配套的面板 fork，请填 `ifsherlock/pz-web-backend`，并确保该仓库发布了同名二进制资产。

#### 🌐 DDNS-GO（DDNS-GO Settings)

| 变量名              | 默认值 | 说明                   |
| ------------------- | ------ | ---------------------- |
| `PORT_DDNS_GO`      | `9876` | ddns-go暴露的端口      |
| `FREQUENCY_DDNS_GO` | `30`   | 单位秒，代表检测的频率 |

### 2.4 构建与启动

> ⚠️如果设置了代理，请开启代理的TUN模式

```bash
#先构建属于你自己的images
#时间可能会有点长（取决于你的网络环境）
docker compose build
#启动
docker compose up -d
```

如果你使用的是`Docker-Desktop`，那可以直接点击查看你刚刚启动的容器，点进去即可查看日志，大致如下：

```bash
2026-01-11 11:23:43 --- 容器启动初始化 ---
2026-01-11 11:23:43 模式: SSL_MODE=off
2026-01-11 11:23:43 域名: DOMAIN_NAME=localhost
2026-01-11 11:23:43 正在给予文件权限...
2026-01-11 11:23:43 权限正确: /home/steam (跳过检查)
2026-01-11 11:23:43 权限正确: /opt/pzserver (跳过检查)
2026-01-11 11:23:43 权限正确: /opt/filebrowser (跳过检查)
2026-01-11 11:23:43 --- 初始化 Web 配置面板 ---
2026-01-11 11:23:43 检测到现有面板程序，跳过复制 (保留持久化版本)。
2026-01-11 11:23:43 提示: /certs 目录是只读的，跳过权限修改。
2026-01-11 11:23:43 --- 初始化 文件浏览器(FileBrowser)变量 ---
2026-01-11 11:23:43 --- FileBrowser 数据库已存在，跳过初始化 ---
2026-01-11 11:23:43 --- 启动进程管理器 ---
```

容器启动后，会在当前目录下生成 data 文件夹用于持久化数据：

```bash
.
├── certs/                  # 存放 HTTPS 证书 (SSL_MODE=custom 或 cloudflare 生成)
├── data/
│   ├── game/               # 游戏本体安装目录 (避免每次重启重新下载)
│   ├── zomboid/            # 核心数据：地图存档、配置文件(Server/)、数据库(db/)
│   ├── steam/              # Steam数据存放（主要是缓存登录凭证）
| 	├── filebrowser/        # 文件管理器（不满意Web管理面板功能时使用）
| 	├── ddns-go/            # ddns-go的目录
│   └── web-backend/        # Web管理面板的二进制文件及缓存数据
├── entrypoint.sh           # 初始化脚本
├── start-pz.sh             # 僵毁服务器初始化脚本
├── supervisord.conf        # supervisord多任务管理配置
├── Dockerfile              # 构建docker的配置
├── .env              		# 设置
└── docker-compose.yml      # 启动容器的配置
```

### 2.5 📖 访问与使用

启动成功后，你可以通过浏览器访问服务器。

> 开启了HTTPS跟没开启HTTPS访问的前缀不一样，这里以HTTPS为例。

* **Web管理面板**（修改僵毁Server.ini/SandboxVar.lua，重启服务器，更新服务器，模组增删改）
  * 地址: https://你的域名 (或 https://服务器IP:设置的端口)

  * 安全验证：浏览器会弹出登录框（Nginx Basic Auth），懒得单独给这玩意儿写权限。

  * 用户名：`.env`中的`PZ_WEB_ACCOUNT`
  * 密码：`.env`中的`PZ_WEB_PASSWORD`
* **FileBrowser文件管理器**（僵毁游戏文件管理，在你不满意Web管理面板时使用，简单地说就是上传 Mods、备份 Saves 文件夹、查看 pz-stdout.log 日志）
  * 地址： https://你的域名/filebrowser (或 https://服务器IP:设置的端口/filebrowser)
  * 安全验证：自带有一套权限系统
  * 用户：`.env` 中的 `FILEBROWSER_ADMIN_USERNAME`
  * 密码：`.env`中的`FILEBROWSER_ADMIN_PASSWORD`
* **[DDNS-GO](https://github.com/jeessy2/ddns-go)**（动态家宽IP绑定域名，字面意思，家庭宽带会因为拨号而变更IP，其作用就是不停轮询IP网站询问自己的公网IP）
  * 地址：localhost:9876(默认端口)
  * 用户名：第一次启动会让你自己设置
  * 密码：同上
  * Token: `.env`中的`CF_TOKEN`
  * TTL: 自动（默认）
  * IPV4
    * 是否启用-启用
    * 通过接口获取
    * domains - 输入你的域名，可以同HTTPS设置的一样，也可以自己多建个子域名。
  * 其它
    * 禁止公网访问：禁止（建议）

* 游戏端口：默认映射 UDP `16261`（游戏端口）和 `16262`（握手端口），可在 `.env` 修改宿主机端口。

* 游戏分支: 可在 Web 面板“服务器配置”中选择。`public` 会自动跟随当前稳定版（目前 42.20.4）；也可填写 Steam 官方分支名。不要把任意版本号直接当作分支名。

* RCON: RCON（Remote Console，远程控制台）允许外部管理工具通过 TCP 连接执行服务器命令。只有需要远程控制时才设置 `RCONPort` 和 `RCONPassword`，否则保持密码为空。

* 服务端配置分组：面板将游戏原生配置项细分为服务端基础、网络与连接、聊天与语音、游戏规则、存档与备份、地图、玩家与 PVP、世界环境、车辆、客户端限制、反作弊、Discord、模组与工坊和服务端安全，并额外提供内存、版本和管理员凭据等面板虚拟项；密码相关项固定在最后。

* 公网访问：容器只负责监听宿主机映射端口。域名解析、路由器端口转发和上游反向代理必须把 HTTP/HTTPS 转发到 `PORT_GAME_SETTING_EXT`（默认 `10888`）；公网 IP 能打开其他管理页不代表已转发到本面板。

## 🛠️ 3. 常见问题 (FAQ)

### Q1: 服务器一直在重启或者无法启动？

请检查日志 `docker compose logs -f pz-server` 或直接在对应 Docker 管理工具中查看。

常见原因是 Steam 下载网络、分支名错误、证书配置或挂载目录权限。先核对 `.env`，再查看启动日志中的 SteamCMD 错误。

### Q2: 如何手动更新游戏？

直接重启容器即可：`docker compose restart pz-server`。

启动脚本会执行 `app_update 380870 -beta <分支> validate`。面板已保存的分支优先于 `.env` 的 `PZ_BRANCH`。

### Q3: 如何切换到指定版本？

在面板“服务器配置 → 游戏版本分支”选择 `public`、`42.19`、`legacy41` 或填写自定义 Steam 分支名，然后点击“保存并重启”。`public` 当前是 42.20.4，并会自动跟随后续稳定版；自定义输入必须是 Steam 已存在的分支名。若需要固定历史构建，请使用 Steam Depot manifest ID 对应的下载方案，不能只输入一个版本号。

### Q4: 如何添加模组 (Mods)？

进入 Web 面板  -> Server 设置 -> 模组管理 -> 使用 Web 面板自带的 模组管理 功能自动解析。

或者使用`FileBrowser`找到`Server.ini`：

找到 WorkshopItems (填 Mod ID) 和 Mods (填 Mod 名称)。

保存并点击“更新并重启”。

### Q5: 为什么修改了 `.env` 里的密码重启没生效？

`FileBrowser` 和 `Nginx` 的密码在首次初始化后会写入数据库或文件。

如果需要强制重置：

`FileBrowser`: 删除 `./data/filebrowser/database.db` 然后重启。

`Web 设置面板`: 删除容器内的 `/etc/nginx/.htpasswd` (或进入容器执行 `rm /etc/nginx/.htpasswd`) 然后重启。

### Q6: Web 配置面板问题

关于面板，我单独拆分出了一个[仓库](https://github.com/ifsherlock/pz-web-backend)。

有什么问题可以去那边提。

如果需要手动更新面板，可从面板仓库的 `Release` 下载与 `PZ_WEB_BACKEND_FILENAME` 一致的 Linux amd64 二进制，替换 `data/web-backend/pz-web-backend` 后重启 `webconfig`。面板模板和 favicon 已内嵌在二进制中，不需要额外挂载前端文件。

### Q7: UID/GID 应该写在哪里？

在 `.env` 设置 `PZ_UID` 和 `PZ_GID`，再执行 `docker compose build`。Compose 会把它们作为构建参数传给 Dockerfile；容器启动时还会修正挂载目录属主。不要把宿主机 UID/GID 写死在 Dockerfile 中。

## 📝 4. License

MIT License
