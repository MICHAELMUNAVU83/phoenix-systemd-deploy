# Customize this deployment for the repository

Give this file and the repository to your AI coding assistant, then use this
prompt:

> Customize the deployment files in this repository for this Phoenix
> application. Inspect `mix.exs`, `config/runtime.exs`, the router, release
> configuration, `.tool-versions`, the default Git branch, and existing CI
> files before editing. Update application-specific example values, the deploy
> branch, health-check path, required production environment variables, database
> examples, and documentation. If `rel/overlays/bin/server` or
> `rel/overlays/bin/migrate` is missing, run `mix phx.gen.release` locally and
> retain its generated release files. Preserve secrets as placeholders and
> never read, generate, commit, or print real credentials. Do not replace `@@APP_NAME@@`,
> `@@APP_DIR@@`, or `@@ENV_FILE@@` in `phoenix.service.tpl`; `deploy.sh` fills
> those values at deployment time. Keep `.env.prod` ignored and run relevant
> syntax or validation checks after making changes. Summarize every value that
> the operator must still configure in GitHub Actions or on the server.

## Files the AI should review

- `.deploy/.env.prod.example`
- `deploy.sh`
- `.deploy/phoenix.service.tpl`
- `.github/workflows/ci-deploy.yml`
- `.gitignore`
- `config/runtime.exs`
- `mix.exs`

## Expected result

The AI should leave the repository with:

- the correct deployment branch in the GitHub Actions workflow;
- committed Phoenix release server and migration scripts;
- a health endpoint that returns success without authentication;
- every required runtime variable documented in `.env.prod.example`;
- `.env.prod` listed in `.gitignore`;
- no real secret values in tracked files;
- commands and paths matching the target repository;
- executable `deploy.sh` and `.deploy/ci.sh` files.

Delete `rename.md` after the repository has been customized, or keep it as a
checklist for future deployment changes.
