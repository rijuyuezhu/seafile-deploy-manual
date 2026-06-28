# Seafile 域名、分享链接和多入口访问

这份文档说明 Seafile 中几个容易混淆的地址：公网域名、Tailscale 域名、反代入口、分享链接域名，以及初始化后改域名时需要同步修改的位置。

## 核心原则

Seafile 可以有多个访问入口，但应该只选一个 **canonical domain** 作为公开地址。这个地址会影响网页跳转、客户端配置、WebDAV 地址和公开分享链接。

常见推荐是：

```text
公网访问 / 分享链接：https://seafile.example.com
维护入口：Tailscale SSH 或 MagicDNS
可选内网入口：https://machine.tailnet.ts.net
```

如果你希望发给别人的分享链接始终使用公网域名，就不要把 Tailscale MagicDNS 域名写成 `SERVICE_URL` 或 `FILE_SERVER_ROOT`。

## `.env` 里的 hostname 限制

`SEAFILE_SERVER_HOSTNAME` 只能填域名或 IP，本仓库的 Compose 模板会配合 `SEAFILE_SERVER_PROTOCOL` 生成 Seafile 初始 URL。

```env
# Good: seafile.example.com
# Good: 192.0.2.10
# Bad: https://seafile.example.com
# Bad: seafile.example.com:8080
# Bad: localhost:8080
SEAFILE_SERVER_HOSTNAME=seafile.example.com
SEAFILE_SERVER_PROTOCOL=https
```

也就是说：

- 不要带 `http://` 或 `https://`。
- 不要带端口。
- 用 Cloudflare Tunnel、Tailscale Serve 或 Nginx 终止 HTTPS 时，`SEAFILE_SERVER_PROTOCOL` 仍然应写成用户实际看到的协议，通常是 `https`。

## 首次初始化前改域名

如果 Seafile 还没有初始化，直接改 `.env` 再启动即可：

```bash
cp .env.example .env
vim .env
bash scripts/deploy.sh
```

第一次启动时，容器会根据 `.env` 生成数据目录中的 Seafile 配置。

## 初始化后改域名

如果 Seafile 已经启动过，只改 `.env` 并重建容器不一定能覆盖已经生成的配置。此时需要同时检查数据目录中的配置文件：

```text
./data/shared/seafile/conf/seahub_settings.py
```

建议按下面顺序处理：

```bash
export DEPLOY=/opt/seafile-deploy
cd "$DEPLOY"

# 1. 先备份配置
cp data/shared/seafile/conf/seahub_settings.py \
  "data/shared/seafile/conf/seahub_settings.py.$(date +%Y%m%d-%H%M%S).bak"

# 2. 修改 .env
vim .env

# 3. 修改 Seahub 设置
vim data/shared/seafile/conf/seahub_settings.py

# 4. 重启 Seafile
docker compose --env-file .env restart seafile
```

`seahub_settings.py` 中至少确认这些项：

```python
SERVICE_URL = "https://seafile.example.com"
FILE_SERVER_ROOT = "https://seafile.example.com/seafhttp"

ALLOWED_HOSTS = [
    "seafile.example.com",
    "machine.tailnet.ts.net",
]

CSRF_TRUSTED_ORIGINS = [
    "https://seafile.example.com",
    "https://machine.tailnet.ts.net",
]

CSRF_COOKIE_SECURE = True
SESSION_COOKIE_SECURE = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True
```

其中 `SERVICE_URL` 和 `FILE_SERVER_ROOT` 决定公开分享链接使用哪个域名。`ALLOWED_HOSTS` 和 `CSRF_TRUSTED_ORIGINS` 决定哪些 HTTPS 入口可以登录 Seahub。

也可以使用仓库里的辅助脚本统一修改：

```bash
bash scripts/set-seafile-domain.sh \
  --public seafile.example.com \
  --extra-origin https://machine.tailnet.ts.net
```

脚本一定会修改 `.env`。如果 `seahub_settings.py` 已经存在，也会同步修改并在改动前自动备份；如果还没有初始化，脚本会提示之后需要再运行一次。

## 多入口访问怎么配

| 场景 | 入口 | 是否建议写入 `SERVICE_URL` | 是否加入 `ALLOWED_HOSTS` / `CSRF_TRUSTED_ORIGINS` |
|---|---|---:|---:|
| 公网分享链接 | `https://seafile.example.com` | 是 | 是 |
| Cloudflare Tunnel | `https://seafile.example.com` | 是 | 是 |
| Tailscale Serve | `https://machine.tailnet.ts.net` | 否，除非只在 tailnet 内使用 | 是，如果要登录 |
| Tailscale SSH / 维护 | SSH 或 Tailscale IP | 否 | 否 |
| 本机检查 | `http://127.0.0.1:8080` | 否 | 否 |

如果你同时使用公网域名和 Tailscale 域名访问，推荐：

```python
SERVICE_URL = "https://seafile.example.com"
FILE_SERVER_ROOT = "https://seafile.example.com/seafhttp"
ALLOWED_HOSTS = ["seafile.example.com", "machine.tailnet.ts.net"]
CSRF_TRUSTED_ORIGINS = [
    "https://seafile.example.com",
    "https://machine.tailnet.ts.net",
]
```

这样用户可以通过 Tailscale 域名登录维护，但公开分享链接仍然使用公网域名。

## 反代 HTTPS 时的头部

如果 HTTPS 终止在 Cloudflare、Tailscale Serve、Caddy 或 Nginx，而 Seafile 容器只看到本机 HTTP，需要确保反代层传递 HTTPS 语义。

Nginx 示例：

```nginx
proxy_set_header Host $host;
proxy_set_header X-Forwarded-Proto https;
proxy_set_header X-Forwarded-Host $host;
```

Seahub 示例：

```python
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True
```

如果这两边不一致，常见现象是登录时报 CSRF 403、浏览器重定向过多，或分享链接里的协议/域名不对。

## 核对命令

```bash
# 本机容器入口
curl -I http://127.0.0.1:8080/

# 经本机 Nginx，手动指定 Host
curl -I -H 'Host: seafile.example.com' http://127.0.0.1/

# 公网入口
curl -I https://seafile.example.com/

# WebDAV 入口；未登录返回 401 通常是正常的
curl -I https://seafile.example.com/seafdav/

# 生成一次分享链接后，在网页上确认域名是否为公网域名
```
