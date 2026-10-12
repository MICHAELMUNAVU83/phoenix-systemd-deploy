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

> **macOS users:** `.deploy` and `.github` are included in the ZIP, but Finder
> hides names beginning with a dot. Press **Command-Shift-.** in Finder to show
> them, or run `ls -la` in Terminal. Copy the extracted folder's complete
> contents—not only the visible `deploy.sh` and `rename.md` files—into the
> Phoenix repository.

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

The easiest method is to open Terminal, change into the Phoenix application,
and run the installer directly from GitHub:

```bash
cd /path/to/my_app
curl -fsSL https://raw.githubusercontent.com/MICHAELMUNAVU83/phoenix-systemd-deploy/main/install.sh | bash
```

The installer:

1. checks that the current folder contains `mix.exs`;
2. downloads and extracts all files, including hidden `.deploy` and `.github`
   folders;
3. refuses to replace deployment files that already exist;
4. makes the shell scripts executable; and
5. adds `/.env.prod` to `.gitignore` so production secrets cannot be committed
   accidentally.

For security, you can inspect
[`install.sh`](https://github.com/MICHAELMUNAVU83/phoenix-systemd-deploy/blob/main/install.sh)
before running it.

Alternatively, download and extract the ZIP into the Phoenix repository, or
copy the files from this repository's `repo-template/` directory:

```bash
APP_REPO=/path/to/my_app

cp -R repo-template/. "$APP_REPO/"
chmod +x "$APP_REPO/deploy.sh" "$APP_REPO/.deploy/ci.sh"
```

Open `rename.md` in the target repository and give its prompt to your AI coding
assistant. Review the resulting changes before committing them.

Before creating any real `.env.prod` file, add its name to `.gitignore` in the
application repository:

```bash
cd "$APP_REPO"
touch .gitignore
grep -qxF '/.env.prod' .gitignore || printf '\n/.env.prod\n' >> .gitignore
```

This rule ignores only the real `.env.prod` file at the repository root. It
does not ignore `.deploy/.env.prod.example`, which contains placeholders and
should be committed so other operators know which variables are required.

Commit the copied files and the `.gitignore` protection:

```bash
cd "$APP_REPO"
git add deploy.sh .deploy .github/workflows/ci-deploy.yml rename.md .gitignore
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

### Allow the VPS to fetch a private application repository

This is a separate SSH connection and should use a separate key pair. Skip this
step if the application repository is public or the server already has working
GitHub credentials.

On the VPS, logged in as the deployment user, generate a key with no
passphrase:

```bash
install -d -m 700 ~/.ssh
ssh-keygen -t ed25519 -C "VPS application deploy key" -f ~/.ssh/github_app_deploy
```

Display the public key:

```bash
cat ~/.ssh/github_app_deploy.pub
```

In the **application repository** on GitHub, add that public key under
**Settings → Deploy keys → Add deploy key**. Read access is sufficient; do not
enable write access. Keep `~/.ssh/github_app_deploy` private on the VPS.

Configure SSH on the VPS to use this key for GitHub:

```bash
cat >> ~/.ssh/config <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_app_deploy
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
ssh -T git@github.com
```

GitHub normally reports successful authentication while noting that it does
not provide shell access. Ensure the application checkout uses an SSH remote:

```bash
git -C ~/YOUR_APPLICATION_REPOSITORY_NAME remote set-url origin git@github.com:OWNER/REPOSITORY.git
git -C ~/YOUR_APPLICATION_REPOSITORY_NAME fetch origin
```

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
