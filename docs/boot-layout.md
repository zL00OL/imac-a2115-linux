# Boot layout, and why `zypper dup` used to break the machine

> **Verified 2026-10-10 on the reference machine, running `7.2.8-1-default`.**

This page exists because an update went wrong in a way that is easy to repeat.
The summary: **the ESP is too small to install a kernel update safely, and this
bootloader only ever looks at the ESP.**

## The two partitions

```
p1  ESP       197 MiB   /boot/efi          holds the loader, entries, and ONE kernel pair
p6  XBOOTLDR  3.8 GiB   /boot/efi-xbootldr  correct type BC13C2FF..., currently the rollback pair
```

`BC13C2FF-59E6-4262-A352-B275FD6F7172` is the XBOOTLDR partition type.
`C12A7328-F81F-11D2-BA4B-00A0C93EC93B` is an **EFI System Partition** type — two
different things, and confusing them makes the partition invisible to the
loader. See [p6 was mistyped](#p6-was-mistyped) below.

## The ESP holds exactly one kernel pair

```
kernel   16.7 MiB
initrd   80.4 MiB
pair     97.1 MiB     of 197 MiB available
```

Two pairs *almost* fit, which is the trap: an install that writes the new kernel
before removing the old one leaves no room, and the write fails part-way.

That is not hypothetical. `zypper dup` on 2026-10-09 installed 163 packages and
then:

```
ERROR: No free space in /boot/efi for new kernel
warning: %posttrans(dracut-...) scriptlet failed, exit status 1
```

The 7.2.8 kernel package ended up registered with rpm but with **no kernel image
on disk at all** — `rpm -ql` listed `/boot/vmlinuz-7.2.8-1-default` and the file
did not exist.

## The bootloader reads the ESP only

This is the fact that decides the whole layout, and it is easy to get wrong.
`systemd-boot` 261.2 **supports** XBOOTLDR — `bootctl status` lists
`✓ Support for XBOOTLDR partition` — but support is not the same as use:

```
$ bootctl status
  Boot Loader Entry Locations:
            ESP: /boot/efi (..., $BOOT)
         config: /boot/efi//loader/loader.conf

  Current Entry: aaa-7.2.7-verified.conf
  Default Entry: aaa-7.2.7-verified.conf
```

Only one entry location is listed. An entry placed on the XBOOTLDR is **not seen**
— it did not appear in `bootctl list`, and `loader.conf` on the XBOOTLDR was
ignored in favour of the ESP copy. A BLS entry on the ESP referencing files that
live on the XBOOTLDR is equally unreliable, because the cross-partition
resolution has to come from the same code path that did not read the XBOOTLDR
entries.

**Therefore: whatever must boot has to be on the ESP.**

Confirm it yourself before trusting any layout:

```bash
bootctl status | sed -n '/Boot Loader Entry Locations/,/token/p'
```

## Current arrangement

```
ESP   opensuse-slowroll/7.2.8-1-default/{linux,initrd}   <- the bootable pair
      loader/entries/zz-7.2.8.conf                       <- the only entry, default
      loader/entries/README-rollback                      <- how to get back to 7.2.7

XBLDR opensuse-slowroll/7.2.7-1-default/{linux,initrd}   <- rollback pair, NOT in the menu
```

The 7.2.7 pair cannot be booted from the menu, because the loader does not read
entries there. `README-rollback` on the ESP has the copy-back commands, and
Snapper **156** is the pre-upgrade filesystem state.

Verify both pairs before trusting them:

```bash
for f in /boot/efi/loader/entries/*.conf; do
  for r in $(awk '$1=="linux"||$1=="initrd"{print $2}' "$f"); do
    [ -f "/boot/efi$r" ] && echo "OK   $r" || echo "MISS $r"
  done
done
```

## The offset moves between kernels

The `set_os` model table lives at a different offset in each build:

| Kernel | last slot offset |
|---|---|
| 7.2.7-1-default | 17524841 |
| 7.2.8-1-default | 17530985 |

Never hardcode it. `scripts/imac-setos-patch` finds the table by content and
refuses to write unless the full 120-byte sequence appears exactly once:

```
SKIPPED: set_os model table not found exactly once (found 0).
Image left stock; iGPU stays hidden.
```

That refusal is the reason a stale offset cannot silently corrupt a kernel.

## p6 was mistyped

During the 2026-10-09 work, p6's partition type was changed from the correct
XBOOTLDR type to `C12A7328-...` on the mistaken belief that this was the
XBOOTLDR type. It is the EFI System Partition type; XBOOTLDR is `BC13C2FF-...`.

Nothing broke immediately, because systemd-boot was reading the ESP anyway. But
a mistyped XBOOTLDR is a latent trap, and the type was restored.

```bash
lsblk -no NAME,PARTTYPE,PARTLABEL /dev/nvme0n1
# p1  c12a7328-... EFI System Partition
# p6  bc13c2ff-... XBOOTLDR
```

## The whole kernel update, in order

This is the sequence that worked, after several failed attempts.

```bash
# 0. snapshot, so a filesystem rollback exists
snapper create --description "pre-update" --cleanup-algorithm number

# 1. confirm the fallback is intact BEFORE freeing anything
lsinitrd /boot/efi/opensuse-slowroll/7.2.7-1-default/initrd >/dev/null && echo ok

# 2. free the ESP (one pair fits, not two)
rm -rf /boot/efi/opensuse-slowroll

# 3. install the kernel package
zypper install kernel-default-7.2.8-1.1        # the full name: -1.1 is part of the version

# 4. apply the six 5K patches to the new source tree, in order, --fuzz=0
#    (see patches/amdgpu-5k/README.md)

# 5. build. Two things are needed and neither is obvious:
cd /usr/src/linux-7.2.8-1
openssl req -new -x509 -newkey rsa:2048 -nodes -days 36500 \
  -keyout $OBJ/.kernel_signing_key.pem -subj "/CN=imac-signing/"
make O=$OBJ -j$(nproc) modules

# 6. install the module where modprobe prefers it
strip --strip-debug /tmp/amdgpu.ko          # 791 MB -> 36 MB
zstd -19 -f /tmp/amdgpu.ko -o /usr/lib/modules/7.2.8-1-default/updates/amdgpu.ko.zst
depmod -a 7.2.8-1-default

# 7. rebuild the initrd. The one the package built predates the DKMS module,
#    so it contains neither patched module. Gate on their presence:
dracut -f --kernel-image <kernel> --kver 7.2.8-1-default /tmp/new-initrd
lsinitrd /tmp/new-initrd | grep -c updates/amdgpu.ko.zst      # must be >= 1
lsinitrd /tmp/new-initrd | grep -c updates/snd-hda-codec-cs8409.ko.zst

# 8. patch the kernel's EFI stub, and only then write the entry
scripts/imac-setos-patch <kernel>

# 9. bootctl parses the entry - it catches malformed fields
bootctl status | grep -i 'unknown line'

# 10. reboot, then verify
```

### Things that are not optional

- **`strip` and `zstd`.** An unstripped `amdgpu.ko` here is 791 MB. Without
  compression it does not fit the ESP at all.
- **The signing key.** A fresh object tree fails with
  `No rule to make target '.kernel_signing_key.pem'`.
- **Rebuilding the initrd after DKMS.** The package's initrd is built from the
  package's own module set and contains neither patched module, so it boots
  without 5K and without the headset codec.
- **The `depmod`.** Without it the initrd picks the stock `amdgpu` from
  `kernel/` instead of `updates/`.

### Gates worth keeping

Every destructive step above was preceded by a check, and two of them caught
real damage:

- checking the fallback initrd was valid before freeing the ESP
- comparing the copied initrd size against the source after the copy

A truncated initrd was produced twice during this work by copying onto a full
ESP and then deleting the source before confirming the copy. Compare sizes, and
confirm the copy, before removing anything.

## `tries` is not a BLS field

Boot counting is supported (`✓ Boot counting`), and `/etc/kernel/tries` is set
to 3. But a `tries 3` line inside an entry is **rejected**:

```
$ bootctl status
/boot/efi/loader/entries/zz-7.2.8.conf:14: Unknown line 'tries', ignoring.
```

So there is **no automatic boot-counting fallback** on this setup. If the new
kernel panics before the menu appears, there is no retry. The fallback is
manual, via `README-rollback` and the 15-second menu.

## What systemd-boot actually chose

Worth recording, because it cost several reboots to understand:

| Entry layout | What booted |
|---|---|
| setos entry + stock entry on the ESP | **stock** — the stock entry won |
| setos entry alone on the ESP | setos — worked |
| setos entry on the XBOOTLDR only | **7.2.7** — the XBOOTLDR entry was ignored |

**Keep exactly one entry.** An entry directory containing "ours plus a fallback"
does not fall back — it picks the other one.