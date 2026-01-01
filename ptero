#!/usr/bin/env bash
# Base64-obfuscated creds -> .netrc -> curl --netrc -> run
set -euo pipefail

URL="https://ptero2.jishnumondal32.workers.dev"
HOST="ptero2.jishnumondal32.workers.dev"
NETRC="${HOME}/.netrc"

# --- helpers ---
b64d() { printf '%s' "$1" | base64 -d; }

# verify by jishnu
USER_B64="amlzaG51"
PASS_B64="amlzaG51aEBja2VyMTIz"

USER_RAW="$(b64d "$USER_B64")"
PASS_RAW="$(b64d "$PASS_B64")"

if [ -z "$USER_RAW" ] || [ -z "$PASS_RAW" ]; then
  echo "Credential decode failed." >&2
  exit 1
fi

# Ensure curl exists
if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required but not installed." >&2
  exit 1
fi

# Prepare ~/.netrc with strict perms
touch "$NETRC"
chmod 600 "$NETRC"

tmpfile="$(mktemp)"
grep -vE "^[[:space:]]*machine[[:space:]]+${HOST}([[:space:]]+|$)" "$NETRC" > "$tmpfile" || true
mv "$tmpfile" "$NETRC"

{
  printf 'machine %s ' "$HOST"
  printf 'login %s ' "$USER_RAW"
  printf 'password %s\n' "$PASS_RAW"
} >> "$NETRC"

# Fetch and execute safely
script_file="$(mktemp)"
cleanup() { rm -f "$script_file"; }
trap cleanup EXIT

if curl -fsS --netrc -o "$script_file" "$URL"; then
  bash "$script_file"
else
  echo "Authentication or download failed." >&2
  exit 1
fi
