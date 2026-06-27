# 毕业前，把学校 Seafile 迁移到自己的旧电脑上

> 写给即将毕业、还在用学校网盘的同学们：毕业快乐！也祝大家在离开校园之后，仍然能把自己的资料、代码、论文、照片和回忆稳稳地带走。

很多学校会提供基于 Seafile 的网盘服务，例如 `box.nju.edu.cn` 这样的校园网盘。它很好用：客户端同步稳定，网页端方便，WebDAV 也能接进各种软件。

但毕业之后，学校账号可能会失效，容量和权限也可能变化。与其临近毕业时手忙脚乱，不如提前把数据迁移到自己的 Seafile 上。

这篇文章记录一次从学校 Seafile 迁移到自建 Seafile 的过程。目标是：

- 使用一台旧电脑、旧笔记本或小主机部署 Seafile；
- 局域网和 Tailscale 内部访问稳定；
- 外网通过 Cloudflare Tunnel 访问；
- 手机、电脑客户端重新配置后继续正常同步；
- WebDAV、分享链接等能力尽量保持原来的体验。

全文使用通用占位符，不包含任何真实密码、token、IP 或私有域名。

---

## 一、为什么选择自建 Seafile

Seafile 是一个开源的文件同步与共享系统。它的体验很接近常见网盘：有网页端、桌面客户端、手机客户端、WebDAV、分享链接、版本历史等功能。

对个人用户来说，社区版已经足够完成这些事情：

- 多设备文件同步；
- 网页端管理文件；
- 手机端访问资料；
- WebDAV 挂载；
- 分享链接；
- 上传链接；
- 版本历史和回收站；
- 客户端加密资料库。

我的需求很简单：把毕业前积累的资料从学校网盘迁出来，之后继续能在电脑、手机、平板之间同步。最终体验证明，切换成本并不高：只需要重新配置客户端地址、重新绑定资料库、重新配置 WebDAV，日常使用基本没有区别。

---

## 二、整体架构

我的部署思路是：

```text
旧电脑 / 小主机
  ├── Docker Compose 跑 Seafile
  ├── 本机 Nginx 反向代理 Seafile
  ├── Tailscale 用于私有访问
  └── Cloudflare Tunnel 用于公网访问
```

访问路径大致分成两类。

### 内部访问

```text
自己的设备
  -> Tailscale
  -> 旧电脑
  -> Nginx
  -> Seafile
```

例如：

```text
https://cloud.internal.example.com
```

这个地址只在自己的 tailnet 里使用，不暴露到公网。

### 外部访问

```text
公网用户 / 手机蜂窝网络
  -> Cloudflare
  -> Cloudflare Tunnel
  -> 旧电脑上的 cloudflared
  -> 本机 Nginx
  -> Seafile
```

例如：

```text
https://cloud.example.com
```

这样不需要在家里路由器上做端口转发，也不需要公网 IP。

---

## 三、硬件准备

硬件要求不高。旧笔记本、旧台式机、小主机都可以。

建议配置：

```text
CPU：普通 x86_64 即可
内存：至少 4 GB，建议 8 GB+
系统盘：SSD 更好
数据盘：根据文件量决定
网络：最好有稳定有线网络
```

如果用旧 SSD，建议额外做好备份。Seafile 是同步服务，不是备份本身。服务器磁盘坏了、数据库损坏了，依然可能造成数据损失。

我的建议是：

```text
Seafile 数据目录：在线使用
另一块硬盘 / 另一台机器：定期备份
重要资料：再保留冷备份
```

---

## 四、目录结构设计

建议把部署文件和数据文件分开，例如：

```text
/opt/seafile-deploy/
├── stack/
│   ├── .env
│   ├── .env.example
│   ├── docker-compose.yml
│   ├── nginx.conf
│   ├── install.sh
│   ├── deploy.sh
│   └── README.md
└── data/
    ├── mysql/
    └── shared/
```

其中：

```text
stack/  放配置文件、脚本、说明文档
data/   放数据库和 Seafile 实际数据
```

如果之后要做成 GitHub 仓库，只提交 `stack/` 里的模板文件，不提交 `data/`，也不要提交 `.env`。

需要特别注意：

```text
不要提交 .env
不要提交数据库
不要提交证书私钥
不要提交 Cloudflare Tunnel token
不要提交任何管理员密码
```

---

## 五、安装 Docker 和 Docker Compose

以常见 Linux 发行版为例，先安装 Docker。

```bash
curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
```

把当前用户加入 docker 组：

```bash
sudo usermod -aG docker "$USER"
```

重新登录后检查：

```bash
docker version
docker compose version
```

---

## 六、启动 Seafile

仓库里提供了 `docker-compose.yml` 和 `.env.example`。先复制配置：

```bash
cp .env.example .env
vim .env
```

至少改这些：

```env
SEAFILE_SERVER_HOSTNAME=cloud.example.com
SEAFILE_SERVER_PROTOCOL=https
MYSQL_ROOT_PASSWORD=change-me
SEAFILE_ADMIN_EMAIL=you@example.com
SEAFILE_ADMIN_PASSWORD=change-me
```

启动：

```bash
docker compose --env-file .env up -d
```

查看状态：

```bash
docker ps
docker logs seafile --tail=100
```

---

## 七、配置 Nginx

Nginx 的作用是：

- 提供统一入口；
- 反向代理到 `127.0.0.1:8080`；
- 给 Seafile 传递正确的 `Host` 和 `X-Forwarded-Proto`；
- 给 Cloudflare Tunnel 提供一个本机 HTTP origin。

