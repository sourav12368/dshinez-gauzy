#!/usr/bin/env bash
# Read-only, fail-closed check for a future opt-in encrypted D'Shinez database mount.
# It cannot create, unlock, mount, initialize, copy, or delete any data.
set -euo pipefail

fail() {
  printf 'DShinez encrypted PGDATA preflight failed: %s\n' "$1" >&2
  exit 1
}

path=${DSHINEZ_ENCRYPTED_PGDATA_DIR:-}
expected_major=${DSHINEZ_EXPECTED_PG_MAJOR:-}
[[ -n "$path" ]] || fail 'DSHINEZ_ENCRYPTED_PGDATA_DIR is unset'
[[ "$path" == /home/sourav/dshinez-encrypted-postgres ]] || fail 'path must be the dedicated DShinez PGDATA mount'
[[ "$expected_major" =~ ^(16|17|18)$ ]] || fail 'set the independently verified deployed PostgreSQL major version'
[[ -d "$path" && ! -L "$path" ]] || fail 'dedicated directory missing or is a symlink'

canonical=$(realpath -e -- "$path") || fail 'path does not resolve'
[[ "$canonical" == "$path" ]] || fail 'path canonicalization mismatch'

for cmd in findmnt cryptsetup stat; do
  command -v "$cmd" >/dev/null 2>&1 || fail "missing $cmd utility"
done

mountpoint=$(findmnt -n -T "$path" -o TARGET) || fail 'mountpoint not found'
[[ "$mountpoint" == "$path" ]] || fail 'directory is not itself a mounted encrypted filesystem'

source=$(findmnt -n -T "$path" -o SOURCE) || fail 'mount source not found'
[[ "$source" == /dev/mapper/dshinez-pgdata ]] || fail 'unexpected mount device; refuse unencrypted or shared disk'

# cryptsetup status verifies active dm-crypt mapping, not merely a convenient mapper name.
crypt_status=$(cryptsetup status dshinez-pgdata) || fail 'dm-crypt mapping not active or inaccessible'
grep -Eq 'type:[[:space:]]*LUKS2' <<<"$crypt_status" || fail 'mapped device is not LUKS2'

[[ -f "$path/PG_VERSION" ]] || fail 'PG_VERSION missing; possible empty bind mount'
actual_major=$(<"$path/PG_VERSION")
[[ "$actual_major" == "$expected_major" ]] || fail 'PG_VERSION differs from verified deployed image major'

# Postgres rejects insecure data directories; stop before activation rather than trying to repair ownership.
mode=$(stat -c '%a' -- "$path") || fail 'unable to read PGDATA permissions'
[[ "$mode" == 700 || "$mode" == 750 ]] || fail 'PGDATA directory mode is not 0700/0750'

printf 'DShinez encrypted PGDATA mount preflight passed (read-only).\n'
