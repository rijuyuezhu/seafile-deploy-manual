# WSL 部署注意事项

WSL2 可以跑 Seafile，但它更适合作为个人轻量部署或过渡方案。长期无人值守时，裸 Linux 仍然更简单，因为 Windows 睡眠、更新重启、端口占用和开机自启都会影响可用性。

## 启用 systemd

本仓库的脚本会用到 Docker、Nginx、cloudflared、Tailscale 等服务。Ubuntu WSL 中如果 `systemctl` 不可用，先启用 systemd：

```bash
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
```

然后在 Windows PowerShell 里重启 WSL：

```powershell
wsl --shutdown
```

重新进入 Ubuntu 后验证：

```bash
systemctl is-system-running || true
systemctl status docker --no-pager
```

## 部署目录放在哪里

推荐把部署目录放在 WSL 的 Linux 文件系统里：

```text
/opt/seafile-deploy
/home/<user>/seafile-deploy
```

不建议放在 `/mnt/c` 或 `/mnt/d` 下直接运行数据库和 Seafile 数据目录。跨 Windows 文件系统边界会带来权限、大小写、文件锁、性能和一致性问题。

如果想使用 D 盘空间，更稳妥的做法是把一块专用磁盘或虚拟磁盘挂载给 WSL，或者在 Linux 文件系统里保存 Seafile 数据，再用独立备份把数据同步到 D 盘。

## D 盘不是“直接变成网盘目录”

Seafile 不会把 D 盘现有目录原样暴露成网盘。它会把上传和同步的数据保存成自己的存储结构，主要位于：

```text
./data/shared
./data/mysql
```

因此：

- 想把 D 盘已有资料放进 Seafile，需要通过客户端、网页或 WebDAV 上传/同步。
- 不要手动修改 `data/shared` 内部对象文件。
- 不要把数据库目录放在不可靠或频繁被 Windows 索引/杀毒扫描的位置。

## 80/443 端口被占用

WSL、Windows 服务、IIS、代理软件、开发服务器都可能占用 80 或 443。检查方式：

```powershell
netstat -ano | findstr ":80"
netstat -ano | findstr ":443"
```

WSL 内也可以检查：

```bash
sudo ss -ltnp | grep -E ':(80|443)\b' || true
```

如果本机 Nginx 不能监听 80，可以选择：

1. Cloudflare Tunnel 直接指向 `http://127.0.0.1:8080`。
2. Tailscale Serve 直接反代 `http://127.0.0.1:8080`。
3. 改用裸 Linux，减少 Windows 端口和生命周期干扰。

## Windows 睡眠和自动重启

Seafile 是同步服务，机器睡眠后公网入口和客户端同步都会中断。建议至少检查：

- 电源设置中关闭自动睡眠。
- Windows Update 自动重启策略。
- WSL 是否随用户登录后自动启动。
- Docker、Tailscale、cloudflared 是否在 WSL 中开机自启。

可以准备一个简单检查命令：

```bash
cd /opt/seafile-deploy
bash scripts/check.sh local
bash scripts/check.sh public https://seafile.example.com
```

## 网络和代理

WSL 里的 Docker daemon 拉取镜像时，不一定会继承 shell 里的 `HTTP_PROXY` / `HTTPS_PROXY`。如果 `docker pull` 超时或 reset，参考 `docs/proxy-dns-clash-mihomo.md` 给 Docker daemon 单独配置代理。

## 何时不建议继续用 WSL

出现以下情况时，建议迁移到裸 Linux 或独立小主机：

- 希望长期 24 小时无人值守。
- 资料库很大，读写频繁。
- Windows 经常睡眠、自动重启或网络切换。
- 需要更稳定的备份、监控和磁盘健康检查。
