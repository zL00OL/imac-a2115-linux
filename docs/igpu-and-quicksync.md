# Exposing the hidden Intel iGPU (and with it, QuickSync)

> **Status: WORKING on iMac19,1.** Applied and verified. `00:02.0`
> (`8086:3e92`, UHD 630) is enumerated, `i915` binds, and QuickSync reports H.264,
> H.265 and VP8 **encode** profiles. The 5K panel still tiles and the patched
> CS8409 codec is unaffected.
>
> This page previously said "NOT APPLIED" and "not verified on iMac19,1". Both
> were wrong by the time you read them. The approach was sound; my conclusion
> that it could not work was not. See [What actually happened](#what-actually-happened).

## Why this exists

The CPU is an i5-8500, whose integrated GPU (Intel UHD 630) can encode H.264 and
H.265 in hardware via QuickSync. That matters for things like OBS recording,
which on this machine otherwise has to use software encoding.

On this machine there is **no GPU encoder at all** on the discrete card:

```
$ vainfo
VAProfileMPEG2Simple  : VAEntrypointVLD      ← decode only
VAProfileJPEGBaseline : VAEntrypointVLD      ← decode only
VAProfileNone         : VAEntrypointVideoProc
```

No encode profiles. The Radeon Pro 570X (Ellesmere, `1002:67df`) exposes no VCN
encoder through VAAPI, and there is no NVIDIA card, so NVENC is irrelevant. The
only hardware encoder reachable on this machine is QuickSync — and that needs
the iGPU, which Apple firmware does not publish.

## The actual mechanism (this is not a firmware patch)

This is the part most write-ups get wrong, including earlier notes in this
project, which described it as an "EFI byte patch". **That was wrong, and this
page corrects it.**

Apple firmware hides the integrated GPU unless the boot loader tells it
"macOS is booting", using Apple's `set_os` EFI protocol, called **before**
`ExitBootServices`. The Linux kernel's own EFI stub already implements this call
— but only for the models listed in `apple_match_product_name()`:

```c
/* drivers/firmware/efi/libstub/x86-stub.c */
static const char type1_product_matches[][15] = {
        "MacBookPro11,3", ... "MacBookPro16,4",
};
```

That list is MacBookPro-only. An iMac is not in it, so the call never happens,
firmware never exposes `00:02.0`, and the iGPU stays invisible to Linux.

**So the fix is to make the kernel's stub make that call for this machine.** Two
ways, and neither involves writing to firmware:

| Approach | What it touches |
|---|---|
| **A — source patch** | Add `"iMac19,1"` to `type1_product_matches[]` in `x86-stub.c` and rebuild the kernel. |
| **B — post-build byte edit** | The list sits **uncompressed** in the built EFI stub as 15-byte NUL-padded slots. Overwrite the last slot (`MacBookPro16,4`, a model this machine never was) with `iMac19,1`. |

Approach A is the right one here. This project already rebuilds the kernel and
the initramfs (`docs/kernel-updates.md`), so adding one string to one table costs
nothing extra and produces a normal, reproducible package. Approach B exists in
the reference project because they generate a **UKI** for Limine and want to
avoid a source fork; this machine boots **systemd-boot with a BLS entry and a
plain `vmlinuz`**, so that constraint does not apply here.

Note B's one genuinely clever trick, in case you ever need it: replacing
`MacBookPro16,4` rather than growing the table keeps the image byte-identical in
size, so nothing shifts. If you do use B, verify the slot table before and after.

## What the reference project established

From `ahmadtv/omarchy-imac18-3` (`igpu/set-os-loader/README.md`), which solved
this on the **iMac18,3** — a sibling machine, same panel generation, same hidden
HD 630:

> This loader proved on the iMac that set_os exposes the iGPU **and fixes the
> backlight**. The patcher now gets the same call from the kernel's own stub, by
> adding iMac18,3 to its model list, and no longer installs this.

Two things worth carrying over:

1. **It worked.** On the iMac18,3 the set_os call is sufficient to expose
   `00:02.0` (`8086:5912`) and keep the backlight SMBus alive.
2. **They retired the standalone EFI loader** in favour of the kernel-stub
   approach. So this is not a speculative technique — it is the settled method,
   and the reference project's own history shows them moving to exactly the
   approach recommended here.

**This has now been verified on iMac19,1.** The prior held. Firmware 2094.80.5.0.0
exposes `00:02.0` as soon as the stub makes the call.

## What actually happened

Recorded because two wrong conclusions led here, and both were mine.

**The wrong conclusion.** `lspci -s 00:02.0` returning nothing was read as "the
device does not exist, so nothing on the Linux side can help." That was a
misread. The evidence was real, but it described a device the firmware was
*withholding*, not one that was absent. Bus 0 jumps from `00:01.0` straight to
`00:12.0`; function 02 is missing from enumeration, not from the hardware.

The clue that should have stopped it: the DSDT still declared
`Device (IGPU) { Name (_ADR, 0x00020000) }`. ACPI expected a device at 00:02.0
that PCI did not report. That mismatch is the signature of a *withheld* device,
not a missing one — and it was sitting in the output I had already collected.

`lspci -vv`, `setpci` and a DSDT read all agreed the device was not there. All
three were right, and together they still said nothing useful, because firmware
hiding looks exactly like absence from the Linux side. The only way to
distinguish them is to change the asking, not to probe harder.

### The patch as applied

Approach **B** (post-build byte edit), now performed by
`/usr/local/libexec/imac-setos-patch` rather than a hardcoded `dd` offset. See
[How it is kept applied](#how-it-is-kept-applied).

```
kernel  /boot/efi/opensuse-slowroll/7.2.7-1-default/linux-setos
size    17,537,392 bytes  (unchanged by the edit)
table   8 slots of 15 bytes, located by content search
          MacBookPro11,3
          MacBookPro11,5
          MacBookPro13,3
          MacBookPro14,3
          MacBookPro15,1
          MacBookPro15,3
          MacBookPro16,1
          MacBookPro16,4     <- last slot, overwritten
```

`"iMac19,1"` is 8 characters and fits the 15-byte NUL-padded slot without
disturbing the table. The offset found on this kernel is 17524841, but treat
that as an observation, not a constant:

```bash
sudo /usr/local/libexec/imac-setos-patch \
  /boot/efi/opensuse-slowroll/$(uname -r)/linux-setos
# patched slot at offset 17524841: MacBookPro16,4 -> iMac19,1
```

Result on this kernel: **exactly 14 bytes changed**, all inside the slot, image
size identical, and the written bytes verified by read-back. More or fewer
differing bytes means something else was touched.

The earlier form of this page documented the raw equivalent:

```bash
printf 'iMac19,1\0\0\0\0\0\0\0' \
  | dd of=linux-setos bs=1 seek=17524841 conv=notrunc status=none
```

It is kept here only to show what the script automates. **Do not run it against
a new kernel without first confirming the offset** — it has no verification and
would corrupt the image silently if the table moved.

### Verified after boot

```
00:02.0  Intel CoffeeLake-S GT2 [UHD Graphics 630] [8086:3e92]
01:00.0  AMD Ellesmere [Radeon RX 570X] [1002:67df]
i915 loaded, amdgpu loaded
card1-eDP-1: 5120x2880            <- 5K still tiled
tiled_stitch: -1
cs8409 module parameters: 10      <- patched codec intact
graphical.target active, 0 failed units
```

QuickSync, read from the **Intel** render node:

```
$ vainfo --display drm --device /dev/dri/renderD129
Intel iHD driver 26.2.2
  VAProfileH264Main      : VAEntrypointEncSlice
  VAProfileHEVCMain      : VAEntrypointEncSlice
  VAProfileVP8Version0_3 : VAEntrypointEncSlice
  VAProfileJPEGBaseline  : VAEntrypointEncPicture
```

### DRM numbering on this machine is not the obvious order

Worth recording, because it is the opposite of what the numbers suggest and it
is easy to get wrong when copying config from another iMac:

```
card0  -> i915     (Intel)   card1  -> amdgpu  (AMD)
renderD128 -> AMD   (no encoders)
renderD129 -> Intel (H.264/HEVC/VP8 encode)
```

**The iGPU holds `card0` but `renderD129`.** The card numbers and the render
numbers do not line up, because i915 registered first and took the lowest card
index while amdgpu took the first render node.

`vainfo` with no `--device` picks the AMD node and looks broken; it is not. Pass
`--device /dev/dri/renderD129` explicitly.

This inverts the reference project's setup, where i915 is loaded from the
initramfs and therefore takes `card1`/`renderD128`. A `VA-API device` of
`renderD128` is correct there and **wrong here**.

### i915 invents connectors on this machine

i915 currently runs with no display options at all:

```
$ cat /sys/module/i915/parameters/disable_display      # N
$ cat /sys/module/i915/parameters/vbt_firmware          # (null)
$ grep -o 'i915[^ ]*' /proc/cmdline                     # (nothing)
```

With no VBT, i915 invents one and creates connectors for every port:

```
card0-DP-4  card0-DP-5  card0-DP-6
card0-HDMI-A-1  card0-HDMI-A-2  card0-HDMI-A-3     all disconnected
```

The panel survives only because amdgpu owns it. The reference project hit this
on the iMac18,3 and ships a synthetic empty VBT plus `i915.disable_display=1` to
suppress it, on the grounds that `disable_display=1` alone "only gates connector
`detect()`" and is not sufficient.

**That fix is deliberately not applied here.** The empty-VBT approach is for an
iGPU that must never own a display; on this machine amdgpu drives the 5K panel
and the arrangement is working. Adding the headless-VBT machinery would be a
larger change than the symptom warrants, and it taints the kernel with an unsafe
module parameter. The phantom connectors are cosmetic, all report
`disconnected`, and nothing selects them.

If a future kernel or driver change makes i915 claim the panel, that is the
symptom to watch for — not the presence of the connectors themselves.

### Reverting

The change lives in the kernel image and nowhere else, so reverting is a matter
of booting a stock kernel. The stock image and its entry are both kept:

```
stock kernel:  /boot/efi/opensuse-slowroll/7.2.7-1-default/linux-e13dc6943...
stock entry:   /var/tmp/boot-entries-parked/
```

To revert, copy a stock entry back into `/boot/efi/loader/entries/` and set it
default:

```bash
sudo cp /var/tmp/boot-entries-parked/opensuse-slowroll-7.2.7-1-default-*.conf \
        /boot/efi/loader/entries/
sudo sed -i 's|^default .*|default opensuse-slowroll-7.2.7-1-default-155.conf|' \
        /boot/efi/loader/loader.conf
```

Note that the stock entry is **parked out of `loader/entries/`** rather than
deleted. That is not tidiness — while both entries are present systemd-boot
selects the stock one, and that is precisely how the iGPU went missing after a
kernel update. Keep only the entry you intend to boot.

## Risks

These were written before the patch was applied and are kept because the next
kernel rebuild re-runs the same ground. **The iGPU is now bound, so these are
live conditions to watch rather than predictions.** See
[DRM numbering](#drm-numbering-on-this-machine-is-not-the-obvious-order) for
what the topology actually is now.

### 1. It changes the DRM device topology — verified safe

The 5K display is driven by the patched `amdgpu`, and `amdgpu.tiled_stitch=-1`
depends on that single-GPU arrangement. A second DRM device changes card
enumeration, connector naming, and which GPU Wayland picks as primary.

This was the risk that mattered most and the one `docs/recovery.md` did not
cover. **It did not materialise**: after the set_os boot, amdgpu still owns the
panel and tiling is intact.

```
card1-eDP-1: 5120x2880        tiled_stitch: -1       i915 loaded, amdgpu loaded
```

Had it broken, the symptom would have been both tiles dark or the resolution
collapsing to 2880-wide — tiling broken, not the display dying.

### 2. It can take the HDA controller — and `gpu_bind=0` is what prevents it

The iGPU and the CS8409 codec share the HDA controller at `00:1f.3`. When the
iGPU binds, `snd_hdac_i915_init()` returns `-EPROBE_DEFER` until i915 has
probed, and because it defers the **whole PCH controller**, that takes the
speakers and microphones with it. `/etc/modprobe.d/99-imac-audio-gpu-bind.conf`
sets `gpu_bind=0` to prevent exactly this.

**This is no longer hypothetical, and the trade has already been made in favour
of audio.** An earlier version of this page said `gpu_bind=0` was "presently a
no-op" because the iGPU was not enumerated. That was true when written and is now
wrong: the iGPU is bound, `gpu_bind=0` is live, and audio is working because of
it. Verified after the set_os boot:

```
cs8409 module parameters: 10          patched codec intact
alsa: card 1 = PCH [HDA Intel PCH], CS8409/CS42L83 Analog present
Internal Mic Capture Switch: on,on    (set by /usr/local/libexec/imac-mic-on)
```

So do **not** relax `gpu_bind=0` to "clean up" a setting that looks unused. It is
load-bearing, and removing it costs the internal mic.

### What is *not* a risk

- **Firmware corruption.** Nothing here writes to Apple firmware. It is a
  boot-time protocol call from the kernel's EFI stub. (Earlier notes in this
  project wrongly described this as an EFI firmware write; that was incorrect.)
- **A brick.** The worst realistic outcome is a failed boot, and
  `docs/recovery.md` already covers recovering a broken boot.

## How it is kept applied

Both of these are installed and running. They exist because the first thing that
went wrong after the patch was applied was **a kernel install quietly reverting
it**.

### What went wrong

A `zypper` transaction ran `kernel-install`, which wrote a fresh **stock** kernel
and a **stock** BLS entry to the ESP. systemd-boot then had two entries to choose
from, and it picked the stock one — so the machine came back with the iGPU
silently gone. Nothing errored; the only symptom was `i915` missing and no
QuickSync.

This is why the boot entry is now the *only* entry on the ESP, and why the
patched image is regenerated automatically.

### `imac-setos-patch` — verified, not a hardcoded offset

`/usr/local/libexec/imac-setos-patch` finds the model table **by content**, not at
a fixed offset:

```bash
/usr/local/libexec/imac-setos-patch /boot/efi/opensuse-slowroll/$(uname -r)/linux-setos
# imac-setos-patch: ...: patched slot at offset 17524841: MacBookPro16,4 -> iMac19,1
```

It requires the full 120-byte stock table (eight 15-byte slots) to appear
**exactly once** in the image. If it does not — a kernel rebuild has moved or
changed the table — it **leaves the image alone** and says so, rather than
writing at a stale offset and corrupting the kernel:

```
SKIPPED: set_os model table not found exactly once (found 0).
Image left stock; iGPU stays hidden.
```

It also refuses to report success unless the size is unchanged and the written
bytes read back correctly. The documented `dd` one-liner earlier in this file
has no such check, which is exactly the fragility this replaces.

### `imac-setos-install` — survives kernel updates

`/etc/kernel/install.d/96-imac-setos.install` runs after every `kernel-install`
and, for the newly installed kernel:

1. copies it to `linux-setos` and patches it,
2. rewrites `aaa-igpu-setos.conf` to point at the new kernel and the initrd
   kernel-install just produced,
3. **parks** the stock entry outside `loader/entries/` so the bootloader has
   exactly one choice, and
4. re-asserts `default aaa-igpu-setos.conf`.

The initrd is **reused, never copied**. The ESP is 197 MiB and one kernel+initrd
pair is about 101 MiB, so a second copy fills the partition — an attempt to do
exactly that during this work produced a truncated 80 MiB initrd and a 100% full
ESP, which was then rolled back. Do not add one.

### Verifying the state

```bash
f=/boot/efi/loader/entries/aaa-igpu-setos.conf
awk '$1=="linux"||$1=="initrd"{print $2}' "$f" | while read r; do
  [ -f "/boot/efi$r" ] && echo "OK   $r" || echo "MISS $r"
done
ls /boot/efi/loader/entries/          # expect exactly one entry
df -h /boot/efi                       # expect free space, not 0
```

## Applying it from scratch (not needed on this machine)

Kept because the machine can be rebuilt. Everything above is already installed.

```bash
sudo install -m 755 imac-setos-patch /usr/local/libexec/
sudo install -m 755 imac-setos-install /usr/local/libexec/
sudo install -m 755 96-imac-setos.install /etc/kernel/install.d/
sudo /usr/local/libexec/imac-setos-install    # apply now
```

### Verify after a reboot

```bash
lspci -nn | grep -iE 'vga|display|3d controller'   # expect Intel 00:02.0 AND AMD
lsmod | grep -iE 'i915|amdgpu'                     # expect both
amixer -c 1 cget 'Internal Mic Capture Switch'     # card 1 once i915 probes first
./scripts/imac-verify                              # display + audio both [ ok ]
cat /sys/module/amdgpu/parameters/tiled_stitch     # expect -1
sudo scripts/check-5k.sh                           # expect tiled 5120x2880
```

### Using QuickSync in OBS

`obs-qsv11.so` loads, but the **RPM** build of OBS cannot use VA-API at all,
because openSUSE's ffmpeg omits the H.264 and HEVC encoders:

```
$ ffmpeg -hide_banner -encoders | grep vaapi
   av1_vaapi   vp8_vaapi   vp9_vaapi   mjpeg_vaapi   mpeg2_vaapi
   # no h264_vaapi, no hevc_vaapi
```

OBS reports `FFmpeg VAAPI H264 encoding not supported` and lists
`ffmpeg_openh264` as its only video encoder. The iGPU is fine — `vainfo` shows
`VAProfileH264Main: VAEntrypointEncSlice` — nothing in the stack asks it to
encode.

The **Flatpak** OBS bundles an ffmpeg that does have them, and enumerates:

```
$ flatpak run com.obsproject.Studio   # Settings > Output > Recording > Encoder
   ffmpeg_vaapi_tex  (FFmpeg VAAPI H.264)   <- the iGPU
   hevc_ffmpeg_vaapi_tex  (FFmpeg VAAPI HEVC)
   obs_qsv11_hevc  (QuickSync HEVC)
```

Set the **VA-API device to `/dev/dri/renderD129`** — the Intel node. See
[DRM numbering](#drm-numbering-on-this-machine-is-not-the-obvious-order) for why
that is not the one you would guess.

## Note on approach A

Approach A (add `"iMac19,1"` to `type1_product_matches[]` and rebuild) remains
the cleaner end state and is what an upstream patch would do. Approach B is in
use because it needs no kernel fork and can be reapplied to any future kernel
automatically.

If you ever rebuild the kernel from source, adding the model to
`x86-stub.c` supersedes the byte patch: `imac-setos-patch` reports
`already patched` and leaves it alone, and `/usr/local/libexec/imac-setos-install`
keeps working unchanged.

## Related

- `docs/recovery.md` — **read before applying any of this**
- `docs/kernel-updates.md` — the rebuild this depends on
- `docs/reference-system.md` — records the iGPU as present-in-firmware but
  absent from PCI
- `docs/audio.md` — the audio this puts at risk
- Upstream: `ahmadtv/omarchy-imac18-3`, `igpu/set-os-loader/` and
  `igpu/linux-side/mkinitcpio/imac-setos` — see `THIRD_PARTY_NOTICES.md`
