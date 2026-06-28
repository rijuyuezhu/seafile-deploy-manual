# Troubleshooting

部署问题通常集中在 Docker 安装、镜像拉取、域名配置、HTTPS 反代和多入口访问。排查时先确认每一层是否独立可用，再继续看下一层。

## 快速分层检查

```bash
cd /opt/seafile-deploy

docker compose --env-file .env ps
curl -I http://127.0.0.1:8080/
curl -I http://127.0.0.1:8080/seafdav/

# 如果使用本机 Nginx
curl -I -H 'Host: cloud.example.com' http://127.0.0.1/

# 如果使用公网域名
curl -I https://cloud.example.com/
curl -I https://cloud.example.com/seafdav/
```

`/seafdav/` 未登录返回 `401 Unauthorized` 通常是正常的，说明 WebDAV 入口已经到达 Seafile。

也可以使用检查脚本：

```bash
bash scripts/check.sh local
bash scripts/check.sh nginx cloud.example.com
bash scripts/check.sh public https://cloud.example.com
bash scripts/check.sh tailscale https://machine.tailnet.ts.net
```

## Docker 安装脚本下载失败

如果 `scripts/install-docker.sh` 报 `curl: (35) Recv failure`、连接超时或 GPG 下载失败，先检查网络：

```bash
curl -I https://get.docker.com
curl -I https://download.docker.com/linux/ubuntu/gpg
```

这通常是网络、代理或 Docker APT 源访问问题。可以先配置代理或可用软件源，再重新执行安装脚本。

脚本默认优先使用 Docker 官方安装脚本。如果官方源暂时不可用，可以显式启用发行版仓库 fallback：

```bash
INSTALL_DOCKER_FALLBACK=1 bash scripts/install-docker.sh
```

fallback 会尝试安装：

```bash
sudo apt-get install -y docker.io docker-compose-v2
```

如果当前发行版没有 `docker-compose-v2` 包，脚本会尝试其他可用的 Compose 包名。fallback 适合 WSL、临时网络不可达、当前 Ubuntu codename 与 Docker 官方源同步不一致等场景；长期服务器仍建议优先使用 Docker 官方源。

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

## Docker Hub 拉镜像失败

如果 `docker compose up -d` 卡在 pull image，或者出现 IPv6 reset、IPv4 timeout、TLS handshake timeout，先区分 shell 代理和 Docker daemon 代理。

给 Docker daemon 配代理：

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/20-proxy.conf >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7897"
Environment="HTTPS_PROXY=http://127.0.0.1:7897"
Environment="NO_PROXY=localhost,127.0.0.1,::1,db,redis,seafile,172.16.0.0/12,10.0.0.0/8,192.168.0.0/16"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
systemctl show --property=Environment docker
```

WSL 中如果代理跑在 Windows 上，`127.0.0.1` 不一定指向 Windows 代理。可以用下面命令找 Windows 侧网关：

```bash
ip route | awk '/default/ {print $3; exit}'
```

更多细节见 `docs/proxy-dns-clash-mihomo.md`。

## `SEAFILE_SERVER_HOSTNAME` 写法错误

`SEAFILE_SERVER_HOSTNAME` 只能写域名或 IP，不能带协议和端口。

```env
# Good
SEAFILE_SERVER_HOSTNAME=cloud.example.com
SEAFILE_SERVER_PROTOCOL=https

