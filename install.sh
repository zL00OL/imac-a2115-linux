#!/bin/bash
# Install this repo's tooling onto an iMac19,1 running openSUSE.
#
#   sudo ./install.sh              # install
#   sudo ./install.sh --dry-run    # print what would happen
#   sudo ./install.sh --uninstall  # remove what this installed
#
# LAYOUT, AND WHY IT IS THIS WAY
#
#   /usr/local/bin/       things a USER types:  imac-update, imac-reapply,
#                                                 imac-verify, check-5k.sh
#   /usr/local/libexec/   things SYSTEMD runs, or that need root: the
#                         kernel-install hooks' helpers and imac-amdgpu-install
#   /etc/kernel/install.d/  hooks that fire on every kernel install
#   /etc/systemd/system/  units
#   /usr/local/share/imac/ patches, and a copy of the docs
#
# The split is not arbitrary: only /usr/local/bin is on a normal user's PATH, and
# putting a root-only helper there would invite running it unprivileged and
# getting a confusing permission error. Earlier revisions mixed ~/bin and
# /usr/local/bin for the same scripts, so a documented command did not exist.
#
# THIS IS THE ONLY INSTALLER. If a file is not installed here, it is not part of
# the supported surface.
set -u
REPO=$(cd "$(dirname "$0")" && pwd)
DRY=0; UNINSTALL=0
case "${1:-}" in
  --dry-run) DRY=1 ;;
  --uninstall) UNINSTALL=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run|--uninstall]" >&2; exit 2 ;;
esac

BIN=/usr/local/bin
LIBEXEC=/usr/local/libexec
HOOKS=/etc/kernel/install.d
UNITS=/etc/systemd/system
SHARE=/usr/local/share/imac
DOCS=/usr/local/share/doc/imac-linux

# user-facing -> /usr/local/bin
USER_BIN="imac-update imac-reapply imac-verify imac-audio check-5k.sh imac-brightness"
# root-only / invoked by systemd -> /usr/local/libexec
LIBEXEC_BIN="imac-setos-patch imac-setos-install imac-amdgpu-install imac-brightness-set imac-mic-on"
# esp-prune-kernels is invoked by 97-esp-prune.install from /usr/local/sbin, a
# legacy path that hook hardcodes; install it there too rather than edit the hook.
SBIN_BIN="esp-prune-kernels"
# kernel-install hooks
HOOK_FILES="01-xbootldr-layout.install 45-amdgpu-5k.install 97-esp-prune.install 96-imac-setos.install"
UNIT_FILES="imac-amdgpu-build@.service"

say(){ printf '%s\n' "$*"; }
run(){ if [ "$DRY" -eq 1 ]; then say "    dry-run: $*"; else "$@"; fi; }

if [ "$(id -u)" -ne 0 ]; then echo "must run as root (use sudo)" >&2; exit 1; fi

if [ "$UNINSTALL" -eq 1 ]; then
  say "removing:"
  for f in $USER_BIN;  do run rm -f "$BIN/$f"; done
  for f in $LIBEXEC_BIN; do run rm -f "$LIBEXEC/$f"; done
  for f in $HOOK_FILES;  do run rm -f "$HOOKS/$f"; done
  for f in $UNIT_FILES;  do run rm -f "$UNITS/$f"; done
  run rm -rf "$SHARE" "$DOCS"
  say "done. Re-enable or disable any units you had enabled separately."
  exit 0
fi

say "installing from $REPO"
run install -d -m 0755 "$BIN" "$LIBEXEC" "$HOOKS" "$UNITS" "$SHARE/patches/amdgpu-5k" "$DOCS"
run install -d -m 0755 /usr/local/sbin

say "  user-facing -> $BIN"
for f in $USER_BIN; do
  [ -f "$REPO/scripts/$f" ] && run install -m 0755 "$REPO/scripts/$f" "$BIN/$f"
done

say "  root / systemd -> $LIBEXEC"
for f in $LIBEXEC_BIN; do
  src=""
  [ -f "$REPO/scripts/$f" ] && src="$REPO/scripts/$f"
  [ -f "$REPO/kernel/$f" ]  && src="$REPO/kernel/$f"
  if [ -n "$src" ]; then run install -m 0755 "$src" "$LIBEXEC/$f"; else say "    WARNING missing source for $f"; fi
done

say "  patches -> $SHARE/patches/amdgpu-5k"
for f in "$REPO"/patches/amdgpu-5k/*.patch; do
  run install -m 0644 "$f" "$SHARE/patches/amdgpu-5k/"
done

say "  docs -> $DOCS"
for f in README.md THIRD_PARTY_NOTICES.md docs/*.md; do
  [ -f "$REPO/$f" ] && run install -m 0644 "$REPO/$f" "$DOCS/"
done

say "  kernel-install hooks -> $HOOKS"
for f in $HOOK_FILES; do
  src=""
  [ -f "$REPO/kernel/$f" ] && src="$REPO/kernel/$f"
  [ -f "$REPO/$f" ]        && src="$REPO/$f"
  if [ -n "$src" ]; then run install -m 0755 "$src" "$HOOKS/$f"; else say "    NOTE $f not in repo (may already be installed)"; fi
done

say "  sbin (legacy path used by 97-esp-prune.install) -> /usr/local/sbin"
for f in $SBIN_BIN; do
  [ -f "$REPO/scripts/$f" ] && run install -m 0755 "$REPO/scripts/$f" "/usr/local/sbin/$f"
done

say "  units -> $UNITS"
for f in $UNIT_FILES; do
  [ -f "$REPO/kernel/$f" ] && run install -m 0644 "$REPO/kernel/$f" "$UNITS/$f"
done

run systemctl daemon-reload

#--- sudoers. Deliberately NOT installed automatically: a wrong sudoers file can
# lock you out of sudo, and the username has to be substituted. See the file.
say ""
say "  sudoers/imac-brightness was NOT installed (it needs your username and a"
say "  visudo check first):"
say "    sed \"s/^YOUR_USER/\$USER/\" sudoers/imac-brightness | \\"
say "      sudo tee /etc/sudoers.d/imac-brightness >/dev/null"
say "    sudo chmod 0440 /etc/sudoers.d/imac-brightness"
say "    sudo visudo -cf /etc/sudoers.d/imac-brightness    # MUST pass"

say ""
say "done. Verify with:  $BIN/imac-verify"