# Tiled 5K: diagnosing and fixing the seam

> **Status: VERIFIED for seamless tiling.**
> The seam was diagnosed and fixed on the reference machine, now running
> `7.2.7-1-default` where the stitching is upstream. `tiled_stitch=-1` is
> measured in both sysfs and the kernel command line. Cold-boot panel
> initialisation remains **BROKEN** — see `docs/kernel-updates.md`.

The panel is two 2560x1440 halves that must behave as **one seamless
5120x2880 desktop**. This document covers how to tell what is actually wrong,
because the symptoms overlap and the causes are different.

Run `scripts/check-5k.sh` first — it prints the state of every relevant thing
and tells you which section below applies.

---

## Kernel 7.2.7 and later: no patch needed for the stitching

> Upstream `amdgpu` gained native `tiled_stitch` between 7.2.2 and 7.2.7, and
> **the SUSE binary module ships it** — claims that it must be rebuilt from
> source are wrong, and the measurement is below.
>
> Note this is about the *parameter only*. `patches/amdgpu-5k/imac5k-stitch-layer-7.x.patch`
> is still required, because the shipped module has the parameter but not the
> second-tile implementation behind it. See
> [All six are still needed](reference-system.md#all-six-are-still-needed).

```c
// drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c, 7.2.7
int amdgpu_tiled_stitch = -1; /* auto */
module_param_named(tiled_stitch, amdgpu_tiled_stitch, int, 0444);
bool amdgpu_dm_has_tiled_stitch_panel(struct amdgpu_device *adev);
```

### What the source has vs what the module has

This is the distinction that was got wrong. Both are true, and only the second
one matters:

```
$ grep -c tiled_stitch /usr/src/linux-7.2.8-1/drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c
5                                  <- the SOURCE has it

$ modinfo -p amdgpu | grep -c tiled_stitch
1                                  <- ...but only because updates/ has OUR patched build
```

Against the **shipped** module the answer is 0:

```bash
$ zstd -dc /usr/lib/modules/7.2.8-1-default/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst > /tmp/s.ko
$ modinfo -p /tmp/s.ko | grep -c tiled_stitch
0
$ modinfo -F srcversion /tmp/s.ko
4BFAA1013BED7E3FB557CF0
```

Note `modinfo -p <file>.ko.zst` prints **nothing**, because modinfo does not
decompress zstd. An empty result is not evidence of absence; it is evidence of
a tool that cannot read the file. Decompress first, as above.

### The check that actually decides it

```bash
# loaded driver
cat /sys/module/amdgpu/srcversion                       # 31F26E96... = ours
                                                          # 4BFAA101... = stock
# and where it came from
modinfo -n amdgpu          # .../updates/amdgpu.ko.zst  = ours
                           # .../kernel/...            = stock
```

### All six patches are required

There is no subset. Each patch covers something the shipped module and the
upstream source both lack:

| Patch | On 7.2.8 |
|---|---|
| `imac5k-stitch-layer-7.x.patch` | **needed** — adds the `tiled_stitch` module parameter |
| `amdgpu-vce3-ring-align-mask.patch` | **needed** — `vce_v3_0.c:939` still has `align_mask = 0xf` |
| `imac5k-lean-core-7.2.x.patch` | **needed** — second-tile wake (`0x4f1`) and genlock are not upstream |
| `imac5k-stitch-hide-slave.patch` | **needed** — `amdgpu_dm_link_is_tiled_stitch_slave()` is not upstream |
| `amdgpu-hpd-skip-during-reset.patch` | **needed** — no `amdgpu_in_reset` guard upstream |
| `amdgpu-vce-suspend-in-reset.patch` | **needed** — no `amdgpu_in_reset` guard in `amdgpu_vce.c` |

All six applied to `/usr/src/linux-7.2.8-1` at `--fuzz=0`, and the module built
from that tree is the one the machine booted.

**A reduced subset has never been booted.** Treat all six as required until one
is proven droppable on a real boot, not by source inspection.

### It works differently, and that is the better behaviour

The out-of-tree patch presents **two connectors** (`eDP-1` and `DP-1`), each
showing half the picture, stitched by the compositor. Upstream instead
synthesises a **single stitched EDID** and exposes only one connector:

```
TILED_STITCH: synthesized root EDID for eDP-1 from source vendor=06 10
              product=0xae26 name="iMac" mode 5120x2880 clock=966500
TILED_STITCH: exposed only stitched mode 5120x2880 on eDP-1 (tile 2560x2880)
TILED_STITCH: kept synthesized stitched mode 5120x2880 on eDP-1 (tile 2560x2880)
```

Consequences when diagnosing on 7.2.7:

- **`DP-1` will report `disconnected` and that is correct.** There is only one
  connector. Do not chase it.
- Section 3 (comparing the two connectors' EDIDs) does not apply; there is one.
- The seam cannot exist in the same way, because the kernel is presenting a
  single logical display rather than asking the compositor to align two.

### `tiled_stitch` is read-only and cannot be switched at runtime

```c
module_param_named(tiled_stitch, amdgpu_tiled_stitch, int, 0444);
```

Mode `0444` means read-only for *everyone* — `/sys/module/amdgpu/parameters/tiled_stitch`
is `-r--r--r--` and not writable even as root. The stitched EDID is synthesised
once during connector probe, not per-modeset, so **"boot untiled and stitch
later" is not possible.** It is a boot-time decision only.

### The sysfs readback question, resolved

The note below asks whether `tiled_stitch` is `bool` or `int`. Upstream 7.2.7
declares it as **`int`**, so it reads back verbatim and the command line and
sysfs agree:

```
$ grep tiled_stitch /proc/cmdline
amdgpu.tiled_stitch=-1
$ cat /sys/module/amdgpu/parameters/tiled_stitch
-1
```

The earlier contradiction came from the out-of-tree patch, which used a
different type. On any patched kernel the sysfs value is therefore not
authoritative, because the patch changes the type the kernel prints.

### `amdgpu` takes about 8 seconds to initialise

Loading Polaris firmware dominates, and it has a direct consequence:

```
[2.2s]  efidrm (EFI framebuffer)
[2.8s]  Plymouth starts
[8.1s]  amdgpu initialised, stitched EDID exposed
```

Any boot splash has under a second of usable display. Plymouth cannot be made
to show on this machine for this reason alone — see
[`docs/recovery.md`](recovery.md#plymouth-cannot-display-here).

### Building the 7.2.7 module (not needed for stitching, still needed for the other four patches)

The module is large; strip it or the initramfs becomes unwieldy:

```bash
cd /usr/src/linux-7.2.7-1
make O=/usr/src/linux-7.2.7-1-obj/x86_64/default \
     M=drivers/gpu/drm/amd/amdgpu modules -j"$(nproc)"
objcopy --strip-debug drivers/gpu/drm/amd/amdgpu/amdgpu.ko /tmp/amdgpu.ko
zstd -19 -f /tmp/amdgpu.ko -o /usr/lib/modules/7.2.7-1-default/updates/amdgpu.ko.zst
depmod -a 7.2.7-1-default
```

787 MB unstripped → 32.8 MB stripped → **5.0 MB compressed**. Install it into
`updates/` and depmod; then it must also be in the initramfs, or the initramfs
copy wins at boot.

If `/usr/src` is read-only — which it is on a snapper snapshot other than the
one you built in — use an overlay instead of copying ~1.4 GB:

```bash
mkdir -p /var/tmp/src-ovl/{upper,work,merged}
mount -t overlay overlay \
  -o lowerdir=/usr/src,upperdir=/var/tmp/src-ovl/upper,workdir=/var/tmp/src-ovl/work \
  /var/tmp/src-ovl/merged
```

### The log burst is a 10-second boot-time burst

Upstream logs one line per modeset. Measured on the reference machine: **242
lines, all within the first 10 seconds, then zero** for the rest of the boot
and afterwards. It is not a modeset loop and not a power problem. Anything that
keeps Plymouth or the console hidden covers it; a journal cap is enough for
the rest.

---

> [!NOTE]
> **`tiled_stitch` is declared `int`, so it reads back verbatim.** Settled by
> measurement on 7.2.8:
>
> ```
> module_param_named(tiled_stitch, amdgpu_tiled_stitch, int, 0444);
> parm: tiled_stitch: ... (-1 = auto/default, 0 = disable, 1 = enable ...) (int)
> ```
>
> Any claim that `sysfs` should report `1` while the command line says `-1` is
> wrong: there is no `bool` normalisation to perform. The kernel command line
> remains authoritative — `amdgpu.tiled_stitch=-1` on this machine.
>
> **How to record a change.** Open an issue on this repository titled
> `tiled_stitch sysfs readback: <1 or -1>` and paste the output of all four:
>
> ```bash
> uname -r
> grep tiled_stitch /proc/cmdline
> cat /sys/module/amdgpu/parameters/tiled_stitch
> modinfo -k "$(uname -r)" amdgpu | grep tiled_stitch
> ```
>
> Include `uname -r`, because the answer may differ by kernel series. When
> someone reports a result it gets folded into this note. Until then the command
> line remains the value to trust.

## 1. Confirm tiling is on

Tiling is a DRM/KMS feature. It must be active **before** the display server
starts, so it comes from the kernel command line.

```bash
grep tiled_stitch /proc/cmdline                # want: amdgpu.tiled_stitch=-1
cat /sys/module/amdgpu/parameters/tiled_stitch   # expect: -1 (measured; see "The sysfs/cmdline readback" below)
```

| Value | Meaning |
|---|---|
| `1` | tiled — correct |
| `0` | not tiled; you have two monitors |
| file missing | parameter not exposed; see [parameter missing](#parameter-missing) |
| cmdline has no flag | default `0` applies |

To change it, edit the kernel command line in the boot entry you actually use:

```bash
# find your default entry
grep -m1 '^default' /boot/efi/loader/loader.conf
# add tiled_stitch=-1 to its options= line
sudoedit /boot/efi/loader/entries/<that-entry>.conf
```

A **reboot is required** — this is a kernel module parameter, not a runtime
setting.

### Parameter missing

Newer amdgpu versions have reworked or dropped `tiled_stitch`. Check what your
kernel exposes:

```bash
modinfo amdgpu | grep -iE 'stitch|tile|link_band'
ls /sys/module/amdgpu/parameters/ | grep -iE 'stitch|tile'
```

Depending on the version, tiling may be enabled implicitly whenever both
connectors carry the same mode, or it may need `drm.edid` overrides. If the
parameter genuinely does not exist, the tiling must come from the display
server instead — see [section 5](#5-if-the-kernel-will-not-tile).

---

## 2. Both connectors must be active and identical

Tiling only happens if **both** links are connected, enabled, and carrying the
**same mode**. If one connector is off, you get one monitor, not a seam.

```bash
for c in /sys/class/drm/card*/status; do
  printf '%-40s %s\n' "$c" "$(cat "$c")"
done
```

Expect both `connected` and `enabled`.

```bash
# modes actually enabled on each connector
for m in /sys/class/drm/card*/modes; do
  printf '%-40s %s\n' "$m" "$(head -1 "$m")"
done
```

Each should read `2560x1440`. If one is blanked or running a different mode,
that is why tiling is not taking.

---

## 3. Diagnosing an actual seam

Assume tiling is on and you see one desktop, but with a defect at the vertical
midline. Work through these in order.

### 3a. Is it a black gap, or a displacement?

A **black gap** means the halves do not meet: there is a run of pixels that
belong to neither. A **content jump** means they meet but are offset by some
number of pixels or scanlines. The cause is the same — the two links disagree
about vertical position — but the visible result differs by whether the panel
bezels hide the transition.

### 3b. Compare the two connectors' EDIDs

The single most common cause is the two halves reporting **different physical
dimensions or vertical offsets**, which makes the compositor scale them
differently.

```bash
for d in /sys/class/drm/card*/edid; do
  echo "=== $d ==="
  edid-decode "$d" 2>/dev/null | grep -iE \
    'display product name|detailed timing descriptor|horizontal size|vertical size|vertical offset|vertical sync|range limits'
done
```

Compare across connectors. If **horizontal size / vertical size** (the physical
mm) differ, or one reports a **vertical offset** and the other does not, that is
your seam.

On this machine the panel's true physical size is **600x340 mm** (~217 DPI). If
Xorg or the greeter instead sees 1354x762 mm, that is the DPI quirk in
`docs/hardware.md#xorg-reports-96-dpi-on-the-5k-panel` — related but a
different symptom.

### 3c. Look at what the compositor composed

```bash
kscreen-doctor -o
```

Look for:

- **One** output at `5120x2880` — correct.
- **Two** outputs at `2560x1440` each — tiling is not reaching the compositor.
- A single output whose `scale` is not `1` — a fractional scale on a tiled
  desktop resamples both halves and can expose or shift the seam. Prefer scale 1.

### 3d. Check the link band / connector order

The tiled framebuffer maps connectors to display areas. If the mapping is
swapped or the vertical extents do not add up, you get a displacement.

```bash
# dmesg at boot records link band setup
sudo dmesg | grep -iE 'amdgpu.*(link band|stitch|dst-|tiled|connector)'
```

Look for `dst-x`/`dst-y` values. For a seamless 5120-wide tile, each connector
should cover a 2560-wide slice with **no overlap and no gap**, and both should
share the same `dst-y` and `dst-height`.

If dmesg shows overlap or a mismatch, this is a driver-side tiling decision and
not something you can fix in the display server.

---

## 4. Fixes, most likely first

Work down this list; stop when the seam is gone.

**1. Force integer scale 1 on the tiled output.** Fractional scaling is the
most common *fixable* cause of a visible midline.

```
kscreen-doctor output.<name>.scale 1
```

or in System Settings → Display → Scale → 100%.

**2. Reset and re-apply the output config.** KWin caches geometry per output and
a stale entry is a common cause after an upgrade.

```bash
# back up first
cp ~/.config/kwinoutputconfig.json{,.bak-$(date +%F)}
rm ~/.config/kwinoutputconfig.json
# log out and back in so KWin re-detects
```

**3. Re-apply the kernel parameter and reboot.** If `tiled_stitch` was not
actually active, nothing above will matter.

**4. Override EDID physical size.** If the two halves report inconsistent
physical dimensions, pin them. Requires a kernel cmdline edit and a reboot:

```
drm.edid=0x<connector>,edid=<hex>
```

Get the hex from `/sys/class/drm/card*/edid` (`xxd -p`), and you need the
connector name (`card1-DP-2` style) from the sysfs path.

**5. Test with the greeter.** SDDM's greeter is plain Xorg and is much easier to
read than a busy session. If the seam is visible on the login screen, it is
display-driver level and not a KWin configuration issue. This is a genuinely
useful bisection step — use it early.

---

## 5. If the kernel will not tile

If `tiled_stitch` is unavailable and the driver does not tile on its own, you
cannot get a true single framebuffer. The fallback is a **scaled dual-head
desktop**, which is visually almost identical but is two outputs:

```bash
kscreen-doctor output.<left>.mode  2560x1440
kscreen-doctor output.<right>.mode 2560x1440
# position the right one exactly adjacent to the left
```

This will never be truly seamless — there is always a boundary the compositor
cannot cross — so treat it as a fallback, not a fix. Be honest about the
difference when judging results.

---

## The sysfs/cmdline readback: settled 2026-10-06

Previously unresolved - sysfs was reported as reading `1` while the command line
said `-1`. Read on the machine:

```
sysfs  : -1
cmdline: amdgpu.tiled_stitch=-1
```

**They agree, and `-1` is correct.** Tiling is on; no discrepancy exists. If a
future report claims sysfs reads `1`, that is a different kernel build, not a
new finding.

## 6. Verifying success

Do not trust a screenshot alone; a screenshot of a tiled desktop can look
correct while the physical seam is still visible.

1. **Move a window slowly across the midline.** A displacement or gap shows up
   immediately as a jump.
2. **Display a 1px vertical grid** spanning the whole desktop at true 5120 width.
   Lines must be continuous and evenly spaced through the middle.
3. **Check on the greeter too** — it is a separate display server path.
4. **After any change, reboot** if you touched the kernel command line, then
   re-run `scripts/check-5k.sh` and confirm the parameter is still set.

## 7. What has actually been verified here

**Confirmed working and seamless.** One 5120x2880 desktop, no gap, no
displacement across the midline. This needs a **patched** `amdgpu` — built from
`patches/amdgpu-5k/` and supplied by the custom initramfs — together with
`amdgpu.tiled_stitch=-1`. No EDID override and no per-connector fixes were needed
beyond what the patch itself does.

The next section is the authority on which driver is actually loaded and how to
confirm it on your own machine. Read it before changing anything: the claim that
the stock driver is sufficient is wrong, and acting on it costs you the second
tile.

If someone reproduces this on similar hardware and *does* see a seam, the checks
in section 3 are still the right starting point — but note that this machine did
**not** need them. The likeliest difference between setups is fractional
scaling: force scale `1` on the tiled output before investigating anything else.

Recording any future change here as you test is worthwhile.
---

## Which `amdgpu` is actually loaded, and why it is not the stock one

This is the load-bearing fact for everything above, and it is worth stating
plainly because getting it wrong is expensive: **the stock driver cannot do
this.**

A common claim is that the seamless 5K comes from the stock driver plus
`amdgpu.tiled_stitch=1`. That is wrong, and the evidence is unambiguous:

```
loaded  /sys/module/amdgpu/srcversion  : 6BE242C1C62DD79046F2E9A
on-disk /lib/modules/7.2.2-1-default/.../amdgpu.ko.zst : 4FA5DDFCFF3DDAE9F5FE22E
```

The loaded module matches **none** of the three files in that directory
(`amdgpu.ko.zst`, `amdgpu.ko.zst.stock`, `amdgpu.ko.5k-backup` are all
byte-identical, 6826583 bytes), and `rpm -V kernel-default` reports the package
intact.

The patched module is **embedded in the initramfs**:

```
$ lsinitrd /boot/efi/opensuse-slowroll/7.2.2-1-default/initrd-stackC | grep amdgpu/amdgpu
amdgpu/amdgpu.ko.zst
```

That is also why the running driver emits messages that exist nowhere in the
on-disk copies or in the 7.2.7 source tree:

```
APPLE5K: link-health build=post-commit-recovery checks=8 recoveries=2
TILED_STITCH: root eDP-1 re-read as product 0xae26 with tile block (attempt 1)
TILED_STITCH: synthesized root EDID for eDP-1 from source vendor=06
TILED_STITCH: exposed only stitched mode 5120x2880 on eDP-1 (tile 2x2)
```

### Confirming which module is loaded

```bash
cat /sys/module/amdgpu/srcversion
modinfo -F srcversion amdgpu
dmesg | grep -m3 -E 'APPLE5K|TILED_STITCH'
```

If `APPLE5K` lines appear, the initramfs patch is active. Do **not** install a
second patched `amdgpu.ko` into `/lib/modules` — the initramfs copy is already
the one in use, and the two will not agree.

### Consequence

`initrd-stackC` is not optional. It carries the display patch. Rebuilding it
from a stock kernel would leave the machine with a 4K panel and, historically,
an unreachable boot.

---

## Known fault: panel fails to initialise on cold boot

The display intermittently fails to come up at 5120x2880, most reliably on a
cold boot and less often on a warm reboot. Observed once taking **2 hours 15
minutes**, during which the machine had no network address at all and could not
be reached remotely.

The initramfs patch logs an 8-pass `link-health` retry loop, and on the bad boot
the tiled-stitch sequence did not complete until `dmesg` timestamp 8109 s.

### Root cause, from the driver tracker

[`ahmadtv/omarchy-imac18-3` issue 7](https://github.com/ahmadtv/omarchy-imac18-3/issues/7)
traces this on an iMac18,3 to an **insufficient AUX-wake timing budget**: the
number of retry attempts allotted before giving up on AUX wake is too low, so
link training gives up before the panel has finished waking. Their fix raises
the attempt counts, not the timeouts, and was validated on two machines.

Current values in the 7.2.7 source on this system:

| File | Setting | Value |
|---|---|---|
| `link_dpms.c:80` | `LINK_TRAINING_ATTEMPTS` | 4 |
| `link_detection.c:68` | `LINK_TRAINING_MAX_VERIFY_RETRY` | 2 |

**Status: identified, not applied.** Applying it means patching whichever source
tree produced the `initrd-stackC` amdgpu, which is not currently on disk —
`/var/cache/5kbuild` was removed once it was confirmed unnecessary for the audio
driver, and it did contain the built module tree.

Until this is fixed, treat a long dark or bright screen after power-on as
**normal, not a hang**: leave it alone. It resolved itself once. Forcing a
power cycle is what risks losing access.


## Measured state on 7.2.8, and how far this goes

> Measured 2026-10-10 on `7.2.8-1-default` (`amdgpu` srcversion
> `31F26E96354E3264CF28120`). All of this is read out of the live system, not
> inferred from the source.

### The stitch path is fully engaged

From `dmesg` at boot:

```
TILED_STITCH: synthesized root EDID for eDP-1 from source vendor=06 10 product=0xae26 name="iMac"
TILED_STITCH: exposed only stitched mode 5120x2880 on eDP-1 (tile 2560x2880)
TILED_STITCH: forced root stream to 2560x2880 tile timing (crtc mode is 5120x2880)
TILED_STITCH: crtc=71 root link[0] stream timing 2560x2880 total 2720x2962 pixclk_100hz=4832500
TILED_STITCH: added peer slave-tile stream link[1] 2560x2880 (one crtc drives both tiles)
TILED_STITCH: forcing initial modeset so both tiles are live before first paint
TILED_STITCH: kept synthesized stitched mode 5120x2880 on eDP-1 (tile 2560x2880)
```

One CRTC drives both tiles, the root stream is forced to tile timing, and both
links come up. Panel reports `connected` at `5120x2880`, with `card2-DP-4/5/6`
all disconnected — the slave tile is correctly *not* exposed as its own output.

### Genlock is NOT confirmed

This is the gap. `amdgpu_dm_force_timing_sync` reads `0`, and `dmesg` contains
**no** genlock, `sync_enabled`, per-frame CRTC reset or vblank-sync messages.
So the software asserts tiling is configured; nothing in the logs states the
two links are scanout-synchronised.

What that means: "one seamless 5120x2880 desktop" is verified as a
**configuration** fact — one connector, one CRTC, two tiles, correct timing.
Whether the two halves are **genlocked in phase** is unverified, and that is
exactly what a visible seam during scrolling would be.

The debugfs handle exists and is writable:

```bash
cat /sys/kernel/debug/dri/0000:01:00.0/amdgpu_dm_force_timing_sync   # 0
```

Writing `1` forces per-frame CRTC reset. That is a *forcing* switch, not a
readout of the current state — there is no read-only way to ask "are these two
links currently in sync". Confirming genlock therefore needs **Tier 1
measurement**, not a sysfs value.

### Measuring it properly

**Tier 1 — high-speed camera.** 1000+ fps, shutter open long enough to span a
frame. Display a pattern that encodes its own frame number or a unique moving
marker crossing y=1440. If the seam is genlocked, the marker is one unbroken
edge; if not, it is stepped, displaced or duplicated across the midline.

**Tier 2 — LED strobe.** A pulsed LED bar photographed with a long exposure.
The pulse is far shorter than a frame, so it renders as a thin line at the exact
scan position; tearing shows as two lines. This is the cheapest rig that
reaches rigour, and is how panel makers validate scanout.

**Tier 3 — software, no camera.** Frame pacing and missed frames via
`presentmon -a`; KWin presentation logging via
`QSG_RENDER_LOOP=basic QT_LOGGING_RULES='qt.scenegraph.general=true'`.
These prove frames are being dropped, which is a different question from whether
the two tiles are in phase.

None of these can answer the genlock question on its own. Tier 3 shows *that*
frames are lost; only Tier 1 or 2 shows *where on the panel* they are lost.

## Boot log findings (7.2.8, one boot, 58 min)

| Item | State |
|---|---|
| amdgpu GPU resets | **0** |
| Failed units | **0** |
| Panel | `connected`, `5120x2880` |
| `tiled_stitch` | `-1` |
| i915 VBT | `Failed to find VBIOS tables (VBT)`, then `DDI A/PHY A failed to retrieve link info, disabling eDP` |

**The i915 messages are expected and harmless.** They are the phantom-connector
case described in `docs/igpu-and-quicksync.md`: with no VBT, i915 invents a port
and immediately disables it. i915 renders nothing — amdgpu owns the panel — so
this costs nothing but log noise.

**One transient during the session, self-recovered:**

```
[2184.908951] amdgpu: enabling link 1 failed: 15
```

`link 1` is the peer slave-tile link. The surrounding `TILED_STITCH` lines show
it was immediately re-added, and the panel stayed at `5120x2880` with zero GPU
resets. This is a link re-enable attempt, not a reset; worth watching if it ever
recurs more than once.

**One kernel oops, caused by reading debugfs:**

```
BUG: kernel NULL pointer dereference
RIP: dmub_trace_mask_show+0x37 [amdgpu]
Oops: ... Comm: grep  Tainted: G OE
Call Trace: simple_attr_read -> debugfs_attr_read -> vfs_read
```

`dmub_trace_mask_show` is an amdgpu debugfs handler. Scanning every file under
`/sys/kernel/debug/dri/0000:01:00.0/` with `grep` reads that attribute and hits
a null deref inside the handler. No data is at risk — it is a read path — but
**do not brute-force `grep` across `/sys/kernel/debug/dri/*`**, and read the
specific files you want instead.

The `Tainted: G OE` is the expected consequence of loading an out-of-tree,
unsigned `amdgpu`: `O` = out-of-tree, `E` = unsigned module. That is the price
of the 5K patches and is not itself a fault.
