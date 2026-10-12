# Phoenix systemd deploy

A small, repo-scoped deployment kit for Phoenix applications on Linux. Install
it into each Phoenix repository and commit it with the application. Each
repository then owns its deployment scripts, systemd template, and CI workflow,
so changes can be reviewed and released together with the code they affect.

The kit builds a Mix release, runs database migrations, installs a user-level
systemd service, restarts the application, and checks that it responds over
HTTP. The same CI script is used locally and in GitHub Actions.

The installer adds `rename.md`, which contains a ready-to-use prompt for an AI
coding assistant to customize the deployment for the target repository.

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

The `.deploy/` folder and GitHub Actions workflow **must be committed** because
they contain reusable scripts and placeholder values. The real `.env.prod` is
different: it contains production passwords and secrets, lives at the
application root on the server, and **must never be committed**.

## 1. Add the kit to a Phoenix repository

Open Terminal and change into your Phoenix application. Copy and run this
command first, replacing the example path with the path to your application:

```bash
cd /path/to/my_app
```

Then copy and run this command separately:

```bash
curl -fsSL https://raw.githubusercontent.com/MICHAELMUNAVU83/phoenix-systemd-deploy/main/install.sh | bash
```

The installer:

1. checks that the current folder contains `mix.exs`;
2. installs all files, including hidden `.deploy` and `.github` folders;
3. refuses to replace deployment files that already exist;
4. makes the shell scripts executable;
5. detects whether the repository uses `main` or `master` and configures the
   deployment workflow accordingly; and
6. adds `/.env.prod` to `.gitignore` so production secrets cannot be committed
   accidentally.

