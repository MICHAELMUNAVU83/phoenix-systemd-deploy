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

INSTALL_MODE="fresh"
if [[ -e "$TARGET_DIR/deploy.sh" && -e "$TARGET_DIR/.deploy/ci.sh" ]]; then
  INSTALL_MODE="update"
elif [[ -e "$TARGET_DIR/deploy.sh" || -e "$TARGET_DIR/.deploy/ci.sh" ]]; then
  fail "Found a partial or conflicting installation; expected both deploy.sh and .deploy/ci.sh."
fi

if [[ "$INSTALL_MODE" == "fresh" ]]; then
  for path in \
    README-FIRST.md \
    .deploy/.env.prod.example \
    .deploy/phoenix.service.tpl \
    .github/workflows/ci-deploy.yml; do
    [[ ! -e "$TARGET_DIR/$path" ]] || fail "$path already exists; installation stopped without overwriting it."
  done
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

printf 'Downloading Phoenix systemd deployment kit...\n'
CACHE_BUSTED_URL="$DOWNLOAD_URL"
if [[ "$DOWNLOAD_URL" == https://github.com/* || "$DOWNLOAD_URL" == https://raw.githubusercontent.com/* ]]; then
  CACHE_BUSTED_URL="${DOWNLOAD_URL}?cache_bust=$(date +%s)"
fi
curl --fail --silent --show-error --location "$CACHE_BUSTED_URL" \
  --output "$TEMP_DIR/phoenix-systemd-deploy.zip"

mkdir -p "$TEMP_DIR/kit"
unzip -q "$TEMP_DIR/phoenix-systemd-deploy.zip" -d "$TEMP_DIR/kit"

if [[ "$INSTALL_MODE" == "update" ]]; then
  mkdir -p "$TARGET_DIR/.deploy"
  cp "$TEMP_DIR/kit/deploy.sh" "$TARGET_DIR/deploy.sh"
  cp "$TEMP_DIR/kit/.deploy/ci.sh" "$TARGET_DIR/.deploy/ci.sh"

  WORKFLOW_FILE="$TARGET_DIR/.github/workflows/ci-deploy.yml"
  if [[ -f "$WORKFLOW_FILE" ]] && ! grep -qE '^[[:space:]]*workflow_dispatch:' "$WORKFLOW_FILE"; then
    if grep -qE '^  pull_request:[[:space:]]*$' "$WORKFLOW_FILE" && \
      { grep -qF "    if: github.event_name == 'push' && github.ref == 'refs/heads/main'" "$WORKFLOW_FILE" || \
        grep -qF "    if: github.event_name == 'push' && github.ref == 'refs/heads/master'" "$WORKFLOW_FILE"; }; then
      awk '
        /^  pull_request:[[:space:]]*$/ {
          print
          print "  workflow_dispatch:"
          next
        }
        $0 == "    if: github.event_name == '\''push'\'' && github.ref == '\''refs/heads/main'\''" ||
        $0 == "    if: github.event_name == '\''push'\'' && github.ref == '\''refs/heads/master'\''" {
          condition = substr($0, 9)
          print "    if: >-"
          print "      (" condition ") ||"
          print "      github.event_name == '\''workflow_dispatch'\''"
          next
        }
        { print }
      ' "$WORKFLOW_FILE" > "$WORKFLOW_FILE.bak"
      mv "$WORKFLOW_FILE.bak" "$WORKFLOW_FILE"
      printf 'Added manual Run workflow support to .github/workflows/ci-deploy.yml.\n'
    else
      printf '\033[1;33mWarning:\033[0m The existing CI workflow is customized; add workflow_dispatch manually.\n'
    fi
  fi
  printf 'Updated deploy.sh and .deploy/ci.sh; preserved customized deployment files.\n'
else
  cp -R "$TEMP_DIR/kit/." "$TARGET_DIR/"
fi
chmod +x "$TARGET_DIR/deploy.sh" "$TARGET_DIR/.deploy/ci.sh"
grep -qF './deploy.sh commands' "$TARGET_DIR/deploy.sh" || fail "Downloaded deploy.sh failed the version check"

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

if [[ "$INSTALL_MODE" == "fresh" && -n "$DEPLOY_BRANCH" ]]; then
  sed -i.bak "s|refs/heads/master|refs/heads/$DEPLOY_BRANCH|g" \
    "$TARGET_DIR/.github/workflows/ci-deploy.yml"
  rm "$TARGET_DIR/.github/workflows/ci-deploy.yml.bak"
  printf 'Deployment branch set to %s.\n' "$DEPLOY_BRANCH"
elif [[ "$INSTALL_MODE" == "fresh" ]]; then
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

if [[ "$INSTALL_MODE" == "update" ]]; then
  printf '\033[1;32mScript update complete.\033[0m\n'
  printf 'Available commands:\n'
  "$TARGET_DIR/deploy.sh" commands
else
  printf '\033[1;32mInstallation complete.\033[0m\n'
fi
if [[ ! -f "$TARGET_DIR/rel/overlays/bin/server" || ! -f "$TARGET_DIR/rel/overlays/bin/migrate" ]]; then
  printf '\033[1;33mRelease setup needed:\033[0m run mix phx.gen.release locally, then commit its generated files.\n'
fi
if [[ "$INSTALL_MODE" == "fresh" ]]; then
  printf 'Next: run %s/deploy.sh commands and follow the setup guide.\n' "$TARGET_DIR"
else
  printf 'Review the updates with: git diff -- deploy.sh .deploy/ci.sh .github/workflows/ci-deploy.yml\n'
fi
