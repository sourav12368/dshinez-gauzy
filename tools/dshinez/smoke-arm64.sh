#!/usr/bin/env bash
set -euo pipefail

env_file=$(mktemp)
compose=(docker compose --env-file "$env_file" -p dshinez-arm64-smoke
  -f docker-compose.caddy.yml -f docker-compose.dshinez-arm64.yml)
cleanup() {
  status=$?
  if (( status != 0 )); then
    "${compose[@]}" ps -a
    "${compose[@]}" logs --tail 100
  fi
  "${compose[@]}" down --volumes || true
  rm -f "$env_file"
  exit "$status"
}
trap cleanup EXIT

for service in api worker webapp; do
  image="$DSHINEZ_IMAGE_PREFIX/$service:$DSHINEZ_IMAGE_TAG"
  [[ $(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image") == "${DSHINEZ_IMAGE_PLATFORM:-linux/arm64}" ]]
done

admin_email=arm-smoke@example.com
admin_password=$(openssl rand -hex 24)
{
  printf 'GAUZY_HTTP_PORT=8080\nGAUZY_HTTPS_PORT=8443\n'
  printf 'GAUZY_PUBLIC_URL=https://localhost:8443\n'
  printf 'DEMO_SUPER_ADMIN_EMAIL=%s\nDEMO_SUPER_ADMIN_PASSWORD=%s\n' "$admin_email" "$admin_password"
  for key in DB_PASS JWT_SECRET JWT_REFRESH_TOKEN_SECRET JWT_VERIFICATION_TOKEN_SECRET EXPRESS_SESSION_SECRET; do
    printf '%s=%s\n' "$key" "$(openssl rand -hex 64)"
  done
  for key in DEMO_ADMIN_PASSWORD DEMO_EMPLOYEE_PASSWORD; do
    printf '%s=%s\n' "$key" "$(openssl rand -hex 24)"
  done
} > "$env_file"

"${compose[@]}" up --detach
base_url=https://localhost:8443
# Caddy uses its local test CA for localhost.
request=(curl --insecure --fail --silent --show-error --max-time 15)
for path in /api/health /; do
  "${request[@]}" --retry 60 --retry-delay 5 --retry-all-errors "$base_url$path" > /dev/null
done
page=$("${request[@]}" "$base_url/")
[[ $page == *assets/branding/dshinez/theme.css* ]]
cmp apps/gauzy/src/assets/branding/dshinez/theme.css \
  <("${request[@]}" "$base_url/assets/branding/dshinez/theme.css")

login_body=$(jq -cn --arg email "$admin_email" --arg password "$admin_password" '{email:$email,password:$password}')
token=$("${request[@]}" --json "$login_body" "$base_url/api/auth/login" | jq -er '.token | strings | select(length > 0)')
"${request[@]}" -H "Authorization: Bearer $token" "$base_url/api/user/me" | jq -e --arg email "$admin_email" '.email == $email'
worker_id=$("${compose[@]}" ps -q worker)
[[ -n $worker_id ]]
[[ $(docker inspect --format '{{.State.Running}} {{.RestartCount}}' "$worker_id") == 'true 0' ]]
