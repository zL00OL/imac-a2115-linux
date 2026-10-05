#!/bin/bash
# Document the iGPU / P3 (wide gamut) situation on this A2115:
#  - is the hidden Intel iGPU present and bound to i915?
#  - what happens if it is enabled (it can steal HD-audio, silencing speakers)
#  - is a P3 ICC profile applied or available?
# Read-only. Nothing is probed or enabled here.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
# Authenticate once, up front, and let sudo prompt normally.
#
# This script used to write a plaintext sudo password to a temp file and pipe it
# into `sudo -S`. That put a real credential in a public repository, and the
# pattern is wrong anyway: a diagnostic has no business handling a password.
# The credentials are not merely stripped from the current file, they remain in
# git history - treat any password that was ever committed here as compromised
# and rotate it.
if ! sudo -n true 2>/dev/null; then
  echo "This audit reads a few /sys and /proc paths that need root." >&2
  echo "Authenticate first, then re-run:" >&2
  echo >&2
  echo "    sudo -v && $0" >&2
  echo >&2
  exit 1
fi
S() { sudo -n "$@"; }

echo "=== 1. GPUs present in PCI ==="
S lspci -nn | grep -iE "vga|display|3d" | sed 's/^/  /'

echo
echo "=== 2. is the Intel iGPU visible at all? ==="
S lspci -nn | grep -iE "8086:" | sed 's/^/  /' || echo "  no Intel display device on the PCI bus"
echo "  --- is i915 loaded? ---"
S grep -E "^i915" /proc/modules | sed 's/^/  /' || echo "  i915 NOT loaded (expected on most setups)"
S lsmod 2>/dev/null | grep -i i915 | sed 's/^/  /' || echo "  (not in lsmod)"
echo "  --- is it blacklisted on the cmdline? ---"
S grep -oE 'module_blacklist=[^ ]*' /proc/cmdline | sed 's/^/  /' || echo "  no module_blacklist on cmdline"
S grep -oE 'snd_hda_core\.gpu_bind=[^ ]*|i915[^ ]*' /proc/cmdline | sed 's/^/  /' || echo "  (no i915/gpu_bind params)"

echo
echo "=== 3. DRM nodes (renderD* indicate compute-capable devices) ==="
S bash -c 'ls -la /dev/dri/ 2>/dev/null' | sed 's/^/  /'
echo "  --- card to driver mapping ---"
for c in /sys/class/drm/card[0-9]/device; do
  [ -e "$c" ] || continue
  n=$(basename "$(dirname "$c")")
  drv=$(S readlink -f "$c/driver" 2>/dev/null | xargs -r basename)
  ven=$(S cat "$c/vendor" 2>/dev/null)
  dev=$(S cat "$c/device" 2>/dev/null)
  echo "  $n: driver=${drv:-none} vendor=$ven device=$dev"
done

echo
echo "=== 4. display connectors currently in use ==="
for s in /sys/class/drm/card*/status; do
  [ -e "$s" ] || continue
  n=$(echo "$s" | sed 's|.*/drm/||; s|/status||')
  printf '  %-16s %s\n' "$n" "$(cat "$s")"
done

echo
echo "=== 5. ICC / wide-gamut colour ==="
echo "  --- generated P3 profile? ---"
S bash -c 'ls -la /home/ilya/.local/share/icc/ 2>/dev/null' | sed 's/^/  /' || echo "  no icc dir"
S bash -c 'ls -la /home/ilya/.icm/ /usr/share/color/icc/ 2>/dev/null | head -20' | sed 's/^/  /' || echo "  no system ICC dirs"
echo "  --- kwinoutputconfig colour config ---"
S bash -c 'grep -iE "icc|profile|p3" /home/ilya/.config/kwinoutputconfig.json 2>/dev/null' | sed 's/^/  /' || echo "  (no ICC keys in kwinoutputconfig)"
echo "  --- colord present? ---"
S bash -c 'command -v colord >/dev/null && echo "  colord installed" || echo "  colord NOT installed"'
S rpm -qa 2>/dev/null | grep -iE "^colord|^kcm-color" | sed 's/^/  /' || echo "  (no colord packages)"

echo
echo "=== 6. Apple firmware set_os state (what gates the iGPU) ==="
S bash -c 'dmesg 2>/dev/null | grep -iE "apple_set_os|set_os|ImacSetOs"' | tail -5 | sed 's/^/  /' \
  || echo "  (no set_os messages in the ring buffer; these appear at boot)"

echo
echo "=== 7. audio safety check (the iGPU can silence HD-audio) ==="
S bash -c 'lsmod 2>/dev/null | grep -iE "snd_hda_intel|snd_hda_codec"' | sed 's/^/  /' \
  || echo "  (modules not loaded or names differ)"
S bash -c 'lsmod 2>/dev/null | grep -iE "i915"' | sed 's/^/  /' \
  && echo "  WARNING: i915 loaded - confirm speakers still work" \
  || echo "  i915 not loaded, so HD-audio is not at risk from it"
echo "DONE-IGPU"