#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo '== docker containers =='
docker compose --env-file .env ps || true

echo
echo '== local Seafile HTTP =='
curl -I --connect-timeout 5 --max-time 10 http://127.0.0.1:8080/ || true

echo
echo '== local Nginx Cloudflare origin example =='
curl -I --connect-timeout 5 --max-time 10 -H 'Host: cloud.example.com' http://127.0.0.1/ || true
