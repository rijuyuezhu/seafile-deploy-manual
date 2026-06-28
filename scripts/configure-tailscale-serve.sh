#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/configure-tailscale-serve.sh [options]

Options:
  --target URL          Local backend target, default: http://127.0.0.1:8080
  --https-port PORT     Tailscale HTTPS listen port, default: 443
  --http-port PORT      Use HTTP instead of HTTPS on the given port
  --reset               Reset existing Tailscale Serve configuration
  --status              Show current Tailscale Serve status
  --dry-run             Print command without running it
  -h, --help            Show help

Examples:
  bash scripts/configure-tailscale-serve.sh
  bash scripts/configure-tailscale-serve.sh --target http://127.0.0.1:8080 --https-port 443
  bash scripts/configure-tailscale-serve.sh --status
  bash scripts/configure-tailscale-serve.sh --reset
EOF
}

target="http://127.0.0.1:8080"
https_port="443"
http_port=""
reset=0
status=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      target=${2:-}
      shift 2
      ;;
    --https-port)
      https_port=${2:-}
      http_port=""
      shift 2
      ;;
    --http-port)
      http_port=${2:-}
      shift 2
      ;;
    --reset)
      reset=1
      shift
      ;;
    --status)
      status=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v tailscale >/dev/null 2>&1 && (( ! dry_run )); then
  echo "tailscale command not found. Install and log in to Tailscale first." >&2
  exit 1
fi

run_cmd() {
  if (( dry_run )); then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

if (( status )); then
  run_cmd tailscale serve status
  exit 0
fi

if (( reset )); then
  run_cmd sudo tailscale serve reset
  exit 0
fi

if [[ -z "$target" ]]; then
  echo "--target must not be empty" >&2
  exit 2
fi

if [[ -n "$http_port" ]]; then
  run_cmd sudo tailscale serve --bg --http="$http_port" "$target"
else
  run_cmd sudo tailscale serve --bg --https="$https_port" "$target"
fi

if (( dry_run )); then
  cat <<EOF

Dry run only; Tailscale Serve was not changed.

To check current status:
  tailscale serve status
EOF
else
  cat <<EOF

Tailscale Serve configured.

Check status:
  tailscale serve status
EOF
fi

cat <<EOF

Then test from another tailnet device:
  curl -I https://<machine>.<tailnet>.ts.net/

If Seahub login reports CSRF verification failed, add the Tailscale HTTPS origin
to data/shared/seafile/conf/seahub_settings.py, or run:

  bash scripts/set-seafile-domain.sh \\
    --public <public-domain> \\
    --extra-origin https://<machine>.<tailnet>.ts.net
EOF