Cloudflare Tunnel 推荐使用 HTTP 到本机 Nginx：

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

        # 用户到 Cloudflare 是 HTTPS，cloudflared 到本机是 HTTP，
        # 所以传给 Seafile 的协议应该仍然是 https。
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header Connection "";
    }
}
```

测试配置：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

本机测试：

```bash
curl -I -H 'Host: cloud.example.com' http://127.0.0.1/
```

预期看到：

```text
HTTP/1.1 302 Found
Location: /accounts/login/?next=/
```

这说明 Nginx 已经正确反代到 Seafile。

---

## 八、配置 Tailscale 内部访问

Tailscale 适合用来做私有访问。安装之后，旧电脑和自己的手机、电脑都会在一个私有 tailnet 里。

安装：

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

查看地址：

```bash
tailscale ip -4
```

假设旧电脑的 Tailscale 地址是：

```text
100.x.y.z
```

可以在 DNS 中配置一个内部域名，例如：

```text
cloud.internal.example.com -> 100.x.y.z
```

或者直接使用 Tailscale MagicDNS 名称。

---

## 九、配置 Cloudflare Tunnel 外部访问

Cloudflare Tunnel 的好处是：

- 不需要公网 IP；
- 不需要家里路由器端口转发；
- 不直接暴露源站；
- 公网 HTTPS 证书由 Cloudflare 处理。

在 Cloudflare Zero Trust 中创建 Tunnel：

```text
Zero Trust -> Networks -> Tunnels -> Create a tunnel
Connector type: cloudflared
```

Cloudflare 会给一条安装命令。命令里包含 token，不要公开。

Connector online 后，添加 Public Hostname：

```text
Hostname: cloud.example.com
Service Type: HTTP
Service URL: http://127.0.0.1
```

保存后访问：

```bash
curl -I https://cloud.example.com/
```

预期：

```text
HTTP/2 302
location: /accounts/login/?next=/
server: cloudflare
```

如果出现 `502 Bad Gateway`，通常是 cloudflared 连不上 origin。看日志：

```bash
sudo journalctl -u cloudflared -n 100 --no-pager
```

如果出现重定向过多，通常是 Cloudflare 到源站使用 HTTP，而源站又强制跳 HTTPS。此时要让本机 HTTP server block 直接反代 Seafile，不要对 Tunnel 域名做 301 到 HTTPS。

---

## 十、也可以用已有云服务器做公网入口

如果你已经有一台云服务器，也可以用它做公网反代：

```text
用户
  -> 云服务器 Caddy / Nginx
  -> Tailscale
  -> 旧电脑 Seafile
```

例如云服务器上用 Caddy：

```caddy
cloud.example.com {
    reverse_proxy https://100.x.y.z {
        header_up Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
        header_up X-Real-IP {remote_host}

        transport http {
            tls_server_name cloud.example.com
        }
    }
}
```

不过如果云服务器在中国大陆，使用域名提供公网服务可能涉及备案要求。某些运营商到云服务器 443 的链路也可能有奇怪的问题。Cloudflare Tunnel 对个人自用来说通常更省心。

---

## 十一、迁移学校 Seafile 数据

迁移可以分几步进行，不建议直接把客户端目录强行覆盖。

### 1. 在学校 Seafile 客户端里确认资料库

先确认自己要迁移哪些资料库：

```text
论文资料
课程资料
代码
照片
实验数据
个人文档
```

如果有加密资料库，确认自己还记得密码。

### 2. 本地完整同步一份

毕业前先让学校 Seafile 客户端把所有资料库完整同步到本地电脑。

确认没有未同步文件、冲突文件、下载占位文件。

### 3. 在自建 Seafile 上创建新资料库

在新的 Seafile 网页端创建对应资料库，例如：

```text
Documents
Research
Courses
Photos
Archive
```

### 4. 上传或重新同步

可以通过网页上传，也可以用 Seafile 客户端把本地目录同步到新服务器。

建议按资料库分批迁移：

```text
先迁移小资料库
确认正常后迁移大资料库
最后迁移照片、压缩包、实验数据等大文件
```

### 5. 重新配置客户端和 WebDAV

桌面客户端、手机客户端都需要添加新的服务器地址：

```text
https://cloud.example.com
```

WebDAV 地址：

```text
https://cloud.example.com/seafdav/
```

未登录时返回 `401 Unauthorized` 通常是正常的，说明 endpoint 存在，只是需要认证。

---

## 十二、切换后的体验

切换完成后，日常体验和学校 Seafile 很接近：

- 桌面端继续同步；
- 手机端继续访问；
- WebDAV 继续可用；
- 分享链接可以重新生成；
- 文件版本历史继续保留在新服务器上。

旧的学校网盘分享链接不会自动迁移。迁移后应该重新生成分享链接。

---

## 十三、备份和维护

自建服务最重要的不是“能跑起来”，而是“坏了之后能恢复”。

至少要备份：

```text
Seafile 数据目录
数据库目录
部署配置文件
Nginx 配置
cloudflared 说明文档
```

不要只把备份放在同一块硬盘上。推荐：

```text
每天本机快照
每周异机备份
重要资料额外冷备份
```

也建议定期检查磁盘健康：

```bash
sudo smartctl -a /dev/sdX
sudo smartctl -a /dev/nvme0n1
```

---

## 十四、毕业快乐

学校网盘陪我们度过了很多课程、作业、实验、论文和项目。毕业之后，账号可能会失效，但那些资料仍然值得被妥善保存。

自建 Seafile 不一定适合所有人，但如果你有一台旧电脑，愿意花一点时间维护，它会是一个很舒服的个人数据中心：

```text
资料在自己手里
同步体验接近学校网盘
内网用 Tailscale
外网用 Cloudflare Tunnel
重要数据定期备份
```

祝所有即将毕业的同学毕业快乐。

愿大家带走的不只是文件，还有那些认真学习、折腾系统、调试网络、写论文、赶 deadline 的日子。
