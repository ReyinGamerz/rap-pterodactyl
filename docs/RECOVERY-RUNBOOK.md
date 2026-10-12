# Recovery and Migration Runbook

This is the planned operational sequence. Test every procedure on disposable infrastructure before relying on it for production.

## Panel restore while the old VPS is available

1. Confirm the chosen backup manifest and encrypted object.
2. Take a fresh safety backup of the current state where possible.
3. Select components deliberately: database, application, environment/config, web server/TLS, queue/cron, or other inventoried services.
4. Restore into a staging path first when possible; validate file ownership, permissions, database consistency, and required versions.
5. Apply the reviewed restore plan and validate login, server list, Node connectivity, queue workers, scheduler, HTTPS, and native backups.
6. Keep the safety backup until acceptance.

## Panel disaster recovery when the old VPS is dead

1. Provision a compatible new VPS and secure SSH access.
2. Install the independent recovery tooling from a reviewed source.
3. Authenticate rclone without committing tokens to Git or exposing them in logs.
4. Retrieve the selected encrypted archive and manifest from Drive.
5. Confirm the correct offline age private key is available; never fetch it from Drive.
6. Verify ciphertext hash/size, decrypt, inspect archive paths, and reject unexpected absolute paths or path traversal entries.
7. Rebuild compatible dependencies, restore database and application/configuration, preserve APP_KEY and required identity values, then repair ownership/permissions.
8. Configure HTTPS for the intended hostname. Do not assume restoring old certificate files is always valid; validate certificate/key matching and renewal.
9. Test the new Panel using a temporary hostname or local hosts override before public DNS cutover.
10. When ready, change the A/AAAA record for panel.rapelz.my.id to the new VPS IP.
11. Verify login, server records, queues, scheduled tasks, Node/Wings connections, customer backup listing, and alerts.
12. Keep old VPS and backup sources until recovery is accepted or document why they are unavailable.

Panel restore does not restore Node volumes unless those Node data sources are also backed up and restored.

## Panel migration while old VPS is alive

1. Build and test the target VPS without changing public DNS.
2. Copy an initial consistent snapshot of application files and database.
3. Schedule maintenance; stop/drain writes and queue work according to the tested migration plan.
4. Make the final database and file sync.
5. Validate APP_KEY, database settings, domain, TLS, permissions, queue, cron, and native backup configuration.
6. Cut over DNS only after acceptance checks.
7. Monitor. Roll back DNS and writes only according to a documented plan that avoids divergent databases.

## Node migration

1. Identify source and target by stable Node IDs and server UUIDs.
2. Inventory volumes, allocations/ports, databases, startup settings, environment, customer-created backup archives, and external backup storage.
3. Provision compatible Wings/Docker and verify firewall, disk, and port availability.
4. Copy data initially; schedule maintenance and stop affected servers for final consistent sync.
5. Update Panel Node mapping only according to the reviewed migration plan; do not create duplicate server identities.
6. Validate UUIDs, volume ownership, allocations, database connectivity, startup, SFTP, Wings heartbeat, and customer access.
7. Keep source data until acceptance and rollback expiry.

## DNS rule

The hostname can remain the same while its IP changes. For a Panel move, test the new host first with a temporary hostname or local hosts override, then change panel.rapelz.my.id to the new IP. Change node.rapelz.my.id only if Wings is also moving; otherwise preserve its existing target.

## Recovery acceptance checklist

- [ ] Correct backup ID and manifest verified
- [ ] Encryption key available offline and decryption succeeded
- [ ] Database integrity checks passed
- [ ] Panel login and server list work
- [ ] Node/Wings connection works
- [ ] Queue workers and scheduler work
- [ ] HTTPS/certificate and renewal validated
- [ ] Customer native backup archives remain discoverable
- [ ] Discord alert tested without exposing secrets
- [ ] Rollback plan and old data retention confirmed