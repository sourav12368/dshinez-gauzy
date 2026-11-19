# D’Shinez PostgreSQL encryption at rest — guarded deployment handoff

**Status: opt-in source preparation only; not installed, not activated, and not evidence of production encryption.**

The production D’Shinez PostgreSQL container currently uses the Compose named `postgres_data` volume. PostgreSQL documents that whole-cluster storage encryption belongs at the filesystem/block layer, not in a database password, HTTPS endpoint, or `pgcrypto` applied to a few columns: <https://www.postgresql.org/docs/17/encryption-options.html>.

The D’Shinez-only optional Compose override in `docker-compose.dshinez-encrypted-db.override.yml` redirects **only** the `db` service's PGDATA mount to a pre-existing encrypted directory. `create_host_path: false` prevents Docker from silently creating an empty replacement directory. This override must never be used before the preparation and restoration checks below.

## Operator-controlled gates, in order

1. **Identify the exact owned live project and data.** Confirm the intended host is `srv2104197`, the Compose project is the D’Shinez one (not the separate `crm` or `aljadeed` projects), the bound PostgreSQL container and named volume ID are unambiguous, the deployed image major matches `PG_VERSION`, and the host directory is Sourav-owned. Capture baseline service health. Do not modify global Nginx, peers or unrelated Docker objects.
2. **Prove a recoverable D’Shinez-only backup first.** Create a consistent source backup using the separate backup procedure; encrypt it with a key held outside Git, the host checkout and chat, and verify restoration into an isolated disposable PostgreSQL test instance. No server-wide VM backup is a substitute.
3. **Prepare a dedicated encryption boundary.** A qualified operator must provision and mount a dedicated LUKS2-encrypted filesystem at `/home/sourav/dshinez-encrypted-postgres` with independently recoverable keys and no shared host storage/disk changes. No command in this repository creates or modifies block devices, performs LUKS formatting, mounts or changes host boot configuration. If an independently dedicated encrypted filesystem cannot be provided, **STOP**. Do not improvise by encrypting an existing shared volume or filesystem in place.
4. **Offline data migration, only in a controlled maintenance window.** After a verified backup and clear rollback plan, stop **only** the D’Shinez database and its dependent D’Shinez services, copy the complete existing PostgreSQL cluster consistently, verify permissions and file integrity, and preserve the original named volume for rollback. The details require the live volume/image evidence from gate 1; this document intentionally does not include unverified one-size-fits-all migration commands. Do not run `docker compose down -v` or delete volumes.
5. **Fail-closed preflight before any activation.** With the original data migrated, run `DSHINEZ_ENCRYPTED_PGDATA_DIR=/home/sourav/dshinez-encrypted-postgres DSHINEZ_EXPECTED_PG_MAJOR=<verified_major> bash scripts/security/check-dshinez-encrypted-db-mount.sh` on the VPS host. The checker is read-only and requires the exact dedicated path, a direct mounted `/dev/mapper/dshinez-pgdata` LUKS2 device, existing PG_VERSION matching the deployed major, and restrictive permissions. Any failure means do not activate.
6. **Activate and verify under one operator.** Combine the existing D’Shinez Compose file with the override (keeping the *actual* project name and current deployment parameters), validate `docker compose config`, and recreate only D’Shinez services during the scheduled cutover. Confirm D’Shinez health, application login, worker, encrypted mount and independent restore; read-only compare peer-site availability. Roll back to the original unchanged named volume if any gate fails. Never change other project Compose files, host default routing, or shared Nginx.

## What this commit does and does not do

- Adds one **opt-in** D’Shinez-only bind-mount override and one **read-only** preflight checker.
- Changes no existing Compose file, database volume, running container, secret, backup, service or server.
- Provides no encryption keys; keys must never be kept in GitHub or chat. An unlocked filesystem exposes plaintext to host administrators and processes with corresponding access; encryption mainly protects stored media when keys are unavailable.
- Does **not** certify at-rest encryption, migration safety or recovery until a real D’Shinez-only mount and restore are independently verified.

If host shell/volume access or a recoverable encrypted backup is unavailable, **block the live change**. Public Docker/Hostinger metadata alone cannot confirm what disk encryption currently protects the data.
