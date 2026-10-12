#!/usr/bin/env bash
# Download/decrypt/inspect an archive into a review directory only.
# This tool NEVER writes restored files into live Panel/Node locations.
set -Eeuo pipefail
umask 077
REMOTE_OBJECT="${1:-}"
BACKUP_ID="${2:-}"
IDENTITY="${RAPELZ_AGE_IDENTITY:-/root/backup-rapelz/rapelz-backup-key.txt}"
REVIEW_ROOT="${RAPELZ_RESTORE_REVIEW_ROOT:-/var/lib/rapelz-restore-review}"
WORK_ROOT="${RAPELZ_RESTORE_WORK_ROOT:-/var/tmp}"
need(){ command -v "$1" >/dev/null 2>&1 || { printf 'Missing required command: %s\n' "$1" >&2; exit 1; }; }
[[ $EUID -eq 0 ]] || { echo "Run as root on a recovery host." >&2; exit 1; }
[[ -n "$REMOTE_OBJECT" && -n "$BACKUP_ID" ]] || { echo "Usage: $0 <exact-rclone-object-path> <backup-id>"; exit 2; }
[[ "$BACKUP_ID" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$ ]] || { echo "Invalid backup ID." >&2; exit 2; }
[[ "$REMOTE_OBJECT" == *:* ]] || { echo "Remote object must use rclone remote:path syntax." >&2; exit 2; }
[[ -r "$IDENTITY" ]] || { echo "Offline age identity is unavailable." >&2; exit 1; }
for cmd in rclone age tar sha256sum mktemp; do need "$cmd"; done
mkdir -p "$REVIEW_ROOT" "$WORK_ROOT"
chmod 700 "$REVIEW_ROOT"
DEST="$REVIEW_ROOT/$BACKUP_ID"
[[ ! -e "$DEST" ]] || { echo "Review destination already exists; refusing to overwrite: $DEST" >&2; exit 1; }
WORK="$(mktemp -d "$WORK_ROOT/rapelz-restore-preflight.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
chmod 700 "$WORK"
printf 'Downloading encrypted object (no live files will be changed)...\n'
rclone copyto "$REMOTE_OBJECT" "$WORK/archive.age" --retries 3
[[ -s "$WORK/archive.age" ]] || { echo "Downloaded archive is empty." >&2; exit 1; }
sha256sum "$WORK/archive.age" > "$WORK/ciphertext.sha256"
age -d -i "$IDENTITY" -o "$WORK/archive.tar.gz" "$WORK/archive.age"
[[ -s "$WORK/archive.tar.gz" ]] || { echo "Decrypted archive is empty." >&2; exit 1; }
tar -tzf "$WORK/archive.tar.gz" > "$WORK/entries.txt"
# Reject absolute paths, parent traversal, and empty archive before extraction.
grep -Eq '^/' "$WORK/entries.txt" && { echo "Unsafe absolute path in archive; refusing extraction." >&2; exit 1; }
grep -Eq '(^|/)\.\.(/|$)' "$WORK/entries.txt" && { echo "Unsafe parent traversal in archive; refusing extraction." >&2; exit 1; }
[[ -s "$WORK/entries.txt" ]] || { echo "Archive contains no entries." >&2; exit 1; }
mkdir -m 700 "$DEST"
tar --no-same-owner --no-same-permissions -xzf "$WORK/archive.tar.gz" -C "$DEST"
cp "$WORK/ciphertext.sha256" "$DEST/ciphertext.sha256"
cp "$WORK/entries.txt" "$DEST/archive-entries.txt"
cat > "$DEST/RESTORE-REVIEW.txt" <<EOF
Rapelz restore preflight completed.
Backup ID: $BACKUP_ID
Source object: $REMOTE_OBJECT
Review directory: $DEST
This directory is for inspection only. No live Panel or Node paths were modified.
Verify manifest, source identity, software versions, file ownership, and database dump before planning a separate restore.
EOF
chmod -R go-rwx "$DEST"
printf 'Preflight succeeded. Review extracted files at: %s\n' "$DEST"
printf 'No live files were overwritten. Review and test before any manual restore.\n'
