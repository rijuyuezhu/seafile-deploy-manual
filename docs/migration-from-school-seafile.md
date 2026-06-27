# Migrating from a school Seafile service

1. In the old school Seafile client, make sure every library is fully synced locally.
2. Check there are no conflict files or placeholder-only files.
3. Create matching libraries on your self-hosted Seafile.
4. Upload or re-sync libraries in batches.
5. Reconfigure desktop/mobile clients to use `https://cloud.example.com`.
6. Reconfigure WebDAV clients to use `https://cloud.example.com/seafdav/`.
7. Regenerate public share links on the new server.

A `401 Unauthorized` response from `/seafdav/` usually means the WebDAV endpoint is alive and waiting for authentication.
