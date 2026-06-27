# 毕业前，把学校 Seafile 迁移到自己的旧电脑上

写给即将毕业、还在用学校网盘的同学们：毕业快乐。离校前最好留一点时间整理文件，把课程资料、代码、论文、照片和实验数据迁移到自己能长期维护的位置。

很多学校会提供基于 Seafile 的网盘服务。南京大学的 `box.nju.edu.cn` 就是一个例子。它的桌面客户端同步稳定，网页端方便管理文件，手机端可以临时查资料，WebDAV 也能接到 Zotero、文件管理器和其他工具里。毕业前需要考虑账号有效期、容量和访问权限的变化，提前迁移会从容一些。

我选择在一台旧电脑上部署自己的 Seafile。Seafile 是开源项目，社区版对个人使用已经够用。迁移完成后，主要变化是客户端和 WebDAV 的服务器地址换成了自己的域名，日常同步体验和学校网盘接近。

这篇文章配套的仓库在这里：

```bash
git clone https://github.com/rijuyuezhu/seafile-deploy-manual.git
```

下面的步骤会直接使用仓库中的模板文件。文章可以单独阅读，也可以和仓库一起操作。

## 选择操作系统

最省事的方案是在旧电脑上直接安装 Linux。我推荐 Ubuntu Server LTS 或 Debian stable。它们的软件包、Docker、Nginx、Tailscale 和 cloudflared 都比较容易安装，重启后也适合长期运行。

如果旧电脑现在跑的是 Windows，也可以用 WSL2。建议安装 Ubuntu WSL2，把 Seafile、Docker、Nginx 和 cloudflared 都放在 WSL 里。部署目录放在 WSL 的 Linux 文件系统中，例如 `/opt/seafile-deploy`，不要放在 `/mnt/c` 下面。WSL 方案适合已经在 Windows 上使用旧电脑的情况，但要注意 Windows 睡眠、自动重启和 WSL 开机启动问题。长期无人值守时，裸 Linux 会更简单。

Windows 上可以先在 PowerShell 中安装 Ubuntu WSL2：

```powershell
wsl --install -d Ubuntu
```

进入 Ubuntu 后，后续命令和普通 Linux 基本一致。后面会用到 `systemctl` 管理 Docker、Nginx 和 cloudflared。如果 WSL 里 `systemctl` 不可用，可以先启用 systemd：

```bash
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
```

然后回到 PowerShell 执行：

```powershell
wsl --shutdown
```

重新进入 Ubuntu 后再继续部署。

## 整体结构

旧电脑上跑 Docker Compose，里面是 Seafile、MariaDB 和 memcached。Seafile 容器只监听本机端口，外部请求统一交给 Nginx。内部访问使用 Tailscale，外部访问使用 Cloudflare Tunnel。这样不需要公网 IP，也不需要在家用路由器上开放端口。

公网访问路径如下：

```text
公网用户 / 手机蜂窝网络
  -> Cloudflare
  -> Cloudflare Tunnel
  -> 旧电脑上的 cloudflared
  -> 本机 Nginx
  -> Seafile
```

已有云服务器的同学也可以用云服务器做公网入口，再通过 Tailscale 反向代理回旧电脑。这个方案同样可行，只是会多依赖一台服务器。如果云服务器在中国大陆，还要考虑备案和不同运营商的链路表现。个人自用场景下，Cloudflare Tunnel 的配置成本更低。

## 准备部署目录

下面假设部署目录是 `/opt/seafile-deploy`，仓库临时克隆到用户家目录。Compose 文件所在目录就是运行目录，数据会放在 `/opt/seafile-deploy/data`。

先安装基础工具并克隆仓库：

```bash
sudo apt update
sudo apt install -y git curl vim nginx ca-certificates

git clone https://github.com/rijuyuezhu/seafile-deploy-manual.git ~/seafile-deploy-manual
export REPO=$HOME/seafile-deploy-manual
export DEPLOY=/opt/seafile-deploy
```

创建部署目录：

```bash
sudo mkdir -p "$DEPLOY"
sudo chown -R "$USER:$USER" "$DEPLOY"
```

把仓库里的模板复制到部署目录：

```bash
cp "$REPO/docker-compose.yml" "$DEPLOY/docker-compose.yml"
cp "$REPO/.env.example" "$DEPLOY/.env"
cp -a "$REPO/scripts" "$DEPLOY/scripts"
cp -a "$REPO/nginx" "$DEPLOY/nginx"
cp -a "$REPO/cloudflare" "$DEPLOY/cloudflare"
cp -a "$REPO/docs" "$DEPLOY/docs"
mkdir -p "$DEPLOY/data/mysql" "$DEPLOY/data/shared"
chmod 755 "$DEPLOY/data/shared"
```

复制后的主要文件位置如下：