# Bad
SEAFILE_SERVER_HOSTNAME=https://cloud.example.com
SEAFILE_SERVER_HOSTNAME=cloud.example.com:8080
SEAFILE_SERVER_HOSTNAME=localhost:8080
```

如果已经初始化过 Seafile，改 `.env` 后还要检查：

```text
./data/shared/seafile/conf/seahub_settings.py
```

详见 `docs/seafile-url-and-domain.md`。

## Seafile 13 启动时报缺少 JWT_PRIVATE_KEY 或数据库密码

本仓库的 `docker-compose.yml` 使用 Seafile 13 风格配置，`.env` 中必须填写至少 32 字符的 `JWT_PRIVATE_KEY`，以及数据库和管理员初始密码：

```env
JWT_PRIVATE_KEY=change-me-random-string-at-least-32-characters
INIT_SEAFILE_MYSQL_ROOT_PASSWORD=change-me-long-random-root-password
SEAFILE_MYSQL_DB_PASSWORD=change-me-long-random-seafile-db-password
INIT_SEAFILE_ADMIN_PASSWORD=change-me-long-random-admin-password
```

可以用下面命令生成随机值：

```bash
openssl rand -base64 48
```

`INIT_SEAFILE_MYSQL_ROOT_PASSWORD` 和 `INIT_SEAFILE_ADMIN_PASSWORD` 只在第一次初始化时生效。已经初始化过的实例如果要改数据库密码或管理员密码，需要按 Seafile 的迁移/重置流程处理，不能只改 `.env`。

## Redis cache 容器没有启动

Seafile 13 默认推荐 Redis 作为 cache。确认 `.env` 中保持：

```env
CACHE_PROVIDER=redis
REDIS_HOST=redis
REDIS_PORT=6379
```

如果曾经使用旧版 memcached 配置，升级前要先备份数据，并阅读 Seafile 13 升级说明。新部署不建议再改回 memcached。

## 分享链接域名不对

先确认 `.env`：

```env
SEAFILE_SERVER_HOSTNAME=cloud.example.com
SEAFILE_SERVER_PROTOCOL=https
```

如果 Seafile 已经初始化，还要确认 `seahub_settings.py`：

```python
SERVICE_URL = "https://cloud.example.com"
FILE_SERVER_ROOT = "https://cloud.example.com/seafhttp"
```

修改后重启：

```bash
docker compose --env-file .env restart seafile
```

也可以使用：

```bash
bash scripts/set-seafile-domain.sh --public cloud.example.com
```

## 登录时报 CSRF verification failed

常见原因是 HTTPS 在 Cloudflare、Tailscale Serve、Nginx 或 Caddy 终止后，Seahub 没有正确识别原始请求是 HTTPS，或者当前访问域名没有加入可信来源。

检查 `data/shared/seafile/conf/seahub_settings.py`：

```python
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

如果使用 Nginx，确认反代头包含：

```nginx
proxy_set_header Host $host;
proxy_set_header X-Forwarded-Proto https;
proxy_set_header X-Forwarded-Host $host;
```

改完重启 Seafile：

```bash
docker compose --env-file .env restart seafile
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

同机部署常见两种模式：

```text
模式 A：Cloudflare Tunnel -> http://127.0.0.1 -> Nginx -> http://127.0.0.1:8080
模式 B：Cloudflare Tunnel -> http://127.0.0.1:8080 -> Seafile
```

模式 A 更容易集中管理反代头和超时；模式 B 更简单，适合 WSL 或宿主 80 端口不可用的场景。

## 浏览器提示重定向过多

通常是 Cloudflare/cloudflared 用 HTTP 连 origin，而 origin 又把 HTTP 重定向到 HTTPS，或者 Seahub 没有识别 `X-Forwarded-Proto=https`。

如果走 Nginx，给 Cloudflare Tunnel 使用的公网域名可以让 80 端口直接反代到 Seafile，并保留：

```nginx
proxy_set_header X-Forwarded-Proto https;
```

同时在 Seahub 中设置：

```python
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
```

## Tailscale MagicDNS 不能访问

先确认 Tailscale 本身在线：

```bash
tailscale status
tailscale ip -4
```

如果使用 Tailscale Serve：

```bash
tailscale serve status
curl -I https://machine.tailnet.ts.net/
```

如果浏览器能打开但登录 CSRF 失败，把 `https://machine.tailnet.ts.net` 加入 `CSRF_TRUSTED_ORIGINS`，并把 `machine.tailnet.ts.net` 加入 `ALLOWED_HOSTS`。

如果只是用 Tailscale SSH 维护机器，不需要把 Tailscale 域名写进 Seafile 配置。

## WSL 中 Nginx 监听 80 失败

如果出现：

```text
bind() to 0.0.0.0:80 failed (98: Address already in use)
```

先查端口占用：

```bash
sudo ss -ltnp | grep ':80' || true
```

在 Windows 侧也查：

```powershell
netstat -ano | findstr ":80"
```

不想抢 80 端口时，可以让 Cloudflare Tunnel 或 Tailscale Serve 直接指向 `http://127.0.0.1:8080`。更多 WSL 注意事项见 `docs/wsl.md`。

## WebDAV 返回 401

未登录访问 `/seafdav/` 返回 401 通常是正常的，表示入口存在并等待认证。需要继续排查的是：

- 404：路径没有到达 Seafile WebDAV。
- 502：反代或 cloudflared 没连到 origin。
- 连接超时：网络、DNS、Tunnel 或防火墙问题。

## Cloudflare token 和敏感信息

`cloudflared service install <token>` 里的 token 等价于 connector 注册凭据。不要把它提交到 git、博客、issue、聊天记录或截图里。

如果怀疑泄露，应在 Cloudflare Zero Trust 中删除或轮换对应 tunnel connector。真实 `.env` 也不要提交；仓库只保留 `.env.example`。
