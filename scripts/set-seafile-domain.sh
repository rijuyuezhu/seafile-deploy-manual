#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage:
  bash scripts/set-seafile-domain.sh --public DOMAIN [options]

Options:
  --public DOMAIN       Canonical public domain, without scheme or port
  --protocol PROTOCOL   Public protocol, default: https
  --extra-host HOST     Additional allowed host, without scheme or port; repeatable
  --extra-origin URL    Additional CSRF trusted origin, repeatable
  --dry-run             Show what would be changed without writing files
  -h, --help            Show help

Examples:
  bash scripts/set-seafile-domain.sh --public seafile.example.com
  bash scripts/set-seafile-domain.sh \
    --public seafile.example.com \
    --extra-origin https://machine.tailnet.ts.net
EOF
}

public_domain=""
protocol="https"
dry_run=0
extra_hosts=()
extra_origins=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public)
      public_domain=${2:-}
      shift 2
      ;;
    --protocol)
      protocol=${2:-}
      shift 2
      ;;
    --extra-host)
      extra_hosts+=("${2:-}")
      shift 2
      ;;
    --extra-origin)
      extra_origins+=("${2:-}")
      shift 2
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

if [[ -z "$public_domain" ]]; then
  echo "Missing --public DOMAIN" >&2
  usage >&2
  exit 2
fi

EXTRA_HOSTS=$(IFS=$'\n'; echo "${extra_hosts[*]-}")
EXTRA_ORIGINS=$(IFS=$'\n'; echo "${extra_origins[*]-}")
export PUBLIC_DOMAIN="$public_domain"
export PUBLIC_PROTOCOL="$protocol"
export EXTRA_HOSTS
export EXTRA_ORIGINS
export DRY_RUN="$dry_run"

python3 - <<'PY'
from __future__ import annotations

import os
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

root = Path.cwd()
public = os.environ["PUBLIC_DOMAIN"].strip()
protocol = os.environ.get("PUBLIC_PROTOCOL", "https").strip() or "https"
dry_run = os.environ.get("DRY_RUN") == "1"
extra_hosts = [x.strip() for x in os.environ.get("EXTRA_HOSTS", "").splitlines() if x.strip()]
extra_origins = [x.strip() for x in os.environ.get("EXTRA_ORIGINS", "").splitlines() if x.strip()]

if "://" in public:
    print("--public must be a domain or IP only, without http:// or https://", file=sys.stderr)
    sys.exit(2)
if "/" in public or "?" in public or "#" in public:
    print("--public must not contain path, query, or fragment", file=sys.stderr)
    sys.exit(2)
if ":" in public:
    print("--public must not include a port", file=sys.stderr)
    sys.exit(2)
if protocol not in {"http", "https"}:
    print("--protocol must be http or https", file=sys.stderr)
    sys.exit(2)

def validate_plain_host(host: str, option: str) -> str:
    host = host.strip()
    if not host:
        print(f"{option} must not be empty", file=sys.stderr)
        sys.exit(2)
    if "://" in host:
        print(f"{option} must be a domain or IP only, without http:// or https://", file=sys.stderr)
        sys.exit(2)
    if "/" in host or "?" in host or "#" in host:
        print(f"{option} must not contain path, query, or fragment", file=sys.stderr)
        sys.exit(2)
    if ":" in host:
        print(f"{option} must not include a port; use --extra-origin for URLs with ports", file=sys.stderr)
        sys.exit(2)
    return host

extra_hosts = [validate_plain_host(x, "--extra-host") for x in extra_hosts]

def host_from_origin(origin: str) -> str:
    parsed = urlparse(origin)
    if not parsed.scheme or not parsed.netloc:
        raise ValueError(f"extra origin must be a full URL with scheme: {origin}")
    return parsed.hostname or parsed.netloc

hosts = [public]
origins = [f"{protocol}://{public}"]
for origin in extra_origins:
    origins.append(origin)
    hosts.append(host_from_origin(origin))
hosts.extend(extra_hosts)

# Deduplicate while preserving order.
hosts = list(dict.fromkeys(hosts))
origins = list(dict.fromkeys(origins))

