# Recovery

> **Status: VERIFIED — the unbound-device case is real.**
> Recovery 3 was written after an actual incident on this machine, not
> hypothetically. The others follow the same failure paths and are written
> conservatively.

**Read this before changing anything on this machine.**

The tiled 5K display depends on a hand-patched `amdgpu` carried inside a
custom initramfs (`initrd-stackC`). There is no in-distro package for it. If
that image is replaced, rebuilt without the patch, or booted with a kernel for
which no patched initramfs exists, you get a black screen at 5120×2880 and no
way to type a command.

That is recoverable. It just is not recoverable from the keyboard in front of
you if you have no second machine and no network.

The single most useful thing you can do before touching this system is make
sure you have **SSH access from somewhere else** on the network or over
Tailscale. Every procedure below assumes it.

---

## Contents

- [Before you start: the one safety habit](#before-you-start-the-one-safety-habit)
- [Rule 0: never chain a destructive step with its own repair](#rule-0-never-chain-a-destructive-step-with-its-own-repair)
- [Recovery 1: black screen after a kernel update](#recovery-1-black-screen-after-a-kernel-update)
- [Recovery 2: you rebuilt the initramfs and lost 5K](#recovery-2-you-rebuilt-the-initramfs-and-lost-5k)
- [Recovery 3: a device disappeared from the system](#recovery-3-a-device-disappeared-from-the-system)
- [Recovery 4: black screen, no network, no second machine](#recovery-4-black-screen-no-network-no-second-machine)
- [Recovery 5: SDDM will not start](#recovery-5-sddm-will-not-start)
- [Recovery 6: the machine will not boot at all](#recovery-6-the-machine-will-not-boot-at-all)
- [What is actually installed where](#what-is-actually-installed-where)

---

## Before you start: the one safety habit

Back up the working initramfs **once**, before you need it:

```bash
sudo cp -p /boot/efi/opensuse-slowroll/7.2.2-1-default/initrd-stackC \
           /boot/efi/opensuse-slowroll/7.2.2-1-default/initrd-stackC.orig.bak
```

That costs 68M on a 197M ESP. If space is tight, copy it somewhere else:

```bash
sudo cp -p /boot/efi/opensuse-slowroll/7.2.2-1-default/initrd-stackC /var/tmp/
```

Either way, a bad rebuild becomes a file copy away from recovery instead of a
machine away from recovery.

**Check the space before you start.** A kernel install needs ~120M free on the
ESP; even a non-kernel update wants ~45M:

```bash
df -h /boot/efi
```

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

## Recovery 1: black screen after a kernel update

**Symptom:** you ran `imac-update --kernel`, rebooted, and the display is black
or shows garbage. The machine is otherwise alive.

**Cause:** the new kernel has no patched `amdgpu`. A stock `amdgpu` has no
`tiled_stitch` parameter at all, so there is no second tile — you get one
2880-wide panel at best, frequently nothing usable on the built-in panel.

**Do not panic and do not rebuild anything.** Pick the old kernel at the boot
menu.

```bash
# over SSH, if the machine still responds:
sudo systemctl reboot
```

Then, during the 30-second boot menu:

1. Use the arrow keys to select `5K openSUSE verified Stack C (no Plymouth)`.
2. Press Enter.

If the menu is not visible on the panel, try the external path: switch to a
lower resolution with `Ctrl+Alt+F2` (a TTY), or attach a monitor to the
Thunderbolt port. A TTY on the built-in panel at a broken mode may still be
legible.

The verified entry is the default and uses `initrd-stackC`, which carries the
patched driver for kernel 7.2.2. It will boot.

**Then, so it cannot happen again**, hold the kernel:

```bash
echo 'kernel = kernel-default = 7.2.2-1-default' | sudo tee /etc/zypp/constraints.d/kernel-block.const
```

See `docs/kernel-updates.md` for building a patched initramfs for a new kernel
properly.

---

## Recovery 2: you rebuilt the initramfs and lost 5K

**Symptom:** you ran `dracut`, `mkinitrd`, or any `imac-update` path that
rebuilt the initramfs, and now the display is broken. It still boots, but the
patched driver is gone.

**Cause:** the patched `amdgpu` exists **only inside** `initrd-stackC`. It is
not installed anywhere on the filesystem. Confirm this:

```bash
modinfo -F srcversion amdgpu    # stock:  4FA5DDFCFF3DDAE9F5FE22E
cat /sys/module/amdgpu/srcversion  # running (patched): 6BE242C1C62DD79046F2E9A
modinfo -p amdgpu | grep -c tiled_stitch   # 0 = you have the stock driver
```

If that last command returns `0`, the initramfs no longer carries the patch.

**Fix:** restore the backup, or rebuild it with the patch in place.

```bash
# If you took the backup in "Before you start":
sudo cp -p /boot/efi/opensuse-slowroll/7.2.2-1-default/initrd-stackC.orig.bak \
           /boot/efi/opensuse-slowroll/7.2.2-1-default/initrd-stackC
sudo reboot
```

If you have no backup, the patch is in this repository and can be rebuilt —
see `docs/kernel-updates.md` and `patches/amdgpu-5k/README.md`. That is a real
rebuild, not a five-minute fix, and it is why the backup exists.

**Verify before rebooting**, so you do not discover the problem twice:

```bash
lsinitrd /boot/efi/opensuse-slowroll/7.2.2-1-default/initrd-stackC | grep amdgpu.ko
```

The size must be **5,989,088 bytes**. A stock `amdgpu.ko.zst` is 6,826,583.
If you see the larger number, the rebuild dropped the patch.

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

The worst case, and the reason to keep a USB keyboard and a known-good
external display around.

1. **Switch to a TTY.** `Ctrl+Alt+F2` through `F6`. A TTY does not need the
   GPU to be working correctly. If the panel is unusable, plug a monitor into
   the Thunderbolt/USB-C port — the iMac19,1 drives external displays over
   TB3.
2. **Log in** at the TTY.
3. **Boot the previous kernel** rather than debugging at the prompt:
   ```bash
   sudo systemctl reboot
   ```
   then pick `5K openSUSE verified Stack C (no Plymouth)` at the menu.
4. If the TTY is also blank, the kernel is not reaching userspace. That is
   outside what this repository can fix — boot from a live USB and restore
   `/boot/efi` from a backup.

**This is the scenario `docs/kernel-updates.md` is written to prevent.** Build
the patched initramfs for a new kernel *before* making that kernel the
default, never after.

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

From a live environment, mount the ESP and check what is there:

```bash
sudo mount /dev/nvme0n1p1 /mnt
ls -lh /mnt/opensuse-slowroll/7.2.2-1-default/
cat /mnt/loader/entries/*.conf
```

The default entry should be `5k-stackc-stitch.conf`, pointing at
`initrd-stackC`. If the initramfs is missing or truncated, restore it from
`initrd-stackC.orig.bak` if that exists, otherwise rebuild per
`docs/kernel-updates.md`.

Then, from that live environment:

```bash
sudo chroot /mnt
sudo grub2-mkconfig -o /boot/efi/loader/loader.conf    # if entries are missing
```

---

## What is actually installed where

Keep this in your head during any recovery. It explains most of the confusion
in this repository.

| Thing | Where it lives | Elsewhere |
|---|---|---|
| Patched `amdgpu` | **only** inside `initrd-stackC` | `/lib/modules` holds a **stock** copy with no `tiled_stitch` |
| `tiled_stitch` value | kernel command line, `amdgpu.tiled_stitch=-1` | sysfs readback mirrors it; both should read `-1` |
| CS8409 audio driver | DKMS, `snd-hda-macbookpro/0.1` → `updates/` | not in-tree |
| Internal speakers | 2-channel `analog-stereo` | the 4-channel `analog-surround-40` enumeration is the broken one |
| Plymouth | omitted from `initrd-stackC` | installed as packages, but stripped from that image |
| iGPU | hidden by Apple firmware (see `docs/igpu-and-quicksync.md`) | enabling it can steal HDA audio **and** changes the DRM topology the 5K tiling depends on |

**Never** treat `/lib/modules/.../amdgpu.ko.zst` as the driver you are running.
It is not. `/sys/module/amdgpu/srcversion` is the truth.

---

## There are two EFI partitions, and the one you are editing may be ignored

This machine has both a standard ESP and an XBOOTLDR, and a kernel update
repopulates them differently:

| Partition | Mount | Holds |
|---|---|---|
| `/dev/nvme0n1p1` (ESP) | `/boot/efi` | snapper-generated BLS entries, ~197 MB, **can fill up** |
| `/dev/nvme0n1p3` (XBOOTLDR) | `/boot/efi-xbootldr` | hand-built entries and initramfs, 8 GB |

Custom 5K entries normally live on **XBOOTLDR**. That is where there is room —
an initramfs of ~85 MB does not fit in what remains of a 197 MB ESP once a
kernel update has taken 92 MB of it.

**The trap that cost a boot:** firmware boots the ESP, so systemd-boot reads
its `loader.conf` — not XBOOTLDR's. An entry sorted first on XBOOTLDR is
irrelevant if the ESP's `loader.conf` names a snapper entry. Symptoms are a
reboot landing in a snapshot you did not choose, with a read-only `/etc`.

Set the default in **both** files:

```bash
for P in /boot/efi /boot/efi-xbootldr; do
  printf 'timeout 30\ndefault %s.conf\nconsole-mode max\n' ENTRY > $P/loader/loader.conf
done
```

Also **do not rely on `default` alone.** Set `sort-key` so the intended entry
sorts first, because a `default` naming an entry that does not exist is
silently ignored:

```bash
sort-key aaa-<your-entry>     # sorts before the snapper-* keys
```

A kernel update rewrites ESP entries and can leave `loader.conf` pointing at a
deleted file. Symptom: the machine boots a snapshot you did not select.

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
