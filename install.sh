#!/bin/sh
# pi-bootstrap: one line to put my pi setup on a new macOS or Linux machine.
#
#   curl -fsSL https://raw.githubusercontent.com/Maheidem/pi-bootstrap/main/install.sh | sh
#
# This script is PUBLIC and contains NO secrets. It:
#   1. gets GitHub's CLI (gh) if missing: official release, sha256-verified, no sudo;
#   2. logs you in to GitHub (device flow: approve a one-time code in any browser, even on a
#      phone), unless an account that can read the private snapshot is already logged in;
#   3. downloads the PRIVATE snapshot repo (Maheidem/pi-setup) as a tarball: no git needed;
#   4. runs its ./setup, which installs pi, asks the passphrase that decrypts the secrets,
#      shows the plan and asks before writing anything (backups + rollback included).
# You need: internet, your GitHub login, the passphrase. Re-run it any time to update.
# Options for setup go after `sh -s --`, e.g.:   curl -fsSL … | sh -s -- --dry-run
#
# Source of truth: bootstrap/install.sh in the private repo; published here unchanged.
set -eu

REPO=${PI_SETUP_REPO:-Maheidem/pi-setup}
REF=${PI_SETUP_REF:-main}
GH_USER=${PI_SETUP_GH_USER:-Maheidem}
DIR=${PI_SETUP_DIR:-$HOME/.pi-setup}
TTY=${PI_BOOTSTRAP_TTY:-/dev/tty}

say() { printf '==> %s\n' "$*"; }
die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

# Everything below may ask questions (GitHub login, passphrase, confirmations). Under
# `curl … | sh` stdin is the script itself, so all interaction goes through the terminal.
if ! (: <"$TTY") 2>/dev/null; then
	die "no interactive terminal. Run the one-liner in a terminal window (it asks for a GitHub login and a passphrase)."
fi

fetch() { # fetch URL [FILE]
	if have curl; then
		if [ $# -gt 1 ]; then curl -fsSL --retry 3 -o "$2" "$1"; else curl -fsSL --retry 3 "$1"; fi
	elif have wget; then
		if [ $# -gt 1 ]; then wget -q -O "$2" "$1"; else wget -q -O - "$1"; fi
	else
		die "need curl or wget to download."
	fi
}

case "$(uname -s)" in
	Darwin) os=macOS ;;
	Linux) os=linux ;;
	*) die "unsupported OS: $(uname -s) (macOS and Linux only)." ;;
esac
case "$(uname -m)" in
	x86_64 | amd64) arch=amd64 ;;
	arm64 | aarch64) arch=arm64 ;;
	*) die "unsupported CPU: $(uname -m)." ;;
esac

mkdir -p "$DIR"
chmod 700 "$DIR" # the snapshot carries secrets.enc
tmp=$(mktemp -d "$DIR/.tmp.XXXXXX")
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

# --- 1. GitHub CLI: an existing install wins; otherwise the official release, verified -----
# (PI_BOOTSTRAP_GH, when set, replaces the PATH lookup; set but empty = "no gh installed".)
if [ "${PI_BOOTSTRAP_GH+set}" = set ]; then gh_bin=$PI_BOOTSTRAP_GH; else gh_bin=$(command -v gh || true); fi
if [ -z "$gh_bin" ] && [ -x "$DIR/tools/gh" ]; then gh_bin=$DIR/tools/gh; fi
if [ -z "$gh_bin" ]; then
	version=$(fetch https://api.github.com/repos/cli/cli/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n 1)
	[ -n "$version" ] || die "could not find the latest GitHub CLI release (is api.github.com reachable?)."
	case "$os" in
		macOS) asset=gh_${version}_macOS_${arch}.zip ;;
		linux) asset=gh_${version}_linux_${arch}.tar.gz ;;
	esac
	base=https://github.com/cli/cli/releases/download/v$version
	say "Getting GitHub CLI $version ($asset)"
	fetch "$base/$asset" "$tmp/$asset"
	fetch "$base/gh_${version}_checksums.txt" "$tmp/checksums.txt"
	expected=$(awk -v file="$asset" '$2 == file { print $1 }' "$tmp/checksums.txt")
	if have sha256sum; then
		actual=$(sha256sum "$tmp/$asset" | awk '{ print $1 }')
	else
		actual=$(shasum -a 256 "$tmp/$asset" | awk '{ print $1 }')
	fi
	if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
		die "checksum mismatch for $asset; refusing to run it."
	fi
	case "$asset" in
		*.zip)
			have unzip || die "need unzip to unpack $asset."
			(cd "$tmp" && unzip -q "$asset")
			unpacked=${asset%.zip}
			;;
		*)
			tar -xzf "$tmp/$asset" -C "$tmp"
			unpacked=${asset%.tar.gz}
			;;
	esac
	mkdir -p "$DIR/tools"
	cp "$tmp/$unpacked/bin/gh" "$DIR/tools/gh"
	chmod 755 "$DIR/tools/gh"
	gh_bin=$DIR/tools/gh
fi

# --- 2. GitHub login: an account that can read the private snapshot ----------------------
# Tokens travel by environment (never on a command line, where `ps` could show them), and gh's
# active account is never switched.
can_read() { GH_TOKEN=$1 "$gh_bin" api "repos/$REPO" --silent >/dev/null 2>&1; }
token=$("$gh_bin" auth token --hostname github.com --user "$GH_USER" 2>/dev/null || true)
[ -n "$token" ] || token=$("$gh_bin" auth token --hostname github.com 2>/dev/null || true)
if [ -z "$token" ] || ! can_read "$token"; then
	say "Log in to GitHub as $GH_USER. gh prints a one-time code: approve it at github.com/login/device in any browser (a phone works)."
	"$gh_bin" auth login --hostname github.com --git-protocol https --web --skip-ssh-key <"$TTY" || die "GitHub login failed."
	token=$("$gh_bin" auth token --hostname github.com --user "$GH_USER" 2>/dev/null || "$gh_bin" auth token --hostname github.com 2>/dev/null || true)
	if [ -z "$token" ] || ! can_read "$token"; then
		die "the GitHub account you logged in with cannot read $REPO."
	fi
fi

# --- 3. The private snapshot, as a tarball through the API (no git or Xcode tools needed) ---
say "Downloading $REPO ($REF)"
GH_TOKEN=$token "$gh_bin" api "repos/$REPO/tarball/$REF" >"$tmp/snapshot.tgz" || die "could not download $REPO."
mkdir "$tmp/repo"
tar -xzf "$tmp/snapshot.tgz" -C "$tmp/repo" --strip-components=1 || die "the downloaded snapshot is not a valid tarball."
[ -x "$tmp/repo/setup" ] || die "the downloaded snapshot has no executable ./setup."
rm -rf "$DIR/repo.previous"
if [ -d "$DIR/repo" ]; then mv "$DIR/repo" "$DIR/repo.previous"; fi
mv "$tmp/repo" "$DIR/repo"
rm -rf "$DIR/repo.previous"

# --- 4. Hand off: setup installs pi, asks the passphrase, shows the plan, asks before writing --
cleanup
trap - EXIT INT TERM
if ! have curl && have wget; then
	PI_SETUP_INSTALLER="wget -qO- https://pi.dev/install.sh | sh"
	export PI_SETUP_INSTALLER
fi
say "Running setup from $DIR/repo"
cd "$DIR/repo"
exec ./setup "$@" <"$TTY"
