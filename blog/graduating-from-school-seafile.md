# 毕业前，把学校 Seafile 迁移到自己的旧电脑上

写给即将毕业、还在用学校网盘的同学们：毕业快乐。希望大家在离开校园之后，仍然能把自己的课程资料、代码、论文、照片和那些很难重新整理的文件稳稳地带走。

很多学校会提供基于 Seafile 的网盘服务。南京大学的 `box.nju.edu.cn` 就是一个典型例子。它的体验其实相当好：桌面客户端同步稳定，网页端可以直接管理文件，手机端能临时查资料，WebDAV 也可以接到 Zotero、文件管理器或其他工具里。读书的时候，这类学校网盘常常像空气一样存在，直到快毕业时才突然意识到：账号不一定能一直用下去，容量和权限也可能发生变化。

所以我决定在毕业前把数据迁出来，部署一套自己的 Seafile。最后的体验比想象中平滑。Seafile 本身是开源的，社区版对个人使用已经足够；找一台旧电脑、旧笔记本或者小主机，把它放在家里或宿舍里，就可以继续拥有一个熟悉的同步网盘。迁移完成之后，日常使用几乎还是原来的方式，只是客户端和 WebDAV 的服务器地址换成了自己的域名。

## 整体思路

这套部署没有追求复杂的企业架构。我的目标是让它足够稳定、足够容易维护，同时不要把家里的机器直接暴露到公网。

旧电脑上跑 Docker Compose，里面是 Seafile、MariaDB 和 memcached。Seafile 容器只监听本机端口，外面由 Nginx 统一反向代理。内部访问交给 Tailscale，这样自己的电脑、手机和平板只要加入同一个 tailnet，就可以像在局域网里一样访问旧电脑。外部访问则交给 Cloudflare Tunnel，它不需要公网 IP，也不需要在路由器上做端口转发。

最后的访问路径大概是这样的：自己设备在内部访问时，会通过 Tailscale 找到旧电脑，再由 Nginx 进入 Seafile；公网访问时，请求先到 Cloudflare，再通过 Tunnel 回到旧电脑上的 `cloudflared`，然后进入本机 Nginx 和 Seafile。

```text
公网用户 / 手机蜂窝网络
  -> Cloudflare
  -> Cloudflare Tunnel
  -> 旧电脑上的 cloudflared
  -> 本机 Nginx
  -> Seafile
```

如果你已经有一台云服务器，也可以不用 Cloudflare Tunnel，而是让云服务器通过 Tailscale 反向代理回旧电脑。这个方案也能工作，但会多依赖一台云服务器。如果服务器在中国大陆，还需要考虑备案和运营商链路的问题。对个人自用来说，Cloudflare Tunnel 通常更省心。

## 准备一台旧电脑

硬件要求并不高。普通 x86_64 旧电脑就能跑，内存 4GB 起步，8GB 会更从容。真正更值得关心的是硬盘和备份。Seafile 是同步系统，不是备份系统；如果服务端磁盘损坏、数据库损坏，或者服务端产生了错误的同步状态，客户端也可能把这个状态同步下来。

因此我不建议只把所有希望寄托在一块旧 SSD 上。旧电脑可以作为在线服务入口，但重要资料最好还有另一份异机备份，特别重要的内容再保留一份冷备份。自建服务最重要的不是“今天能跑起来”，而是“半年后出问题还能恢复”。

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

`stack` 里放可以版本管理的配置模板和脚本，`data` 里放数据库和 Seafile 的实际文件数据。这个仓库也是按这个思路整理的：文章、Compose 文件、Nginx 示例和辅助脚本放在一起，真正运行时产生的数据留在部署机器上。

## 用 Docker Compose 安装 Seafile

安装 Docker 之后，整个 Seafile 服务可以用 Compose 管起来。仓库里提供了一个简化的 `docker-compose.yml`，核心思路是 MariaDB 保存数据库，memcached 做缓存，Seafile 主容器把数据写入 `./data/shared`，并且只把 Web 端口暴露到本机的 `127.0.0.1:8080`。

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

最关键的是设置服务器域名、协议、数据库密码和管理员账号：

```env
SEAFILE_SERVER_HOSTNAME=cloud.example.com
SEAFILE_SERVER_PROTOCOL=https
MYSQL_ROOT_PASSWORD=change-me
SEAFILE_ADMIN_EMAIL=you@example.com
SEAFILE_ADMIN_PASSWORD=change-me
```

然后启动：

```bash
docker compose --env-file .env up -d
```

如果容器正常启动，`http://127.0.0.1:8080` 就应该能看到 Seafile。此时它还只是本机服务，下一步再交给 Nginx、Tailscale 和 Cloudflare Tunnel。

## 配置 Nginx

Nginx 负责把外部请求转发给本机的 Seafile 容器。这里有一个很容易踩坑的点：如果 Cloudflare Tunnel 到本机 Nginx 使用 HTTP，而 Nginx 又把 HTTP 强制跳转到 HTTPS，就会出现浏览器提示“重定向过多”。

我最后采用的方式是让 Cloudflare Tunnel 连接本机的 HTTP 入口，也就是 `http://127.0.0.1`。这一段只发生在旧电脑本机内部，不经过公网；公网侧的 HTTPS 证书由 Cloudflare 处理。为了让 Seafile 知道用户实际访问的是 HTTPS，Nginx 反代时需要设置 `X-Forwarded-Proto https`。

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

配置完成后先在旧电脑上本地测试：

