#!/usr/bin/env bash

# Commands:
#   ./deploy.sh commands          List all commands and their purpose.
#   ./deploy.sh local             Build and run a release using config/dev.exs.
#   ./deploy.sh deploy            Build, migrate, restart, check, and save a release.
#   ./deploy.sh up                Restart the existing production release.
#   ./deploy.sh status            Show the systemd service status.
#   ./deploy.sh releases          List saved production releases by number.
#   ./deploy.sh rollback NUMBER   Restore a saved release by its listed number.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${APP_DIR:-$(pwd)}"
COMMAND="${1:-deploy}"
if [[ "$COMMAND" == "local" ]]; then
  ENV_FILE="${ENV_FILE:-}"
else
  ENV_FILE="${ENV_FILE:-${APP_DIR}/.env.prod}"
fi
SERVICE_TEMPLATE="${SERVICE_TEMPLATE:-${SCRIPT_DIR}/.deploy/phoenix.service.tpl}"
HEALTH_PATH="${HEALTH_PATH:-/}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

load_config() {
  APP_DIR="$(cd "$APP_DIR" && pwd)"
  [[ -f "$APP_DIR/mix.exs" ]] || fail "APP_DIR is not a Phoenix project: $APP_DIR"

  if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi

  APP_NAME="${APP_NAME:-$(sed -nE 's/.*app: :([a-z0-9_]+).*/\1/p' "$APP_DIR/mix.exs" | head -1)}"
  [[ -n "$APP_NAME" ]] || fail "Set APP_NAME or add an app: entry to mix.exs"

  SERVICE_NAME="${SERVICE_NAME:-${APP_NAME}.service}"
  PORT="${PORT:-4000}"
  RELEASES_TO_KEEP="${RELEASES_TO_KEEP:-5}"
  [[ "$RELEASES_TO_KEEP" =~ ^[1-9][0-9]*$ ]] || fail "RELEASES_TO_KEEP must be a positive whole number"
  RELEASE_ROOT="$APP_DIR/_build/prod/rel/$APP_NAME"
  RELEASE_BIN="$RELEASE_ROOT/bin"
  RELEASES_DIR="${RELEASES_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/phoenix-systemd-deploy/$APP_NAME/releases}"
  USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  UNIT_FILE="$USER_UNIT_DIR/$SERVICE_NAME"
}

