# Backup notes

Seafile is a sync service, not a complete backup strategy.

Back up at least:

```text
./data/mysql
./data/shared
.env or a secure secret backup
Nginx configuration
Cloudflare/Tailscale documentation
```

Do not store the only backup on the same old SSD.

Suggested schedule:

```text
Daily local snapshot
Weekly off-machine backup
Cold backup for critical documents
```
