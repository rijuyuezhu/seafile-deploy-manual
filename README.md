# Seafile Deploy Manual

一个面向毕业生的自建 Seafile 部署手册与模板仓库。

场景：从学校部署的 Seafile，例如 `box.nju.edu.cn`，把个人资料迁移到自己的旧电脑、旧笔记本或小主机上。内部访问用 Tailscale，外部访问用 Cloudflare Tunnel。

> 本仓库所有域名、IP、密码、token 均为示例占位符。请不要把真实 `.env`、证书私钥、Cloudflare Tunnel token、数据库目录提交到 Git。

## 内容

- `blog/graduating-from-school-seafile.md`：可直接发布的博客草稿
- `docker-compose.yml`：Seafile Community Edition 示例 Compose
- `.env.example`：脱敏环境变量模板
- `nginx/`：Nginx 示例配置
- `cloudflare/tunnel.md`：Cloudflare Tunnel 配置说明
- `docs/`：迁移、Tailscale、备份、故障排除
- `scripts/`：安装、部署、检查、备份脚本

## 快速开始

```bash
cp .env.example .env
vim .env
./scripts/install-docker.sh
./scripts/deploy.sh
```

本地检查：

```bash
./scripts/check.sh
```

Cloudflare Tunnel 推荐把 Public Hostname 配成：

```text
cloud.example.com -> http://127.0.0.1
```

同时 Nginx 的 80 server block 直接反代 Seafile，并设置：

```nginx
proxy_set_header X-Forwarded-Proto https;
```

这样公网证书由 Cloudflare 处理，cloudflared 到本机 Nginx 走 localhost HTTP，避免本机证书校验问题。

## 安全注意

不要提交：

- `.env`
- `data/`
- `*.pem`、`*.key`
- Cloudflare Tunnel token
- 数据库 dump
- 管理员密码

## 许可证

文档内容采用 CC BY 4.0；脚本和配置模板采用 MIT。见 `LICENSE`。
