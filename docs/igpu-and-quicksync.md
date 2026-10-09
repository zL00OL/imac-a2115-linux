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

Approach **B** (post-build byte edit). This machine boots systemd-boot with a BLS
entry and a plain `vmlinuz`, so there is no UKI constraint here.

```
kernel  /boot/efi-xbootldr/opensuse-slowroll/7.2.7-1-default/linux
size    17,537,392 bytes  (unchanged by the edit)
table   8 slots of 15 bytes, starting at offset 17524736
          17524736  MacBookPro11,3
          17524751  MacBookPro11,5
          17524766  MacBookPro13,3
          17524781  MacBookPro14,3
          17524796  MacBookPro15,1
          17524811  MacBookPro15,3
          17524826  MacBookPro16,1
          17524841  MacBookPro16,4     <- last slot, overwritten
```

`"iMac19,1"` is 8 characters and fits the 15-byte NUL-padded slot without
disturbing the table:

```bash
printf 'iMac19,1\0\0\0\0\0\0\0' \
  | dd of=linux-setos bs=1 seek=17524841 conv=notrunc status=none
```

Result: **exactly 14 bytes changed**, all inside the slot, image size identical.
That is the check that proves the edit was surgical — more or fewer differing
bytes means something else was touched.

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

`renderD128` is the AMD card and still reports no encoders. `vainfo` with no
`--device` picks that one and looks broken; it is not.

### Reverting

The stock kernel entry is kept alongside. Selecting
`openSUSE 7.2.7-1-default` (no `iGPU: set_os patched` suffix) at the boot menu
reverts this, because the change lives in the kernel image and nowhere else.

## Risks — read before applying

Enabling the iGPU is not a display-only change. Two concrete hazards:

### 1. It will change the DRM device topology

The 5K display is driven by the patched `amdgpu` in `initrd-stackC`, and
`amdgpu.tiled_stitch` depends on that single-GPU arrangement. Adding a second
DRM device changes card enumeration, connector naming, and which GPU
`KDE`/`Wayland` picks as primary.

**This is the risk that matters most**, and it is not covered by
`docs/recovery.md`, which assumes one GPU. Symptom to watch for: both panels
dark, or resolution collapsing to 2880-wide — that would mean tiling broke, not
that the display died.

### 2. It can take the HDA controller

The iGPU and the CS8409 codec share the HDA controller at `00:1f.3`. When the
iGPU binds, it can claim the audio device — which is the entire reason
`/etc/modprobe.d/99-imac-audio-gpu-bind.conf` sets `gpu_bind=0`.

Worth being precise about the current state: **`gpu_bind=0` is presently a
no-op.** The iGPU is not enumerated at all, so there is nothing for it to stop
from binding. The setting only starts to matter *after* the set_os call works —
at which point it becomes the thing standing between you and silent speakers and
a dead microphone. Expect to have to decide deliberately whether to relax it.

That is a genuine trade: QuickSync hardware encoding against working internal
audio. Given that the internal mic on this machine has already been fragile, this
is not a decision to make casually.

### What is *not* a risk

- **Firmware corruption.** Nothing here writes to Apple firmware. It is a
  boot-time protocol call from the kernel's EFI stub. (Earlier notes in this
  project wrongly described this as an EFI firmware write; that was incorrect.)
- **A brick.** The worst realistic outcome is a failed boot, and
  `docs/recovery.md` already covers recovering a broken boot.

## Procedure

Not run. This is the order it should be attempted in.

### Before you start

```bash
sudo cp -p "/boot/efi/opensuse-slowroll/$(uname -r)/initrd-stackC" \
           ~/initrd-stackC.backup
ls -lh ~/initrd-stackC.backup; df -h /boot/efi
```

Confirm you can reach the machine over SSH **and** have physical access. This
change touches boot, so "I can't get back in" is a real outcome.

### 1. Confirm the starting state

```bash
lspci -nn | grep -iE 'vga|display|3d controller'   # expect: AMD only
[ -e /sys/bus/pci/devices/0000:00:02.0 ] && echo PRESENT || echo "ABSENT - expected"
```

### 2. Apply the source patch

In the kernel source, `drivers/firmware/efi/libstub/x86-stub.c`, add the model to
`type1_product_matches[]`:

```c
        "MacBookPro11,3", ... "MacBookPro16,4",
+       "iMac19,1",
```

The entries are `[15]`-byte slots, so `"iMac19,1"` (8 chars) fits without
changing the table's layout.

### 3. Rebuild

Per `docs/kernel-updates.md`. Keep `gpu_bind=0` in place for the first boot — you
want to see whether the iGPU appears *before* it can interfere with audio.

### 4. Verify after reboot

```bash
lspci -nn | grep -iE 'vga|display|3d controller'   # expect Intel 00:02.0 TOO
modinfo i915 | head -1
lsmod | grep -iE 'i915|amdgpu'                      # expect both
amixer -c 0 cget 'Internal Mic Capture Switch'      # expect: on,on
arecord -l                                            # expect the internal codec present
./scripts/imac-verify                                # expect display + audio both [ ok ]
```

**Also confirm the 5K panel still tiles** — that is the thing at risk:

```bash
cat /sys/module/amdgpu/parameters/tiled_stitch      # expect -1
sudo scripts/check-5k.sh                            # expect 2 connectors, tiled
```

If either panel goes dark, stop and revert — see below.

### 5. Only then consider QuickSync

`obs-qsv11.so` is already installed on this machine and loads successfully, so
no OBS reinstall is needed. Once the iGPU appears, the QSV encoder should become
available and `obs_qsv` will show up in OBS's encoder list.

## Reverting

Fully reversible, and cheap.

```bash
# 1. restore the working initramfs
sudo cp -p ~/initrd-stackC.backup \
        "/boot/efi/opensuse-slowroll/$(uname -r)/initrd-stackC"
# 2. drop the model from the kernel source and rebuild, or boot the previous
#    kernel at the systemd-boot menu - the stub change is per-kernel-image,
#    so an unpatched kernel simply will not make the set_os call.
# 3. reboot
```

Because the change lives in the kernel image rather than in firmware or in a
persistent setting, **selecting the previous kernel at the boot menu reverts it
without any file changes.**

## Related

- `docs/recovery.md` — **read before applying any of this**
- `docs/kernel-updates.md` — the rebuild this depends on
- `docs/reference-system.md` — records the iGPU as present-in-firmware but
  absent from PCI
- `docs/audio.md` — the audio this puts at risk
- Upstream: `ahmadtv/omarchy-imac18-3`, `igpu/set-os-loader/` and
  `igpu/linux-side/mkinitcpio/imac-setos` — see `THIRD_PARTY_NOTICES.md`
