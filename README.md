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
curl -fsSL "https://raw.githubusercontent.com/MICHAELMUNAVU83/phoenix-systemd-deploy/main/install.sh?$(date +%s)" | bash
```

The installer:

1. checks that the current folder contains `mix.exs`;
2. installs all files, including hidden `.deploy` and `.github` folders;
3. when rerun, updates `deploy.sh` and `.deploy/ci.sh` and adds the manual
   workflow trigger to a recognized older workflow when needed;
4. makes the shell scripts executable;
5. detects whether the repository uses `main` or `master` and configures the
   deployment workflow accordingly; and
6. adds `/.env.prod` to `.gitignore` so production secrets cannot be committed
   accidentally.

You can safely run the same `curl` command again when a newer deployment kit
is available. Existing installations update these shared scripts:

```text
deploy.sh
.deploy/ci.sh
```

The updater otherwise preserves `.deploy/.env.prod.example`,
`.deploy/phoenix.service.tpl`, `.github/workflows/ci-deploy.yml`, `rename.md`,
and all application files because those may have app-specific customizations.
If the existing workflow still has the standard push-only deployment
condition, the updater adds `workflow_dispatch` while preserving its `main` or
`master` deployment branch. It warns instead of changing a workflow it cannot
safely recognize. Review every update before committing it:

```bash
git diff -- deploy.sh .deploy/ci.sh .github/workflows/ci-deploy.yml
./.deploy/ci.sh
```

For security, you can inspect
[`install.sh`](https://github.com/MICHAELMUNAVU83/phoenix-systemd-deploy/blob/main/install.sh)
before running it.

After installation, start by viewing every available deployment command:

```bash
./deploy.sh commands
```

This only displays help; it does not build, migrate, restart, or otherwise
change the application.

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

If the new `rel/` folder does not appear in Source Control or
`git status --short`, check whether Git is ignoring it:

```bash
git check-ignore -v rel/overlays/bin/server
git check-ignore -v rel/overlays/bin/migrate
```

If either command prints a rule, the first column identifies the ignore source.
Remove the `rel` or `/rel/` rule from the application's `.gitignore` when it is
no longer needed. If the rule comes from a global ignore file, or you
intentionally want to keep that rule, explicitly stage the reviewed generated
folder once:

```bash
git add -f rel
```

Using `-f` is appropriate here only for the generated `rel/` support files that
must ship with the application. Never use it for `.env.prod` or another secret.
Confirm that the files are now staged:

```bash
git status --short rel
git diff --cached -- rel
```

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
git add lib/YOUR_APP/release.ex
git add rel || git add -f rel
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

Before running local mode, view its built-in help:

```bash
./deploy.sh --help
```

You can also inspect the exact `run_local` function without executing it:

```bash
sed -n '/^run_local()/,/^}/p' deploy.sh
```

`./deploy.sh local` is not a dry run. It:

1. uses `MIX_ENV=dev` and the database configuration in `config/dev.exs`;
2. fetches dependencies and compiles the application;
3. builds and digests the static assets;
4. assembles a development release under `_build/dev/rel/`;
5. cleans generated digest copies from the source `priv/static/` directory;
6. runs the generated release migration command against the development
   database; and
7. starts the release in the foreground until you press **Ctrl-C**.

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

### If Mix reports an invalid regular expression term

A development release must store values from `config/dev.exs`. If Mix reports
that a configured regular expression needs the `/E` modifier, add `E` after
that expression's closing delimiter. For example, change:

```elixir
~r/priv\/static\/(?!uploads\/).*(js|css|png|jpeg|jpg|gif|svg)$/
```

to:

```elixir
~r/priv\/static\/(?!uploads\/).*(js|css|png|jpeg|jpg|gif|svg)$/E
```

Apply the same change to any other configured regex named in the error, then
run `./deploy.sh local` again. The `E` modifier makes the compiled regex safe
for Mix to export into a release configuration.

To update all single-line regexes at every level under `config/`, run this from
the application root:

```bash
find config -type f \( -name '*.ex' -o -name '*.exs' \) -exec perl -pi.bak -e 'if (/~r"/ && !/"[A-Za-z]*E[A-Za-z]*\s*,?\s*$/) { s/"([A-Za-z]*)(\s*,?\s*)$/"$1E$2/ } elsif (/~r\// && !m{/([A-Za-z]*E[A-Za-z]*)\s*,?\s*$}) { s{/([A-Za-z]*)(\s*,?\s*)$}{/$1E$2} }' {} +
```

The command creates a `.bak` copy beside each checked config file, updates both
`~r"..."` and `~r/.../` forms, preserves existing modifiers, and does not add a
second `E`. Review all changes:

```bash
git diff -- config
```

If the diff is correct, remove the backup and retry the local release:

```bash
find config -type f -name '*.bak' -delete
./deploy.sh local
```

If an earlier local build left fingerprinted files and `.gz` copies under
`priv/static`, remove only Phoenix's generated digest output with:

```bash
MIX_ENV=dev mix phx.digest.clean --all
```

Keep and commit your original images, `robots.txt`, and other source assets.
Commit `.deploy/`, `.github/workflows/`, `deploy.sh`, the generated `rel/`
scripts, and `lib/YOUR_APP/release.ex`. Delete `README-FIRST.md` after setup.
Files ending in `.bak`, `.DS_Store`, `.env.prod`, and
`priv/static/cache_manifest.json` should not be committed; the installer adds
ignore rules for them.

If the application stores user-generated files under `priv/static/uploads/`,
add `/priv/static/uploads/` to `.gitignore` too. Do not add that rule if the
folder contains deliberate source assets that should ship with the application.

## Check everything before pushing

Run the same CI checks used by GitHub Actions from the application root:

```bash
./.deploy/ci.sh
```

Do not push if this command fails. Fix the reported formatting, compilation, or
test error, then run it again until it ends with `CI checks passed`.

Confirm that the production secret file is ignored:

```bash
git check-ignore -v .env.prod
```

Finally, inspect everything that will be committed:

```bash
git status --short
git diff --check
git diff --cached
```

Make sure `.env.prod`, `.DS_Store`, backup files, uploads, and generated digest
files are not staged. Push only after the CI script passes and the staged diff
contains the intended source, release, and deployment files.

## 2. Prepare the server checkout

The server needs Linux with systemd, Erlang, Elixir, Git, curl, the
application's database, and any asset-build tools used by the application.
Deploy as a normal Linux user rather than root.

If Erlang and Elixir are installed with asdf, install them for the same VPS
user that performs deployments. The deployment script automatically adds
`~/.asdf/bin` and `~/.asdf/shims` to `PATH`, including for non-interactive SSH
sessions started by GitHub Actions. Verify the installation as that user:

```bash
~/.asdf/shims/elixir --version
~/.asdf/shims/mix --version
```

### Give the server access to a private GitHub repository

Do this **before cloning** if the application repository is private. Skip this
subsection if the repository is public or the server already has working
GitHub credentials.

[GitHub deploy keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys)
belong to one repository and cannot be reused for another. Therefore, every
private application needs its own key filename and SSH alias.

The repository has not been cloned yet, so its Phoenix app name cannot be
detected automatically. In every command below, replace `YOUR_APP_NAME` with a
short, unique name such as `kabeberi`. Use the same name consistently for that
application. A second application on the VPS must use a different name.

First, check which deploy keys already exist:

```bash
install -d -m 700 ~/.ssh
find ~/.ssh -maxdepth 1 -type f -name 'github_*_deploy*' -print
```

If a key for this same application already exists, reuse it. Otherwise, create
it. When asked for a passphrase, press Enter twice so automated deployments can
fetch without prompting:

```bash
if [ -f ~/.ssh/github_YOUR_APP_NAME_deploy ] && [ -f ~/.ssh/github_YOUR_APP_NAME_deploy.pub ]; then
  echo "Key already exists; reusing it"
