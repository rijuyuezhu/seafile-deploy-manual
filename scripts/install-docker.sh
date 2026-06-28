#!/usr/bin/env bash
set -euo pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

print_postinstall_note() {
  cat <<'EOF'

Docker installed or detected. Verify whether the current user can use Docker and Compose:

  docker info >/dev/null
  docker compose version

If docker info reports permission denied, run:

  sudo usermod -aG docker "$USER"

Then log out and back in, or run:

  newgrp docker
EOF
}

start_docker() {
  if command_exists systemctl; then
    sudo systemctl enable --now docker || sudo systemctl start docker || true
  elif command_exists service; then
    sudo service docker start || true
  fi
}

compose_v2_available() {
  docker compose version >/dev/null 2>&1
}

warn_if_daemon_unreachable() {
  if command_exists docker && ! docker info >/dev/null 2>&1; then
    cat >&2 <<'EOF'

Docker CLI is installed, but the current user cannot talk to the Docker daemon.
If this is a permission issue, run:

  sudo usermod -aG docker "$USER"

Then log out and back in, or run:

  newgrp docker
EOF
  fi
}

install_official_docker() {
  local tmp_installer
  tmp_installer=$(mktemp)

  if ! curl -fsSL https://get.docker.com -o "$tmp_installer"; then
    rm -f "$tmp_installer"
    cat >&2 <<'EOF'
Failed to download Docker's install script.

Check network access first:

  curl -I https://get.docker.com
  curl -I https://download.docker.com/linux/ubuntu/gpg
EOF
    return 1
  fi

  if ! sudo sh "$tmp_installer"; then
    rm -f "$tmp_installer"
    return 1
  fi

  rm -f "$tmp_installer"
  start_docker
}

apt_has_package() {
  apt-cache show "$1" >/dev/null 2>&1
}

apt_install_packages() {
  sudo apt-get update
  sudo apt-get install -y "$@"
}

install_compose_v2_with_apt() {
  if ! command_exists apt-get; then
    return 1
  fi

  if apt_has_package docker-compose-v2; then
    apt_install_packages docker-compose-v2
  elif apt_has_package docker-compose-plugin; then
    apt_install_packages docker-compose-plugin
  else
    return 1
  fi
}

install_apt_fallback() {
  if ! command_exists apt-get; then
    cat >&2 <<'EOF'
Fallback installer only supports apt-based systems for now.
Install Docker manually for your distribution.
EOF
    return 1
  fi

  cat >&2 <<'EOF'

Using apt fallback installer.
This installs distribution packages instead of Docker's official packages.
It is useful when get.docker.com or Docker's APT repository is temporarily unusable,
for example in some WSL, proxy, mirror, or new Ubuntu codename environments.
EOF

  sudo apt-get update

  local packages=(docker.io)

  if apt_has_package docker-compose-v2; then
    packages+=(docker-compose-v2)
  elif apt_has_package docker-compose-plugin; then
    packages+=(docker-compose-plugin)
  else
    cat >&2 <<'EOF'

WARNING: no Docker Compose v2 package was found in apt.
Docker Engine can be installed, but this repository requires `docker compose`.
EOF
  fi

  sudo apt-get install -y "${packages[@]}"
  start_docker
}

if command_exists docker; then
  docker version || true
  start_docker
  warn_if_daemon_unreachable

  if compose_v2_available; then
    docker compose version
    exit 0
  fi

  cat >&2 <<'EOF'

Docker CLI is installed, but Docker Compose v2 (`docker compose`) is missing.
Trying to install a Compose v2 plugin via apt.
EOF

  if install_compose_v2_with_apt && compose_v2_available; then
    docker compose version
    print_postinstall_note
    exit 0
  fi

  cat >&2 <<'EOF'

Failed to install Docker Compose v2 automatically.
Install docker-compose-plugin or docker-compose-v2, then verify:

  docker compose version
EOF
  exit 1
fi

if [[ ${INSTALL_DOCKER_FALLBACK:-0} == 1 ]]; then
  install_apt_fallback
else
  if ! install_official_docker; then
    cat >&2 <<'EOF'

Official Docker installation failed.
Trying apt fallback. To force this path next time, run:

  INSTALL_DOCKER_FALLBACK=1 bash scripts/install-docker.sh
EOF
    install_apt_fallback
  fi
fi

if ! compose_v2_available; then
  cat >&2 <<'EOF'

Docker was installed, but Docker Compose v2 (`docker compose`) is still unavailable.
Install docker-compose-plugin or docker-compose-v2 before running deploy.sh.
EOF
  exit 1
fi

docker compose version
print_postinstall_note
