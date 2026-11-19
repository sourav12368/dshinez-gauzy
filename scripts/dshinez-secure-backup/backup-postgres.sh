#!/usr/bin/env bash
# D'Shinez-only PostgreSQL backup: encrypted from the dump stream, no plaintext dump file.
set -Eeuo pipefail
umask 077

fail() { printf 'DShinez backup: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"; }
for tool in docker openssl flock mktemp stat df date ln sha256sum; do require "$tool"; done

readonly expected_container='dshinez-db-1'
readonly expected_project='dshinez'
readonly expected_service='db'
readonly backup_dir='/home/sourav/dshinez-backups'
readonly public_certificate='/home/sourav/.config/dshinez-backup/public-recipient.pem'

expected_certificate_sha256="${DSHINEZ_BACKUP_CERT_SHA256:-}"
[[ "$expected_certificate_sha256" =~ ^[[:xdigit:]]{64}$ ]] || fail 'provide the pinned SHA-256 of the approved public encryption certificate'

[[ -d "$backup_dir" && ! -L "$backup_dir" ]] || fail "the dedicated backup directory must already exist: $backup_dir"
[[ -f "$public_certificate" && ! -L "$public_certificate" ]] || fail "public encryption certificate not found: $public_certificate"
[[ "$(stat -c '%a' -- "$backup_dir")" == '700' ]] || fail 'backup directory permissions must be 0700'
actual_certificate_sha256="$(sha256sum -- "$public_certificate" | cut -d ' ' -f1)"
[[ "${actual_certificate_sha256,,}" == "${expected_certificate_sha256,,}" ]] || fail 'public encryption certificate digest did not match the trusted pin'
openssl x509 -in "$public_certificate" -noout -checkend 0 >/dev/null 2>&1 || fail 'recipient certificate is invalid or expired'

identity="$(docker container inspect --format '{{index .Config.Labels "com.docker.compose.project"}} {{index .Config.Labels "com.docker.compose.service"}}' "$expected_container" 2>/dev/null)" || fail 'DShinez DB container not found'
[[ "$identity" == "$expected_project $expected_service" ]] || fail 'refusing to back up a container outside the DShinez db service'

# Reserve at least 5 GiB of free space for other VPS workloads, plus an entire uncompressed DB-size estimate.
db_bytes="$(docker exec --user postgres "$expected_container" sh -ceu 'exec psql -Aqt -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT pg_database_size(current_database())"')" || fail 'cannot measure the DShinez database size'
[[ "$db_bytes" =~ ^[0-9]+$ ]] || fail 'invalid database size result'
read -r free_blocks block_size < <(stat -f -c '%a %S' -- "$backup_dir")
free_bytes=$((free_blocks * block_size))
reserve_bytes=$((5 * 1024 * 1024 * 1024))
(( free_bytes > db_bytes + reserve_bytes )) || fail 'insufficient dedicated backup space while preserving 5 GiB of shared-host free space'

exec 9>"$backup_dir/.dshinez-backup.lock"
flock -n 9 || fail 'another DShinez database backup is already running'

stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
temporary="$(mktemp "$backup_dir/.${stamp}.postgres.XXXXXXXX.cms.partial")"
cleanup() { [[ ! -e "$temporary" ]] || rm -- "$temporary"; }
trap cleanup EXIT

# Do not run shell with -x or log environment values. pg_dump writes only into authenticated CMS encryption.
docker exec --user postgres "$expected_container" sh -ceu \
  'exec pg_dump --format=custom --no-owner --no-privileges -U "$POSTGRES_USER" -d "$POSTGRES_DB"' |
  openssl cms -encrypt -stream -binary -outform DER -aes-256-gcm \
    -recip "$public_certificate" -out "$temporary"

[[ -s "$temporary" ]] || fail 'encrypted output is empty'
openssl cms -cmsout -inform DER -in "$temporary" >/dev/null 2>&1 || fail 'invalid CMS envelope'
output="$backup_dir/${stamp}.dshinez-postgres.cms"
# A hard link is atomic and refuses to overwrite a previous backup.
ln -- "$temporary" "$output" || fail 'backup filename collision or output error'
rm -- "$temporary"
trap - EXIT
sha256sum -- "$output" > "${output}.sha256"
chmod 600 -- "$output" "${output}.sha256"
printf 'Encrypted DShinez backup saved: %s\n' "$output"
