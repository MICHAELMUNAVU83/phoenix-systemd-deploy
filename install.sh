#!/usr/bin/env bash

set -euo pipefail

DOWNLOAD_URL="${PHOENIX_DEPLOY_DOWNLOAD_URL:-https://github.com/MICHAELMUNAVU83/phoenix-systemd-deploy/raw/main/download/phoenix-systemd-deploy.zip}"
TARGET_DIR="${1:-$(pwd)}"

fail() {
  printf '\033[1;31mError:\033[0m %s\n' "$*" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v unzip >/dev/null 2>&1 || fail "unzip is required"

TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
[[ -f "$TARGET_DIR/mix.exs" ]] || fail "Run this command from a Phoenix project (mix.exs was not found)."

for path in \
  deploy.sh \
  rename.md \
  README-FIRST.md \
  .deploy/.env.prod.example \
  .deploy/ci.sh \
  .deploy/phoenix.service.tpl \
  .github/workflows/ci-deploy.yml; do
  [[ ! -e "$TARGET_DIR/$path" ]] || fail "$path already exists; installation stopped without overwriting it."
done

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

printf 'Downloading Phoenix systemd deployment kit...\n'
curl --fail --silent --show-error --location "$DOWNLOAD_URL" \
  --output "$TEMP_DIR/phoenix-systemd-deploy.zip"

unzip -q "$TEMP_DIR/phoenix-systemd-deploy.zip" -d "$TARGET_DIR"
chmod +x "$TARGET_DIR/deploy.sh" "$TARGET_DIR/.deploy/ci.sh"

touch "$TARGET_DIR/.gitignore"
if ! grep -qxF '/.env.prod' "$TARGET_DIR/.gitignore"; then
  printf '\n# Production secrets (never commit this file)\n/.env.prod\n' >> "$TARGET_DIR/.gitignore"
fi

printf '\033[1;32mInstallation complete.\033[0m\n'
printf 'Next: open %s/rename.md and follow its instructions.\n' "$TARGET_DIR"
