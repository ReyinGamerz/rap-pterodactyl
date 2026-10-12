# Rapelz Pterodactyl — Backup, Restore & Migration

This repository is the integration and operations project for Rapelz Hosting on **Pterodactyl Panel 1.15.1**.

## Status

The repository is a new integration project. It does not replace or patch a live Panel automatically.

- [Architecture and security contract](docs/ARCHITECTURE.md)
- [Restore and migration runbooks](docs/RECOVERY-RUNBOOK.md)
- [Theme integration notes](docs/THEME-INTEGRATION.md)
- [Configuration example](config/rapelz-backup.example.json)

## Non-negotiable safety rules

1. Preserve the existing native Pterodactyl backup feature.
2. Never run an unreviewed installer directly against production.
3. Do not expose a general-purpose root shell through an HTTP API.
4. Do not delete older backups when a new backup has failed.
5. Do not store age private keys, Drive tokens, Discord webhooks, or Panel secrets in Git.
6. Do not claim a backup is recoverable until integrity and restore tests pass.
7. Never migrate server data based on a display name alone; use stable server UUID and explicit source/target Node IDs.
8. Keep old VPS/data available until the target is validated and rollback is agreed.

## Intended deployment

The approved dark UI prototype lives in the separate rap-theme repository. This repository defines the service/agent contract and operational workflow that will eventually feed that UI.

Pterodactyl 1.15.1 is a Laravel/React application. Any Panel integration must be developed against the exact 1.x source tree and tested on a staging copy before production. Do not assume extension APIs from newer major versions exist here.

## Development sequence

1. Inventory current Panel, database, Nodes, storage, customer backups, and existing backup script.
2. Define and implement a least-privilege backup service and per-host agent.
3. Add a verified backup catalogue/manifest and node-scoped query API.
4. Implement backup execution and failure-safe retention.
5. Implement restore previews, safety snapshots, and guarded restore workers.
6. Implement Panel/Node disaster recovery and migration runbooks.
7. Integrate the UI only after the API contract is tested.
8. Run end-to-end restore tests on disposable staging systems.
