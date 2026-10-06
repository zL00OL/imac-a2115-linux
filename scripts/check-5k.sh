#!/bin/bash
#==============================================================================
# check-5k.sh - read-only diagnostic for tiled 5K output on iMac A2115
#
#   sudo scripts/check-5k.sh
#
# Changes nothing. Tells you which of the distinct failure modes you have.
# See docs/tiled-5k.md for what to do about each result.
#==============================================================================
set -uo pipefail
S() { sudo -S -p '' "$@"; }
[ "$(id -u)" -eq 0 ] || S true

hr() { printf '%s\n' "------------------------------------------------------------"; }
note() { printf '  -> %s\n' "$*"; }
good() { printf '  [ ok ] %s\n' "$*"; }
bad()  { printf '  [BAD ] %s\n' "$*"; }
warn() { printf '  [warn] %s\n' "$*"; }

echo "=============================================================="
echo " iMac A2115 - tiled 5K diagnostic   $(date -Is)"
echo "=============================================================="

#---------------------------------------------------------------- 1. tiling
hr; echo "1. KERNEL TILING PARAMETER"
if [ -r /sys/module/amdgpu/parameters/tiled_stitch ]; then
  T=$(cat /sys/module/amdgpu/parameters/tiled_stitch)
  if [ "$T" = "-1" ]; then good "tiled_stitch=-1 (tiling ON, the verified value)"
  elif [ "$T" = "1" ]; then warn "tiled_stitch=1 — UNVERIFIED on this machine; the docs standardise on -1"
  else bad "tiled_stitch=$T (tiling OFF - two separate displays)"; fi
else
  bad "/sys/module/amdgpu/parameters/tiled_stitch missing"
  note "driver may have dropped the parameter; see docs/tiled-5k.md#parameter-missing"
fi
if grep -q 'amdgpu.tiled_stitch' /proc/cmdline; then
  good "cmdline: $(grep -o 'amdgpu.tiled_stitch=[^ ]*' /proc/cmdline)"
else
  warn "not present on the kernel command line (default 0 would apply)"
fi
echo "  amdgpu module: $(modinfo -F filename amdgpu 2>/dev/null)"
echo "  srcversion:    $(modinfo -F srcversion amdgpu 2>/dev/null)"
case "$(modinfo -F filename amdgpu 2>/dev/null)" in
  */updates/*) warn "module loaded from updates/ - this is a LOCAL OVERRIDE, not stock";;
  # Not a verdict on the driver. /lib/modules ALWAYS holds a stock copy on this
  # machine, because the patched one lives in the initramfs. Only /sys/module/...
  # srcversion tells you what is actually running - see the note above.
  *) note "on-disk copy at $1 is the kernel package build (expected: the patched driver lives in the initramfs, not here)";;
esac

#------------------------------------------------------------ 2. connectors
hr; echo "2. CONNECTORS"
NC=0
for c in /sys/class/drm/card*/status; do
  [ -e "$c" ] || continue
  name=$(echo "$c" | sed 's|/sys/class/drm/||; s|/status||')
  st=$(cat "$c" 2>/dev/null)
  en=$(cat "${c%/status}/enabled" 2>/dev/null)
  printf '  %-14s status=%-12s enabled=%s\n' "$name" "$st" "${en:-n/a}"
  [ "$st" = "connected" ] && NC=$((NC+1))
done
if [ "$NC" -ge 2 ]; then good "$NC connectors connected"
else bad "$NC connector(s) connected - tiling needs both"; fi

hr; echo "3. ACTIVE MODE PER CONNECTOR"
for m in /sys/class/drm/card*/modes; do
  [ -e "$m" ] || continue
  name=$(echo "$m" | sed 's|/sys/class/drm/||; s|/modes||')
  printf '  %-14s first=%-14s enabled=[' "$name" "$(head -1 "$m" 2>/dev/null)"
  tr '\n' ' ' < "${m%/modes}/enabled" 2>/dev/null | sed 's/$/]/'
done

