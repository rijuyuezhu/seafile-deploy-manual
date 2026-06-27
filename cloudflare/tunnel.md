# Cloudflare Tunnel

推荐的 Public Hostname 配置：

```text
Hostname: cloud.example.com
Service Type: HTTP
Service URL: http://127.0.0.1
```

这里 origin 使用 HTTP 是可以接受的，因为链路实际是：

```text
浏览器 -> Cloudflare: HTTPS
Cloudflare -> cloudflared: 加密 tunnel
cloudflared -> 本机 Nginx: localhost HTTP
```

这样可以避开本机证书和 `localhost` 不匹配的问题，例如：

```text
x509: certificate is valid for *.example.com, not localhost
```

## 步骤

1. 把域名接入 Cloudflare DNS。
2. 在 Cloudflare Zero Trust 创建 Tunnel。
3. 按 Dashboard 给出的命令安装并运行 `cloudflared`。
4. 添加 Public Hostname：
   - Hostname: `cloud.example.com`
   - Service: `http://127.0.0.1`
5. 本机 Nginx 使用 `nginx/seafile-cloudflare-tunnel.conf.example`。
6. 测试：

```bash
curl -I https://cloud.example.com/
```

预期会看到 Cloudflare 响应头，以及 Seafile 登录页的跳转：

```text
HTTP/2 302
location: /accounts/login/?next=/
server: cloudflare
```

不要把 Cloudflare tunnel token 贴到公开 issue、博客或 commit 里。
