#!/usr/bin/env bash
set -euo pipefail

if command -v docker >/dev/null 2>&1; then
  docker version
  exit 0
fi

curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
printf '\nDocker installed. Consider running:\n  sudo usermod -aG docker "$USER"\nthen log out and back in.\n'
