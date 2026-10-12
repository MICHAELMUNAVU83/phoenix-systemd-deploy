#!/usr/bin/env bash

# Run the exact checks used by the GitHub Actions workflow.

set -euo pipefail

APP_DIR="${1:-${APP_DIR:-$(pwd)}}"
APP_DIR="$(cd "$APP_DIR" && pwd)"
[[ -f "$APP_DIR/mix.exs" ]] || { echo "Not a Mix project: $APP_DIR" >&2; exit 1; }

export MIX_ENV=test

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

start_github_actions_database() {
  [[ "${GITHUB_ACTIONS:-false}" == "true" ]] || return 0
  command -v docker >/dev/null 2>&1 || fail "Docker is required to start the CI database"

  local database_engine="${CI_DATABASE_ENGINE:-auto}"
  if [[ "$database_engine" == "auto" ]]; then
    if grep -q '"myxql"' mix.lock; then
      database_engine="mysql"
    else
      database_engine="postgres"
    fi
  fi

  case "$database_engine" in
    postgres|postgresql)
      if docker ps --format '{{.Image}}' | grep -q '^postgres:'; then
        info "Using the PostgreSQL service already started by the workflow"
        return 0
      fi
      info "Starting PostgreSQL for CI"
      docker run --detach --name phoenix-ci-postgres \
        --env POSTGRES_USER=postgres \
        --env POSTGRES_PASSWORD=postgres \
        --publish 5432:5432 \
        postgres:16 >/dev/null
      for _ in {1..30}; do
        docker exec phoenix-ci-postgres pg_isready -U postgres >/dev/null 2>&1 && return 0
        sleep 2
      done
      docker logs phoenix-ci-postgres || true
      fail "PostgreSQL did not become ready"
      ;;
    mysql)
      if docker ps --format '{{.Image}}' | grep -q '^mysql:'; then
        info "Using the MySQL service already started by the workflow"
        return 0
      fi
      info "Starting MySQL for CI"
      docker run --detach --name phoenix-ci-mysql \
        --env MYSQL_ALLOW_EMPTY_PASSWORD=yes \
        --env MYSQL_ROOT_HOST=% \
        --publish 3306:3306 \
        mysql:8.4 >/dev/null
      for _ in {1..45}; do
        docker exec phoenix-ci-mysql mysqladmin ping --host=127.0.0.1 --user=root --silent \
          >/dev/null 2>&1 && return 0
        sleep 2
      done
      docker logs phoenix-ci-mysql || true
      fail "MySQL did not become ready"
      ;;
    *)
      fail "CI_DATABASE_ENGINE must be auto, postgres, postgresql, or mysql"
      ;;
  esac
}

cd "$APP_DIR"

start_github_actions_database

info "Installing dependencies"
mix deps.get

info "Checking formatting"
mix format --check-formatted

info "Compiling with warnings treated as errors"
mix compile --warnings-as-errors

info "Running tests"
mix test

ok "CI checks passed"
