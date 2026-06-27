#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BACKUP_ROOT=${BACKUP_ROOT:-./backups}
STAMP=$(date +%Y%m%d-%H%M%S)
DEST="$BACKUP_ROOT/seafile-$STAMP"
mkdir -p "$DEST"

cp -a .env.example "$DEST/" 2>/dev/null || true
cp -a docker-compose.yml nginx docs cloudflare scripts README.md "$DEST/" 2>/dev/null || true

cat > "$DEST/README-restore.txt" <<'EOF'
This backup contains deployment templates only by default.
Back up ./data/mysql and ./data/shared separately with your preferred method.
Never put plaintext secrets into a public backup.
EOF

tar -C "$BACKUP_ROOT" -czf "$DEST.tar.gz" "$(basename "$DEST")"
rm -rf "$DEST"
echo "$DEST.tar.gz"
