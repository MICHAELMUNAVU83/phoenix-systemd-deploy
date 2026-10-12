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

DEPLOY_BRANCH=""
if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REMOTE_DEFAULT="$(git -C "$TARGET_DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  REMOTE_DEFAULT="${REMOTE_DEFAULT#origin/}"
  CURRENT_BRANCH="$(git -C "$TARGET_DIR" branch --show-current 2>/dev/null || true)"

  if [[ "$REMOTE_DEFAULT" == "main" || "$REMOTE_DEFAULT" == "master" ]]; then
    DEPLOY_BRANCH="$REMOTE_DEFAULT"
  elif [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
    DEPLOY_BRANCH="$CURRENT_BRANCH"
  elif git -C "$TARGET_DIR" show-ref --verify --quiet refs/heads/main; then
    DEPLOY_BRANCH="main"
  elif git -C "$TARGET_DIR" show-ref --verify --quiet refs/heads/master; then
    DEPLOY_BRANCH="master"
  fi
fi

if [[ -n "$DEPLOY_BRANCH" ]]; then
  sed -i.bak "s|refs/heads/master|refs/heads/$DEPLOY_BRANCH|g" \
    "$TARGET_DIR/.github/workflows/ci-deploy.yml"
  rm "$TARGET_DIR/.github/workflows/ci-deploy.yml.bak"
  printf 'Deployment branch set to %s.\n' "$DEPLOY_BRANCH"
else
  printf '\033[1;33mWarning:\033[0m Could not detect main or master; the workflow currently deploys master.\n'
  printf 'Check .github/workflows/ci-deploy.yml before committing.\n'
fi

touch "$TARGET_DIR/.gitignore"
if ! grep -qxF '/.env.prod' "$TARGET_DIR/.gitignore"; then
  printf '\n# Production secrets (never commit this file)\n/.env.prod\n' >> "$TARGET_DIR/.gitignore"
fi
for ignore_rule in '.DS_Store' '*.bak' '/priv/static/cache_manifest.json'; do
  if ! grep -qxF "$ignore_rule" "$TARGET_DIR/.gitignore"; then
    printf '%s\n' "$ignore_rule" >> "$TARGET_DIR/.gitignore"
  fi
done

printf '\033[1;32mInstallation complete.\033[0m\n'
if [[ ! -f "$TARGET_DIR/rel/overlays/bin/server" || ! -f "$TARGET_DIR/rel/overlays/bin/migrate" ]]; then
  printf '\033[1;33mRelease setup needed:\033[0m run mix phx.gen.release locally, then commit its generated files.\n'
fi
printf 'Next: open %s/rename.md and follow its instructions.\n' "$TARGET_DIR"
