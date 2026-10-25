# pi-bootstrap

One line to put my pi setup (pi, extensions, configuration, encrypted secrets) on a new
macOS or Linux machine:

```sh
curl -fsSL https://raw.githubusercontent.com/Maheidem/pi-bootstrap/main/install.sh | sh
```

No curl? `wget -qO- https://raw.githubusercontent.com/Maheidem/pi-bootstrap/main/install.sh | sh`

**You need:** internet, your GitHub login (an account that can read the private snapshot), and
the passphrase. Nothing else: no git, no Xcode tools, no other machine.

**What happens:**

1. GitHub's CLI (`gh`) is used if installed, otherwise downloaded from its official release and
   sha256-verified (no sudo, kept in `~/.pi-setup/tools`).
2. GitHub login through the device flow: gh shows a one-time code, you approve it at
   github.com/login/device in any browser (a phone works). Skipped when an account that can
   read the snapshot is already logged in.
3. The private snapshot is downloaded as a tarball into `~/.pi-setup/repo`.
4. Its `./setup` installs pi (official installer), asks the passphrase, shows exactly what will
   change, and asks before writing anything. Every overwritten file is backed up;
   `~/.pi-setup/repo/setup --rollback <timestamp>` undoes a run.

**Options** go to setup after `sh -s --`, for example:

```sh
curl -fsSL https://raw.githubusercontent.com/Maheidem/pi-bootstrap/main/install.sh | sh -s -- --dry-run
```

(`--dry-run`, `--yes`, `--exact`, `--install-deps`, `--smoke`, `--list-backups`, `--rollback <ts>`.)

**Updating:** run the same line again; it fetches the latest snapshot and shows what changed.

This script is public on purpose and contains no secrets. The configuration and the encrypted
secrets live in a private repository; the passphrase never leaves your head.
