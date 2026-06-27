# Tailscale internal access

Install Tailscale:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Get the Tailscale IP:

```bash
tailscale ip -4
```

You can then use either MagicDNS or a private DNS record:

```text
cloud.internal.example.com -> 100.x.y.z
```

This private entrypoint remains useful even if the public Cloudflare Tunnel is down.
