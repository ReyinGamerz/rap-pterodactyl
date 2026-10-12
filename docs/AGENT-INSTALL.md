# Backup Agent Installation Notes

This is an operator-reviewed script, not a one-click installer. It must be installed and tested on a staging host first.

## Requirements

- Bash, tar/gzip, age, rclone, jq, sha256sum, rsync/cp utilities, mysqldump when database allowlist is enabled.
- A configured rclone remote named by RAPELZ_RCLONE_REMOTE.
- An age **public recipient** in a root-owned environment file. The private key stays offline.
- Root-owned allowlists and optional database client defaults file.

## Configuration files

Create `/etc/rapelz-backup/` owned by root with mode 700. Review and adapt:

- `paths.txt` from `config/paths.example.txt`
- `databases.txt` from `config/databases.example.txt` only if databases are audited
- `mysql.cnf` from `config/mysql.cnf.example`, mode 600
- `agent.env` with `RAPELZ_SOURCE_KIND`, `RAPELZ_SOURCE_ID`, `RAPELZ_RCLONE_REMOTE`, and `RAPELZ_AGE_RECIPIENT`

Keep real secrets out of shell history, Git, support tickets, and Discord. Use the existing production backup script until the new agent passes a restore drill.

## Discord webhook notifications

The backup agent calls `/usr/local/sbin/rapelz-discord-notify.sh` after success or failure when the helper is installed. Install it as root with mode `0750`; configure the API and helper to use the same `RAPELZ_WEBHOOK_SETTINGS_FILE` path (default `/var/lib/rapelz-backup-service/discord-webhook.json`). The service saves this file with mode `0600`; its parent directory must be service-owned and mode `0700`. Configure the URL through the authenticated API, never in Git or the static theme. The helper only accepts HTTPS Discord webhook URLs and suppresses curl diagnostics so the URL is not written to logs. Test this on staging with a private test channel before enabling notifications on production.

## Important scope limitation

The agent only backs up paths explicitly present in the allowlist and databases explicitly present in the database list. It does not automatically discover all Nodes, all customer databases, Docker volume semantics, customer native backup metadata, or a full Pterodactyl recovery plan. Do not describe the host as fully protected until inventory is complete and a restore test succeeds.

## Manual validation before scheduling

1. Inspect script with `bash -n` and ShellCheck where available.
2. Use a disposable directory and test database, not production customer data.
3. Confirm encrypted archive exists and the plaintext staging directory is removed.
4. Confirm remote object and sidecar manifest sizes match.
5. Download the archive to a test host and decrypt with the offline recovery key.
6. List and extract into a temporary directory; verify paths, file hashes, and database restore.
7. Test failure cases: no Drive connection, invalid recipient, full disk, failed dump, and remote-size mismatch. Older backups must remain untouched.

Do not enable a timer/cron until these tests pass.