For security, you can inspect
[`install.sh`](https://github.com/MICHAELMUNAVU83/phoenix-systemd-deploy/blob/main/install.sh)
before running it.

Open `rename.md` in the target repository and give its prompt to your AI coding
assistant. Review the resulting changes before committing them.

### Generate Phoenix release support locally

The deployment script builds releases, but it does **not** generate the release
support files. In your Phoenix application on your local development machine,
check whether these files already exist:

```bash
ls rel/overlays/bin/server rel/overlays/bin/migrate
```

If both files exist, skip this step. If they are missing, run:

```bash
mix phx.gen.release
```

Run this locally—not on the production server. Review the generated files and
commit them with the application. You normally run this generator only once;
future deployments reuse those committed files.

A sandboxed coding assistant may ask permission because Mix needs a local
filesystem lock or writes tools under your user account. That permission is for
running the one-time generator locally; it is not part of a production deploy.
Review the request before allowing it, as you would for any local command.

Confirm the branch used by the deployment workflow:

```bash
grep "github.ref ==" .github/workflows/ci-deploy.yml
```

The result should contain your production branch, for example
`refs/heads/main` or `refs/heads/master`. If the installer could not detect the
branch, edit `.github/workflows/ci-deploy.yml` and replace `master` with the
correct branch name before committing.

The installer adds `/.env.prod` to `.gitignore` automatically. Confirm that it
is present before creating any real production environment file:

```bash
grep -n '^/.env\.prod$' .gitignore
```

This rule ignores only the real `.env.prod` file at the repository root. It
does not ignore `.deploy/.env.prod.example`, which contains placeholders and
should be committed so other operators know which variables are required.

Stage the installed deployment files and `.gitignore` protection:

```bash
git add deploy.sh .deploy .github/workflows/ci-deploy.yml rename.md .gitignore
```

If you ran `mix phx.gen.release`, use `git status --short` to see its generated
files and stage them too. They normally include `rel/` and a release module
under `lib/`:

```bash
git status --short
git add rel lib/YOUR_APP/release.ex
```

Then commit everything:

```bash
git commit -m "Add repo-scoped systemd deployment"
```

Repeat this installation for each Phoenix application. Once installed, each
application's files are independent and can be customized for that application.

## Test the release workflow locally

You can test the release workflow on your development machine before using a
VPS. Local mode uses `MIX_ENV=dev`, including the database settings already in
`config/dev.exs`. It does not read `.env.prod`, use the production database, or
install the Linux `systemd` service.

Make sure the development database configured by `config/dev.exs` exists:

```bash
mix ecto.create
```

Then build a development release, run its release migration command against
the development database, and start it in the foreground:

```bash
./deploy.sh local
```

In another terminal, test it:

```bash
curl --fail http://localhost:4000/
```

Press **Ctrl-C** in the first terminal to stop the release. This verifies asset
building, release creation, the generated migration script, and release
startup. It does not test `config/runtime.exs` production settings, production
secrets, a Linux build, or `systemd`; the first manual VPS deployment remains
the final production check.

## 2. Prepare the server checkout

The server needs Linux with systemd, Erlang, Elixir, Git, curl, the
application's database, and any asset-build tools used by the application.
Deploy as a normal Linux user rather than root.

### Give the server access to a private GitHub repository

Do this **before cloning** if the application repository is private. Skip this
subsection if the repository is public or the server already has working
GitHub credentials.

Log in to the VPS as the deployment user and create a dedicated SSH key. When
`ssh-keygen` asks for a passphrase, press Enter twice to leave it empty so
automated deployments can fetch without prompting:

```bash
install -d -m 700 ~/.ssh
ssh-keygen -t ed25519 -C "VPS application deploy key" -f ~/.ssh/github_app_deploy
```

This creates two files:

- `~/.ssh/github_app_deploy` is the private key. It stays on the VPS and must
  never be copied to GitHub or committed.
- `~/.ssh/github_app_deploy.pub` is the public key. Display it with:

```bash
cat ~/.ssh/github_app_deploy.pub
```

Copy the complete output. In the **application repository** on GitHub, open
**Settings → Deploy keys → Add deploy key**, paste the public key, and save it.
Read access is sufficient; do not enable write access.

Tell SSH to use that private key when the VPS connects to GitHub:

```bash
cat >> ~/.ssh/config <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_app_deploy
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
```

Test the connection:

```bash
ssh -T git@github.com
```

The first connection may ask whether you trust GitHub's host key. Verify the
displayed fingerprint against
[GitHub's published SSH key fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
before entering `yes`. A successful test says that authentication succeeded
and that GitHub does not provide shell access.

### Clone the application

Use the repository's **SSH** URL, which begins with `git@github.com:`. A
separate deployment-kit checkout is not required:

```bash
cd ~
git clone git@github.com:OWNER/REPOSITORY.git
cd YOUR_APPLICATION_REPOSITORY_NAME
```

After cloning, confirm that the committed release support files are present:

```text
rel/overlays/bin/server
rel/overlays/bin/migrate
```

If they are missing, stop and run `mix phx.gen.release` locally as described in
step 1, commit its output, and then pull the commit onto the server. Do not make
uncommitted application changes directly on the production server.

## 3. Create the production environment

First, confirm that the `.gitignore` committed in step 1 contains this line:

```gitignore
/.env.prod
```

Then, on the server, copy the safe example to the application root and protect
the new file so only the deployment user can read it:

```bash
cd ~/YOUR_APPLICATION_REPOSITORY_NAME
cp .deploy/.env.prod.example .env.prod
chmod 600 .env.prod
```

Immediately verify that Git ignores the real file:

```bash
git check-ignore -v .env.prod
git status --short
```

The first command should print the matching `.gitignore` rule. The second
command must not list `.env.prod`. Stop and fix `.gitignore` before adding any
secret if either check fails. Never run `git add -f .env.prod`.

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

Replace `DATABASE_NAME` with the exact database name you created and want this
application to use—for example, `my_app_prod`. It is not automatically derived
from `APP_NAME`.

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

## 5. Test the deployment manually on the production server

Do this before configuring GitHub Actions. It proves that the server, database,
environment file, release, systemd service, and health check work together.
GitHub Actions will eventually run this same deployment command.

`./deploy.sh deploy` is not a dry run: it builds the release, runs migrations
against the database in `.env.prod`, and restarts the service. To rehearse
without touching production data, use a separate Linux staging server, staging
database, and staging `.env.prod` file.

Do not run `./deploy.sh deploy` on macOS: use `./deploy.sh local` there instead.
The full `deploy` command installs a Linux `systemd` service. SSH into the VPS
as the deployment user, then change into the application:

```bash
cd ~/YOUR_APPLICATION_REPOSITORY_NAME
```

Confirm the secret environment file exists and is ignored by Git:

```bash
test -f .env.prod && echo ".env.prod exists"
git check-ignore -v .env.prod
```

Now run the complete production deployment manually:

```bash
./deploy.sh deploy
```

The app name is detected from `mix.exs`. For an app named `my_app`, the script
creates `~/.config/systemd/user/my_app.service`, builds and migrates the release,
enables and starts the service, and performs an HTTP health check. A successful
run ends with `Deployment is healthy`.

Verify the running service:

```bash
./deploy.sh status
curl --fail http://127.0.0.1:4000/
```

Replace port `4000` and `/` if `.env.prod` or `HEALTH_PATH` uses different
values. If deployment fails, inspect the service logs:

```bash
journalctl --user -u YOUR_APP_NAME.service -n 100 --no-pager
```

Fix the reported problem and run `./deploy.sh deploy` again. The command is
intended to be safely rerun after configuration or application changes.

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

On your local development machine, run `./.deploy/ci.sh` for formatting,
compilation, and tests. Use `./deploy.sh local` when you also want to smoke-test
the production release without attempting to install a Linux service.

## 7. Deploy updates

```bash
cd ~/YOUR_APPLICATION_REPOSITORY_NAME
git pull --ff-only origin YOUR_DEPLOY_BRANCH
./deploy.sh deploy
```

Replace `YOUR_DEPLOY_BRANCH` with the branch selected during installation,
usually `main` or `master`.

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

The installed workflow runs CI for pushes and pull requests. Deployment runs
only after CI succeeds on a push to the `main` or `master` branch selected by
the installer.

### Create the GitHub Actions-to-VPS SSH key

Create a dedicated key pair on your own computer. Do not add a passphrase:
GitHub Actions cannot answer an interactive passphrase prompt.

```bash
ssh-keygen -t ed25519 -C "github-actions deployment" -f ./github-actions-vps
```

This creates two files:

- `github-actions-vps` is the **private key**. Copy its entire contents,
  including the `BEGIN` and `END` lines, into the GitHub Actions secret
  `VPS_SSH_PRIVATE_KEY`.
- `github-actions-vps.pub` is the **public key**. Install it for the deployment
  user on the VPS.

From your computer, the simplest way to install the public key is:

```bash
ssh-copy-id -i ./github-actions-vps.pub -p 22 deploy@YOUR_VPS_HOST
```

If `ssh-copy-id` is unavailable, log in to the VPS and prepare its SSH
directory:

```bash
install -d -m 700 ~/.ssh
```

Append the single line from `github-actions-vps.pub` to
`~/.ssh/authorized_keys`, then correct the file permission:

```bash
chmod 600 ~/.ssh/authorized_keys
```

Test the same key from your computer before adding it to GitHub:

```bash
ssh -i ./github-actions-vps -p 22 deploy@YOUR_VPS_HOST
```

After the GitHub secret has been saved and a deployment workflow has connected
successfully, securely remove the local `github-actions-vps` private-key file.
The public-key file may be retained. Never commit either file to the
application repository.

### Record and verify the VPS host key

GitHub Actions uses `VPS_KNOWN_HOSTS` to verify that it is connecting to the
intended server. On a trusted computer, collect the server's public host keys
(replace the port if SSH does not use port 22):

```bash
ssh-keyscan -p 22 YOUR_VPS_HOST > vps_known_hosts
ssh-keygen -lf vps_known_hosts
```

Before trusting the output, compare the displayed fingerprints with the host
key fingerprints shown directly on the VPS console:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
sudo ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub
sudo ssh-keygen -lf /etc/ssh/ssh_host_rsa_key.pub
```

Only matching key types need to be compared. Copy the full contents of
`vps_known_hosts` into the `VPS_KNOWN_HOSTS` GitHub Actions secret. Do not use
an unverified `ssh-keyscan` result: scanning discovers the presented key but
does not prove the server's identity.

### Add the GitHub Actions secrets

Add these secrets under **Application repository → Settings → Secrets and
variables → Actions**. Repository secrets work, or add them to the `production`
environment used by the workflow:

| Secret                | Description                                         |
| --------------------- | --------------------------------------------------- |
| `VPS_HOST`            | Server hostname or IP                               |
| `VPS_USER`            | Deployment user, such as `deploy`                   |
| `VPS_PORT`            | SSH port; optional, defaults to `22`                |
| `VPS_APP_PATH`        | Application checkout, such as `/home/deploy/my_app` |
| `VPS_SSH_PRIVATE_KEY` | Private SSH deployment key                          |
| `VPS_KNOWN_HOSTS`     | Verified SSH host-key lines                         |

The resulting key placement is:

| Connection | Private key | Public key |
| ---------- | ----------- | ---------- |
| GitHub Actions → VPS | GitHub secret `VPS_SSH_PRIVATE_KEY` | VPS deployment user's `~/.ssh/authorized_keys` |
| VPS → private GitHub repository | VPS `~/.ssh/github_app_deploy` | Application repository's GitHub deploy keys |
| VPS identity verification | VPS `/etc/ssh/ssh_host_*_key` | GitHub secret `VPS_KNOWN_HOSTS` |

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
