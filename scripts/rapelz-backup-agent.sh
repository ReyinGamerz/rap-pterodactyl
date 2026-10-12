#!/usr/bin/env bash
# Rapelz Backup Agent — reviewed, allowlisted local backup runner.
# Configure via environment or a root-owned EnvironmentFile. Never commit secrets.
set -Eeuo pipefail
umask 077

readonly SCRIPT_NAME="rapelz-backup-agent"
readonly DEFAULT_ROOT="/var/lib/rapelz-backup-agent"
ROOT="${RAPELZ_BACKUP_WORKDIR:-$DEFAULT_ROOT}"
SOURCE_KIND="${RAPELZ_SOURCE_KIND:-node}"
SOURCE_ID="${RAPELZ_SOURCE_ID:-node-001}"
REMOTE_ROOT="${RAPELZ_RCLONE_REMOTE:-gdrive:rapelz-backups}"
RECIPIENT="${RAPELZ_AGE_RECIPIENT:-}"
PATHS_FILE="${RAPELZ_BACKUP_PATHS_FILE:-/etc/rapelz-backup/paths.txt}"
MYSQL_DEFAULTS_FILE="${RAPELZ_MYSQL_DEFAULTS_FILE:-/etc/rapelz-backup/mysql.cnf}"
DB_NAMES_FILE="${RAPELZ_DATABASES_FILE:-/etc/rapelz-backup/databases.txt}"
LOG_FILE="${RAPELZ_BACKUP_LOG:-/var/log/rapelz-backup-agent.log}"
LOCK_FILE="${RAPELZ_BACKUP_LOCK:-/run/lock/rapelz-backup-agent.lock}"
KEEP_LOCAL_DAYS="${RAPELZ_KEEP_LOCAL_DAYS:-2}"

log(){ printf '%s [%s] %s\n' "$(date -Is)" "$SCRIPT_NAME" "$*" | tee -a "$LOG_FILE" >&2; }
fail(){ log "ERROR: $*"; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || fail "Required command missing: $1"; }
cleanup(){ [[ -n "${STAGE:-}" && -d "${STAGE:-}" ]] && rm -rf -- "$STAGE"; }
trap cleanup EXIT
trap 'rc=$?; log "FAILED rc=$rc line=$LINENO"; exit "$rc"' ERR

[[ $EUID -eq 0 ]] || fail "Run as root; protect configuration and logs."
[[ "$SOURCE_KIND" =~ ^(panel|node|server|database|file)$ ]] || fail "Invalid RAPELZ_SOURCE_KIND."
[[ "$SOURCE_ID" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$ ]] || fail "Invalid RAPELZ_SOURCE_ID."
[[ "$REMOTE_ROOT" == *:* ]] || fail "RAPELZ_RCLONE_REMOTE must be an rclone remote path."
[[ -n "$RECIPIENT" ]] || fail "RAPELZ_AGE_RECIPIENT is required; use the public age recipient only."
[[ -r "$PATHS_FILE" ]] || fail "Paths allowlist is not readable: $PATHS_FILE"
[[ "$KEEP_LOCAL_DAYS" =~ ^[0-9]+$ ]] || fail "KEEP_LOCAL_DAYS must be an integer."

for cmd in age tar gzip rclone sha256sum flock date mktemp cp stat sed find awk; do need "$cmd"; done
need jq
mkdir -p -- "$ROOT" "$(dirname "$LOG_FILE")" "$(dirname "$LOCK_FILE")"
chmod 700 "$ROOT"
exec 9>"$LOCK_FILE"
flock -n 9 || fail "Another backup job is running."

stamp="$(date +%Y-%m-%d_%H%M%S)"
STAGE="$(mktemp -d "$ROOT/.stage.XXXXXX")"
chmod 700 "$STAGE"
PAYLOAD="$STAGE/payload"
mkdir -p "$PAYLOAD"
MANIFEST="$STAGE/manifest.json"
ARCHIVE="$ROOT/${SOURCE_ID}-${SOURCE_KIND}-${stamp}.tar.gz.age"
if [[ "$SOURCE_KIND" == "panel" ]]; then
  REMOTE_DIR="${REMOTE_ROOT%/}/panel/daily"
  MANIFEST_DIR="${REMOTE_ROOT%/}/panel/manifests"
else
  REMOTE_DIR="${REMOTE_ROOT%/}/nodes/${SOURCE_ID}/daily"
  MANIFEST_DIR="${REMOTE_ROOT%/}/nodes/${SOURCE_ID}/manifests"
fi
REMOTE_FILE="$REMOTE_DIR/$(basename "$ARCHIVE")"
REMOTE_MANIFEST="$MANIFEST_DIR/$(basename "$ARCHIVE").json"

log "Starting source_kind=$SOURCE_KIND source_id=$SOURCE_ID"

