#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

env_host=""
if [[ -f .env ]]; then
  env_host=$(sed -n 's/^SEAFILE_SERVER_HOSTNAME=//p' .env | tail -n 1)
fi

HOST=${HOST:-${env_host:-cloud.example.com}}
failures=0

check() {
  local name=$1
  shift

  echo
  echo "== $name =="
  if "$@"; then
    echo "OK: $name"
  else
    echo "FAIL: $name" >&2
    failures=$((failures + 1))
  fi
}

check "docker containers" docker compose --env-file .env ps
check "local Seafile HTTP" curl -fsSI --connect-timeout 5 --max-time 10 http://127.0.0.1:8080/
check "local Nginx Cloudflare origin" curl -fsSI --connect-timeout 5 --max-time 10 -H "Host: $HOST" http://127.0.0.1/

if (( failures > 0 )); then
  echo
  echo "Check finished with $failures failure(s)." >&2
  exit 1
fi

echo
echo "All checks passed."
