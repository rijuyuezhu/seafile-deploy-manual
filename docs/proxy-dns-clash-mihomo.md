# 代理、DNS 和 Docker Hub 拉取问题

如果部署环境在校园网、家庭宽带、公司网络或 WSL 中，Docker Hub 拉镜像可能出现连接重置、IPv6 优先但不可达、IPv4 超时、DNS 污染或代理没有被 Docker daemon 使用等问题。

这份文档只记录排查思路，不假设你一定使用 Clash、Mihomo 或其他特定代理。

## 先区分 shell 代理和 Docker daemon 代理

下面这些变量只影响当前 shell 中的 `curl`、`apt` 等程序：

```bash
export HTTP_PROXY=http://127.0.0.1:7897
export HTTPS_PROXY=http://127.0.0.1:7897
export NO_PROXY=localhost,127.0.0.1,::1
```

但 `docker pull` 是 Docker daemon 在拉镜像，通常需要给 systemd service 单独配置代理。

## 给 Docker daemon 配代理

创建 systemd drop-in：

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
```

验证 Docker daemon 是否读到了代理：

```bash
systemctl show --property=Environment docker
```

然后测试：

```bash
docker pull hello-world
```

如果代理跑在 Windows 上，而 Docker daemon 在 WSL 里，`127.0.0.1` 未必指向 Windows 代理。可以在 WSL 中查看默认网关：

```bash
ip route | awk '/default/ {print $3; exit}'
```

假设输出是 `172.28.112.1`，代理地址可能需要写成：

```text
http://172.28.112.1:7897
```

同时确认 Windows 防火墙和代理软件允许局域网/WSL 访问。

## IPv6 优先导致连接失败

如果日志里先出现 IPv6 连接 reset，再回退 IPv4 超时，可以临时让系统更偏向 IPv4：

```bash
sudo tee -a /etc/gai.conf >/dev/null <<'EOF'
precedence ::ffff:0:0/96  100
EOF
```

这只能作为辅助。真正决定 `docker pull` 是否可用的，通常还是 Docker daemon 自己能否访问 Docker Hub。

## DNS 排查

先看域名解析：

```bash
getent hosts registry-1.docker.io
dig registry-1.docker.io +short || true
```

再看 HTTPS 连通性：

```bash
curl -I https://registry-1.docker.io/v2/
```

返回 `401 Unauthorized` 通常说明网络到达了 Docker Registry，只是未认证；连接超时、TLS 握手失败或 DNS 解析异常才需要继续排查网络。

## apt 代理和 Docker 代理是两回事

`apt update` 使用的代理可以放在：

```text
/etc/apt/apt.conf.d/95proxies
```

示例：

```bash
sudo tee /etc/apt/apt.conf.d/95proxies >/dev/null <<'EOF'
Acquire::http::Proxy "http://127.0.0.1:7897";
Acquire::https::Proxy "http://127.0.0.1:7897";
EOF
```

这不会自动影响 Docker daemon。Docker daemon 仍然需要前面的 systemd drop-in。

## 清理代理配置

如果迁移到网络正常的机器，或者代理端口变化，可以删除 drop-in：

```bash
sudo rm -f /etc/systemd/system/docker.service.d/20-proxy.conf
sudo systemctl daemon-reload
sudo systemctl restart docker
```

再验证：

```bash
systemctl show --property=Environment docker
```
