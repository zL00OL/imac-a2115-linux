# iGPU and P3 wide-gamut colour

**Status on this machine: NOT AUDITED.** The iMac was powered off before this
could be checked. Everything below is either (a) from the reference project for
sibling hardware, or (b) from earlier notes on this machine that have not been
re-verified. Run `scripts/check-igpu.sh` when the machine is on.

---

## The hidden Intel iGPU

The A2115 has, alongside the Radeon, an **Intel HD 630** (`8086:5912`) that Apple
firmware deliberately hides. macOS normally wakes it via the Apple `set_os` EFI
protocol and runs it **headless** — no framebuffers — using it only for video
encode/decode (H.264/HEVC), while the Radeon drives the display.

Nobody has published i915 working on an iMac18,x under Linux. The only upstream
attempt (an iMac20,1, early 2026, unmerged) **blanked the Radeon-driven panel**
once i915 probed a display it invented.

### ⚠️ The most dangerous consequence

> Once the iGPU becomes visible, `snd_hda_intel` waits on i915 forever
> (`-EPROBE_DEFER` in `snd_hdac_i915_init`) and **the speakers and microphones
> vanish**.

This is why the reference project uses `snd_hda_core.gpu_bind=0` rather than
`probe_mask`: with `gpu_bind=0`, HD-audio never waits for i915, so even a failing
i915 cannot take the speakers with it.

Given that **audio is already the worst problem on this machine** (distorted at
every level), enabling the iGPU without `gpu_bind=0` risks losing audio
entirely. Do not experiment on a machine you depend on.

### Safe enablement, if you want it

Not needed for 5K. Only pursue for hardware video encode/decode.

1. **Verify `set_os` works first.** It requires an EFI-stage `set_os` call
   (`imac-setos` mkinitcpio hook, or an `imac-set-os.efi` chainloader) before the
   kernel starts. Without it the iGPU stays hidden and nothing happens.
2. **Always add `snd_hda_core.gpu_bind=0`** when i915 binds.
3. **Keep i915 headless:** `i915.disable_display=1` plus a no-outputs VBT
   (`i915.vbt_firmware=…`). If i915 claims a connector, the panel blanks and you
   lose the desktop.
4. **Keep the Radeon as boot VGA** and pin the compositor to it. Verify after
   every boot that the 5K desktop is on `amdgpu` and audio still plays.

### What to check

```bash
# is the Intel iGPU even on the bus?
lspci -nn | grep -iE "8086:"

# is i915 loaded? (should NOT be, in a safe default config)
lsmod | grep i915

# DRM nodes: AMD should own the card, Intel only ever a render node
ls -la /dev/dri/

# which driver owns each card
for c in /sys/class/drm/card[0-9]/device; do
  echo "$(basename $(dirname $c)): $(basename $(readlink -f $c/driver))"
done
```

A healthy configuration looks like: **Radeon owns `card*` and drives the
panel**; any Intel device appears only as `renderD*` with **zero connectors**.

---

## P3 wide-gamut colour

**Status: unresolved.** Earlier notes recorded a generated profile at
`/home/ilya/.local/share/icc/imac5k-p3.icc` and an active ICC entry in
`~/.config/kwinoutputconfig.json`, but also recorded that activation was
**blocked by invalid EDID chromaticity bytes `0x19-0x1C`**. Neither the file nor
the block was re-verified.

The A2115's panel is a wide-gamut P3 display. Getting P3 output working needs:

1. A valid ICC profile matching the panel.
2. KWin applying it to the tiled output.
3. `colord` installed, or the profile applied directly in
   `kwinoutputconfig.json`.

### Why this may be hard here

**Tiling complicates colour management.** Both halves are one logical output, so
a single profile must describe the pair. If the two connectors' EDIDs disagree on
chromaticity — which is exactly what the recorded `0x19-0x1C` invalid bytes
suggest — KWin may reject or misapply the profile. The same EDID inconsistency is
also the classic cause of the vertical seam described in `docs/tiled-5k.md`, so
one underlying fault could explain both.

If you pursue P3, verify **both connectors** decode cleanly first:

```bash
for d in /sys/class/drm/card*/edid; do
  echo "=== $d ==="
  edid-decode "$d" 2>/dev/null | grep -iE 'chromaticity|red|green|blue|white point'
done
```

The sibling reference project advertises "true wide-gamut colour" as a headline
feature, so it is achievable — but it targeted **iMac18,3** on Omarchy/Arch, not
A2115 on openSUSE.

---

## Why this is secondary

Neither the iGPU nor P3 affects the seamless 5K desktop. The display already
works with the stock Radeon alone. Add the iGPU only for hardware video encode,
and treat P3 as a colour-fidelity improvement. Neither is required.

**Audit first, then decide.** `scripts/check-igpu.sh` is read-only and will
report the actual state on this machine.