else
  ssh-keygen -t ed25519 -C "YOUR_APP_NAME VPS deploy key" -f ~/.ssh/github_YOUR_APP_NAME_deploy
fi
```

This creates two app-specific files:

- `~/.ssh/github_YOUR_APP_NAME_deploy` is the private key. It stays on the VPS and
  must never be copied to GitHub or committed.
- `~/.ssh/github_YOUR_APP_NAME_deploy.pub` is the public key. Display it with:

```bash
cat ~/.ssh/github_YOUR_APP_NAME_deploy.pub
```

Copy the complete output. In the **application repository** on GitHub, open
**Settings → Deploy keys → Add deploy key**, paste the public key, and save it.
Read access is sufficient; do not enable write access.

Give this repository its own SSH alias. This command checks before adding it,
so rerunning it does not duplicate the configuration:

```bash
if ! grep -qxF "Host github-YOUR_APP_NAME" ~/.ssh/config 2>/dev/null; then
  cat >> ~/.ssh/config <<'EOF'
Host github-YOUR_APP_NAME
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_YOUR_APP_NAME_deploy
  IdentitiesOnly yes
EOF
fi
chmod 600 ~/.ssh/config
```

Test the connection:

```bash
ssh -T git@github-YOUR_APP_NAME
```

The first connection may ask whether you trust GitHub's host key. Verify the
displayed fingerprint against
[GitHub's published SSH key fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
before entering `yes`. A successful test says that authentication succeeded
and that GitHub does not provide shell access.

### Clone the application

Use the app-specific SSH alias in the clone URL. Replace `OWNER` and
`REPOSITORY`; a separate deployment-kit checkout is not required:

```bash
cd ~
git clone git@github-YOUR_APP_NAME:OWNER/REPOSITORY.git
cd YOUR_APPLICATION_REPOSITORY_NAME
```

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
RELEASES_TO_KEEP="5"
```

