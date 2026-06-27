# Troubleshooting

## Cloudflare shows 502

Check cloudflared logs:

```bash
sudo journalctl -u cloudflared -n 100 --no-pager
```

Common causes:

- Origin URL points to the wrong port.
- Nginx is not listening on the configured origin port.
- You configured HTTPS origin but certificate verification fails.
- Host header does not match the Nginx server block.

For a same-machine deployment, prefer:

```text
Tunnel origin: http://127.0.0.1
Nginx: listen 80 and reverse_proxy to 127.0.0.1:8080
```

## Too many redirects

Usually Cloudflare/cloudflared connects to origin over HTTP, while Nginx redirects HTTP to HTTPS. For the Cloudflare Tunnel hostname, let HTTP directly proxy to Seafile and set:

```nginx
proxy_set_header X-Forwarded-Proto https;
```

## WebDAV returns 401

This is usually normal when unauthenticated. It means the endpoint exists and requires credentials.

## Share links use the wrong domain

Check `.env`:

```env
SEAFILE_SERVER_HOSTNAME=cloud.example.com
SEAFILE_SERVER_PROTOCOL=https
```

Then recreate the Seafile container.
