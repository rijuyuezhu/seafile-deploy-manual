# 毕业前，把学校 Seafile 迁移到自己的旧电脑上

写给即将毕业、还在用学校网盘的同学们：毕业快乐。离校前最好留一点时间整理文件，把课程资料、代码、论文、照片和实验数据迁移到自己能长期维护的位置。

很多学校会提供基于 Seafile 的网盘服务。南京大学的 `box.nju.edu.cn` 就是一个例子。它的桌面客户端同步稳定，网页端方便管理文件，手机端可以临时查资料，WebDAV 也能接到 Zotero、文件管理器和其他工具里。毕业前需要考虑账号有效期、容量和访问权限的变化，提前迁移会从容一些。

我选择在一台旧电脑上部署自己的 Seafile。Seafile 是开源项目，社区版对个人使用已经够用。迁移完成后，主要变化是客户端和 WebDAV 的服务器地址换成了自己的域名，日常同步体验和学校网盘接近。

## 整体思路

这套部署面向个人使用，重点放在稳定和可维护上。旧电脑上用 Docker Compose 跑 Seafile、MariaDB 和 memcached。Seafile 容器只监听本机端口，外部请求统一交给 Nginx 反向代理。

内部访问使用 Tailscale。自己的电脑、手机和平板加入同一个 tailnet 后，可以直接访问旧电脑。外部访问使用 Cloudflare Tunnel。这样不需要公网 IP，也不需要在家用路由器上开放端口。

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

## 准备一台旧电脑

普通 x86_64 旧电脑就能跑这套服务。内存 4GB 可以起步，8GB 会更宽裕。相比 CPU，硬盘和备份更值得关注。Seafile 是同步服务，服务端磁盘损坏、数据库损坏，或者服务端产生异常同步状态时，客户端可能会同步到受影响的数据。

旧电脑可以作为在线服务入口，但重要资料最好保留异机备份。特别重要的内容可以再保留一份离线备份。自建服务需要考虑恢复能力，不能只关注部署当天能否启动。

我把部署文件和数据文件分开存放。一个比较清晰的结构是：

```text
/opt/seafile-deploy/
├── stack/
│   ├── .env
│   ├── docker-compose.yml
│   ├── nginx.conf
│   └── scripts/
└── data/
    ├── mysql/
    └── shared/
```

`stack` 里放可以版本管理的配置模板和脚本，`data` 里放数据库和 Seafile 的实际文件数据。这个仓库也按这个思路整理，文章、Compose 文件、Nginx 示例和辅助脚本放在一起，运行时产生的数据留在部署机器上。

## 用 Docker Compose 安装 Seafile

安装 Docker 之后，Seafile 可以用 Compose 管理。仓库里提供了一个简化的 `docker-compose.yml`。MariaDB 保存数据库，memcached 做缓存，Seafile 主容器把数据写入 `./data/shared`，Web 端口只暴露到本机的 `127.0.0.1:8080`。

```bash
curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

重新登录后，复制环境变量模板：

```bash
cp .env.example .env
vim .env
```

主要配置项包括服务器域名、协议、数据库密码和管理员账号：

```env
SEAFILE_SERVER_HOSTNAME=cloud.example.com
SEAFILE_SERVER_PROTOCOL=https
MYSQL_ROOT_PASSWORD=change-me
SEAFILE_ADMIN_EMAIL=you@example.com
SEAFILE_ADMIN_PASSWORD=change-me
```

然后启动服务：

```bash
docker compose --env-file .env up -d
```

容器启动后，`http://127.0.0.1:8080` 应该能访问 Seafile。此时服务只在本机可见，后面再接入 Nginx、Tailscale 和 Cloudflare Tunnel。

## 配置 Nginx

Nginx 负责把请求转发给本机的 Seafile 容器。为了配合 Cloudflare Tunnel，我把公网域名对应的本机入口放在 HTTP 上，让 Tunnel 连接 `http://127.0.0.1`，再由 Nginx 反代到 Seafile。

这段 HTTP 连接只发生在旧电脑本机内部。公网侧 HTTPS 由 Cloudflare 处理。为了让 Seafile 生成正确的链接，Nginx 反代时需要传入 `X-Forwarded-Proto https`。

示例配置如下：

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name cloud.example.com;

    client_max_body_size 0;
    proxy_read_timeout 310s;
    proxy_send_timeout 310s;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header Connection "";
    }
}
```

配置完成后在旧电脑上测试：

```bash
curl -I -H 'Host: cloud.example.com' http://127.0.0.1/
```

如果看到 `302 Found`，并且 `Location` 指向 `/accounts/login/?next=/`，说明 Nginx 已经进入 Seafile。

## 用 Tailscale 做内部访问

Tailscale 用来建立私有访问路径。旧电脑、笔记本和手机加入同一个 tailnet 后，即使不在同一个局域网，也可以通过 Tailscale 地址访问旧电脑。

安装命令如下：

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

查看旧电脑的 Tailscale 地址：

```bash
tailscale ip -4
```

可以直接使用 Tailscale 的 MagicDNS，也可以配置一个内部域名，例如 `cloud.internal.example.com`，指向旧电脑的 Tailscale IP。公网入口不可用时，内部地址仍然可以用于维护和恢复服务。

## 用 Cloudflare Tunnel 做外部访问

Cloudflare Tunnel 负责公网入口。旧电脑上的 `cloudflared` 主动连接 Cloudflare，外部用户访问域名时，流量通过 Tunnel 回到旧电脑。这样不需要公网 IP，也不用在路由器上开放 80 或 443 端口。

在 Cloudflare Zero Trust 里创建 Tunnel，选择 `cloudflared` 作为 connector。按照页面给出的命令在旧电脑上安装并启动之后，Dashboard 里应该能看到 connector online。

然后添加 Public Hostname：

```text
Hostname: cloud.example.com
Service Type: HTTP
Service URL: http://127.0.0.1
```

这条配置表示，公网用户到 Cloudflare 使用 HTTPS，Cloudflare 通过 Tunnel 找到旧电脑，`cloudflared` 再把请求交给本机 Nginx 的 HTTP 入口。本机 Nginx 只负责把请求转给 Seafile。

保存后可以从任意网络测试：

```bash
curl -I https://cloud.example.com/
```

正常情况下会看到 Cloudflare 的响应头，以及 Seafile 登录页对应的 302 跳转。

## 从学校 Seafile 迁移数据

迁移数据时，我使用客户端迁移。先在学校 Seafile 客户端里确认所有资料库都完整同步到本地，尤其是大文件、加密资料库和很久没打开过的目录。确认本地数据完整后，再在新的自建 Seafile 里创建对应资料库，并分批上传或重新同步。

这种方式比较容易控制进度。可以先迁移小资料库，确认网页端、桌面客户端和手机端都正常，再迁移论文资料、课程资料、代码、照片和实验数据。迁移过程中如果出现冲突文件，也比较容易定位。

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

```env
SEAFILE_SERVER_HOSTNAME=cloud.example.com
SEAFILE_SERVER_PROTOCOL=https
```

## 这个仓库里有什么

这篇文章所在的仓库记录了一条适合个人毕业迁移的路径，包括旧电脑部署、Docker Compose、Nginx、Tailscale、Cloudflare Tunnel 和常见问题处理。

仓库结构如下：

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