Keep the `ecto://` scheme for both PostgreSQL and MySQL. Ecto accepts a generic
URL scheme and uses the repository adapter configured by the application to
select PostgreSQL or MySQL. Do not change it to `mysql://` unless the
application's own runtime configuration explicitly requires that format.

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

After editing `.env.prod`, check its shell syntax and list the configured
variable names without printing their secret values:

```bash
bash -n .env.prod
sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' .env.prod
```

Then display the deployment commands available in this repository:

```bash
./deploy.sh commands
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
values. The health check intentionally uses `127.0.0.1`: it tests the Phoenix
service directly on the VPS without depending on public DNS, TLS, or firewall
configuration. A connection failure means the service did not bind to the
configured `PORT`; changing the check to the public IP or removing it would
hide that startup problem.

To deliberately allow deployments to finish without verifying that the
application started, add this to `.env.prod` on the VPS:

```bash
HEALTH_CHECK_ENABLED="false"
```

This is not recommended for normal production use: GitHub Actions may report a
successful deployment even when the service is unavailable. Set it back to
`"true"` after diagnosing the startup problem.

If deployment fails, the script stops waiting when the service is inactive and
prints its status and recent journal entries. You can also inspect them
directly:

```bash
journalctl --user -u YOUR_APP_NAME.service -n 100 --no-pager
```

Fix the reported problem and run `./deploy.sh deploy` again. The command is
intended to be safely rerun after configuration or application changes.

Enable lingering once so the deployment user's service starts after a reboot
without an active SSH session. These are system-level commands and can be run
from any directory on the VPS:

```bash
sudo loginctl enable-linger "$(whoami)"
loginctl show-user "$(whoami)" --property=Linger
```

The expected output is `Linger=yes`. Run these while logged in as the Linux user
that owns and deploys the application; `$(whoami)` supplies that username
automatically. This is normally the only setup command that requires root
privileges.

## 6. Operate the service

Use systemd while logged in as the deployment user:

```bash
systemctl --user status my_app.service
systemctl --user restart my_app.service
journalctl --user -u my_app.service -f
```

Or use the simpler repo-local commands from the application root:

```bash
./deploy.sh commands
./deploy.sh up
./deploy.sh deploy
./deploy.sh status
./deploy.sh console
./deploy.sh logs
./deploy.sh logs-follow
./deploy.sh releases
```

Run `./deploy.sh commands` at any time to see every supported command and what
it does without starting a deployment.

`up` starts or restarts the existing release, `deploy` builds the release, runs
migrations, and restarts it, and `status` displays its systemd status.

Use `./deploy.sh console` to attach a remote IEx shell to the running production
release. Exit IEx normally when finished; do not stop the application from the
remote shell.

Use `./deploy.sh logs` to open the complete service journal in a scrollable
pager. Navigate with the arrow keys, **Page Up**, or **Page Down**, search with
`/text`, and press `q` to exit. Use `./deploy.sh logs-follow` to stream new log
entries and press **Ctrl-C** to stop following them.

### What happens if the application is killed?

Production releases started by `./deploy.sh deploy` or `./deploy.sh up` are
supervised by systemd. The installed service uses:

```ini
Restart=on-failure
RestartSec=5
```

If the BEAM process crashes, receives `SIGKILL`, or exits with a failure status,
systemd normally starts it again after five seconds. An intentional
`systemctl --user stop YOUR_APP_NAME.service` does not trigger a restart.
`./deploy.sh local` runs in the foreground without systemd, so it also does not
restart automatically if it is stopped or killed.

Check the production service after a failure:

```bash
./deploy.sh status
./deploy.sh logs
```

If repeated crashes cause systemd to rate-limit restart attempts, fix the
underlying error and run:

```bash
systemctl --user reset-failed YOUR_APP_NAME.service
./deploy.sh up
```

The service also starts after a VPS reboot only when it has been enabled and
lingering is enabled for the deployment user, as described in step 5.

Every successful deployment saves a numbered release snapshot. The newest
snapshot is number 1. The value of `RELEASES_TO_KEEP` in `.env.prod` controls
how many are retained; it defaults to 5. List them with:

```bash
./deploy.sh releases
```

Example output:

```text
NUMBER  RELEASE
1       20261012T101500Z-a1b2c3d
2       20261011T164200Z-e4f5a6b
```

To restore the release shown as number 2:

```bash
./deploy.sh rollback 2
```

The rollback replaces the active application release, restarts the service,
and performs the health check. If that check fails, the script restores the
release that was active before the rollback.

> **Database warning:** rollback changes application code only. It does not
> reverse database migrations. Before deploying a migration, make it compatible
> with both the old and new application versions, or prepare a separately
> reviewed database rollback procedure.

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
| `HEALTH_CHECK_ENABLED` | `true`; set to `false` to skip verification  |
| `PORT`             | `4000`, unless set in `.env.prod`                |
| `RELEASES_TO_KEEP` | `5`; number of successful releases to retain     |
| `RELEASES_DIR`     | User data directory outside the Git checkout     |

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

### PostgreSQL and MySQL

Production deployment is database-adapter agnostic: it passes `DATABASE_URL`
to the Phoenix release and runs the application's release migration command.
The application must already be configured with the appropriate Ecto adapter
(`postgrex` for PostgreSQL or `myxql` for MySQL), and the production database
and user must already exist.

On GitHub Actions, `.deploy/ci.sh` inspects `mix.lock`. It starts MySQL 8.4 when
it finds `myxql`; otherwise it starts PostgreSQL 16. To override detection, add
the repository variable `CI_DATABASE_ENGINE` under **Settings → Secrets and
variables → Actions → Variables** and set it to `mysql` or `postgres`.

The default CI containers use the conventional generated Phoenix test
credentials: PostgreSQL user/password `postgres`/`postgres`, or MySQL user
`root` with an empty password. If the application's `config/test.exs` uses
different credentials, customize the database startup in `.deploy/ci.sh` or
the test configuration. Local CI continues to use the database already
configured on the developer's computer; it does not start Docker.

### Customize CI checks

The included CI checks are a starting point. You can edit the `test` job in
`.github/workflows/ci-deploy.yml` to add, remove, or replace checks for the
application—for example, Credo, Dialyzer, security scanning, JavaScript tests,
or asset builds.

Keep the job identifier named `test` if the repository ruleset requires the
`test` status check. If you rename it, update the required status check in the
GitHub ruleset as well. The installer preserves customized workflow contents
when it cannot safely apply a narrowly scoped workflow upgrade.

## Configure GitHub Actions deployment

The installed workflow runs CI for pushes and pull requests. Deployment runs
only after CI succeeds on a push to the `main` or `master` branch selected by
the installer.

### One-time deployment setup

Do this once for each GitHub repository. You do not need to repeat it for
future deployments.

On your own computer—not on the VPS—create the deployment key pair in your
home directory:

```bash
ssh-keygen -t ed25519 -C "github-actions YOUR_APP_NAME" -f ~/github-actions-YOUR_APP_NAME
```

Replace `YOUR_APP_NAME` with the repository or application name. For example,
an application named `my-shop` would use `github-actions-my-shop`. Press Enter
when asked for a passphrase so the key has no passphrase. This creates two
files locally on your computer:

- `~/github-actions-YOUR_APP_NAME` is the private key.
- `~/github-actions-YOUR_APP_NAME.pub` is the public key.

Do not copy either file to the VPS. You will copy and paste only the public
key's text in the next steps.

Still on your computer, display the public key and copy its entire single line:

```bash
cat ~/github-actions-YOUR_APP_NAME.pub
```

Choose the VPS account that GitHub Actions will use. Replace `YOUR_VPS_USER`
with that account name—for example, `deploy` for a dedicated deployment user
or `root` if the server is configured for root deployments. Log in as that
user:

```bash
ssh -p 22 YOUR_VPS_USER@YOUR_VPS_HOST
```

Once logged in, prepare that user's SSH directory:

```bash
install -d -m 700 ~/.ssh
```

On the VPS, open the authorized-keys file:

```bash
nano ~/.ssh/authorized_keys
```

Paste the copied public-key line on a new line. Save with Ctrl-O, press Enter,
and then exit with Ctrl-X.

Set the correct file permission:

```bash
chmod 600 ~/.ssh/authorized_keys
```

Exit the VPS:

```bash
exit
```

Then test the deployment key from your computer:

```bash
ssh -i ~/github-actions-YOUR_APP_NAME -p 22 YOUR_VPS_USER@YOUR_VPS_HOST
```

The test should log in without asking for the VPS user's password. Use the same
account name later for the GitHub Actions `VPS_USER` secret. The public key is
authorized only for the account whose `~/.ssh/authorized_keys` file you edited.

Back on your computer, display the private key locally:

```bash
cat ~/github-actions-YOUR_APP_NAME
```

Keep this output secret and never paste it on the VPS. Copy everything,
including the `BEGIN OPENSSH PRIVATE KEY` and `END OPENSSH PRIVATE KEY` lines.
Then open the GitHub repository and go to **Settings → Secrets and variables →
Actions → New repository secret**. Create a secret named
`VPS_SSH_PRIVATE_KEY`, paste the copied private-key text into the secret value,
and save it.

Once deployment works, securely delete the local
`github-actions-YOUR_APP_NAME` private-key file. You may keep
`github-actions-YOUR_APP_NAME.pub`. Never commit either key file to Git.

If several projects deploy to the same VPS, use a separate key for each
repository. This lets you remove one project's access without affecting the
others.

### Record and verify the VPS host key

GitHub Actions uses `VPS_KNOWN_HOSTS` to verify that it is connecting to the
intended server. This is a one-time setup for each repository, not something
you repeat for every deployment. Repositories connecting to the same VPS and
SSH port may use the same verified `VPS_KNOWN_HOSTS` value.

Repeat this setup if the VPS is rebuilt, its SSH host keys change, or its
hostname, IP address, or SSH port changes. On your computer, collect the
server's public host keys (replace the port if SSH does not use port 22):

```bash
ssh-keyscan -p 22 YOUR_VPS_HOST > ~/YOUR_APP_NAME-vps-known-hosts
ssh-keygen -lf ~/YOUR_APP_NAME-vps-known-hosts
```

Before trusting the output, compare the displayed fingerprints with the host
key fingerprints shown directly on the VPS console:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
sudo ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub
sudo ssh-keygen -lf /etc/ssh/ssh_host_rsa_key.pub
```

