# Recovery

> **Status: VERIFIED — the unbound-device case is real.**
> Recovery 3 was written after an actual incident on this machine, not
> hypothetically. The others follow the same failure paths and are written
> conservatively.

**Read this before changing anything on this machine.**

The tiled 5K display depends on a hand-patched `amdgpu`. There is no in-distro
package for it. The patched module lives in
`/usr/lib/modules/$(uname -r)/updates/amdgpu.ko.zst` and must also be carried in
the initramfs, because a stock `amdgpu` has **no `tiled_stitch` parameter at
all** and will bring up one tile instead of two — silently, with nothing logged
as an error.

That is recoverable. It just is not recoverable from the keyboard in front of you
if you have no second machine and no network.

The single most useful thing you can do before touching this system is make sure
you have **SSH access from somewhere else** on the network or over Tailscale.
Every procedure below assumes it.

> [!WARNING]
> **There is no partition backup on the reference machine.** Every recovery below
> that says "restore from backup" is describing a step you must first create.
> The Quickstart in the README has the `dd`. Take it before any kernel update.

---

## Contents

- [Before you start: the one safety habit](#before-you-start-the-one-safety-habit)
- [Rule 0: never chain a destructive step with its own repair](#rule-0-never-chain-a-destructive-step-with-its-own-repair)
- [Recovery 1: black screen, or one tile, after a kernel update](#recovery-1-black-screen-or-one-tile-after-a-kernel-update)
- [Recovery 2: you rebuilt the initramfs and lost 5K](#recovery-2-you-rebuilt-the-initramfs-and-lost-5k)
- [Recovery 3: a device disappeared from the system](#recovery-3-a-device-disappeared-from-the-system)
- [Recovery 4: black screen, no network, no second machine](#recovery-4-black-screen-no-network-no-second-machine)
- [Recovery 5: SDDM will not start](#recovery-5-sddm-will-not-start)
- [Recovery 6: the machine will not boot at all](#recovery-6-the-machine-will-not-boot-at-all)
- [What is actually installed where](#what-is-actually-installed-where)
- [There are two EFI partitions, and only one of them boots](#there-are-two-efi-partitions-and-only-one-of-them-boots)

**If you are in a hurry:** the two commands that answer "is this machine
healthy, and is the display driver mine?" are:

```bash
sudo /usr/local/bin/imac-verify
sudo /usr/local/libexec/imac-amdgpu-install --check
```

---

## Before you start: the one safety habit

Two backups, in priority order. Neither exists on a fresh machine, so both are
setup, not something you look up in a crisis.

### 1. The partition image — the one that actually saves you

```bash
# root partition: where patched kernels, boot entries and /etc live.
# Check your own free space first; this was 338G free on the reference machine.
sudo dd if=/dev/nvme0n1p4 of=/mnt/doomsday/root-$(date +%Y%m%d).img \
        bs=64M conv=fsync status=progress
sync && sudo md5sum /mnt/doomsday/root-*.img | sudo tee /mnt/doomsday/SHA256SUMS
```

**Do not skip this to save 68 MB of ESP space.** Backing up the initramfs
(§2) turns a 45-minute rebuild into a file copy; it does not help at all if the
boot entries themselves are gone or the partition will not mount.

### 2. The current initramfs — turns a rebuild into a copy

```bash
K=$(uname -r)
sudo cp -p "/boot/efi/opensuse-slowroll/$K/initrd" "/var/tmp/initrd-$K.bak"
ls -lh "/var/tmp/initrd-$K.bak"
```

Put it in `/var/tmp`, **not** on the ESP. The ESP is 197 MiB and holds exactly one
kernel pair; a second copy of a ~81 MiB initramfs does not fit, and an attempt to
make it fit is what truncated the bootable image on 2026-10-09.

**Check the space before you start.** A kernel install needs ~120M free on the ESP:

```bash
df -h /boot/efi
```

### 3. Snapper, which you already have

Root is Btrfs and `snapper` is installed. Every `zypper` transaction takes a
`pre`/`post` snapshot, and those already contain `/etc` and `/boot`:

```bash
snapper list | tail -5
sudo snapper -a 170 rollback     # pick a number you have confirmed, see docs/recovery.md
```

This is the fastest recovery for a bad config change and it costs nothing to keep.
It does **not** help with a corrupted ESP, which is a separate filesystem.

## Rule 0: never chain a destructive step with its own repair

This is written first because it is the mistake that actually happens, and it
was made on this machine.

```bash
# WRONG. If the unbind succeeds and the rebind fails, you have made it worse
# and left yourself no way back.
sudo sh -c 'echo 0000:00:1f.3 > /sys/bus/pci/devices/0000:00:1f.3/driver/unbind
            echo 0000:00:1f.3 > /sys/bus/pci/devices/0000:00:1f.3/bind'
```

Unbinding a PCI device **deletes** the `bind` file. It is not recreated until
the device re-probes, which does not happen until reboot. So after a
successful unbind there is no `bind` file to write to, and no module reload
will bring the device back — the module is still held by its dependencies and
refuses to unload.

The correct shape is to verify each step, and to confirm the repair path
exists *before* taking the destructive one:

```bash
ls /sys/bus/pci/devices/0000:00:1f.3/driver/unbind   # confirm you can do this
ls /sys/bus/pci/drivers/snd-hda-intel/bind           # confirm you can undo it
```

If the second `ls` fails, **stop and do not unbind.** You are one reboot away
from losing the device, and you have already confirmed the reboot is the only
way back.

---

## Recovery 1: black screen, or one tile, after a kernel update

**Symptom:** you ran `imac-update --kernel`, rebooted, and you get either a black
screen or a **working desktop that is only 2880 pixels wide**.

**Cause:** the new kernel has no patched `amdgpu` installed, or has one on disk
that never made it into the initramfs. Both look like this. **Do not panic and do
not rebuild anything.**

**Diagnose first, over SSH** — this tells you which of the two causes it is:

```bash
/usr/local/libexec/imac-amdgpu-install --check          # must NOT say "stock"
I=/boot/efi/opensuse-slowroll/$(uname -r)/initrd
lsinitrd "$I" | grep -cE 'updates/amdgpu\.ko\.zst|updates/snd-hda-codec-cs8409\.ko\.zst'
# 2 = the initramfs is correct. 0 or 1 = the module never got into it.
```

**Then go back to the previous kernel**, which is the fast fix either way:

```bash
sudo systemctl reboot
```

At the boot menu, choose the fallback. Its entry is not always visible, so write
it yourself first if you can still get a shell — this is a file copy and does not
need the display to work:

```bash
# XBOOTLDR holds the previous kernel pair. Copy it back onto the ESP, which is
# the only partition systemd-boot actually reads here.
K=7.2.7-1-default
sudo mkdir -p "/boot/efi/opensuse-slowroll/$K"
sudo cp -p "/boot/efi-xbootldr/opensuse-slowroll/$K/linux" \
           "/boot/efi-xbootldr/opensuse-slowroll/$K/initrd" \
           "/boot/efi/opensuse-slowroll/$K/"
sudo tee "/boot/efi/loader/entries/zz-$K.conf" >/dev/null <<EOF
title      openSUSE $K (rollback)
version    $K
sort-key   01-rollback
linux      /opensuse-slowroll/$K/linux
initrd     /opensuse-slowroll/$K/initrd
options    root=/dev/nvme0n1p4 amdgpu.tiled_stitch=-1 acpi_backlight=video security=selinux selinux=1 mitigations=auto
EOF
sudo bootctl list-entries | grep "$K"    # confirm it is on the ESP
```

**Check the ESP has room before that copy** — 93M free against a ~92M pair:

```bash
df -h /boot/efi
```

If the copy does not fit, delete the failed kernel's directory first; you are
trying to boot the *other* one.

**Then, so it cannot happen again.** The `45-amdgpu-5k.install` hook builds the
patched module on every kernel install, but detached — 20–45 minutes. Do not
reboot until it is done:

```bash
journalctl -fu "imac-amdgpu-build@$(uname -r)"
sudo /usr/local/libexec/imac-amdgpu-install --check --kver "$(uname -r)"
```

Only reboot when `--check` does not say stock.

---

## Recovery 2: you rebuilt the initramfs and lost 5K

**Symptom:** you ran `dracut`, `mkinitrd`, or any `imac-update` path that rebuilt
the initramfs, and now the display is broken. It still boots.

**Cause:** the initramfs no longer carries the patched module. Note that the
module still exists on disk — that is what makes this recoverable in seconds
rather than requiring a rebuild:

```bash
ls -l /usr/lib/modules/$(uname -r)/updates/amdgpu.ko.zst   # should exist
```

**Confirm what is actually loaded.** This is the check that matters, and it is
read-only:

```bash
cat /sys/module/amdgpu/srcversion
# 31F26E96354E3264CF28120 = ours (7.2.8)  <- correct
# 6A1BCCFD6F2E5A1A8F4807D = ours (7.2.7)
# 4BFAA1013BED7E3FB557CF0 = STOCK, and you have one tile

modinfo -n amdgpu    # .../updates/ = ours; .../kernel/ = stock
```

> [!NOTE]
> Always check `srcversion`, not just the parameter's presence. This build's
> `modinfo` reads the compressed `.zst` directly and reports `tiled_stitch`
> correctly, but that is a property of the tool version, not of the module. The
> srcversion check is unambiguous on any version:
> ```bash
> modinfo -F srcversion /usr/lib/modules/$(uname -r)/updates/amdgpu.ko.zst
> ```

**Fix — rebuild the initramfs from the module already on disk.** No kernel
rebuild needed; this takes about a minute:

```bash
K=$(uname -r)
I="/boot/efi/opensuse-slowroll/$K/initrd"
ls -l "$I" && sudo cp -p "$I" /var/tmp/initrd-broken.bak    # so you can retry
sudo dracut -f "$I" "$K"
```

**Verify before rebooting**, so you do not discover the problem twice:

```bash
lsinitrd "$I" | grep -E 'updates/(amdgpu|snd-hda-codec-cs8409)\.ko\.zst'
# must print TWO lines
```

If it prints fewer than two, the rebuild still dropped something — do not reboot,
read `journalctl -u dracut` or re-run with output visible.

The sizes on the reference machine, for comparison: patched `amdgpu.ko.zst` is
**5,596,535** bytes, the whole initramfs **84,923,115**. A materially smaller
initramfs is the symptom.

---

## Recovery 3: a device disappeared from the system

**Symptom:** hardware that used to work is gone from `lspci`, `lsusb`, or
`arecord -l`. On this machine it happened to the internal audio device: after
a failed unbind/rebind attempt, `arecord -l` listed only the USB interface and
card 1 was simply absent.

**First, distinguish "gone" from "not bound":**

```bash
lspci -nn | grep -i audio              # device still enumerated?
ls /sys/bus/pci/drivers/ | grep hda    # driver still present?
ls /sys/bus/pci/devices/0000:00:1f.3/ # driver/ and bind/ present?
```

- **Device gone from `lspci` entirely** — hardware or bus level. Reboot.
- **Device listed, but `driver/` is missing or empty** — unbound. Reboot.
- **Device listed, `driver/` present, still misbehaving** — a driver-level
  fault. Try reloading the driver before assuming the worst:

```bash
sudo systemctl restart sound.target
```

**Reboot is the reliable fix for an unbound device.** The PCI bus re-probes at
boot and re-attaches drivers. There is no runtime repair for an unbound
device, because unbinding removes the `bind` file and nothing recreates it
short of a re-probe.

**This is safe.** Unbinding is a runtime sysfs operation. It is not written to
disk, and it does not touch `/boot/efi`. A reboot clears it completely. The
default boot entry is unchanged and known-good.

What it costs you is whatever was running — an active call, an unsaved session.
That is the real trade-off, not the audio device.

---

## Recovery 4: black screen, no network, no second machine

The worst case, and the reason to keep a USB keyboard and a known-good external
display around.

1. **Switch to a TTY.** `Ctrl+Alt+F2` through `F6`. A TTY does not need the GPU
   to be working correctly. If the panel is unusable, plug a monitor into the
   Thunderbolt/USB-C port — the iMac19,1 drives external displays over TB3.
2. **Log in** at the TTY.
3. **Boot the previous kernel** rather than debugging at the prompt. Write the
   rollback entry as in Recovery 1, then:
   ```bash
   sudo systemctl reboot
   ```
4. If the TTY is also blank, the kernel is not reaching userspace. Boot a live
   USB — see Recovery 6.

**This is the scenario `docs/kernel-updates.md` is written to prevent.** The
amdgpu build must complete *before* you reboot into a new kernel, never after.

---

## Recovery 5: SDDM will not start

Independent of the graphics stack — a broken greeter is a login problem, not a
display problem.

```bash
systemctl status sddm
sudo systemctl restart sddm
```

To confirm the display is fine and only the greeter is broken, switch to a
plain session manager at a TTY:

```bash
startplasma-wayland        # or: startx
```

If the desktop starts, the machine is healthy and the problem is the greeter.
The working configuration and two traps in it are in the SDDM notes under
`docs/audio.md`.

---

## Recovery 6: the machine will not boot at all

You need another machine or a live USB. Nothing on this disk will help.

Mount the **ESP** — p1, not the root partition. systemd-boot reads this one:

```bash
sudo mount /dev/nvme0n1p1 /mnt
ls -lh /mnt/opensuse-slowroll/
sudo cat /mnt/loader/entries/*.conf
sudo bootctl status | head -20
```

**What should be there:** exactly one kernel directory and exactly one entry.

```
/mnt/opensuse-slowroll/7.2.8-1-default/{linux,initrd}
/mnt/loader/entries/zz-7.2.8.conf
```

**If the entry is missing**, write one by hand — it is four lines and needs no
tools from this disk:

```bash
K=7.2.8-1-default
sudo tee "/mnt/loader/entries/zz-$K.conf" >/dev/null <<EOF
title      openSUSE $K
version    $K
sort-key   02-$K
linux      /opensuse-slowroll/$K/linux
initrd     /opensuse-slowroll/$K/initrd
options    root=/dev/nvme0n1p4 amdgpu.tiled_stitch=-1 acpi_backlight=video security=selinux selinux=1 mitigations=auto
EOF
```

**If the initramfs is truncated**, copy the known-good one from the XBOOTLDR,
which systemd-boot does *not* read but which still holds the previous pair:

```bash
sudo mount /dev/nvme0n1p6 /mnt2
sudo cp -p /mnt2/opensuse-slowroll/7.2.7-1-default/initrd \
           /mnt/opensuse-slowroll/7.2.8-1-default/initrd
```

Otherwise rebuild per `docs/kernel-updates.md`.

**There is no `grub2-mkconfig` on this machine.** It is systemd-boot with BLS
entries, so regenerating entries with grub tooling does nothing here.

---

## What is actually installed where

Keep this in your head during any recovery. It explains most of the confusion in
this repository.

| Thing | Where it lives | Note |
|---|---|---|
| Patched `amdgpu` | `/usr/lib/modules/$(uname -r)/updates/amdgpu.ko.zst` | **and** in the initramfs. Both, or you get one tile. |
| `tiled_stitch` value | kernel command line, `amdgpu.tiled_stitch=-1` | declared `int`, so `sysfs` reads it back verbatim |
| CS8409 audio driver | DKMS `snd-hda-macbookpro/0.2` → `updates/` | plus the patched initramfs |
| Internal speakers | 2-channel `analog-stereo` | `analog-surround-40` is the broken enumeration |
| iGPU | hidden by Apple firmware (see `docs/igpu-and-quicksync.md`) | enabling it can steal HDA audio **and** changes the DRM topology the 5K tiling depends on |
| Boot entries | `/boot/efi/loader/entries/`, one file | the ESP is the only partition systemd-boot reads |
| Bootloader | systemd-boot, not GRUB | there is no `/etc/default/grub` to edit |

**Two facts that cause most of the confusion here:**

1. `/lib/modules/.../kernel/drivers/gpu/drm/amd/amdgpu.ko.zst` is a **stock**
   copy. It exists, it looks plausible, and it is not what you are running.
   `/sys/module/amdgpu/srcversion` is the truth, not the file's presence.
2. The patched module on disk is not enough on its own — it must be in the
   **initramfs** as well, because that is what loads first. A module in
   `updates/` with a stock initramfs gives you one tile and no error.

```bash
# both facts, one command
sudo /usr/local/libexec/imac-amdgpu-install --check
```

---

## There are two EFI partitions, and only one of them boots

This machine has both a standard ESP and an XBOOTLDR, and a kernel update
repopulates them differently:

| Partition | Mount | Size | Holds |
|---|---|---|---|
| `/dev/nvme0n1p1` (ESP) | `/boot/efi` | 197 MB | **the only kernel systemd-boot will boot**, plus its single BLS entry |
| `/dev/nvme0n1p6` (XBOOTLDR) | `/boot/efi-xbootldr` | 3.8 GB | staging and rollback pairs — **never searched at boot** |

The XBOOTLDR exists because a kernel+initramfs pair is ~92 MB and the ESP holds
exactly one. There is nowhere else for the previous pair to live.

**The trap that cost a boot on 2026-10-09:** systemd-boot here reads **only the
ESP**, so an entry that exists solely on XBOOTLDR is invisible no matter how it is
sorted. Confirm which partition the firmware is actually using:

```bash
sudo bootctl status | grep -iE 'Available Boot Loaders|ESP:'
# -> ESP: /boot/efi (/dev/disk/by-partuuid/1d721b24-...)
```

The machine *supports* an XBOOTLDR partition — `bootctl` says so — but on this
system the ESP is the only entry location listed, and that is the one that
decides what boots.

Anything you want bootable must be on `/boot/efi`. Copy it there; do not assume a
write to the XBOOTLDR took effect.

Set `sort-key` as well as `default`, because a `default` naming an entry that
does not exist is silently ignored:

```bash
ENTRY=zz-7.2.8.conf
for P in /boot/efi /boot/efi-xbootldr; do
  printf 'timeout 30\ndefault %s\nconsole-mode max\n' "$ENTRY" > "$P/loader/loader.conf"
done
sudo bootctl list-entries | grep -i "$ENTRY"
```

---

## Snapper snapshots other than your working one have a read-only `/etc`

On the reference machine, snapshot 121 (the one a kernel update creates) has
**`/etc` and `/usr` read-only**, while `/var`, `/tmp`, `/home` and `/usr/local`
stay writable because they are separate subvolumes.

Everything system-wide then fails in a way that looks like a permissions
problem:

```
Failed to mask unit: File /etc/systemd/system/sleep.target: Read-only file system
touch /etc/x -> Read-only file system
depmod: ERROR: ... /lib/modules/7.2.7-1-default ... Read-only file system
```

Only `/usr/local`, `/var`, `/tmp` and `/home` accept writes. Check before
concluding a fix failed:

```bash
findmnt -no TARGET,OPTIONS /etc /usr /var 2>/dev/null
```

If you have booted the wrong snapshot, **reboot rather than repair it** —
there is nothing to fix, the snapshot is simply not your working root. Confirm
with `findmnt -no SOURCE /`; the working root here is `@/.snapshots/1/snapshot`.

This also means DKMS installs and `depmod` cannot add modules for the kernel
you are running from such a snapshot. The modules must already be in its tree,
or the initramfs must carry them.

## Plymouth cannot display here

Not a misconfiguration, and not worth further attempts without reading
[`docs/tiled-5k.md`](tiled-5k.md#amdgpu-takes-about-8-seconds-to-initialise).

```
[2.2s]  efidrm (EFI framebuffer)
[2.8s]  Plymouth starts
[8.1s]  amdgpu initialised — the real panel finally exists
[~11s] Plymouth starts again (system phase)
[14.5s] Plymouth terminates when the display manager starts
```

Plymouth runs for about 3.8 s with a usable display, and the panel needs ~5.2 s
of Polaris firmware loading before that exists. It works on a stock
initramfs, because there Plymouth falls back to the EFI framebuffer — but that
combination does not tile, so it is not a useful trade.

`rd.driver.blacklist=efi-framebuffer` is not honoured for DRM drivers;
`modprobe.blacklist=` is **not a kernel parameter** (the kernel takes
`module_blacklist=`). Neither changes the outcome. If Plymouth is enabled and
you want the boot seconds back, remove `rd.plymouth=1` from the entry.

## A rebuilt entry can silently drop the brightness parameter

Brightness depends on `acpi_backlight=video` on the kernel command line. It is
not a module, not a udev rule and not in `/etc/default/grub` — this machine has
no such file. It lives only in the hand-maintained BLS entries:

```
/boot/efi-xbootldr/loader/entries/5k-727.conf
/boot/efi-xbootldr/loader/entries/5k-722.conf
```

So anything that regenerates entries — `kernel-install`, a copied entry, a
distribution upgrade — can drop it, and the symptom is only that the screen is
stuck at one brightness with no slider. The display is otherwise perfect, which
makes it easy to dismiss as a hardware fault.

If brightness stops working after an update, check the parameter before
anything else:

```bash
tr ' ' '\n' < /proc/cmdline | grep backlight
ls /sys/class/backlight/          # expect acpi_video0, not amdgpu_bl*
```

There is no `grub2-mkconfig` involvement and no `/etc/default/grub` to edit.

## A keep-awake inhibitor can silently block rebooting

This one presents as "reboot does nothing", which is very hard to connect to
its cause. The command that looks like it failed:

```
$ systemctl reboot
Call to Reboot failed: Operation denied due to active block inhibitor
```

`systemd-inhibit --what=idle:sleep:shutdown` blocks **shutdown and reboot** as
well as sleep. To prevent idle suspend without preventing a deliberate reboot:

```bash
ExecStart=/usr/bin/systemd-inhibit --what=idle:sleep \
  --who=imac-keep-awake --why="..." sleep infinity
```

Check for the culprit before anything else when a reboot appears to do nothing:

```bash
systemd-inhibit --list
systemctl status imac-keep-awake.service
```

Note also that `systemd-run --on-active=2 systemctl reboot` and a backgrounded
`(sleep 2; systemctl reboot)` both appear to succeed while leaving the machine
running, because the unit's failure is easy to miss in the output. Check
`journalctl -u <unit>` if a scheduled reboot does not happen.

---

## Related

- `docs/kernel-updates.md` — building a patched initramfs for a new kernel
- `docs/tiled-5k.md` — tiling diagnostics and the three failure modes
- `docs/troubleshooting.md` — display problems that are not emergencies
- `docs/brightness.md` — panel brightness, and the `acpi_backlight=video` fix
- `docs/audio.md` — the CS8409 codec, headset capture, and `dmesg` permissions
- `patches/amdgpu-5k/README.md` — patch provenance and apply order
- `scripts/check-5k.sh` — read-only diagnostic; safe to run at any time
