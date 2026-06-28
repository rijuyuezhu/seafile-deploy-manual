# Tailscale 内部访问

Tailscale 可以作为维护通道，也可以作为浏览器访问 Seafile 的内网 HTTPS 入口。最稳妥的做法是：公网分享链接继续使用公网域名，Tailscale 只用于维护或备用登录。

## 模式 1：只作为维护通道

安装并登录：

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

查看旧电脑的 Tailscale IP：

```bash
tailscale ip -4
tailscale status
```

如果只需要维护机器，到这一步就够了。浏览器、客户端和分享链接仍然统一使用公网域名：

```text
https://cloud.example.com
```

这种模式下，不需要把 Tailscale 域名写进 Seafile 配置。

## 模式 2：Tailscale Serve 反代 Seafile

如果希望在 tailnet 内通过 HTTPS 直接打开 Seafile，可以使用 Tailscale Serve 把 Tailscale HTTPS 入口反代到本机 Seafile：

```bash
sudo tailscale serve --bg --https=443 http://127.0.0.1:8080
```

查看状态：

```bash
tailscale serve status
```

测试：

```bash
curl -I https://machine.tailnet.ts.net/
```

把 `machine.tailnet.ts.net` 换成你的 MagicDNS 名称。Tailscale Serve 的 HTTPS 由 Tailscale daemon 终止，后端仍然是本机 `http://127.0.0.1:8080`。

如果要清理 Serve 配置：

```bash
sudo tailscale serve reset
```

仓库也提供了一个薄封装脚本：

```bash
bash scripts/configure-tailscale-serve.sh \
  --target http://127.0.0.1:8080 \
  --https-port 443
```

## Tailscale Serve 和分享链接域名

即使你可以通过 Tailscale 域名登录，也不一定要把分享链接域名改成 Tailscale 域名。

推荐配置是：

```python
SERVICE_URL = "https://cloud.example.com"
FILE_SERVER_ROOT = "https://cloud.example.com/seafhttp"
ALLOWED_HOSTS = [
    "cloud.example.com",
    "machine.tailnet.ts.net",
]
CSRF_TRUSTED_ORIGINS = [
    "https://cloud.example.com",
    "https://machine.tailnet.ts.net",
]
CSRF_COOKIE_SECURE = True
SESSION_COOKIE_SECURE = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True
```

这样：

- 你可以用 Tailscale 域名登录和维护；
- 分享链接仍然生成公网域名；
- 客户端和 WebDAV 仍然可以统一使用公网域名；
- 公网入口坏了时，tailnet 内仍有备用入口。

配置文件位置：

```text
./data/shared/seafile/conf/seahub_settings.py
```

更多说明见 `docs/seafile-url-and-domain.md`。

## 模式 3：内部域名 + 宿主 Nginx + 自备证书

如果不想用 Tailscale Serve，也可以准备一个内部域名：

```text
cloud.internal.example.com -> 100.x.y.z
```

仓库里的模板：

```text
nginx/seafile-tailscale-https.conf.example
```

假定你已经准备好了内部 HTTPS 证书。没有证书时不要直接启用这个模板。可以使用 Tailscale 证书、自己的内网 CA，或者跳过这个模式，只把 Tailscale 当维护通道。

启用示例：

```bash
export DEPLOY=/opt/seafile-deploy
sudo cp "$DEPLOY/nginx/seafile-tailscale-https.conf.example" /etc/nginx/conf.d/seafile-internal.conf
sudo vim /etc/nginx/conf.d/seafile-internal.conf
sudo nginx -t
sudo systemctl reload nginx
```

## MagicDNS 排查

确认 Tailscale 连接：

```bash
tailscale status
tailscale ip -4
```

确认 MagicDNS 名称：

```bash
tailscale status --json | python3 -m json.tool | head -n 40
```

从另一台已经加入 tailnet 的设备测试：

```bash
ping machine.tailnet.ts.net
curl -I https://machine.tailnet.ts.net/
```

如果能打开页面但登录时报 CSRF 403，把 Tailscale 域名加入 Seahub 的 `ALLOWED_HOSTS` 和 `CSRF_TRUSTED_ORIGINS`，然后重启 Seafile。

## 不要误用 Funnel

Tailscale Serve 只在 tailnet 内共享服务。Tailscale Funnel 会把服务暴露到公网，安全模型不同。个人 Seafile 通常不需要 Funnel；公网入口建议继续使用 Cloudflare Tunnel 或你自己维护的公网反代。
