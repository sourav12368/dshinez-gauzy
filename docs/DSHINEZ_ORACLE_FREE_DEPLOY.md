# D'Shinez Gauzy — Oracle Always Free deployment

Status (17 November 2026): **NOT LIVE**. Public TCP 80/443 rules are now saved and verified; no VM has been allocated. Oracle Hyderabad AD-1 returned
`Out of capacity for shape VM.Standard.A1.Flex` for both 2 OCPU/12 GB
and 1 OCPU/6 GB requests; an intermediate request also hit a temporary
user rate limit. Do not claim a VPS or public address has been allocated.

## Verified assets

- Repository: `sourav12368/dshinez-gauzy`, deployment branch `dshinez-arm64`.
- CI-verified release: `052bb71880a108fa286c3832ddd037717f25c2f4`.
- Successful ARM64 build, HTTPS/login/worker smoke test, and GHCR image
  publication: https://github.com/sourav12368/dshinez-gauzy/actions/runs/44016822173
- OCI home region: `ap-hyderabad-1`, availability domain AD-1.
- VCN `dshinez-gauzy-vcn`: `10.0.0.0/16`.
- Regional public subnet `dshinez-gauzy-public`: `10.0.0.0/24`.
- Internet gateway `dshinez-gauzy-igw`; VCN default route
  `0.0.0.0/0` points to the gateway.
- Planned VM: `dshinez-gauzy-arm64`, Ubuntu 24.04 Minimal aarch64,
  `VM.Standard.A1.Flex` (2 OCPU / 12 GB selected in a new request,
  but not submitted after the Oracle browser stalled), 100 GB boot volume
  at 10 VPUs, public IPv4, automatic fault domain.
- User reported saving the generated SSH private key
  corresponding to `ssh-key-2026-11-17`. Never place the key in Git.

The OCI Always Free service includes 2 OCPUs/12 GB of Ampere A1 in
the home region and 200 GB of combined boot/block storage. Keep within
these combined limits; do not upgrade the tenancy or use paid shapes.

## Launch checklist

1. Wait for A1 capacity to become available. Do not hammer the Create
   endpoint when it reports rate limiting. Confirm an instance is
   actually in Running state and note its public IPv4 address.
2. **Done:** Stateful TCP ingress from `0.0.0.0/0` to ports **80** and
   **443** was saved and verified in the VCN default security list.
   Existing SSH/ICMP rules were preserved.
3. Create a DNS A record for the intended host
   `crm.dshinez.com` pointing to the new instance's public IP. Do
   not change existing `www` or apex DNS records.
4. On the *new dedicated OCI ARM64 VM*, connect with the matching SSH
   private key as `ubuntu`. Run the repo's pinned bootstrap:
   `sudo bash tools/dshinez/install-oracle-free.sh crm.dshinez.com <admin-email>`.
   The installer is intended only for a dedicated fresh instance and
   will install Docker and deploy PostgreSQL, Redis, API, worker,
   Angular web app and Caddy. If the GHCR packages are private,
   authorize package access; never add tokens to the repository.
5. Retrieve the generated `DEMO_SUPER_ADMIN_PASSWORD` securely via
   SSH from the root-readable `/opt/dshinez/gauzy/.env.caddy`.
   Verify `https://crm.dshinez.com/api/health`, HTTPS certificate,
   web app branding, login, invitation flow, background worker and
   persistent data after restart.
6. Configure encrypted backups, monitoring, and an update/rollback
   procedure before relying on Gauzy for production operations.

## Stack implementation

- Base: `docker-compose.caddy.yml`.
- Verified ARM image override: `docker-compose.dshinez-arm64.yml`.
- Oracle security/memory override: `docker-compose.dshinez-oracle.yml`.
- Bootstrap: `tools/dshinez/install-oracle-free.sh`.
- The installation generates unique production JWT/session secrets,
  PostgreSQL password, and seeded-account passwords locally on the VM;
  none are committed or sent to GitHub.

The exact OCI firewall and DNS configuration must be verified before
telling staff the software is live. An OCI public IPv4 address does
not exist until the VM is allocated.
