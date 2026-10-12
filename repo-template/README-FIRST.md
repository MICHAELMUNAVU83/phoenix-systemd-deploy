# The deployment folders are hidden by default

This download contains four items:

```text
.deploy/
.github/
README-FIRST.md
deploy.sh
```

The `.deploy` and `.github` folders begin with a dot, so macOS Finder hides them
by default. Press **Command-Shift-.** in Finder to show hidden files and folders,
or inspect the extracted download in Terminal:

```bash
ls -la
```

Copy **all** of these items into the root of your Phoenix application. From
Terminal, this command includes the hidden folders:

```bash
cp -R /path/to/extracted-folder/. /path/to/your-phoenix-app/
```

Then run `./deploy.sh commands` and follow the setup guide in the project
README. You may delete this `README-FIRST.md` file after installation.