def update_env(text: str) -> str:
    pairs = {
        "SEAFILE_SERVER_HOSTNAME": public,
        "SEAFILE_SERVER_PROTOCOL": protocol,
    }
    for key, value in pairs.items():
        line = f"{key}={value}"
        if re.search(rf"^{re.escape(key)}=", text, flags=re.M):
            text = re.sub(rf"^{re.escape(key)}=.*$", line, text, flags=re.M)
        else:
            if text and not text.endswith("\n"):
                text += "\n"
            text += line + "\n"
    return text

def py_string_list(values: list[str]) -> str:
    if not values:
        return "[]"
    inner = "\n".join(f'    "{v}",' for v in values)
    return "[\n" + inner + "\n]"

def set_python_assignment(text: str, name: str, value: str) -> str:
    pattern = rf"^{re.escape(name)}\s*=.*(?:\n(?:\s+.*|\].*))?"
    replacement = f"{name} = {value}"
    if re.search(rf"^{re.escape(name)}\s*=", text, flags=re.M):
        # Safer line-oriented replacement for both one-line and bracketed lists.
        lines = text.splitlines()
        out: list[str] = []
        i = 0
        replaced = False
        while i < len(lines):
            line = lines[i]
            if re.match(rf"^{re.escape(name)}\s*=", line):
                out.append(replacement)
                replaced = True
                if "[" in line and "]" not in line:
                    i += 1
                    while i < len(lines) and "]" not in lines[i]:
                        i += 1
                i += 1
                continue
            out.append(line)
            i += 1
        text = "\n".join(out) + ("\n" if text.endswith("\n") else "")
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        text += "\n" + replacement + "\n"
    return text

env_path = root / ".env"
if env_path.exists():
    env_text = env_path.read_text()
else:
    example = root / ".env.example"
    env_text = example.read_text() if example.exists() else ""
new_env = update_env(env_text)

settings_path = root / "data" / "shared" / "seafile" / "conf" / "seahub_settings.py"
settings_exists = settings_path.exists()
new_settings = None
backup_path = None
if settings_exists:
    settings_text = settings_path.read_text()
    new_settings = settings_text
    new_settings = set_python_assignment(new_settings, "SERVICE_URL", repr(f"{protocol}://{public}"))
    new_settings = set_python_assignment(new_settings, "FILE_SERVER_ROOT", repr(f"{protocol}://{public}/seafhttp"))
    new_settings = set_python_assignment(new_settings, "ALLOWED_HOSTS", py_string_list(hosts))
    new_settings = set_python_assignment(new_settings, "CSRF_TRUSTED_ORIGINS", py_string_list(origins))
    if protocol == "https":
        new_settings = set_python_assignment(new_settings, "CSRF_COOKIE_SECURE", "True")
        new_settings = set_python_assignment(new_settings, "SESSION_COOKIE_SECURE", "True")
        new_settings = set_python_assignment(new_settings, "SECURE_PROXY_SSL_HEADER", '("HTTP_X_FORWARDED_PROTO", "https")')
        new_settings = set_python_assignment(new_settings, "USE_X_FORWARDED_HOST", "True")
    else:
        new_settings = set_python_assignment(new_settings, "CSRF_COOKIE_SECURE", "False")
        new_settings = set_python_assignment(new_settings, "SESSION_COOKIE_SECURE", "False")
        new_settings = set_python_assignment(new_settings, "SECURE_PROXY_SSL_HEADER", "None")
        new_settings = set_python_assignment(new_settings, "USE_X_FORWARDED_HOST", "True")
    backup_path = settings_path.with_name(settings_path.name + "." + datetime.now().strftime("%Y%m%d-%H%M%S") + ".bak")

print("Public URL:", f"{protocol}://{public}")
print("Allowed hosts:", ", ".join(hosts))
print("CSRF trusted origins:", ", ".join(origins))
print("Update .env:", env_path)
if settings_exists:
    print("Update Seahub settings:", settings_path)
    print("Backup:", backup_path)
else:
    print("Seahub settings not found yet:", settings_path)
    print("Only .env will be updated. Run this script again after first initialization if needed.")

if dry_run:
    print("Dry run only; no files written.")
    sys.exit(0)

env_path.write_text(new_env)
if settings_exists and new_settings is not None:
    shutil.copy2(settings_path, backup_path)
    settings_path.write_text(new_settings)

print("Done. Restart Seafile afterwards:")
print("  docker compose --env-file .env restart seafile")
PY
