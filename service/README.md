# Read-only Backup Catalogue API

Node.js 20+ service using only built-in modules. It provides an authenticated, read-only API for Node and backup metadata. It deliberately cannot run shell commands, restore files, or trigger backup jobs yet.

## Local test

1. Copy catalog.example.json to a host-local catalog path and replace demo data with reviewed metadata.
2. Set `RAPELZ_BACKUP_API_TOKEN` to a random secret with at least 32 characters. Keep it outside Git.
3. Set `RAPELZ_BACKUP_CATALOG` to the catalog path.
4. Run `npm run check` and `npm start`.
5. Bind to loopback or a private network behind TLS/reverse proxy. Do not expose the port publicly without firewalling and TLS.
6. Send `Authorization: Bearer <token>` to `/health`, `/v1/nodes`, or `/v1/backups?node_id=node-001`.

## Discord webhook settings API (implemented, not yet connected to Panel login)

The same bearer-authenticated service exposes:
- `GET /v1/settings/webhook` — returns enabled/configured flags, masked status, and event toggles; never returns the secret URL.
- `PUT /v1/settings/webhook` — saves the webhook URL, enabled flag, and event toggles to a service-local JSON file with mode 0600.
- `POST /v1/settings/webhook/test` — sends a test message.

Set `RAPELZ_WEBHOOK_SETTINGS_FILE` to the desired service-owned settings path. Default: `/var/lib/rapelz-backup-service/discord-webhook.json`. Keep the parent directory service-owned and mode 0700. Requests require the API bearer token and should remain on loopback/private network behind an authenticated Admin bridge. **Do not put the bearer token into the static theme JavaScript.** The current theme is a demo and its save/test buttons intentionally do not contact this API.

Webhook URLs are restricted to HTTPS Discord webhook paths on `discord.com` or `discordapp.com`; arbitrary hosts, ports, query strings, and redirects are not used. The URL is not returned by the API and must never be logged. Test delivery reports only a sanitized status.

The backup agent now calls `/usr/local/sbin/rapelz-discord-notify.sh` for backup success/failure if that helper is installed. Install the helper from `scripts/rapelz-discord-notify.sh` with root ownership and mode 0750 on each host using the agent. Configure the same `RAPELZ_WEBHOOK_SETTINGS_FILE` path for the helper and API. Notifications are controlled by the saved enabled flag and per-event toggles.

## Scope boundary

This is the webhook settings API and the first backup-agent success/failure hooks—not a completed Pterodactyl Admin integration. Restore, migration, verification-failure, and retention events need their own workers before their toggles can trigger real events. The static theme currently offers a preview-only settings panel. Do not expose the bearer token to browser code or deploy the API publicly.

## Important current limitation

This is a read-only catalogue API. It does not yet import manifests from Google Drive, persist jobs, execute backups, manage retention, send Discord alerts, or perform restore/migration. Those require separate reviewed workers and end-to-end tests. Never populate production with fabricated demo records.
