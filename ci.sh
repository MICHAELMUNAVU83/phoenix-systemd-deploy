#!/usr/bin/env bash

# Run the exact checks used by the GitHub Actions workflow.

set -euo pipefail

APP_DIR="${1:-${APP_DIR:-$(pwd)}}"
APP_DIR="$(cd "$APP_DIR" && pwd)"
[[ -f "$APP_DIR/mix.exs" ]] || { echo "Not a Mix project: $APP_DIR" >&2; exit 1; }

export MIX_ENV=test

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m✓\033[0m %s\n' "$*"; }

cd "$APP_DIR"

info "Installing dependencies"
mix deps.get

info "Checking formatting"
mix format --check-formatted

info "Compiling with warnings treated as errors"
mix compile --warnings-as-errors

info "Running tests"
mix test

ok "CI checks passed"