| 文件或目录 | 放置位置 | 用途 |
|---|---|---|
| `docker-compose.yml` | `/opt/seafile-deploy/docker-compose.yml` | Seafile、MariaDB、memcached 的 Compose 配置 |
| `.env` | `/opt/seafile-deploy/.env` | 域名、协议、数据库密码、管理员账号 |
| `scripts/` | `/opt/seafile-deploy/scripts/` | 安装、部署、检查脚本 |
| `nginx/` | `/opt/seafile-deploy/nginx/` | Nginx 模板 |
| `data/mysql/` | `/opt/seafile-deploy/data/mysql/` | MariaDB 数据 |
| `data/shared/` | `/opt/seafile-deploy/data/shared/` | Seafile 数据 |

这个目录结构和仓库模板保持一致，后面升级或排查时比较容易对照。

## 配置 `.env`

编辑 `/opt/seafile-deploy/.env`：

```bash
vim "$DEPLOY/.env"
```

至少需要改这些值：

```env
SEAFILE_SERVER_HOSTNAME=cloud.example.com
SEAFILE_SERVER_PROTOCOL=https
MYSQL_ROOT_PASSWORD=change-me-long-random-password
SEAFILE_ADMIN_EMAIL=you@example.com
SEAFILE_ADMIN_PASSWORD=change-me-long-random-password
```

`SEAFILE_SERVER_HOSTNAME` 填将来公开访问的域名。即使用 Tailscale 做内部访问，Seafile 的 canonical URL 也建议先统一成公网域名，分享链接和客户端配置会更清楚。

密码可以用下面的命令生成后填入 `.env`：

```bash
openssl rand -base64 32
```

## 安装 Docker 并启动 Seafile

仓库里有安装 Docker 的脚本。进入部署目录后执行：

```bash
cd "$DEPLOY"
bash scripts/install-docker.sh
```

如果脚本提示需要把当前用户加入 docker 组，执行提示里的命令，然后重新登录。之后启动 Seafile：

```bash
cd "$DEPLOY"
bash scripts/deploy.sh
```

检查容器状态：

```bash
docker compose --env-file .env ps
curl -I http://127.0.0.1:8080/
```

如果 `127.0.0.1:8080` 有响应，说明 Seafile 容器已经起来。此时它还没有接入正式入口，下一步配置 Nginx。

## 配置 Nginx

仓库中已经提供了 Cloudflare Tunnel 使用的 Nginx 模板：

```text
/opt/seafile-deploy/nginx/seafile-cloudflare-tunnel.conf.example
```

把它复制到 Nginx 配置目录：

```bash
sudo cp "$DEPLOY/nginx/seafile-cloudflare-tunnel.conf.example" /etc/nginx/conf.d/seafile-cloud.conf
sudo vim /etc/nginx/conf.d/seafile-cloud.conf
```

主要修改 `server_name`，把模板里的 `cloud.example.com` 改成自己的公网域名。这个模板会监听本机 80 端口，并把请求反代到 `127.0.0.1:8080`。Cloudflare 到旧电脑的最后一段走本机 HTTP，公网 HTTPS 由 Cloudflare 处理。

修改后验证并重载 Nginx：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

在旧电脑本机测试 Nginx 是否进入 Seafile：

```bash
curl -I -H 'Host: cloud.example.com' http://127.0.0.1/
```

把 `cloud.example.com` 换成你的域名。正常情况下会看到 Seafile 登录页对应的 302 跳转。

## 配置 Tailscale 内部访问

Tailscale 提供内部访问和维护通道。先安装并登录：

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

查看旧电脑的 Tailscale 地址：

```bash
tailscale ip -4
```

最简单的用法是通过 Tailscale SSH 或 Tailscale IP 维护这台机器。这样即使公网入口不可用，也能进入旧电脑查看 Docker、Nginx 和 cloudflared 状态。

如果希望浏览器也通过 Tailscale 直接访问 Seafile，可以准备一个内部域名，例如 `cloud.internal.example.com`，指向旧电脑的 Tailscale IP。仓库里提供了内部 HTTPS 模板：

```text
/opt/seafile-deploy/nginx/seafile-tailscale-https.conf.example
```

复制后再修改 server name 和证书路径：

```bash
sudo cp "$DEPLOY/nginx/seafile-tailscale-https.conf.example" /etc/nginx/conf.d/seafile-internal.conf
sudo vim /etc/nginx/conf.d/seafile-internal.conf
sudo nginx -t
sudo systemctl reload nginx
```

内部浏览访问可以先不做。对多数个人部署来说，Tailscale 先作为维护通道即可，日常客户端访问可以统一走公网域名。

## 配置 Cloudflare Tunnel 外部访问

在 Cloudflare Zero Trust 里创建 Tunnel，选择 `cloudflared` 作为 connector。Dashboard 会给出安装命令，把它复制到旧电脑上执行。命令执行成功后，页面里应该能看到 connector online。

然后添加 Public Hostname：

```text
Hostname: cloud.example.com
Service Type: HTTP
Service URL: http://127.0.0.1
```