Only matching key types need to be compared. After verifying the fingerprints,
display the saved host keys on your computer:

```bash
cat ~/YOUR_APP_NAME-vps-known-hosts
```

Copy the full output into the `VPS_KNOWN_HOSTS` GitHub Actions secret. Do not
use an unverified `ssh-keyscan` result: scanning discovers the presented key
but does not prove the server's identity.

### Add the GitHub Actions secrets

Add these secrets under **Application repository → Settings → Secrets and
variables → Actions**. Repository secrets work, or add them to the `production`
environment used by the workflow:

| Secret                | Description                                         |
| --------------------- | --------------------------------------------------- |
| `VPS_HOST`            | Server hostname or IP                               |
| `VPS_USER`            | Deployment user, such as `deploy`                   |
| `VPS_PORT`            | SSH port; optional, defaults to `22`                |
| `VPS_APP_PATH`        | Absolute application directory reported by `pwd`    |
| `VPS_SSH_PRIVATE_KEY` | Private SSH deployment key                          |
| `VPS_KNOWN_HOSTS`     | Verified SSH host-key lines                         |

To get `VPS_APP_PATH`, log in to the VPS as `VPS_USER`, change into the
production application's directory, and run:

```bash
pwd
```

Copy the complete output, such as `/home/deploy/my_app` or `/root/my_app`, into
the `VPS_APP_PATH` GitHub Actions secret. Do not use the path from your local
computer.

