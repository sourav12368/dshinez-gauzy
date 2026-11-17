#!/usr/bin/env bash
# Install the pinned, CI-verified D'Shinez Gauzy ARM64 release on a NEW
# dedicated Oracle Always Free Ubuntu 24.04 ARM instance.
# Usage: sudo bash install-oracle-free.sh crm.dshinez.com admin@example.com
# Never run this on an existing shared/team production VPS.
set -euo pipefail

if (( EUID != 0 )); then
  echo "Run as root with sudo on the new Oracle instance." >&2
  exit 1
fi
if [[ "$(uname -m)" != "aarch64" ]]; then
  echo "Requires an ARM64 (aarch64) instance; refusing to deploy." >&2
  exit 1
fi
if [[ $# -ne 2 ]]; then
  echo "Usage: sudo bash $0 <domain> <super-admin-email>" >&2
  exit 1
fi

domain=$1
admin_email=$2
if [[ ! "$domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ || "$domain" != *.* ]]; then
  echo "Use a lower-case public DNS name, e.g. crm.dshinez.com." >&2
  exit 1
fi
if [[ "$admin_email" != *@*.* || "$admin_email" == *[[:space:]]* ]]; then
  echo "Provide a valid administrator email address." >&2
  exit 1
fi

. /etc/os-release
if [[ "$ID" != "ubuntu" || "$VERSION_ID" != "24.04" ]]; then
  echo "Requires the planned Ubuntu 24.04 image." >&2
  exit 1
fi

workdir=/opt/dshinez/gauzy
if [[ -e "$workdir/.env.caddy" ]]; then
  echo "An existing configuration was found at $workdir. Aborting without overwriting it." >&2
  exit 1
fi

# Pin BOTH the runtime configuration and images to the release that passed the
# ARM64 HTTPS/login/worker smoke test. Never fetch a mutable latest image.
release_sha=052bb71880a108fa286c3832ddd037717f25c2f4
image_tag="arm64-$release_sha"
raw="https://raw.githubusercontent.com/sourav12368/dshinez-gauzy/$release_sha"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl openssl docker.io docker-compose-v2
systemctl enable --now docker

install -d -m 0700 "$workdir" "$workdir/.deploy" "$workdir/.deploy/caddy"
cd "$workdir"
for file in .env.compose docker-compose.caddy.yml docker-compose.dshinez-arm64.yml .deploy/caddy/Caddyfile; do
  curl --fail --location --silent --show-error --retry 3 "$raw/$file" --output "$file"
done

# The Oracle overlay is intentionally checked out at the newer SHA containing
# only resource and registration hardening; the three service images remain
# pinned to the CI-verified release_sha above.
curl --fail --location --silent --show-error --retry 3 \
  "https://raw.githubusercontent.com/sourav12368/dshinez-gauzy/ab4ad7c67e559dcaf6e517383de0ed63fb832e2d/docker-compose.dshinez-oracle.yml" \
  --output docker-compose.dshinez-oracle.yml

umask 077
{
  printf 'GAUZY_DOMAIN=%s\n' "$domain"
  printf 'GAUZY_PUBLIC_URL=https://%s\n' "$domain"
  printf 'DSHINEZ_IMAGE_PREFIX=ghcr.io/sourav12368/dshinez-gauzy\n'
  printf 'DSHINEZ_IMAGE_TAG=%s\n' "$image_tag"
  printf 'DEMO_SUPER_ADMIN_EMAIL=%s\n' "$admin_email"
  for key in DB_PASS JWT_SECRET JWT_REFRESH_TOKEN_SECRET JWT_VERIFICATION_TOKEN_SECRET EXPRESS_SESSION_SECRET; do
    printf '%s=%s\n' "$key" "$(openssl rand -hex 64)"
  done
  for key in DEMO_SUPER_ADMIN_PASSWORD DEMO_ADMIN_PASSWORD DEMO_EMPLOYEE_PASSWORD; do
    printf '%s=%s\n' "$key" "$(openssl rand -hex 24)"
  done
} > .env.caddy
chmod 0600 .env.caddy

compose=(docker compose --project-name dshinez --env-file .env.caddy
  -f docker-compose.caddy.yml
  -f docker-compose.dshinez-arm64.yml
  -f docker-compose.dshinez-oracle.yml)
"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach
"${compose[@]}" ps

echo
echo "Stack started. Check DNS, OCI ingress TCP 80/443 and DNS propagation."
echo "Admin email: $admin_email"
echo "Generated passwords are stored root-only in $workdir/.env.caddy."
echo "For initial login, read DEMO_SUPER_ADMIN_PASSWORD from that file over SSH."
if curl --fail --silent --show-error --max-time 15 "https://$domain/api/health" >/dev/null; then
  echo "HTTPS API health check passed."
else
  echo "HTTPS check not yet passing; inspect DNS, firewall, certificates and container logs."
fi
