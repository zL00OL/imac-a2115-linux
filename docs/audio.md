# Audio: the CS8409 codec and the internal speakers

> **Status: three separate faults, each with its own fix. Read the labels.**
>
> - **Headset (EarPods) capture: FIXED** — required
>   `cs8409-headset-capture.patch` on top of the jackdanyell tree. It was
>   digital silence before. See
>   [Headset (EarPods) microphone](#headset-earpods-microphone--fixed-2026-10-07).
>   Confirm a patched module with
>   `ls /sys/module/snd_hda_codec_cs8409/parameters | wc -l` → **10**.
> - **Internal mic: node now exists, capture still silent** — the card was
>   stuck on a playback-only profile so no mic node existed at all. Profile is
>   fixed at runtime; gain is 40,40 / boost 0. PipeWire-level capture is still
>   returning digital silence. See
>   [Internal microphone](#internal-microphone--two-faults-2026-10-10).
> - **PipeWire capture on kernel 7.2.7: OPEN** — `arecord` works on both
>   kernels, PipeWire only on 7.2.2. The driver's routing is provably correct;
>   the fault is downstream. See the section above for the evidence.
> - **Internal speakers: FIXED** — `power_save=0` plus the DKMS driver. The
>   4-channel `analog-surround-40` enumeration is **BROKEN**; `analog-stereo`
>   is the working one. WirePlumber reverts to the 4-channel profile often
>   enough that this needs re-checking after any audio daemon restart.

This repository covers two things: the seamless tiled 5K display, and the
internal audio. This page is the audio half — how the Apple CS8409 codec is
installed, why DKMS, what was tried first and why it was wrong, and why the
speakers work on a 2-channel enumeration rather than the 4-channel one that
looks more complete.

Everything here was measured on openSUSE **Slowroll** (see
`docs/distro-matrix.md`). Portability notes are in that file.

---

## Contents

| Section | |
|---|---|
| [Headset (EarPods) microphone](#headset-earpods-microphone--fixed-2026-10-07) | capture that was silent for a day |
| [Internal microphone level](#internal-microphone-level--fixed-2026-10-07) | a gain control that clipped at 0 dBFS |
| [Turning the driver's logging on](#turning-the-drivers-logging-on--the-diagnostic-that-finally-worked) | `MYSOUNDDEBUG`, and why `dmesg` as a normal user lies |
| [Audio — FIXED](#audio--fixed-tweeters--woofers-verified-2026-10-03) | the working configuration |
| [Audio: earlier diagnosis](#audio-earlier-diagnosis-kept-for-the-record) | superseded, kept for the record |
| [Internal speakers](#internal-speakers--what-actually-works-and-why-the-eq-cannot-be-applied) | the 4-channel fault, and why the EQ stays parked |

---

## Headset (EarPods) microphone — FIXED, 2026-10-07

> **Outcome:** capture from a 4-pole (TRRS) headset is confirmed working —
> peak −10.3 dBFS, 99% non-zero samples, 0% clipped. It was digital silence
> before. **This was a driver bug, not a mixer setting, and not a PipeWire
> problem.** Every ALSA-level change tried beforehand had no effect, which is
> what finally pointed at the driver.

### The bug

The stock `jackdanyell` tree binds the capture DMA to the **internal** mic ADC
but configures the **headset** mic, or the reverse — so with a headset plugged
in the stream is fed by an ADC that has nothing connected to it. Result:
`peak 0.00000`, a running PCM, and total silence. From the patch's own
header:

> On plug-in `cs_8409_capture_pcm_prepare` branches on `have_mike` and routes
> the headset mic (pin `0x3c`) to the cs42l83 ADC `0x1a` — but the PCM stays
> bound to `intmike_adc_nid` (0x23). **Nothing feeds 0x23, so capture is digital
> silence: peak 0.00000 with a headset in**, while the internal mike alone
> worked fine.

Two further defects in the same driver: a plug/unplug that happens while a
capture stream is already open does nothing at all (`PLUGIN WHILE CAPTURING
UNIMPLEMENTED`), and the internal mic gain is pinned to a constant that is 24 dB
below where it needs to be.

### The fix

`ahmadtv/omarchy-imac18-3` carries
[`patches/cs8409-headset-capture.patch`](../patches/cs8409-headset-capture.patch),
written against **jackdanyell/imac18-3-cs8409-linux-audio at commit
`be90113`**. It adds six module parameters, which is how you confirm it is
actually loaded:

```
headset_buttons=1  headset_mike_boost=1  headset_mike_gain=12
hp_hold_on_capture=Y  intmike_gain=51  button_debounce_ms=80
button_long_press_ms=300  button_max_hold_ms=3000
int_drain_max=40  int_drain_burst=24
```

An unpatched module exposes **none** of these. That is the single fastest check:

```bash
ls /sys/module/snd_hda_codec_cs8409/parameters | wc -l    # 0 = unpatched, 10 = patched
```

Verify a capture:

```bash
pw-record ~/mic.wav      # then play it back
# expect: peak well above -60 dBFS, non-zero samples
```

Expected from the reference machine: **−10.3 dBFS peak, 99% non-zero, 0%
clipped.** The patch's own measurement target is −21.7 dBFS RMS with −8.9 dBFS
peaks, so anything near that is correct.

### The patch lives in the driver tree, not in this repository

`cs8409-headset-capture.patch` is not vendored here. It applies to a tree that
DKMS builds, and shipping a copy that can drift from `be90113` is worse than
pinning the upstream commit:

```
upstream: https://github.com/jackdanyell/imac18-3-cs8409-linux-audio
commit:   be90113a7638eb264b2ff5acfe888cd72c8364c6
patch:    https://github.com/ahmadtv/omarchy-imac18-3/blob/master/patches/cs8409-headset-capture.patch
```

Apply in that order — the patch's hunks are written against `be90113` and will
not apply cleanly elsewhere.

### Building it without a 155 MB download

`jackdanyell`'s installer wants to download `linux-<ver>.tar.xz` from
`cdn.kernel.org`. That download **stalled permanently at 14%** on the reference
machine. It is not needed:

- `/usr/src/linux-7.2.7-1` is a **complete** source tree (94,376 files, full
  `sound/hda`, 307 amdgpu `.c` files).
- The openSUSE-shipped `/usr/src/linux-7.2.2-1` is **stripped** — 16,672 files
  and `sound/hda` reduced to 19 stub `Kconfig`/`Makefile` files.

So `sound/hda` can be taken from the 7.2.7 tree and built against either
kernel's headers. Satisfy the installer with a locally staged tarball whose
top-level directory matches what its `tar` expects:

```bash
S=/usr/src/snd_hda_macbookpro-0.2
mkdir -p $S/build /tmp/stage/linux-$(uname -r | cut -d- -f1)
cp -a /usr/src/linux-7.2.7-1/sound /tmp/stage/linux-$(uname -r | cut -d- -f1)/
tar -cJf $S/build/linux-$(uname -r | cut -d- -f1).tar.xz \
    -C /tmp/stage linux-$(uname -r | cut -d- -f1)/sound/hda
```

Note the internal version is `7.2.2`, not `7.2.2-1-default` — `kernel_version`
in the installer is `uname -r` cut on the first `-`. Getting this wrong yields
`tar: Cannot open: No such file or directory`, which looks like a corrupt
tarball rather than a naming mistake.

### Kernel 7.2.7: the driver is correct but PipeWire still gets silence

With the patched driver, **`arecord` works on both kernels but PipeWire works
only on 7.2.2.** The driver's own logging confirms it routes correctly on
7.2.7:

```
cs_8409_capture_pcm_prepare: NID=0x23, stream=0x1, format=0x4041
cs_8409_capture_pcm_prepare: capture nid 0x23 -> 0x1a (jack 1 mike 1)
headset_mike_adc_level: boost 1 gain 12 dB (0x1d01 0x01 0x1d03 0x0c)
```

`jack 1 mike 1` and the switch to ADC `0x1a` are exactly right. The ALSA layer
is equally innocent — while a PipeWire capture runs:

```
/proc/asound/card1/pcm0c/sub0/   status: RUNNING
  access: MMAP_INTERLEAVED   format: S32_LE   channels: 2   rate: 44100
```

Identical to the `arecord` capture that yields −1.3 dBFS, yet PipeWire receives
zeros. `arecord` in RW, MMAP, MMAP-with-explicit-buffers and `plughw` modes all
work, so access type is not the variable. The open question is PipeWire's
repeated stream re-open: the debug log shows `cs_8409_capture_pcm_prepare`
blocks recurring, and each one re-drives the codec over I2C. Suspected race,
not yet proven.

**Until that is resolved, boot the 7.2.2 fallback entry when you need the
microphone** — `arecord`/`parecord` work on both kernels, but PipeWire-native
applications (OBS, browsers, Discord) need 7.2.2.

## Internal microphone — two faults, 2026-10-10

The mic was reported "not working". That turned out to be **two unrelated faults**,
and the 2026-10-07 note above only ever addressed one of them — and got the
direction of it wrong. Both are recorded here because the old note was the reason
this took a while to find.

### Fault 1 (real, and the actual cause): the card had no capture node

This is why no application could open the built-in mic. It was not a mute and not
a level problem.

```
Active Profile: output:analog-stereo        ← sinks: 1, sources: 0
Sources:
 *  47. UMC204HD 192k Direct                 ← the USB interface, and only that
```

`alsa_input.pci-0000_00_1f.3.analog-stereo` — the node the default source pointed
at — **did not exist**. ALSA underneath was fine the whole time; `arecord -D
hw:0,0` returned clean signal on demand. PipeWire simply never created the node,
so nothing built on PipeWire could reach the microphone.

Cause: `~/.config/wireplumber/wireplumber.conf.d/51-imac-surround.conf` forced

```lua
monitor.alsa.rules = [ { matches = [ … ], actions = { update-props = { … } } } ]
```

WirePlumber **0.4 array syntax**. On 0.5+/1.6 this is not honoured, and the profile
it half-applied produced a playback-only graph. The port itself is present and
fine: `analog-input-internal-mic`, priority 8900. `pactl set-card-profile
alsa_card.pci-0000_00_1f.3 output:analog-stereo+input:analog-stereo` creates the
node immediately.

The old rule asked for `output:analog-surround-40`. The internal speakers have
never been 4-channel on this machine — they enumerate as 2-channel
`analog-stereo` and work there — so that request bought nothing and cost the
microphone.

### Fault 2: the gain values

Measured peak per 3s, `hw:0,0` direct, S32:

| Capture Volume | Boost | Peak | Clipped |
|---|---|---|---|
| 63 | 2 (+20 dB) | 2147483392 | 13526 |
| 50 | 0 | 2147483392 | 1155 |
| 45 | 0 | 1393639424 | 0 |
| **40** | **0** | **784498688** | **0** |
| 30 | 0 | 251799552 | 0 |
| 20 | 0 | 80262656 | 0 |

The 2026-10-07 note recorded 20,20 / 0,0 as the fix for clipping. 20,20 does
avoid clipping, but it is **~20x too quiet to use** (−28.5 dBFS peak). The clip
fix and a usable level were conflated. Current setting is **40,40 with boost 0**,
chosen by ear: ~−8.7 dBFS peak, no clipping.

Codec defaults (63, 2) clip. `imac-mic-on` now sets 40 / 0.

### The switch was never the problem

The old script's header claimed `Internal Mic Capture Switch` comes up `off,off`
and must be reset every boot. **That is false here.** The service log shows it
succeeded, the driver does not clear it across any capture-prepare/stop cycle in
dmesg, and it stays `on,on` under observation. It is still set, as cheap
insurance, but it was not the fault.

### Why the old script appeared to work and changed nothing

These are not ordinary mixer controls:

```
Internal Mic Capture Switch    access=rw------    owner write only
Internal Mic Capture Volume    access=rw---R--    READ ONLY
Internal Mic Boost Volume      access=rw---R--    READ ONLY
```

Volume and Boost are marked read-only to *every* user; only the driver's HDA verb
path sets them. An unprivileged `amixer` exits 0 and changes nothing. The script
ran as root via systemd so its writes were real — but the values it wrote were
wrong, and it discarded stderr, so a failure would have been invisible.

`scripts/imac-mic-on` now verifies after writing and exits non-zero on a mismatch.

### Still open

With the duplex profile applied the node exists, but **app-level capture through
PipeWire returns digital silence** — peak 0, 705600/705600 samples zero — while
`arecord -D hw:0,0` directly is clean. The hardware path works; something between
PipeWire and it still yields nothing. Leading suspect is the driver hook in dmesg:

```
cs_8409_capture_pcm_hook jack_present 0
```

The codec reports no jack, so the capture hook may be stopping the stream when
opened through the normal path. **Not resolved.**

### Persistence caveat

The working profile was set with `pactl set-card-profile` and is **runtime only**.
It will revert on reboot or session restart. The corrected `51-imac-surround.conf`
written in 0.5+ block syntax did **not** take effect — after restarting
WirePlumber the profile was still `output:analog-stereo`. Left in place but
unproven; it is not yet a working fix.

`scripts/imac-verify` checks the gain values.

## Turning the driver's logging on — the diagnostic that finally worked

The driver has a full set of debug printfs that are **compiled out by
default**, which is why a capture attempt can be completely silent in the log
and look like "the driver is not involved":

```c
#ifdef MYSOUNDDEBUGFULL
        ... logging on
#else
#define mycodec_info(...)
#define myprintk(...)
#endif
```

The file that carries the switch is `patch_cirrus/patch_cirrus_apple.h` (pulled
in by `patch_cs8409.c`). Define it there, rebuild, and you get the whole
capture path:

```bash
sed -i '0,/^#ifdef MYSOUNDDEBUGFULL/s//#define MYSOUNDDEBUG 1\n#ifdef MYSOUNDDEBUGFULL/' \
    /usr/src/snd_hda_macbookpro-0.2/patch_cirrus/patch_cirrus_apple.h
dkms remove -m snd_hda_macbookpro -v 0.2 --all
dkms add -m snd_hda_macbookpro -v 0.2
dkms build -m snd_hda_macbookpro -v 0.2 -k 7.2.7-1-default
dkms install -m snd_hda_macbookpro -v 0.2 -k 7.2.7-1-default --force
```

Rebuild the initramfs too, or the old module loads from it.

**Turn it back off afterwards.** The logging is extremely verbose — 121,000
lines per minute of wall clock on the reference machine, enough to fill a
journal in minutes.

### `dmesg` as a normal user returns nothing, silently

This invalidated four measurements before it was caught. `dmesg` needs root,
and `2>/dev/null` turns the permission error into an empty result that is
indistinguishable from "the driver printed nothing":

```bash
sudo dmesg | wc -l              # real count
dmesg 2>/dev/null | wc -l       # 0, every time, as a normal user
```

Any "the driver logged nothing" conclusion reached from a script running as a
user is worthless. If you need kernel output from a user-level script, snapshot
it from a root process:

```bash
# as root
for i in $(seq 1 60); do dmesg >> /var/tmp/dmesg-snap.txt; sleep 1; done &
# as the user, trigger the capture, then read /var/tmp/dmesg-snap.txt
```

`journalctl -k` has the same problem for non-root.

### Card numbering moves

The internal codec is card **0 or 1** depending on whether the Intel iGPU is
published, because publishing it changes enumeration order. Never hardcode
`hw:1,0`. Detect it:

```bash
for c in 0 1 2 3; do
  amixer -c $c contents 2>/dev/null | grep -q "Internal Mic Capture Switch" && { C=$c; break; }
done
```

## Audio — FIXED (tweeters + woofers), verified 2026-10-03

> **Outcome:** `power_save=0 power_save_controller=N` plus davidjo's
> `snd_hda_macbookpro` driver (DKMS) makes the internal speakers work. The
> driver must be present *as well as* the power management fix — either alone
> is not enough. See "Cause 1" and "Cause 2" below for why.
>
> **✅ SETTLED 2026-10-06.** This account is the correct one. Read off the machine:
>
> ```
> $ dkms status
> snd-hda-macbookpro/0.2, 7.2.2-1-default, x86_64: installed (Original modules exist)
> snd-hda-macbookpro/0.2, 7.2.7-1-default, x86_64: installed (Original modules exist)
>
> $ modinfo -n snd_hda_codec_cs8409
> /usr/lib/modules/7.2.2-1-default/updates/snd-hda-codec-cs8409.ko.zst
> $ cat /sys/module/snd_hda_codec_cs8409/srcversion
> 5957235DD0C11693189E2C5        # matches modinfo -F srcversion
> ```
>
> DKMS installs into `updates/`, and the loaded module is that DKMS build — so
> DKMS wins the codec bind on this machine and the patched driver is what is
> actually loaded. The retired `scripts/imac-audio-module`'s ordering argument
> (`updates/ext01` sorting before `updates/dkms`) does not apply: DKMS is not
> installing into `updates/dkms` here, so there is nothing to sort ahead of.
> Its DKMS check has been downgraded from FAIL to warn accordingly.

### What was actually required

```bash
# /etc/modprobe.d/99-imac-audio.conf
options snd_hda_intel power_save=0 power_save_controller=N
```

```bash
# davidjo/snd_hda_macbookpro via DKMS, built against this kernel
sudo dkms install --force snd-hda-macbookpro/0.2
```

Verified markers after reboot:

```
Primary patch_cs8409 NOT FOUND trying APPLE
Codec: Cirrus Logic CS8409/CS42L83
modinfo -n snd_hda_codec_cs8409 -> .../updates/snd-hda-codec-cs8409.ko.zst
```

`CS8409/CS42L83` is the signature that the patched driver is live; the in-tree
driver only ever reports `CS8409`.

### Two traps that cost hours

**The DKMS build path.** Upstream `dkms.conf` already carries
`BUILT_MODULE_LOCATION[0]="build/hda/codecs/cirrus"`, which is required on
kernels where the HDA codecs moved. If a build "fails" but the log shows
`exit code: 0`, DKMS could not find the `.ko` and installed nothing.

**This host cannot reach `cdn.kernel.org`.** davidjo's installer downloads the
kernel tarball, and it hung here for many minutes. It now copies the `sound/hda`
subtree from a preserved source directory instead
(`/usr/src/snd-hda-macbookpro-0.2/hda-src`, 109 MB). `GitHub` is also
unreachable from this machine, so clone the driver elsewhere and copy it in.

### Cause 2 — TDM slots: diagnosed, NOT fixed

With the driver and `power_save` fixed, playback is audible but the channels are
wrong: **tweeters only**, and on one test a loud hiss. That is 2 of 4 channels,
matching [issue #211](https://github.com/davidjo/snd_hda_macbookpro/issues/211)
exactly — slots 0 and 3 clean, the middle slots corrupted.

The prescribed fix is to offer `SNDRV_PCM_FMTBIT_S24_3LE`. The playback path in
`cirrus_apple.h` omits it while the capture paths include it:

```c
hinfo->formats = SNDRV_PCM_FMTBIT_S32_LE | SNDRV_PCM_FMTBIT_S24_LE;   /* needs S24_3LE */
```

**Adding the flag is not sufficient.** PipeWire always negotiates `s32le` and
ignored the new format, and restricting the mask to `S24_3LE` only made things
worse — PipeWire then failed to open the device at all (`Input/output error`).
Forcing the format from userspace is the unsolved part.

### Also required: a working PipeWire state

A stale WirePlumber state (muted sink, bad volume, sticky 4-channel profile)
produced **total silence** at one point, which looked like a driver failure but
was not. Resetting it restored audio immediately:

```bash
systemctl --user stop wireplumber pipewire pipewire-pulse
mv ~/.local/state/wireplumber ~/.local/state/wp.bak
systemctl --user start pipewire pipewire-pulse wireplumber
```

### Warning: there is no stock codec fallback

`rpm -V kernel-default` reports:

```
missing  /usr/lib/modules/7.2.2-1-default/kernel/sound/hda/codecs/cirrus/snd-hda-codec-cs8409.ko.zst
```

DKMS archived and removed the in-tree module when it installed. If the DKMS
registration is ever removed, **no codec loads at all**. Restore with
`sudo dkms install --force snd-hda-macbookpro/0.2`.

### The old ext01 approach — superseded

`scripts/imac-audio-module` built into `updates/ext01` and is retained only
because it is the correct mechanism for a *hand-built* module. It is not how the
audio is fixed now: DKMS with `power_save=0` is. Its vermagic check is also
insufficient on its own — a mismatched tree produces `disagrees about version of
symbol module_layout` while vermagic still matches, so it now compares the
`module_layout` CRC as well.

---

## Audio: earlier diagnosis (kept for the record)

**The previous diagnosis in this file was wrong twice over.** It first blamed
gain staging and a missing limiter, then blamed kernel module ordering. Both
were red herrings. Both were reached before anyone searched the driver tracker
for this exact machine model, which is the mistake that cost a whole evening.

**Current symptom:** rear pair works, front pair is silent. No mixer setting
changes it.

### Cause 1 — HDA runtime power management (total silence)

`davidjo/snd_hda_macbookpro` issue #209, filed on an **iMac19,1** — this
machine. The reporter had everything apparently correct and no sound:

> `Primary patch_cs8409 NOT FOUND trying APPLE` · codec `CS8409/CS42L83` ·
> `CS8409/CS42L83 Analog` present · jack detection correct · PCM `state:
> RUNNING` · pin `0x24` at `Pin-ctls: 0x40: OUT` — **silent at every volume.**

With a debug build the amplifier I2C status read `0x20` instead of `0x18`, and
neither the CS42L83 nor the four **TAS5764L** amplifiers answered.

The cause is HDA runtime power management. Distros ship
`snd_hda_intel power_save=1`, so the controller runtime-suspends after a second
of idle. **The CS8409's I2C bridge is powered from that controller**, so while
it is suspended the amplifiers cannot be programmed at all. There is no error
anywhere: digital path running, pin enabled, PCM running, no sound. Issue #217
adds that with the default setting the codec state goes bad after ~10 s idle.

```bash
# /etc/modprobe.d/99-imac-audio.conf
options snd_hda_intel power_save=0 power_save_controller=N
```

The reporter states that after this, internal speakers work **with davidjo's
driver unmodified from master**. This may also explain why the same model works
for people on Fedora and Arch but not on Ubuntu.

### Cause 2 — TDM slot corruption (partial silence)

`davidjo#211` bisected this on a different model and it matches our symptom
exactly:

> only **2 of the 4 speaker drivers** ever play. The failure is in the CS8409's
> TDM output: **slots 1 and 2** (the middle of the frame) are never delivered
> correctly. **Slots 0 and 3 are always clean.**

Two of four channels working is precisely a "rear pair works, front pair silent"
result. Apple's native format for this codec is **`0x4033` — S24_3LE, 4ch,
44.1 kHz**; adding `SNDRV_PCM_FMTBIT_S24_3LE` to the driver's format mask woke
the dead amplifiers. The 2-channel path in the driver misaligns data; a native
4-channel stream is clean (#217).

### Cause 3 — there is no hardware volume

`davidjo#217`: no codec node has an amp, so `PCM Playback Volume` is an ALSA
`softvol` that PipeWire mistakes for a hardware mixer. The result is a stepped
curve — mute up to ~12%, then nearly full. Fix with
`api.alsa.soft-mixer = true`.

### Applying it

```bash
scripts/imac-audio --check      # verify what is loaded right now (read-only)
sudo scripts/imac-audio --install
sudo scripts/imac-audio --mic    # capture diagnostics
scripts/imac-audio --help
```

> **Both older audio scripts are retired.** `imac-audio-fix` and
> `imac-audio-module` each recorded that jackdanyell's fork "targets the
> iMac18,3" and should be removed. That is backwards — jackdanyell's tree is
> what carries the headset capture fix, and `imac-audio-fix` would have run
> `dkms remove snd_hda_macbookpro/0.2 --all`. They are stubs now and exit 1.
> Their originals are in git history.

The `power_save` option is worth keeping — HDA runtime power management
suspends the controller that powers the CS8409 I2C bridge, so the amplifiers
can never be programmed, giving total silence with no error anywhere
(`davidjo/snd_hda_macbookpro` issues 209 and 217):

```
options snd_hda_intel power_save=0 power_save_controller=N
```

**The 4-channel forcing is not.** It configures the `analog-surround-40`
enumeration, which is the faulty one. The internal codec should stay at
`analog-stereo`; see [Speakers](#speakers).

### The DKMS build trap (why davidjo appeared not to work here)

On kernels where the HDA codecs moved to `sound/hda/codecs/cirrus/`, the module
compiles but DKMS cannot find it:

```
  LD [M]  codecs/cirrus/snd-hda-codec-cs8409.ko
  # exit code: 0
Error! Build of build/hda/snd-hda-codec-cs8409.ko failed for: <kernel>
```

`dkms.conf` still points `BUILT_MODULE_LOCATION` at the old path, so DKMS
declares failure and installs nothing. One line:

```diff
-BUILT_MODULE_LOCATION[0]="build/hda"
+BUILT_MODULE_LOCATION[0]="build/hda/codecs/cirrus"
```

**This means the driver may never have been under test here at all.** It also
reinterprets `jackdanyell` issue #3 — its "no PCM devices are registered at
all" is exactly what a spurious DKMS failure produces, so the
`updates/ext01` ordering theory built from it was probably solving a
non-problem.

### What was tried and abandoned, and why

| Attempt | Outcome |
|---|---|
| Unity-gain PipeWire chain, ALSA levels to 100% | No effect on the fault |
| jackdanyell v0.2 (`imac18-3-cs8409-linux-audio`) | **WRONGLY DISMISSED — this is the fix.** See "Headset (EarPods) microphone" below. The row used to read "Wrong model; targets iMac18,3"; that was incorrect and cost a day |
| DKMS install of that fork | No PCM devices registered |
| Hand-built module in `updates/ext01` | `disagrees about version of symbol module_layout` — `vermagic` matched, so the guard missed it. The tree had a different `.config` (`module_layout` CRC `0x60b44b0b` vs the real `0xbb7f52aa`) |
| `updates/ext01` ordering theory | Built on issue #2 vs #3; likely a red herring (see above) |

`scripts/imac-audio-module` is retained because building against
`/lib/modules/$(uname -r)/build` is still the correct mechanism, but it is not
the fix. **Use `scripts/imac-audio`.**

### If it is still silent after a reboot

Report these three facts:

1. Does `scripts/imac-audio --check` pass, and is `power_save` still `N`?
2. Does `/proc/asound/card0/codec#0` show the CS42L83 sub-codec?
3. With a 4-channel stream, do channels 0 and 3 play while 1 and 2 stay silent?

Those distinguish cause 1 from cause 2.

## Internal speakers — what actually works, and why the EQ cannot be applied

> **Outcome:** internal speakers work. The woofer fault was a sink-enumeration
> problem, not a broken driver. A speaker EQ is **not achievable** on this machine
> because PipeWire's filter-chain module fails to initialise. Read this before
> touching the tuning files.

### The woofer fault was the 4-channel enumeration

The internal codec has been observed in **two different enumerations** in a
single session:

```
alsa_output.pci-0000_00_1f.3.analog-stereo       2ch 44100Hz   WORKS
alsa_output.pci-0000_00_1f.3.analog-surround-40  4ch            woofer hisses / silent
```

On the 4-channel form, channels 3-4 drive the woofer and that path
misbehaves. On the 2-channel form everything plays cleanly, and **no
configuration change was required to get there** — the codec simply settled on
the working enumeration after a stream was moved and the sink re-enumerated.

This matches davidjo's NOTES.md for this driver: the tweeters are channels 1-2
(node `0x02 -> 0x24`) and the woofer is channels 3-4 (node `0x03 -> 0x25`), two
different paths. Only the 3-4 path misbehaves.

Be aware the sink name can change underneath you. **Anything that hardcodes
`analog-surround-40` will silently stop matching** when it flips to
`analog-stereo`, and vice versa.

### The EQ cannot run: filter-chain fails to initialise

```
[E] mod.filter-chain | can't connect: Operation not supported
```

`libpipewire-module-filter-chain` will not instantiate its nodes on this
machine. Because it is loaded with `flags = [ nofail ]`, PipeWire **ignores the
failure and continues** — so no node appears, audio bypasses the EQ, and
`pactl`/`wpctl` show a perfectly healthy graph.

Two consequences worth internalising:

- **This is why the 4-way tuning was parked.** The upstream author's notes
  describe the identical symptom ("started, reported itself applied, created no
  nodes, audio silently bypassed the EQ"). It was never a config mistake.
- **A missing EQ looks exactly like a working EQ.** Never trust "the tuning is
  applied" without confirming the node exists in `wpctl status`.

Caveat on the diagnosis: the module failure was reproduced in an isolated
PipeWire with no session manager, and separately observed to produce no node in
the running instance. Those two were not proven to share a root cause.

### The tuning that is parked, and why it is the right one to keep parked

`~/.config/pipewire/pipewire.conf.d/90-imac-speakers.conf.disabled-by-imac-audio-fix`

That file is **not** a hand-fitted curve. It was generated by
`tools/generate-filter-chain.py` from `data/layout16-dsp.json`, and every
coefficient comes from macOS `AppleHDA.kext` layout 16 — the layout Apple's
firmware selects for this machine. Generator and data are in
`~/imac-a2115-linux/`. It builds a 4-way crossover: stereo in, a
12-section input EQ per channel, pre-split gain, then a split to tweeters
(FL/FR, highpass ~2999 Hz) and woofers (RL/RR, lowpass ~1380 Hz) each with its
own curve.

It is parked for two independent reasons: it targets the 4-channel sink name,
and filter-chain cannot load here. It should stay parked. If filter-chain is
ever fixed, this file is the one to re-enable — not a substitute curve.

A 2-channel variant was built by extracting the pre-split portion of this chain
(input EQ + pre-split gain, coefficients verified byte-identical) and is parked
as `50-imac-2ch.conf.disabled-filterchain-broken`. The per-driver curves cannot
be reproduced on a stereo output: summing a highpassed and a lowpassed copy of
the same signal reconstructs the input rather than correcting it.

### Ruled out

Do not spend time on these again:

- `options snd_hda_intel model=imac` — comes from an *egorenar*-based install
  script. With the davidjo driver the Apple path is already forced, so the model
  string is very likely ignored.
- Forcing `S24_3LE` — PipeWire needs both ends of the graph to agree;
  constraining only the sink produces I/O errors. The rate was already correct
  at 44100 Hz.
- The ALSA `equalizer` PCM route — PipeWire opens the ALSA device directly and
  bypasses `~/.asoundrc`, so this needs the device re-plumbed first.
- An LV2 lookahead limiter — this system has **zero** LV2 plugins installed and
  `lsp-plugins-lv2` is not in the openSUSE repos.

### The honest bottom line

The CS8409 does no DSP at all on Linux; macOS's voicing is entirely software EQ.
Without filter-chain there is no way to reproduce it, so these speakers will
sound thinner and brighter than the same machine under macOS. That is a driver
limitation, not a misconfiguration.




