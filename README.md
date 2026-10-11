# Phoenix systemd deploy

A small, repo-scoped deployment kit for Phoenix applications on Linux. Copy it
into each Phoenix repository and commit it with the application. Each repository
then owns its deployment scripts, systemd template, and CI workflow, so changes
can be reviewed and released together with the code they affect.

The kit builds a Mix release, runs database migrations, installs a user-level
systemd service, restarts the application, and checks that it responds over
HTTP. The same CI script is used locally and in GitHub Actions.

[⬇ **Download the repo-scoped folder (.zip)**](https://github.com/MICHAELMUNAVU83/phoenix-systemd-deploy/raw/main/download/phoenix-systemd-deploy.zip)

The download includes `rename.md`, which contains a ready-to-use prompt for an
AI coding assistant to customize the deployment for the target repository.

## Repository layout

After installation, each Phoenix repository should contain:

```text
my_app/
├── rename.md
├── deploy.sh
├── .deploy/
│   ├── .env.prod.example
│   ├── ci.sh
│   └── phoenix.service.tpl
├── .github/workflows/ci-deploy.yml
├── lib/
├── mix.exs
└── ...
```

`.deploy/` and the workflow are committed. The real `.env.prod` contains
secrets, lives at the application root on the server, and is never committed.

## 1. Add the kit to a Phoenix repository

Download and extract the folder above into the Phoenix repository, or copy the
files from this repository's `repo-template/` directory:

```bash
APP_REPO=/path/to/my_app

cp -R repo-template/. "$APP_REPO/"
chmod +x "$APP_REPO/deploy.sh" "$APP_REPO/.deploy/ci.sh"
```

Open `rename.md` in the target repository and give its prompt to your AI coding
assistant. Review the resulting changes before committing them.

Commit the copied files in the application repository:

```bash
cd "$APP_REPO"
git add deploy.sh .deploy .github/workflows/ci-deploy.yml rename.md
git commit -m "Add repo-scoped systemd deployment"
```

Repeat this copy step for each Phoenix application. Once copied, each
application's files are independent and can be customized for that application.

## 2. Prepare the server checkout

The server needs Linux with systemd, Erlang, Elixir, Git, curl, the
application's database, and any asset-build tools used by the application.
Deploy as a normal Linux user rather than root.

Clone only the application repository; a separate deployment-kit checkout is
not required:

```bash
cd ~
git clone YOUR_APPLICATION_REPOSITORY_URL
cd YOUR_APPLICATION_REPOSITORY_NAME
```

The Phoenix application must provide release commands at:

```text
_build/prod/rel/APP_NAME/bin/server
_build/prod/rel/APP_NAME/bin/migrate
```

If they are missing, run `mix phx.gen.release` in the application repository
and commit its output.

## 3. Create the production environment

On the server, copy the example to the application root and protect it:

```bash
cd ~/YOUR_APPLICATION_REPOSITORY_NAME
cp .deploy/.env.prod.example .env.prod
chmod 600 .env.prod
```

Add `.env.prod` to the application's `.gitignore`. It contains secrets and must
never be committed.

Generate `SECRET_KEY_BASE` once and keep it stable between deployments:

```bash
mix phx.gen.secret
```

If project dependencies are not installed yet, use `openssl rand -base64 64`.
Changing this value later invalidates existing signed cookies and sessions.

Edit `.env.prod` with the application's production values:

```bash
DATABASE_URL="ecto://STRONG_DATABASE_USERNAME:STRONG_DATABASE_PASSWORD@127.0.0.1/DATABASE_NAME"
SECRET_KEY_BASE="PASTE_THE_GENERATED_SECRET_HERE"
PHX_HOST="example.com"
PORT="4000"
POOL_SIZE="10"
FORCE_SSL="true"
```

Use `FORCE_SSL="false"` only while testing direct HTTP without an HTTPS reverse
proxy. Add every other runtime dependency to this file as well, for example:

```bash
FACE_SEARCH_URL="http://127.0.0.1:5000"
S3_BUCKET="my-production-bucket"
AWS_REGION="eu-west-1"
```

## 4. Verify the production database

This deployment process assumes the production database and its user already
exist and that `DATABASE_URL` contains working credentials. You do not need to
create the database as part of this deployment procedure.

The deployment script runs the release migration command (equivalent to
`mix ecto.migrate`) against the existing database. Migrations create and update
the application's tables, but they do not create the database, create database
users, or grant permissions.

## 5. Perform the first deployment

Run the repo-local script from the application root as the deployment user:

```bash
cd ~/YOUR_APPLICATION_REPOSITORY_NAME
./deploy.sh deploy
```

The app name is detected from `mix.exs`. For an app named `my_app`, the script
creates `~/.config/systemd/user/my_app.service`, builds and migrates the release,
then enables and starts the service.

Enable lingering once so the user service starts after a reboot without an
active SSH session:

```bash
sudo loginctl enable-linger deploy
loginctl show-user deploy --property=Linger
```

The expected output is `Linger=yes`. This is normally the only setup command
that requires root privileges.

## 6. Operate the service

Use systemd while logged in as the deployment user:

```bash
systemctl --user status my_app.service
systemctl --user restart my_app.service
journalctl --user -u my_app.service -f
```

Or use the simpler repo-local commands from the application root:

```bash
./deploy.sh up
./deploy.sh deploy
./deploy.sh status
```

`up` starts or restarts the existing release, `deploy` builds the release, runs
migrations, and restarts it, and `status` displays its systemd status. Use
`journalctl --user -u my_app.service -f` when you need live logs.

## 7. Deploy updates

```bash
cd ~/YOUR_APPLICATION_REPOSITORY_NAME
git pull --ff-only origin master
./deploy.sh deploy
```

The running service restarts only after the release builds and migrations
succeed. Because `.deploy/` belongs to the application repository, deployment
script changes arrive with the same pull as application changes.

## Configuration overrides

| Variable           | Default                                          |
| ------------------ | ------------------------------------------------ |
| `APP_DIR`          | Current directory                                |
| `APP_NAME`         | Detected from `mix.exs`                          |
| `SERVICE_NAME`     | `APP_NAME.service`                               |
| `ENV_FILE`         | `APP_DIR/.env.prod`                              |
| `SERVICE_TEMPLATE` | `.deploy/phoenix.service.tpl`                    |
| `HEALTH_PATH`      | `/`                                              |
| `PORT`             | `4000`, unless set in `.env.prod`                |

For example:

```bash
HEALTH_PATH=/health SERVICE_NAME=my-app.service ./deploy.sh deploy
```

## Run CI locally

From the application root, run the exact checks used by GitHub Actions:

```bash
./.deploy/ci.sh
```

The script runs `mix deps.get`, formatting checks, compilation with warnings as
errors, and the test suite.

## Configure GitHub Actions deployment

The copied workflow runs CI for pushes and pull requests. Deployment runs only
after CI succeeds on a push to `master`.

Add these secrets under **Application repository → Settings → Secrets and
variables → Actions**:

| Secret                | Description                                         |
| --------------------- | --------------------------------------------------- |
| `VPS_HOST`            | Server hostname or IP                               |
| `VPS_USER`            | Deployment user, such as `deploy`                   |
| `VPS_PORT`            | SSH port; optional, defaults to `22`                |
| `VPS_APP_PATH`        | Application checkout, such as `/home/deploy/my_app` |
| `VPS_SSH_PRIVATE_KEY` | Private SSH deployment key                          |
| `VPS_KNOWN_HOSTS`     | Verified SSH host-key lines                         |

No deployment-kit repository token, second Actions checkout, or separate
`VPS_DEPLOY_TOOL_PATH` is needed: CI and deployment both use the files committed
inside the application repository.

## What a deployment does

Running `./deploy.sh deploy`:

1. validates the Phoenix project and production environment;
2. creates or updates `~/.config/systemd/user/APP_NAME.service`;
3. reloads the user systemd manager;
4. fetches production dependencies and builds the release;
5. runs database migrations;
6. enables and restarts the service;
7. performs an HTTP health check;
8. prints recent journal logs if the health check fails.