```bash
curl -I -H 'Host: cloud.example.com' http://127.0.0.1/
```

如果看到 `302 Found`，并且 `Location` 指向 `/accounts/login/?next=/`，就说明 Nginx 已经正确进入 Seafile 了。

## 用 Tailscale 做内部访问

Tailscale 的作用是给自己的设备建立一个私有网络。旧电脑、笔记本、手机都加入同一个 tailnet 之后，即使它们不在同一个物理局域网里，也可以通过 Tailscale 地址互相访问。

安装很简单：

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

然后查看旧电脑的 Tailscale 地址：

```bash
tailscale ip -4
```

你可以直接用 Tailscale 的 MagicDNS，也可以给自己配置一个内部域名，例如 `cloud.internal.example.com` 指向旧电脑的 Tailscale IP。这样即使公网入口临时不可用，自己的设备仍然可以通过内部地址访问 Seafile。

对我来说，Tailscale 是这套方案里很重要的一层保险。公网入口方便分享和手机蜂窝网络访问，但真正维护、排错、恢复服务时，有一个稳定的内部入口会安心很多。

## 用 Cloudflare Tunnel 做外部访问

Cloudflare Tunnel 解决的是公网入口问题。它的好处是旧电脑不需要公网 IP，也不需要在路由器上开放 80 或 443 端口。旧电脑上的 `cloudflared` 主动连到 Cloudflare，外部用户访问域名时，流量再通过 Tunnel 回到旧电脑。

在 Cloudflare Zero Trust 里创建 Tunnel，选择 `cloudflared` 作为 connector。按照页面给出的命令在旧电脑上安装并启动之后，Dashboard 里应该能看到 connector online。

然后添加 Public Hostname：

```text
Hostname: cloud.example.com
Service Type: HTTP
Service URL: http://127.0.0.1
```

这就是前面 Nginx 配置里不对这个域名做 HTTP 到 HTTPS 跳转的原因。公网用户到 Cloudflare 是 HTTPS，Cloudflare 到 `cloudflared` 是 Tunnel，加密和证书都由 Cloudflare 处理；最后 `cloudflared` 到本机 Nginx 是 localhost HTTP，简单而且不容易遇到本机证书校验问题。

保存后可以从任意网络测试：

```bash
curl -I https://cloud.example.com/
```

正常情况下会看到 Cloudflare 返回的响应头，以及 Seafile 登录页对应的 302 跳转。

如果这里出现 `502 Bad Gateway`，通常是 `cloudflared` 连不上本机 Nginx，或者 origin URL 写错了。可以在旧电脑上看日志：

```bash
sudo journalctl -u cloudflared -n 100 --no-pager
```

如果看到“证书不匹配 localhost”之类的错误，说明 Tunnel 被配置成了 HTTPS origin，但本机证书和 `localhost` 对不上。对于这套同机部署，直接使用 `http://127.0.0.1` 会更省事。

## 从学校 Seafile 迁移数据

迁移数据时，我没有直接在文件系统层面搬 Seafile 服务端数据，而是采用更稳妥的客户端迁移。先在原来的学校 Seafile 客户端里确认所有资料库都已经完整同步到本地，尤其是大文件、加密资料库和很久没打开过的目录。等本地确认完整之后，再在新的自建 Seafile 里创建对应资料库，并分批上传或重新同步。

这样做虽然看起来朴素，但好处是可控。先迁移小资料库，确认网页端、桌面客户端和手机端都正常，再迁移论文资料、课程资料、代码、照片和实验数据这些更大的目录。迁移过程中如果出现冲突文件，也比较容易定位。

桌面客户端和手机客户端都需要重新添加服务器地址：

```text
https://cloud.example.com
```

WebDAV 地址也要改成新服务器：

```text
https://cloud.example.com/seafdav/
```

未登录时访问 `/seafdav/` 返回 `401 Unauthorized` 通常是正常现象，说明 WebDAV 入口存在，只是在等待认证。真正需要排查的是 404、502 或连接超时。

旧的学校网盘分享链接不会自动迁移。迁移完成后，如果之前给别人发过分享链接，需要在新服务器上重新生成。Seafile 的公开地址也要设置成新的域名，否则新生成的分享链接可能会带错域名。

```env
SEAFILE_SERVER_HOSTNAME=cloud.example.com
SEAFILE_SERVER_PROTOCOL=https
```

## 这个仓库里有什么

这篇文章所在的仓库不试图替代官方文档，而是记录一条适合个人毕业迁移的路径：旧电脑、Docker Compose、Nginx、Tailscale、Cloudflare Tunnel，再加上一些常见问题的处理方法。

仓库结构大致如下：

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

如果有同学也想从学校 Seafile 迁出来，可以先读这篇文章，再按自己的机器和域名改配置。真正长期运行时，最好再补上自动备份、磁盘健康检查和恢复演练。

## 结尾

学校网盘陪我们度过了很多课程、作业、实验、论文和项目。毕业之后，账号可能会失效，但那些资料仍然值得被妥善保存。

自建 Seafile 不一定适合所有人。它需要一点 Linux、Docker、网络和备份意识，也需要你愿意偶尔维护一下旧电脑。但如果你刚好有一台闲置机器，又希望自己的资料离开校园后还能继续稳定同步，这会是一个很舒服的个人数据中心。

祝所有即将毕业的同学毕业快乐。愿大家带走的不只是文件，也有那些认真学习、折腾系统、调试网络、写论文和赶 deadline 的日子。