# Copy only explicitly allowlisted absolute paths. Reject traversal and root.
while IFS= read -r path || [[ -n "$path" ]]; do
  path="${path%%#*}"
  path="$(printf '%s' "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$path" ]] && continue
  [[ "$path" == /* ]] || fail "Allowlisted path must be absolute: $path"
  [[ "$path" != "/" ]] || fail "Refusing to back up the entire root filesystem."
  [[ "$path" != *"/../"* && "$path" != */.. && "$path" != *"/./"* ]] || fail "Unsafe path rejected: $path"
  [[ -e "$path" || -L "$path" ]] || { log "WARN: allowlisted path missing, skipped: $path"; continue; }
  target="$PAYLOAD$path"
  mkdir -p -- "$(dirname "$target")"
  cp -a -- "$path" "$target"
  log "Added allowlisted path: $path"
done < "$PATHS_FILE"

# Optional database dumps: use a root-owned mysql defaults file, never put passwords on argv.
if [[ -r "$DB_NAMES_FILE" ]]; then
  need mysqldump
  [[ -r "$MYSQL_DEFAULTS_FILE" ]] || fail "Database list exists but MySQL defaults file is missing."
  [[ "$(stat -c %a "$MYSQL_DEFAULTS_FILE")" == "600" ]] || fail "MySQL defaults file must have mode 600."
  while IFS= read -r db || [[ -n "$db" ]]; do
    db="${db%%#*}"
    db="$(printf '%s' "$db" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$db" ]] && continue
    [[ "$db" =~ ^[a-zA-Z0-9_]+$ ]] || fail "Unsafe database name in allowlist."
    mkdir -p "$PAYLOAD/_database"
    log "Dumping database: $db"
    mysqldump --defaults-extra-file="$MYSQL_DEFAULTS_FILE" --single-transaction --quick --routines --triggers --events --hex-blob "$db" > "$PAYLOAD/_database/$db.sql"
    [[ -s "$PAYLOAD/_database/$db.sql" ]] || fail "Database dump is empty: $db"
  done < "$DB_NAMES_FILE"
fi

# Manifest deliberately excludes secret values. Inventory paths are recorded, not credential contents.
export SOURCE_KIND SOURCE_ID stamp
jq -n --arg source_kind "$SOURCE_KIND" --arg source_id "$SOURCE_ID" --arg created_at "$(date -u -Is)" --arg hostname "$(hostname -f 2>/dev/null || hostname)" --arg script "$SCRIPT_NAME" '{schema_version:1,source_kind:$source_kind,source_id:$source_id,created_at_utc:$created_at,source_host:$hostname,agent:$script,encrypted:true,verification:"pending"}' > "$PAYLOAD/rapelz-manifest.json"
tar -C "$STAGE" -czf "$STAGE/backup.tar.gz" payload
[[ -s "$STAGE/backup.tar.gz" ]] || fail "Archive creation failed."
age -r "$RECIPIENT" -o "$ARCHIVE" "$STAGE/backup.tar.gz"
[[ -s "$ARCHIVE" ]] || fail "Encrypted archive is empty."
cipher_sha="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
cipher_size="$(stat -c '%s' "$ARCHIVE")"
log "Encrypted archive ready size=$cipher_size sha256=$cipher_sha"

rclone mkdir "$REMOTE_DIR"
rclone mkdir "$MANIFEST_DIR"
rclone copyto "$ARCHIVE" "$REMOTE_FILE" --retries 3 --low-level-retries 5
remote_json="$(rclone lsjson "$REMOTE_FILE" --stat)"
remote_size="$(printf '%s' "$remote_json" | jq -r '.Size // empty')"
[[ "$remote_size" =~ ^[0-9]+$ ]] || fail "Unable to verify remote object size."
[[ "$remote_size" == "$cipher_size" ]] || fail "Remote size mismatch local=$cipher_size remote=$remote_size"

# Publish a sanitized sidecar manifest only after the encrypted object upload is verified.
jq -n --arg id "$(basename "$ARCHIVE")" --arg source_kind "$SOURCE_KIND" --arg source_id "$SOURCE_ID" --arg created_at "$(date -u -Is)" --arg object "$REMOTE_FILE" --arg sha256 "$cipher_sha" --argjson size "$cipher_size" '{schema_version:1,backup_id:$id,source_kind:$source_kind,source_id:$source_id,created_at_utc:$created_at,object:$object,ciphertext_sha256:$sha256,ciphertext_size_bytes:$size,encrypted:true,remote_size_verified:true,restore_test:"not_yet_tested"}' > "$STAGE/remote-manifest.json"
rclone copyto "$STAGE/remote-manifest.json" "$REMOTE_MANIFEST" --retries 3
manifest_remote="$(rclone lsjson "$REMOTE_MANIFEST" --stat | jq -r '.Size // empty')"
manifest_local="$(stat -c '%s' "$STAGE/remote-manifest.json")"
[[ "$manifest_remote" == "$manifest_local" ]] || fail "Manifest upload verification failed."

# Keep only a short local encrypted copy. Plaintext staging is removed by trap.
find "$ROOT" -maxdepth 1 -type f -name '*.tar.gz.age' -mtime "+$KEEP_LOCAL_DAYS" -delete
log "SUCCESS backup_id=$(basename "$ARCHIVE") remote=$REMOTE_FILE size=$cipher_size sha256=$cipher_sha"
