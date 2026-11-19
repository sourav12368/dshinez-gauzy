#!/usr/bin/env bash
# Run ONLY on an isolated test machine, never on the shared Hostinger VPS.
set -Eeuo pipefail
umask 077

fail() { printf 'DShinez restore test: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 1 && -f "$1" ]] || fail 'usage: verify-restore-isolated.sh /path/to/encrypted-backup.cms'
[[ "${DSHINEZ_ISOLATED_RESTORE_TEST:-}" == 'YES' ]] || fail 'set DSHINEZ_ISOLATED_RESTORE_TEST=YES on the isolated test machine'
case "$(hostname -s)" in srv2104197*) fail 'refusing to run on the shared production VPS' ;; esac

for tool in docker openssl hostname sha256sum; do command -v "$tool" >/dev/null || fail "required command not found: $tool"; done

if docker ps --format '{{.Names}}' | grep -Fxq 'dshinez-db-1'; then
  fail 'refusing to run where the production DShinez database container exists'
fi

certificate="${DSHINEZ_ISOLATED_PUBLIC_CERT:-}"
private_key="${DSHINEZ_ISOLATED_PRIVATE_KEY:-}"
[[ -f "$certificate" && -f "$private_key" ]] || fail 'set DSHINEZ_ISOLATED_PUBLIC_CERT and DSHINEZ_ISOLATED_PRIVATE_KEY'
[[ "$(stat -c '%a' -- "$private_key")" == '600' ]] || fail 'private key must be mode 0600'

archive="$1"
# Authenticate the GCM tag before creating/restoring a database; the archive must be trusted and immutable during the test.
starting_hash="$(sha256sum -- "$archive" | cut -d ' ' -f1)"
openssl cms -decrypt -binary -inform DER -in "$archive" -recip "$certificate" -inkey "$private_key" >/dev/null || fail 'CMS authenticated decryption failed'
[[ "$(sha256sum -- "$archive" | cut -d ' ' -f1)" == "$starting_hash" ]] || fail 'encrypted archive changed during authentication'
name="dshinez-restore-verify-${RANDOM}-${RANDOM}"
container_id=''
cleanup() { [[ -z "$container_id" ]] || docker rm --force "$container_id" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# The disposable PostgreSQL instance has no network access and no persistent volume.
# Do not pass real deployment passwords or credentials into this test.
container_id="$(docker run --rm --detach --network none --name "$name" \
  --tmpfs /var/lib/postgresql/data:rw,size=2g \
  -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine)" || fail 'could not start isolated PostgreSQL'

ready=0
for _ in {1..60}; do
  if docker exec --user postgres "$container_id" pg_isready -U postgres -d postgres >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[[ "$ready" == 1 ]] || fail 'isolated PostgreSQL did not become ready'
docker exec --user postgres "$container_id" createdb -U postgres dshinez_restore_verify

# Plaintext is never stored: authenticated custom dump bytes stream directly into the disposable test database.
openssl cms -decrypt -binary -inform DER -in "$archive" -recip "$certificate" -inkey "$private_key" |
  docker exec -i --user postgres "$container_id" pg_restore --exit-on-error --no-owner --no-privileges \
    -U postgres -d dshinez_restore_verify

tables="$(docker exec --user postgres "$container_id" psql -Aqt -U postgres -d dshinez_restore_verify \
  -c "SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema')")"
[[ "$tables" =~ ^[0-9]+$ && "$tables" -gt 0 ]] || fail 'restore yielded no application tables'
printf 'Isolated encrypted restore succeeded; application tables restored: %s\n' "$tables"