#------------------------------------------------------------ 4. EDID match
hr; echo "4. EDID PHYSICAL SIZE / OFFSET  (a mismatch here causes the seam)"
have_decode=0; command -v edid-decode >/dev/null && have_decode=1
declare -a SZ=()
for d in /sys/class/drm/card*/edid; do
  [ -s "$d" ] || continue
  name=$(echo "$d" | sed 's|/sys/class/drm/||; s|/edid||')
  echo "  --- $name ---"
  if [ "$have_decode" -eq 1 ]; then
    edid-decode "$d" 2>/dev/null | grep -iE \
      'display product name|detailed timing descriptor|horizontal size|vertical size|vertical (offset|sync)' \
      | sed 's/^/    /'
    V=$(edid-decode "$d" 2>/dev/null | grep -oP 'vertical size:\s*\K[0-9]+' | head -1)
    H=$(edid-decode "$d" 2>/dev/null | grep -oP 'horizontal size:\s*\K[0-9]+' | head -1)
    SZ+=("$name:${H}x${V}mm")
  else
    note "edid-decode not installed; raw size $(stat -c%s "$d") bytes"
  fi
done
if [ "$have_decode" -eq 1 ]; then
  if [ "${#SZ[@]}" -ge 2 ]; then
    uniq_count=$(printf '%s\n' "${SZ[@]}" | sed 's/.*://' | sort -u | wc -l)
    if [ "$uniq_count" -eq 1 ]; then good "both halves report the same physical size"
    else warn "PHYSICAL SIZE MISMATCH between halves: ${SZ[*]}"
         note "this is a prime cause of a vertical seam/displacement"; fi
  fi
else
  warn "install edid-decode for EDID analysis (zypper install edid-decode)"
fi

#---------------------------------------------------- 5. compositor's view
hr; echo "5. COMPOSITOR OUTPUT CONFIGURATION"
if command -v kscreen-doctor >/dev/null; then
  # kscreen-doctor talks to the session over the user bus. Run under sudo it
  # cannot see the session and reports 0 outputs, which looks like a fault.
  # Ask as the session owner instead.
  SUDO_U=${SUDO_USER:-$(logname 2>/dev/null || echo ilya)}
  kscreen-doctor -o 2>/dev/null | sed 's/^/  /'
  NOUT=$(su -c 'kscreen-doctor -o 2>/dev/null | grep -c "^Output:"' "$SUDO_U" 2>/dev/null || echo "?")
  [ "$NOUT" = "0" ] && echo "  (0 outputs can also mean this ran outside the graphical session)"
  echo "  outputs reported: $NOUT"
  if [ "$NOUT" -eq 1 ]; then good "compositor sees ONE output (tiled as intended)"
  else warn "$NOUT outputs - tiling may not be reaching the compositor"; fi
else
  warn "kscreen-doctor unavailable"
fi

hr; echo "6. LINK BAND / DST GEOMETRY (from dmesg)"
if [ -r /var/log/kern.log ] || dmesg >/dev/null 2>&1; then
  dmesg 2>/dev/null | grep -iE 'amdgpu.*(link band|dst-|stitch|tiled)' | tail -12 | sed 's/^/  /' \
    || echo "  (no link-band messages in the ring buffer; they appear at boot)"
  note "reboot and re-run to capture these"
else
  warn "cannot read dmesg"
fi

#------------------------------------------------------------ 7. verdict
hr; echo "7. SUMMARY"
T=$(cat /sys/module/amdgpu/parameters/tiled_stitch 2>/dev/null || echo "?")
NOUT=$(kscreen-doctor -o 2>/dev/null | grep -c '^Output:')
cat <<EOF
  tiling parameter : $T  (cmdline value is -1; the sysfs readback is UNVERIFIED - see docs/tiled-5k.md)
  compositor views : $NOUT output(s)  (want 1)
  connectors live  : $NC  (want >= 2)

  A SEAM CANNOT BE DIAGNOSTICALLY CONFIRMED BY SCRIPT.
  Verify by hand - docs/tiled-5k.md section 6:
    1. drag a window slowly across the vertical midline
    2. show a 1px vertical grid spanning the full 5120 width
    3. check the SDDM greeter too (separate Xorg path)
EOF
hr
echo "Next: read docs/tiled-5k.md"