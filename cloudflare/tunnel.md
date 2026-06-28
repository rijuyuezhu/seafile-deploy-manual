# Cloudflare Tunnel

Cloudflare Tunnel 适合没有公网 IP、不能在路由器上开放端口、或者旧电脑放在家用网络里的部署。公网 HTTPS 由 Cloudflare 处理，旧电脑只需要运行 `cloudflared` 并能访问本机 Seafile origin。

## 先选 origin 模式

本仓库支持两种常见模式。

### 模式 A：Tunnel 到本机 Nginx

```text
浏览器 -> Cloudflare HTTPS
Cloudflare -> cloudflared tunnel
cloudflared -> http://127.0.0.1:80
Nginx -> http://127.0.0.1:8080
Seafile
```

Cloudflare Public Hostname：

```text
Hostname: cloud.example.com
Service Type: HTTP
Service URL: http://127.0.0.1
```

本机 Nginx 使用：

```text
nginx/seafile-cloudflare-tunnel.conf.example
```

这个模式的优点是可以在 Nginx 里集中处理：

- `Host` / `X-Forwarded-Proto` / `X-Forwarded-Host` 等反代头；
- 上传大小和超时；
- 日志；
- 后续扩展多个 location。

如果宿主机可以监听 80，优先使用这个模式。

### 模式 B：Tunnel 直接到 Seafile 8080

```text
浏览器 -> Cloudflare HTTPS
Cloudflare -> cloudflared tunnel
cloudflared -> http://127.0.0.1:8080
Seafile
```

Cloudflare Public Hostname：

```text
Hostname: cloud.example.com
Service Type: HTTP
Service URL: http://127.0.0.1:8080
```

这个模式适合：

- WSL 或宿主机 80 端口被占用；
- 不想额外维护本机 Nginx；
- 只需要一个简单公网入口。

使用直连 8080 后，仍然要检查 Seahub 对公网域名、CSRF 和分享链接的配置。详见 `docs/seafile-url-and-domain.md`。

## 为什么 origin 可以用 HTTP

这里 origin 使用 HTTP 是可以接受的，因为公网侧仍然是 HTTPS：

```text
浏览器 -> Cloudflare: HTTPS
Cloudflare -> cloudflared: 加密 tunnel
cloudflared -> 本机 origin: localhost HTTP
```

这样可以避开本机证书和 `localhost` 不匹配的问题，例如：

```text
x509: certificate is valid for *.example.com, not localhost
```

如果把 Tunnel origin 配成 HTTPS，需要确保本机证书和 origin hostname 匹配，否则很容易 502。

## 配置步骤

1. 把域名接入 Cloudflare DNS。
2. 在 Cloudflare Zero Trust 创建 Tunnel。
3. 按 Dashboard 给出的命令安装并运行 `cloudflared`。
4. 添加 Public Hostname。
5. 选择模式 A 或模式 B。
6. 确认 `.env` 和 Seahub 里的公网域名一致。
7. 测试公网入口、WebDAV 和分享链接。

模式 A 的 Public Hostname：

```text
Hostname: cloud.example.com
Service Type: HTTP
Service URL: http://127.0.0.1
```

模式 B 的 Public Hostname：

```text
Hostname: cloud.example.com
Service Type: HTTP
Service URL: http://127.0.0.1:8080
```

这里的 `cloud.example.com` 要和 `.env` 中的 `SEAFILE_SERVER_HOSTNAME`、Seahub 中的 `SERVICE_URL` 保持一致。

## Seahub 反代配置

如果登录时报 CSRF 403，或者分享链接域名不对，检查：

```text
./data/shared/seafile/conf/seahub_settings.py
```

建议配置：

```python
SERVICE_URL = "https://cloud.example.com"
FILE_SERVER_ROOT = "https://cloud.example.com/seafhttp"
ALLOWED_HOSTS = ["cloud.example.com"]
CSRF_TRUSTED_ORIGINS = ["https://cloud.example.com"]
CSRF_COOKIE_SECURE = True
SESSION_COOKIE_SECURE = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True
```

如果同时使用 Tailscale 域名登录，把 Tailscale 域名也加入 `ALLOWED_HOSTS` 和 `CSRF_TRUSTED_ORIGINS`，但 `SERVICE_URL` / `FILE_SERVER_ROOT` 仍建议保持公网域名。

## 测试

本机 Seafile 入口：

```bash
curl -I http://127.0.0.1:8080/
```

模式 A 额外测试本机 Nginx：

```bash
curl -I -H 'Host: cloud.example.com' http://127.0.0.1/
```

公网入口：

```bash
curl -I https://cloud.example.com/
curl -I https://cloud.example.com/seafdav/
```

预期会看到 Cloudflare 响应头，以及 Seafile 登录页的跳转：

```text
HTTP/2 302
location: /accounts/login/?next=/
server: cloudflare
```

`/seafdav/` 返回 `401 Unauthorized` 通常是正常的，说明 WebDAV 入口到达 Seafile 并等待认证。

检查脚本示例：

```bash
bash scripts/check.sh local
bash scripts/check.sh nginx cloud.example.com
bash scripts/check.sh public https://cloud.example.com
```

如果使用模式 B，可以不跑 `nginx` 检查。

## 常见问题

### Cloudflare 502

先看 cloudflared 日志：

```bash
sudo journalctl -u cloudflared -n 100 --no-pager
```

重点确认 Public Hostname 的 Service URL 是否指向正确端口：

```text
模式 A：http://127.0.0.1
模式 B：http://127.0.0.1:8080
```

### 重定向过多

通常是 origin 又把 HTTP 重定向到 HTTPS，或者 Seahub 没识别 `X-Forwarded-Proto=https`。如果使用 Nginx，确认模板中保留：

```nginx
proxy_set_header X-Forwarded-Proto https;
```

同时确认 Seahub 中有：

```python
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
```

### Token 泄露

不要把 Cloudflare tunnel token 贴到公开 issue、博客、commit、聊天记录或截图里。如果已经泄露，在 Cloudflare Zero Trust 中删除或轮换对应 connector。
