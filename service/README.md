# Read-only Backup Catalogue API

Node.js 20+ service using only built-in modules. It provides an authenticated, read-only API for Node and backup metadata. It deliberately cannot run shell commands, restore files, or trigger backup jobs yet.

## Local test

1. Copy catalog.example.json to a host-local catalog path and replace demo data with reviewed metadata.
2. Set `RAPELZ_BACKUP_API_TOKEN` to a random secret with at least 32 characters. Keep it outside Git.
3. Set `RAPELZ_BACKUP_CATALOG` to the catalog path.
4. Run `npm run check` and `npm start`.
5. Bind to loopback or a private network behind TLS/reverse proxy. Do not expose the port publicly without firewalling and TLS.
6. Send `Authorization: Bearer <token>` to `/health`, `/v1/nodes`, or `/v1/backups?node_id=node-001`.

## Important current limitation

This is a read-only catalogue API. It does not yet import manifests from Google Drive, persist jobs, execute backups, manage retention, send Discord alerts, or perform restore/migration. Those require separate reviewed workers and end-to-end tests. Never populate production with fabricated demo records.
