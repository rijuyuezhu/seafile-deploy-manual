#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONNECT_TIMEOUT=${CONNECT_TIMEOUT:-5}
MAX_TIME=${MAX_TIME:-15}
failures=0

usage() {
  cat <<'EOF'
Usage:
  bash scripts/check.sh [mode] [target]

Modes:
  local       Check Docker Compose and local Seafile at http://127.0.0.1:8080
  nginx       Check a local Nginx origin with Host header
  public      Check a public HTTPS/HTTP URL
  tailscale   Check a Tailscale Serve or internal HTTPS URL
  all         Check local, plus optional nginx/public/tailscale targets from env

Examples:
  bash scripts/check.sh local
  bash scripts/check.sh nginx cloud.example.com
  NGINX_ORIGIN=http://127.0.0.1 bash scripts/check.sh nginx cloud.example.com
  bash scripts/check.sh public https://cloud.example.com
  bash scripts/check.sh tailscale https://machine.tailnet.ts.net

Environment:
  HOST           Host header for nginx mode; defaults to SEAFILE_SERVER_HOSTNAME in .env
  NGINX_ORIGIN   Origin URL for nginx mode; default: http://127.0.0.1
  PUBLIC_URL     URL used by all mode for public check
  TAILSCALE_URL  URL used by all mode for tailscale check
  CHECK_NGINX=1  In all mode, also run nginx check
EOF
}

read_env_value() {
  local key=$1
  if [[ -f .env ]]; then
    sed -n "s/^${key}=//p" .env | tail -n 1
  fi
}

ENV_HOST=$(read_env_value SEAFILE_SERVER_HOSTNAME || true)
ENV_PROTOCOL=$(read_env_value SEAFILE_SERVER_PROTOCOL || true)
HOST=${HOST:-${ENV_HOST:-cloud.example.com}}
ENV_PROTOCOL=${ENV_PROTOCOL:-https}
DEFAULT_PUBLIC_URL="${ENV_PROTOCOL}://${HOST}"

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

curl_head() {
  curl -fsSI --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" "$@"
}

curl_head_status() {
  local expected=$1
  shift
  local status
  status=$(curl -sSI --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" -o /dev/null -w '%{http_code}' "$@")
  [[ "$expected" == *",$status,"* ]]
}

strip_trailing_slash() {
  local url=$1
  while [[ "$url" == */ && "$url" != "http://" && "$url" != "https://" ]]; do
    url=${url%/}
  done
  printf '%s\n' "$url"
}

check_compose() {
  if [[ ! -f .env ]]; then
    echo "Missing .env. Copy .env.example to .env and edit it first." >&2
    return 1
  fi
  docker compose --env-file .env ps
}

check_local() {
  check "docker compose services" check_compose
  check "local Seafile HTTP" curl_head http://127.0.0.1:8080/
  check "local WebDAV endpoint (200/301/302/401 accepted)" \
    curl_head_status ',200,301,302,401,' http://127.0.0.1:8080/seafdav/
}

check_nginx() {
  local host=${1:-$HOST}
  local origin=${NGINX_ORIGIN:-http://127.0.0.1}
  check "local Nginx origin (${origin}, Host: ${host})" \
    curl_head -H "Host: ${host}" "$origin/"
}

check_public() {
  local url=${1:-${PUBLIC_URL:-$DEFAULT_PUBLIC_URL}}
  url=$(strip_trailing_slash "$url")
  check "public Seafile URL (${url})" curl_head "$url/"
  check "public WebDAV endpoint (${url}/seafdav/, 200/301/302/401 accepted)" \
    curl_head_status ',200,301,302,401,' "$url/seafdav/"
}

check_tailscale() {
  local url=${1:-${TAILSCALE_URL:-}}
  if [[ -z "$url" ]]; then
    echo "tailscale mode needs a URL, for example: bash scripts/check.sh tailscale https://machine.tailnet.ts.net" >&2
    return 1
  fi
  url=$(strip_trailing_slash "$url")
  check "Tailscale/internal URL (${url})" curl_head "$url/"
  check "Tailscale/internal WebDAV endpoint (${url}/seafdav/, 200/301/302/401 accepted)" \
    curl_head_status ',200,301,302,401,' "$url/seafdav/"
}

mode=${1:-all}
target=${2:-}

case "$mode" in
  -h|--help|help)
    usage
    exit 0
    ;;
  local)
    check_local
    ;;
  nginx)
    check_nginx "${target:-$HOST}"
    ;;
  public)
    check_public "${target:-${PUBLIC_URL:-$DEFAULT_PUBLIC_URL}}"
    ;;
  tailscale)
    check_tailscale "${target:-${TAILSCALE_URL:-}}"
    ;;
  all)
    check_local
    if [[ ${CHECK_NGINX:-0} == 1 ]]; then
      check_nginx "$HOST"
    fi
    if [[ -n ${PUBLIC_URL:-} ]]; then
      check_public "$PUBLIC_URL"
    fi
    if [[ -n ${TAILSCALE_URL:-} ]]; then
      check_tailscale "$TAILSCALE_URL"
    fi
    ;;
  *)
    echo "Unknown mode: $mode" >&2
    usage >&2
    exit 2
    ;;
esac

if (( failures > 0 )); then
  echo
  echo "Check finished with $failures failure(s)." >&2
  exit 1
fi

echo
echo "All requested checks passed."