### Trigger CI and deployment manually

After saving all six secrets, commit and push the installed workflow. In the
application's GitHub repository, open **Actions → CI and deploy**, select **Run
workflow**, choose the branch to deploy, and select **Run workflow** again.

The manual run executes CI first. If CI succeeds, the deployment job connects
to the VPS and runs the deployment. Open the deployment job in GitHub Actions
to see whether the SSH connection and deployment succeeded. A manual run is a
real production deployment, not a connection-only test.

The workflow also continues to deploy automatically after CI succeeds on a
push to the configured `main` or `master` branch. Pull requests run CI without
deploying.

### Require CI before updating the production branch

The workflow cannot reject a Git push by itself. Protect the production branch
with a GitHub ruleset so changes must go through a pull request and pass CI
before they can be merged.

First, run the workflow at least once so GitHub knows about its `test` status
check. Then open the application repository and go to **Settings → Rules →
Rulesets → New ruleset → New branch ruleset**:

1. Give the ruleset a name and set **Enforcement status** to **Active**.
2. Under **Target branches**, include the default branch (`main` or `master`).
3. Enable **Require a pull request before merging**.
4. Enable **Require status checks to pass** and add the workflow's `test`
   check as required.
5. Optionally require the branch to be up to date before merging.
6. Enable **Block force pushes**, then create the ruleset.

Do not add a bypass for users who should follow this rule. Afterward, push work
to a feature branch, open a pull request, and merge it only after `test` passes.
The successful merge updates the production branch and starts deployment.

The resulting key placement is:

| Connection | Private key | Public key |
| ---------- | ----------- | ---------- |
| GitHub Actions → VPS | GitHub secret `VPS_SSH_PRIVATE_KEY` | VPS deployment user's `~/.ssh/authorized_keys` |
| VPS → private GitHub repository | VPS `~/.ssh/github_YOUR_APP_NAME_deploy` | Application repository's GitHub deploy keys |
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
8. prints recent journal logs if the health check fails; and
9. after a successful health check, saves the release and prunes snapshots
   beyond `RELEASES_TO_KEEP`.
