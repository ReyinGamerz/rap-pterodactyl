# Architecture and Security Contract

## Components

- **Panel UI:** visual client only. It never receives root credentials or age private keys.
- **Backup API/service:** authenticates admin requests, authorizes operations, queues jobs, records status and audit events, and returns paginated backup metadata.
- **Host agent:** runs on the Panel host or each Node. It accepts only authenticated, structured jobs and invokes a fixed set of reviewed operations.
- **Object storage:** Google Drive via rclone; archive objects are age-encrypted before upload.
- **Offline recovery key:** private age key is held outside Google Drive and outside the web application.

## Node identity

A Node registry record must contain a stable internal ID, Pterodactyl Node ID, display name, hostname, enabled state, agent identity, last heartbeat, and configured storage policy. Display names and IP addresses are not stable identifiers. Removing a Node from the active registry must not remove historical manifests or backup objects.

## Backup record contract

Each record should include: backup ID, source kind (panel/node/server/database/file), stable Node ID if applicable, Pterodactyl server UUID if applicable, created-at UTC timestamp, display timezone, archive object key, encrypted size, SHA-256, encryption key fingerprint/public-key identifier, manifest object key, component list, source software versions, and verification status.

Never expose private credentials, raw environment values, private keys, Drive refresh tokens, or Discord webhook URLs in API responses, manifests, logs, or UI.

## API contract (planned)

All endpoints must require authenticated admin authorization and CSRF protection where applicable. Agent endpoints use separate per-agent credentials with rotation and revocation.

- GET /api/rapelz-backup/v1/health — service health and dependency state, no secrets.
- GET /api/rapelz-backup/v1/nodes — registered Nodes and health.
- GET /api/rapelz-backup/v1/backups?node_id=&kind=&status=&from=&to=&q=&page=&per_page= — filtered, paginated catalogue.
- GET /api/rapelz-backup/v1/backups/{id} — metadata and verification details.
- POST /api/rapelz-backup/v1/jobs — request a typed backup, verification, restore-preview, or migration-preflight job.
- GET /api/rapelz-backup/v1/jobs/{id} — job status and sanitized logs.
- POST /api/rapelz-backup/v1/restore-previews — validate source backup and target before any destructive step.
- POST /api/rapelz-backup/v1/restores — execute only a previously validated, explicitly confirmed restore plan.

These routes are a contract, not an assertion that a running API has already been implemented.

## Job safety

- Use a durable queue and idempotent job IDs.
- Validate every enum, Node ID, UUID, path, archive object key, and target.
- Never accept arbitrary shell commands or arbitrary filesystem paths from the browser.
- Enforce per-operation allowlists, timeouts, resource limits, and structured logs.
- Require an explicit restore plan and confirmation for destructive operations.
- Take a safety snapshot where feasible before overwriting live data.
- Block deletion/retention while backup status is failed, incomplete, or unverified.
- Never run two conflicting restore/migration jobs against the same server or Node concurrently.

## Encryption and storage

1. Encrypt locally with age using the configured public key.
2. Upload the ciphertext using rclone.
3. Verify remote size and, where supported, download/compare a ciphertext checksum.
4. Write the manifest only after the upload is verified; mark backup usable only after archive/listing/integrity checks succeed.
5. Keep the private key offline. Document key fingerprint and recovery instructions, never the private key itself.
6. Do not treat remote size equality alone as a complete restore test.

## Retention

Retention target is 30 days. Delete only after a new backup for the same source is uploaded and verified, and only after checking that the candidate is not the last known-good recovery point. Record every deletion in an audit log. Legacy archives remain untouched until migration and restore tests are accepted.

## Consistency

Database backups must use database-native consistent dump procedures. Copying active database files or Docker internals blindly is not an acceptable substitute. Identify customer DB hosts and Pterodactyl backup storage from actual configuration before implementing source paths.

## Status vocabulary

Use explicit states: queued, running, verifying, succeeded, failed, cancelled, restore-preview-ready, restore-running, restored, and rollback-required. Do not show “success” until verification is complete.