这里的 `cloud.example.com` 要和 `.env` 里的 `SEAFILE_SERVER_HOSTNAME`、Nginx 里的 `server_name` 保持一致。

保存后从外部网络测试：

```bash
curl -I https://cloud.example.com/
```

正常情况下会看到 Cloudflare 的响应头，以及 Seafile 登录页对应的 302 跳转。之后就可以在浏览器中打开这个域名，完成初始化和登录。

如果你已经有云服务器，也可以用云服务器上的 Caddy 或 Nginx 做公网反代，再通过 Tailscale 访问旧电脑。仓库没有强制这个方案，因为 Cloudflare Tunnel 对没有公网 IP 的旧电脑更直接。

## 从学校 Seafile 迁移数据

迁移数据时，我使用客户端迁移。先在学校 Seafile 客户端里确认所有资料库都完整同步到本地，尤其是大文件、加密资料库和很久没打开过的目录。确认本地数据完整后，再在新的自建 Seafile 里创建对应资料库，并分批上传或重新同步。

可以先迁移小资料库，确认网页端、桌面客户端和手机端都正常，再迁移论文资料、课程资料、代码、照片和实验数据。迁移过程中如果出现冲突文件，也比较容易定位。

桌面客户端和手机客户端都需要重新添加服务器地址：

```text
https://cloud.example.com
```

WebDAV 地址也要改成新服务器：

```text
https://cloud.example.com/seafdav/
```

这一步完成后，原来依赖学校 WebDAV 的软件就可以逐个切到新地址。

旧的学校网盘分享链接不会自动迁移。迁移完成后，如果之前给别人发过分享链接，需要在新服务器上重新生成。Seafile 的公开地址也要设置成新的域名，否则新生成的分享链接可能会带错域名。

## 检查和备份

仓库里提供了一个简单检查脚本：

```bash
cd "$DEPLOY"
bash scripts/check.sh
```

脚本里的示例 Host 是 `cloud.example.com`。如果你已经换成自己的域名，可以直接编辑 `scripts/check.sh`，或者手动运行：

```bash
curl -I -H 'Host: your-domain.example' http://127.0.0.1/
```

备份至少要覆盖两个目录：

```text
/opt/seafile-deploy/data/mysql
/opt/seafile-deploy/data/shared
```

仓库里的 `scripts/backup.sh` 只打包部署模板和说明，不会替你备份实际数据。长期使用时建议另外配置定时备份，把数据库目录和 Seafile 数据目录备份到另一块硬盘或另一台机器。

## 这个仓库里有什么

仓库记录了一条适合个人毕业迁移的路径，包括旧电脑部署、Docker Compose、Nginx、Tailscale、Cloudflare Tunnel 和常见问题处理。

```text
seafile-deploy-manual/
├── README.md
├── blog/
│   └── graduating-from-school-seafile.md
├── docker-compose.yml
├── .env.example
├── nginx/
├── cloudflare/
├── docs/
└── scripts/
```

如果有同学也想从学校 Seafile 迁出来，可以先读这篇文章，再按自己的机器和域名改配置。长期运行时，建议补上自动备份、磁盘健康检查和恢复演练。

## Troubleshooting

部署问题通常集中在公网入口这一层。如果 Cloudflare 页面显示 `502 Bad Gateway`，先确认 Tunnel 的 Public Hostname 是否指向了正确的本机服务，例如 `http://127.0.0.1`，再到旧电脑上看 `cloudflared` 日志：

```bash
sudo journalctl -u cloudflared -n 100 --no-pager
```

如果浏览器提示重定向过多，一般是 Cloudflare Tunnel 访问本机 HTTP，而 Nginx 又把这个 HTTP 请求跳回 HTTPS。对同机部署来说，可以让公网域名的 80 server block 直接反代到 Seafile，并在反代头里保留 `X-Forwarded-Proto https`。

如果日志里出现证书和 `localhost` 不匹配，通常是 Tunnel 被配置成了 HTTPS origin，但本机证书没有签给 `localhost`。可以把 Tunnel origin 改成 `http://127.0.0.1`，让 Cloudflare 处理公网侧 HTTPS，本机只处理 localhost HTTP。

WebDAV 方面，访问 `/seafdav/` 时看到 `401 Unauthorized` 往往是正常的，因为它在等待客户端认证。需要继续排查的是 404、502 或连接超时。

## 结尾

学校网盘陪我们保存了很多课程、作业、实验、论文和项目文件。毕业之后，账号可能会失效，但这些资料仍然值得妥善保存。

自建 Seafile 需要一点 Linux、Docker、网络和备份知识，也需要定期维护旧电脑。如果你有一台闲置机器，又希望离校后继续保留接近学校网盘的同步体验，这是一条可行的路线。

祝所有即将毕业的同学毕业快乐。希望这篇记录能帮你顺利完成迁移。
