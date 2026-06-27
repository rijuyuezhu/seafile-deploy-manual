# Cloudflare Tunnel

Recommended setup:

```text
Hostname: cloud.example.com
Service Type: HTTP
Service URL: http://127.0.0.1
```

Why HTTP origin is acceptable here:

```text
Browser -> Cloudflare: HTTPS
Cloudflare -> cloudflared: encrypted tunnel
cloudflared -> local Nginx: localhost HTTP
```

This avoids local certificate mismatch errors such as:

```text
x509: certificate is valid for *.example.com, not localhost
```

## Steps

1. Add your domain to Cloudflare DNS.
2. Create a Zero Trust Tunnel.
3. Install and run `cloudflared` using the command shown in the dashboard.
4. Add a Public Hostname:
   - Hostname: `cloud.example.com`
   - Service: `http://127.0.0.1`
5. Configure local Nginx using `nginx/seafile-cloudflare-tunnel.conf.example`.
6. Test:

```bash
curl -I https://cloud.example.com/
```

Expected:

```text
HTTP/2 302
location: /accounts/login/?next=/
server: cloudflare
```

## Notes

Do not paste Cloudflare tunnel tokens into public issues, blog posts, or commits.
