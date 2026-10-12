#!/usr/bin/env bash
# Send a non-secret operational message to the configured Discord webhook.
set -Eeuo pipefail
umask 077
EVENT="\${1:-}"
MESSAGE="\${2:-Rapelz backup event}"
SETTINGS="\${RAPELZ_WEBHOOK_SETTINGS_FILE:-/var/lib/rapelz-backup-service/discord-webhook.json}"
[[ "$EVENT" =~ ^(backup_success|backup_failure|verification_failure|restore_success|restore_failure|migration_success|migration_failure|retention_deleted)$ ]] || exit 2
[[ -r "$SETTINGS" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0
enabled="$(jq -r '.enabled // false' "$SETTINGS" 2>/dev/null || printf false)"
event_enabled="$(jq -r --arg event "$EVENT" '.events[$event] // false' "$SETTINGS" 2>/dev/null || printf false)"
url="$(jq -r '.webhook_url // empty' "$SETTINGS" 2>/dev/null || true)"
[[ "$enabled" == true && "$event_enabled" == true && -n "$url" ]] || exit 0
# Strict Discord host/path allowlist; never log URL or curl diagnostics.
[[ "$url" =~ ^https://(discord\.com|discordapp\.com)/api/webhooks/[0-9]{15,25}/[A-Za-z0-9._-]{20,200}/?$ ]] || exit 0
payload="$(jq -cn --arg content "$MESSAGE" '{content:($content|.[0:1800]),allowed_mentions:{parse:[]}}')" || exit 0
config_url="$(printf '%s' "$url" | sed 's/\\/\\\\/g; s/"/\\"/g')"
config_data="$(printf '%s' "$payload" | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf 'url = "%s"\nrequest = "POST"\nheader = "Content-Type: application/json"\ndata = "%s"\n' "$config_url" "$config_data" |
  curl --config - --silent --output /dev/null --max-time 8 --proto '=https' --tlsv1.2 2>/dev/null || true
exit 0
