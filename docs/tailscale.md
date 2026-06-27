# Tailscale 内部访问

Tailscale 可以先作为维护通道使用。公网入口出问题时，仍然可以通过 Tailscale SSH 或 Tailscale IP 登录旧电脑，检查 Docker、Nginx 和 cloudflared。

安装并登录：

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

查看旧电脑的 Tailscale IP：

```bash
tailscale ip -4
```

如果只需要维护机器，到这一步就够了。浏览器和客户端仍然可以统一使用公网域名。

如果还想通过 Tailscale 直接浏览 Seafile，可以准备一个内部域名：

```text
cloud.internal.example.com -> 100.x.y.z
```

仓库里的 `nginx/seafile-tailscale-https.conf.example` 假定你已经准备好了内部 HTTPS 证书。没有证书时不要直接启用这个模板。可以使用 Tailscale 证书、自己的内网 CA，或者先跳过内部 HTTPS，只把 Tailscale 当维护通道。
