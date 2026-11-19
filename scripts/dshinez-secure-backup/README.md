# D’Shinez — encrypted PostgreSQL backups (D’Shinez only)

These scripts back up **only the `dshinez-db-1` PostgreSQL service**. They do not back up or modify other Docker projects on Hostinger VPS `srv2104197`, Nginx, firewall, VM snapshots, shared storage configuration, or Compose. The streamed `pg_dump -Fc` is encrypted directly with authenticated **OpenSSL CMS AES-256-GCM** to an approved public X.509 certificate. The matching private decryption key must **never** be placed on the shared VPS or in GitHub.

**Not installed or scheduled.** This is source-only preparation; validate VPS ownership, space, command availability and production impact before running it. A full dump causes disk reads and CPU work, so the execution window must be chosen to avoid affecting other client workloads. Do not run the restore-test script on the shared VPS.

The harmless cryptographic fixture can be checked locally with `bash scripts/dshinez-secure-backup/test-cms-roundtrip.sh`; it verifies authenticated round-trip and rejection of modified ciphertext but does **not** substitute for a real PostgreSQL restore acceptance test.

## One-time preparation (only after scoped access is verified)

1. On an independent trusted machine, generate a dedicated RSA-3072-or-stronger private key with a matching public X.509 encryption certificate using OpenSSL. Store the private key in secure offline custody, keep a second recovery copy offline, and validate authenticated encryption/decryption with a harmless fixture. Export **only the public certificate** to the VPS. Never transfer the private key onto the VPS.
2. On the VPS, create `/home/sourav/dshinez-backups` with permission `0700` and install the validated public certificate at `/home/sourav/.config/dshinez-backup/public-recipient.pem`. Pin its full SHA-256 file digest independently; do not use an unverified certificate. Do not create any directory outside Sourav’s area.
3. Verify the exact container `dshinez-db-1` belongs to Docker Compose project `dshinez`, service `db`, using read-only `docker inspect`. Confirm space, restore access and work scheduling. The script itself also validates those labels, requires free space exceeding the uncompressed database size plus a **5 GiB shared-host reserve**, and refuses concurrent runs.
4. Run `DSHINEZ_BACKUP_CERT_SHA256=<64-character-approved-digest> bash scripts/dshinez-secure-backup/backup-postgres.sh` from the D’Shinez checkout. Never run with shell tracing. It writes an authenticated encrypted `*.cms` archive and a checksum in Sourav’s backup directory, without creating an on-disk plaintext dump. Existing archives are not overwritten or deleted.

## Restore acceptance test (on isolated test machine)

1. Transfer the encrypted archive to a separate, isolated test machine over an approved protected channel. Bring the private decryption key from offline custody; keep it at mode `0600` only on that test machine. Verify the encrypted archive is stable.
2. On the isolated machine, with Docker and OpenSSL installed, run:

   ```bash
   DSHINEZ_ISOLATED_RESTORE_TEST=YES \
   DSHINEZ_ISOLATED_PUBLIC_CERT=/secure/public-recipient.pem \
   DSHINEZ_ISOLATED_PRIVATE_KEY=/secure/offline-private-key.pem \
     bash scripts/dshinez-secure-backup/verify-restore-isolated.sh /secure/backup.cms
   ```

3. The script first validates the CMS GCM authentication tag **before creating a database**, then starts a disposable `postgres:17-alpine` container **without networking** and on a temporary filesystem, streams decrypted bytes to `pg_restore --exit-on-error`, checks application table presence and deletes only that disposable test container. Never use a production database for this restore test.

## Limitations and gates

- A database dump does **not** include the `api_public` uploads volume, Redis state, keys, or unrelated files; those require a separately scoped protection and recovery plan.
- CMS backup encryption does not prove that the underlying live database volume is encrypted at rest. Database-at-rest encryption is a separate workstream.
- No backup retention/deletion job is included; preserve existing archives until a separate recovery policy is approved.
- The scripts are deliberately **not** wired into cron, Compose, CI or deployment. A live sign-off requires a successful encrypted production backup, encrypted archive verification, isolated restore, key custody review and peer-impact checks.
- If OpenSSL, Docker, permissions, disk space, or exclusive ownership are unavailable, stop. Do not change global VPS configuration or use a whole-VM restore as a workaround.

Official references: [PostgreSQL `pg_dump`](https://www.postgresql.org/docs/current/app-pgdump.html), [PostgreSQL `pg_restore`](https://www.postgresql.org/docs/current/app-pgrestore.html), [OpenSSL CMS](https://docs.openssl.org/3.5/man1/openssl-cms/).