require_production_env() {
  [[ -f "$ENV_FILE" ]] || fail "Missing production environment file: $ENV_FILE"
  [[ -n "${DATABASE_URL:-}" ]] || fail "DATABASE_URL is missing from $ENV_FILE"
  [[ -n "${SECRET_KEY_BASE:-}" ]] || fail "SECRET_KEY_BASE is missing from $ENV_FILE"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

install_service() {
  command -v systemctl >/dev/null 2>&1 || fail "systemctl is required"
  [[ -f "$SERVICE_TEMPLATE" ]] || fail "Missing service template: $SERVICE_TEMPLATE"

  local escaped_app_dir escaped_env_file escaped_app_name
  escaped_app_dir="$(escape_sed_replacement "$APP_DIR")"
  escaped_env_file="$(escape_sed_replacement "$ENV_FILE")"
  escaped_app_name="$(escape_sed_replacement "$APP_NAME")"

  mkdir -p "$USER_UNIT_DIR"
  sed \
    -e "s|@@APP_DIR@@|$escaped_app_dir|g" \
    -e "s|@@ENV_FILE@@|$escaped_env_file|g" \
    -e "s|@@APP_NAME@@|$escaped_app_name|g" \
    "$SERVICE_TEMPLATE" > "$UNIT_FILE"

  systemctl --user daemon-reload
  ok "Installed $UNIT_FILE"
}

build_release() {
  info "Building $APP_NAME release"
  (
    cd "$APP_DIR"
    export MIX_ENV=prod
    mix local.hex --force --if-missing
    mix local.rebar --force --if-missing
    mix deps.get --only prod
    mix compile
    mix assets.deploy
    mix release --overwrite
  )
  [[ -x "$RELEASE_BIN/server" ]] || fail "Release did not create $RELEASE_BIN/server"
  ok "Release built"
}

migrate() {
  [[ -x "$RELEASE_BIN/migrate" ]] || fail "Release migration command is missing"
  info "Running database migrations"
  "$RELEASE_BIN/migrate"
  ok "Migrations complete"
}

restart_service() {
  info "Starting $SERVICE_NAME"
  systemctl --user enable "$SERVICE_NAME" >/dev/null
  systemctl --user restart "$SERVICE_NAME"
}

health_check() {
  local url="http://127.0.0.1:${PORT}${HEALTH_PATH}"
  info "Checking $url"

  for _ in {1..30}; do
    if curl --silent --show-error --fail --max-time 3 "$url" >/dev/null; then
      ok "Deployment is healthy"
      return 0
    fi
    sleep 2
  done

  journalctl --user -u "$SERVICE_NAME" -n 100 --no-pager || true
  return 1
}

list_releases() {
  local number=0 release_path
  [[ -d "$RELEASES_DIR" ]] || { info "No saved releases"; return 0; }

  printf 'NUMBER  RELEASE\n'
  while IFS= read -r release_path; do
    number=$((number + 1))
    printf '%-7s %s\n' "$number" "$(basename "$release_path")"
  done < <(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -print | sort -r)

  [[ "$number" -gt 0 ]] || info "No saved releases"
}

save_release() {
  local release_id commit release_path number=0 old_path
  [[ -d "$RELEASE_ROOT" ]] || fail "Cannot save missing release: $RELEASE_ROOT"

  commit="$(git -C "$APP_DIR" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  release_id="$(date -u +%Y%m%dT%H%M%SZ)-$commit"
  release_path="$RELEASES_DIR/$release_id"
  [[ ! -e "$release_path" ]] || release_path="${release_path}-$$"

  mkdir -p "$RELEASES_DIR"
  cp -a "$RELEASE_ROOT" "$release_path"
  ok "Saved release $(basename "$release_path")"

  while IFS= read -r old_path; do
    number=$((number + 1))
    if [[ "$number" -gt "$RELEASES_TO_KEEP" ]]; then
      [[ "$old_path" == "$RELEASES_DIR/"* ]] || fail "Refusing to prune unexpected path: $old_path"
      rm -rf -- "$old_path"
    fi
  done < <(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -print | sort -r)
}

rollback_release() {
  local selection="$1" selected_path active_backup staged_release number=0 release_path
  [[ "$selection" =~ ^[1-9][0-9]*$ ]] || fail "Choose a release number shown by: ./deploy.sh releases"
  [[ -d "$RELEASE_ROOT" ]] || fail "Active release is missing: $RELEASE_ROOT"

  while IFS= read -r release_path; do
    number=$((number + 1))
    if [[ "$number" == "$selection" ]]; then
      selected_path="$release_path"
      break
    fi
  done < <(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -r)
  [[ -n "${selected_path:-}" ]] || fail "Release number $selection does not exist"

  require_production_env
  install_service
  staged_release="${RELEASE_ROOT}.rollback.$$"
  active_backup="${RELEASE_ROOT}.before-rollback.$$"
  cp -a "$selected_path" "$staged_release"
  mv "$RELEASE_ROOT" "$active_backup"
  mv "$staged_release" "$RELEASE_ROOT"

  if restart_service && health_check; then
    rm -rf -- "$active_backup"
    ok "Rolled back to $(basename "$selected_path")"
  else
    mv "$RELEASE_ROOT" "$staged_release"
    mv "$active_backup" "$RELEASE_ROOT"
    restart_service || true
    rm -rf -- "$staged_release"
    fail "Rollback health check failed; restored the previous active release"
  fi
}

deploy() {
  require_production_env
  install_service
  build_release
  migrate
  restart_service
  health_check || fail "Health check failed"
  save_release
}

run_local() {
  local local_release_bin="$APP_DIR/_build/dev/rel/$APP_NAME/bin"

  info "Building $APP_NAME development release using config/dev.exs"
  if ! (
    cd "$APP_DIR"
    export MIX_ENV=dev
    mix deps.get
    mix compile
    mix assets.deploy
    mix release --overwrite
  ); then
    (cd "$APP_DIR" && MIX_ENV=dev mix phx.digest.clean --all) || true
    fail "Development release build failed"
  fi
  (cd "$APP_DIR" && MIX_ENV=dev mix phx.digest.clean --all) || true
  [[ -x "$local_release_bin/server" ]] || fail "Development release did not create $local_release_bin/server"
  [[ -x "$local_release_bin/migrate" ]] || fail "Development release migration command is missing"

  info "Running migrations with the config/dev.exs database settings"
  "$local_release_bin/migrate"
  info "Starting $APP_NAME development release locally on port $PORT"
  info "Press Ctrl-C to stop it"
  exec "$local_release_bin/server"
}

usage() {
  cat <<'EOF'
Usage: ./deploy.sh [commands|local|up|deploy|status|releases|rollback NUMBER]

Commands:
  commands          List these commands without running a deployment.
  local             Build, migrate, and run a development release using
                    config/dev.exs. Does not use systemd.
  deploy            Build the production release, run migrations, restart the
                    service, check health, and save a release snapshot.
  up                Install/update the service definition and restart the
                    existing production release without rebuilding it.
  status            Show the systemd user-service status.
  releases          List saved production releases. Number 1 is the newest.
  rollback NUMBER   Restore a release shown by the releases command.

The default command is deploy. Set APP_DIR when the Phoenix application is not
the current directory, for example:

  APP_DIR=/srv/my_app ./deploy.sh deploy
EOF
}

if [[ "${1:-}" == "commands" || "${1:-}" == "help" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

load_config

case "$COMMAND" in
  deploy) deploy ;;
  local) run_local ;;
  up)
    require_production_env
    install_service
    restart_service
    health_check || fail "Health check failed"
    ;;
  status) systemctl --user status "$SERVICE_NAME" ;;
  releases) list_releases ;;
  rollback) rollback_release "${2:-}" ;;
  *) usage; exit 1 ;;
esac
