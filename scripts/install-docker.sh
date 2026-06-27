#!/usr/bin/env bash
set -euo pipefail

if command -v docker >/dev/null 2>&1; then
  docker version
  if ! docker info >/dev/null 2>&1; then
    cat >&2 <<'EOF'

Docker CLI is installed, but the current user cannot talk to the Docker daemon.
If this is a permission issue, run:

  sudo usermod -aG docker "$USER"

Then log out and back in, or run:

  newgrp docker

Finally verify:

  docker info >/dev/null
EOF
  fi
  exit 0
fi

TMP_INSTALLER=$(mktemp)
cleanup() {
  rm -f "$TMP_INSTALLER"
}
trap cleanup EXIT

if ! curl -fsSL https://get.docker.com -o "$TMP_INSTALLER"; then
  cat >&2 <<'EOF'
Failed to download Docker's install script.

Check network access first:

  curl -I https://get.docker.com
  curl -I https://download.docker.com/linux/ubuntu/gpg

If you are on a restricted network, configure proxy or a reachable Docker APT mirror,
then rerun this script.
EOF
  exit 1
fi

sudo sh "$TMP_INSTALLER"
sudo systemctl enable --now docker

cat <<'EOF'

Docker installed. Verify whether the current user can use Docker:

  docker info >/dev/null

If it reports permission denied, run:

  sudo usermod -aG docker "$USER"

Then log out and back in, or run:

  newgrp docker
EOF
