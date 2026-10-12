# The deployment folders are hidden by default

This download contains five items:

```text
.deploy/
.github/
README-FIRST.md
deploy.sh
rename.md
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

Then open `rename.md` and follow its customization instructions. You may delete
this `README-FIRST.md` file after installation.
