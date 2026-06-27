# Troubleshooting

## Docker 安装脚本下载失败

如果 `scripts/install-docker.sh` 报 `curl: (35) Recv failure`、连接超时或 GPG 下载失败，先检查网络：

```bash
curl -I https://get.docker.com
curl -I https://download.docker.com/linux/ubuntu/gpg
```

这通常是网络、代理或 Docker APT 源访问问题。先配置可用代理或镜像源，再重新执行安装脚本。

## 当前用户不能运行 Docker

如果 `docker info` 报 permission denied，把当前用户加入 docker 组：

```bash
sudo usermod -aG docker "$USER"
```

然后退出重新登录，或者临时执行：

```bash
newgrp docker
```

继续之前先确认：

```bash
docker info >/dev/null
```

## Cloudflare 显示 502

查看 cloudflared 日志：

```bash
sudo journalctl -u cloudflared -n 100 --no-pager
```

常见原因：

- Tunnel 的 origin URL 指到了错误端口。
- Nginx 没有监听对应端口。
- Tunnel 配成了 HTTPS origin，但本机证书校验失败。
- Host header 和 Nginx 的 `server_name` 不匹配。

同机部署时优先使用：

```text
Tunnel origin: http://127.0.0.1
Nginx: listen 80 and proxy_pass to 127.0.0.1:8080
```

## 浏览器提示重定向过多

通常是 Cloudflare/cloudflared 用 HTTP 连 origin，而 Nginx 又把 HTTP 重定向到 HTTPS。给 Cloudflare Tunnel 使用的公网域名可以让 80 端口直接反代到 Seafile，并保留：

```nginx
proxy_set_header X-Forwarded-Proto https;
```

## WebDAV 返回 401

未登录访问 `/seafdav/` 返回 401 通常是正常的，表示入口存在并等待认证。需要继续排查的是 404、502 或连接超时。

## 分享链接域名不对

检查 `.env`：

```env
SEAFILE_SERVER_HOSTNAME=cloud.example.com
SEAFILE_SERVER_PROTOCOL=https
```

修改后重新创建 Seafile 容器。
