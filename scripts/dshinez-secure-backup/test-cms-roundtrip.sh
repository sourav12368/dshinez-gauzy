#!/usr/bin/env bash
# Local fixture test only: no Docker, production data, or real backup keys.
set -Eeuo pipefail
umask 077

for tool in openssl mktemp cmp; do command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }; done
work="$(mktemp -d)"
cleanup() { rm -r -- "$work"; }
trap cleanup EXIT

# The private key is generated on this temporary test machine only.
openssl req -new -x509 -newkey rsa:3072 -keyout "$work/private.pem" -out "$work/public.pem" \
  -nodes -days 1 -subj '/CN=dshinez-backup-test' >/dev/null 2>&1
printf 'INERT NONPRODUCTION TEST ARCHIVE\n' > "$work/plaintext"
openssl cms -encrypt -stream -binary -outform DER -aes-256-gcm \
  -recip "$work/public.pem" -in "$work/plaintext" -out "$work/ciphertext.cms"
openssl cms -decrypt -binary -inform DER -in "$work/ciphertext.cms" \
  -recip "$work/public.pem" -inkey "$work/private.pem" -out "$work/decrypted"
cmp --silent "$work/plaintext" "$work/decrypted"

# Tamper with the tag/ciphertext: GCM authentication must reject the altered archive.
cp -- "$work/ciphertext.cms" "$work/tampered.cms"
python3 -c 'import sys; p=sys.argv[1]; f=open(p,"r+b"); f.seek(-1,2); b=f.read(1); f.seek(-1,2); f.write(bytes([b[0]^1])); f.close()' "$work/tampered.cms"
if openssl cms -decrypt -binary -inform DER -in "$work/tampered.cms" \
  -recip "$work/public.pem" -inkey "$work/private.pem" -out /dev/null 2>/dev/null; then
  echo 'TAMPER TEST FAILED: modified ciphertext was accepted' >&2
  exit 1
fi
printf 'CMS AES-256-GCM fixture round-trip and tamper rejection: PASS\n'
