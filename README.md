# Phoenix systemd deploy

A reusable deployment kit for Phoenix applications on Linux. It builds a Mix
release, runs database migrations, installs a user-level systemd service,
restarts the application, and checks that it responds over HTTP.

The same `ci.sh` script is used locally and by the included GitHub Actions
workflow, so you can run the exact CI checks before pushing.

## What a deployment does

Running `deploy.sh deploy`:

1. validates the Phoenix project and production environment;
2. creates or updates `~/.config/systemd/user/APP_NAME.service`;
3. reloads the user systemd manager;
4. fetches production dependencies and builds the release;
5. runs database migrations;
6. enables and restarts the service;
7. performs an HTTP health check;
8. prints recent journal logs if the health check fails.

## Requirements

The server needs Linux with systemd, Erlang, Elixir, Git, curl, the application's
database, and any asset-build tools used by the application. Deploy as a normal
Linux user rather than root.

The Phoenix application must provide release commands at:

```text
_build/prod/rel/APP_NAME/bin/server
_build/prod/rel/APP_NAME/bin/migrate
```

If they are missing, run `mix phx.gen.release` in the application repository
and commit its output.

## 1. Install the deployment kit and application

The kit can live outside the Phoenix application and deploy multiple apps:

```bash
git clone YOUR_DEPLOY_KIT_REPOSITORY_URL /home/deploy/phoenix-systemd-deploy
chmod +x /home/deploy/phoenix-systemd-deploy/deploy.sh
chmod +x /home/deploy/phoenix-systemd-deploy/ci.sh

git clone YOUR_APPLICATION_REPOSITORY_URL /home/deploy/my_app
```

In this guide, `deploy` is the Linux user, `/home/deploy/my_app` is the Phoenix
application, and `/home/deploy/phoenix-systemd-deploy` is this kit. Both
directories should belong to the deployment user.

## 2. Create the production environment

Copy the template into the Phoenix application and protect it:

```bash
cp /home/deploy/phoenix-systemd-deploy/.env.prod.example \
  /home/deploy/my_app/.env.prod
chmod 600 /home/deploy/my_app/.env.prod
```

Add `.env.prod` to the application's `.gitignore`. It contains secrets and must
never be committed.

### Generate `SECRET_KEY_BASE`

Generate a secure secret from the application directory:

```bash
cd /home/deploy/my_app
mix phx.gen.secret
```

Copy the complete output into `.env.prod`. Generate this once and keep it stable
between deployments. Changing it invalidates existing signed cookies and
sessions.

If project dependencies are not installed yet, you can instead use:

```bash
openssl rand -base64 64
```

### Edit `.env.prod`

```bash
DATABASE_URL="ecto://my_app:STRONG_DATABASE_PASSWORD@127.0.0.1/my_app_prod"
SECRET_KEY_BASE="PASTE_THE_GENERATED_SECRET_HERE"
PHX_HOST="example.com"
PORT="4000"
POOL_SIZE="10"
FORCE_SSL="true"
```

Use `FORCE_SSL="false"` only while testing direct HTTP without an HTTPS reverse
proxy. For production behind Nginx or Caddy, use `FORCE_SSL="true"`.

Add every runtime dependency to this file too:

```bash
FACE_SEARCH_URL="http://127.0.0.1:5000"
S3_BUCKET="my-production-bucket"
AWS_REGION="eu-west-1"
```

Test local supporting services before deployment:

```bash
curl --fail http://127.0.0.1:5000/health
```

An incorrect URL or stopped dependency commonly appears as
`Req.TransportError` with `:econnrefused`.

## 3. Prepare the database

Create a production database and dedicated user. A typical PostgreSQL setup is:

```sql
CREATE USER my_app WITH PASSWORD 'STRONG_DATABASE_PASSWORD';
CREATE DATABASE my_app_prod OWNER my_app;
```

Ensure `DATABASE_URL` uses those credentials. The deployment script runs
migrations but intentionally does not create database users or grant access.

## 4. Perform the first deployment

Run this as the deployment user:

```bash
APP_DIR=/home/deploy/my_app \
  /home/deploy/phoenix-systemd-deploy/deploy.sh deploy
```

The app name is detected from `mix.exs`. For an app named `my_app`, the script
creates `~/.config/systemd/user/my_app.service`, reloads systemd, builds and
migrates the release, then enables and starts the service. You do not need to
copy or link the service file manually.

## 5. Start the service automatically after reboot

Enable lingering once so the user service runs without an active SSH session
and starts after a reboot:

```bash
sudo loginctl enable-linger deploy
loginctl show-user deploy --property=Linger
```

The expected output is `Linger=yes`. This is normally the only setup command
that requires root privileges.

## 6. Start, stop, and inspect the service

Use systemd while logged in as the deployment user:

```bash
systemctl --user status my_app.service
systemctl --user start my_app.service
systemctl --user stop my_app.service
systemctl --user restart my_app.service
systemctl --user enable my_app.service
systemctl --user disable my_app.service
```

Follow logs or show the most recent 100 lines:

```bash
journalctl --user -u my_app.service -f
journalctl --user -u my_app.service -n 100 --no-pager
```

The deployment kit also provides shortcuts:

```bash
APP_DIR=/home/deploy/my_app /home/deploy/phoenix-systemd-deploy/deploy.sh status
APP_DIR=/home/deploy/my_app /home/deploy/phoenix-systemd-deploy/deploy.sh logs
APP_DIR=/home/deploy/my_app /home/deploy/phoenix-systemd-deploy/deploy.sh restart
```

## 7. Deploy updates

```bash
git -C /home/deploy/my_app pull --ff-only origin master

APP_DIR=/home/deploy/my_app \
  /home/deploy/phoenix-systemd-deploy/deploy.sh deploy
```

The running service restarts only after the release builds and migrations
succeed.

## Configuration overrides

These shell variables customize a deployment:

| Variable | Default |
| --- | --- |
| `APP_DIR` | Current directory |
| `APP_NAME` | Detected from `mix.exs` |
| `SERVICE_NAME` | `APP_NAME.service` |
| `ENV_FILE` | `APP_DIR/.env.prod` |
| `HEALTH_PATH` | `/` |
| `PORT` | `4000`, unless set in `.env.prod` |

For example:

```bash
APP_DIR=/home/deploy/my_app \
HEALTH_PATH=/health \
SERVICE_NAME=my-app.service \
  /home/deploy/phoenix-systemd-deploy/deploy.sh deploy
```

## Run CI locally before pushing

Run the exact checks used by GitHub Actions:

```bash
/home/deploy/phoenix-systemd-deploy/ci.sh /home/deploy/my_app
```

The script runs `mix deps.get`, formatting checks, compilation with warnings as
errors, and the test suite. Fix all failures before pushing.

## Configure GitHub Actions

Copy the workflow template into the Phoenix application:

```bash
mkdir -p /home/deploy/my_app/.github/workflows
cp /home/deploy/phoenix-systemd-deploy/github-workflows/ci-deploy.yml \
  /home/deploy/my_app/.github/workflows/ci-deploy.yml
```

Replace `YOUR_ORG/phoenix-systemd-deploy` inside the copied workflow with the
GitHub repository containing this kit, then commit the workflow. CI runs for
pushes and pull requests. Deployment runs only after CI succeeds on a push to
`master`.

Add these secrets under **Application repository → Settings → Secrets and
variables → Actions**:

| Secret | Description |
| --- | --- |
| `VPS_HOST` | Server hostname or IP |
| `VPS_USER` | Deployment user, such as `deploy` |
| `VPS_PORT` | SSH port; optional, defaults to `22` |
| `VPS_APP_PATH` | `/home/deploy/my_app` |
| `VPS_DEPLOY_TOOL_PATH` | `/home/deploy/phoenix-systemd-deploy` |
| `VPS_SSH_PRIVATE_KEY` | Private SSH deployment key |
| `VPS_KNOWN_HOSTS` | Verified SSH host-key lines |

A private deployment-kit repository needs a token or deploy key for the second
checkout in the workflow. A public kit repository needs no extra credential.

## Troubleshooting

### Service does not start

```bash
systemctl --user status my_app.service
journalctl --user -u my_app.service -n 100 --no-pager
ls -l /home/deploy/my_app/_build/prod/rel/my_app/bin/server
```

### `Failed to connect to bus`

Run systemd commands as the deployment user. Log in directly over SSH and
confirm that lingering is enabled.

### Health check fails

```bash
grep '^PORT=' /home/deploy/my_app/.env.prod
curl --verbose http://127.0.0.1:4000/
```

Set `HEALTH_PATH=/health` when deploying if the application uses a dedicated
health endpoint.

### External service returns `:econnrefused`

Verify its URL in `.env.prod`, confirm its process is running, and test its
listening port directly:

```bash
systemctl --user status FACE_SERVICE_NAME.service
curl --verbose http://127.0.0.1:5000/health
```

Restarting Phoenix cannot repair a separate service that is stopped or bound to
the wrong interface or port.
