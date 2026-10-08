# Brightness

> **Status: SOLVED.** Add `acpi_backlight=video` to the kernel command line and
> reboot. The panel responds across its full range and the KDE slider works
> again. No DSDT override, no kernel patch, no AML.

This page records what the actual fault was, because the symptom is identical
to several dead ends below and the wrong ones look convincing.

## The fix

Both boot entries carry it. On this machine there is no `/etc/default/grub`;
the entries are hand-maintained BLS files, which is why the parameter must be
edited in both places:

```
/boot/efi-xbootldr/loader/entries/5k-727.conf
/boot/efi-xbootldr/loader/entries/5k-722.conf

options root=UUID=… rootflags=subvol=@/.snapshots/1/snapshot \
        amdgpu.tiled_stitch=-1 acpi_backlight=video
```

## What was actually wrong

Two faults were tangled together, and the second was invisible until the first
was worked around.

**1. The only backlight node was a `raw` one that the panel ignores.**

```
/sys/class/backlight/amdgpu_bl2   current=65535 max=65535 type=raw
$ echo 30000 > …/amdgpu_bl2/brightness
$ cat …/amdgpu_bl2/brightness
30000            # accepted, and the panel did not change
```

This is amdgpu's DP-aux backlight, not what this panel is wired to. Writes
succeed because the kernel never checks whether anything is on the other end.

**2. The desktop had nothing to drive.**

`acpi_backlight` defaults to `native` here, and that was in the command line
already. In `native` mode amdgpu registers its own backlight and the kernel
**never creates the ACPI one**. PowerDevil enumerates `/sys/class/backlight`
but only acts on nodes of type `firmware` or `platform` — `raw` is skipped. So
the slider had exactly one candidate and rejected it.

This was previously misdiagnosed as a UPower regression. It is not:

```
$ upower -e
/org/freedesktop/UPower/devices/ups_hiddev1
/org/freedesktop/UPower/devices/DisplayDevice
```

UPower exposes no backlight device in either mode. PowerDevil reads sysfs
itself; the `raw` type was the whole problem.

With `acpi_backlight=video` the kernel registers the firmware driver instead
and stands amdgpu down:

```
amdgpu 0000:01:00.0: [drm] Skipping amdgpu DM backlight registration

/sys/class/backlight/acpi_video0   89/89    type=firmware   <- the 5K panel
/sys/class/backlight/acpi_video1   100/100  type=firmware   <- the IGPU, no panel
```

`acpi_video0` is `GFX0`, the dGPU that drives the panel. Its 89 steps are the
firmware's own level table (below). `acpi_video1` is the iGPU and has nothing
attached — ignore it.

Verified working across the whole range, and by eye:

```
$ for v in 0 22 45 67 89; do echo $v > /sys/class/backlight/acpi_video0/brightness; \
      printf "%s -> %s\n" $v "$(cat /sys/class/backlight/acpi_video0/brightness)"; done
0 -> 0
22 -> 22
45 -> 45
67 -> 67
89 -> 89
```

## The firmware's brightness path

The panel is driven by ACPI. On this machine (iMac19,1, firmware revision
`0x00150001`) the real paths, printed from the machine's own DSDT, are:

```
\_SB.PCI0.PEG0.EGP0.EGP1.GFX0    Device (GFX0)   -- dGPU, the 5K panel
    Method (ABCM, 1)             set brightness, takes a level 0..90
    Method (ABCL, 0)             Return (Package) — the level table
    Method (BSET, 1)             scale 655 * level onto the controller
\_SB.PCI0.PEG0.EGP0.EGP1.GFX0.LCD  Device (LCD)
    Method (_BCL, 0)             Return (ABCL ())
    Method (_BCM, 1)             ABCM (Arg0)
    Method (_BQC, 0)             Return (BRTL)

\_SB.PCI0.PEG0.GFX0               Device (GFX0)   -- second instance, one per GPU
    ... same ABCM/ABCL, and an LCD child with the same three methods
```

`ABCL` returns 92 entries: a two-byte header (`0x50`, `0x32`), then levels
`1..90`. Because `BSET` scales by `655 * level`, the firmware's maximum of 90
reaches `58950` of `65535` — about **90% of what macOS can drive**. Apple caps
the table below the panel's real range, which is why `acpi_video0` reports
`max_brightness=89` and why the slider does not quite reach the top end. This
is a firmware cap, not a driver limit, and it is not worth chasing.

`BRTL` — returned by `_BQC` — is an *external reference* to a field unit rather
than a plain integer. `_BCL` and `_BCM` are the integers that matter.

### One thing left unexplained

`_BCL`/`_BCM`/`_BQC` sit on the `LCD` **child** of `GFX0`, while `GFX0` itself
carries only `ABCM`/`ABCL`. The ACPI video driver looks for brightness methods
on the *video device*, so on the face of it it should not have found them — yet
`acpi_video0` registered with exactly the 89 levels from that table, so it did
find them.

Whether it reads a `_BCL` on `GFX0` that the brace-tracking above missed, or
walks to the `LCD` child, was not established. It does not affect the fix, and
the ASL route to forcing the question is closed anyway — see below.

## The AML route is closed, and it is worth knowing why

The obvious plan was an SSDT that **adds** delegating methods to `GFX0`, since
`GFX0` has no `_BCL` of its own, so nothing would be redefined and the kernel
would accept the table. It cannot be written:

```
$ iasl -p bright bright.dsl
Error 6105 - Invalid object type for reserved name
```

**`_BCL`, `_BCM` and `_BQC` are ACPI reserved names.** ASL will not define
them, so no supplementary table can add them. That is almost certainly why
several 5K projects rename these methods in their patches instead of wrapping
them.

Two related dead ends, for anyone repeating this:

- ACPICA does not resolve paths across `DefinitionBlock`s. Compiling the table
  together with the machine's decompiled DSDT gives `Error 6161`
  (`One or more objects within the Pathname do not exist`) and then `Error
  6164`. `External` declarations do fix the resolution, and then `Error 6105`
  closes it regardless of where the `External` lines are placed.
- Do not infer scope paths from indentation when reading a decompiled DSDT. A
  first attempt produced `\_SB._SB.EGP0.EGP1.GFX0`, which does not exist; the
  real path is `\_SB.PCI0.PEG0.EGP0.EGP1.GFX0`.

## The DSDT override: built, never needed

An override extending `ABCL` from levels `1..90` to `1..100` plus 101 (bumping
the OEM revision so the kernel would prefer it) was built and verified:

```
before:  ABCL count=0x5C (92)   entries: 92   first: [0x50, 0x32, One, 0x02 …]
after:   ABCL count=0x67 (103)  entries: 103  first: [0x64, 0x32, One, 0x02 …]
         OEM Revision 0x00150001 -> 0x00150002
```

It is **not loaded**, and no longer needs to be. It was placed in the initramfs
at the root named for the table signature (`lsinitrd` shows `-rw-r--r-- 1 root
root 30231 DSDT`) with `CONFIG_ACPI_TABLE_UPGRADE=y`, yet the live table still
reports revision `0x00150001`. The expected cause is DSDT-vs-SSDT:
`acpi_table_upgrade()` reads SSDTs out of the initramfs, while the DSDT is
consumed from firmware before the initramfs exists. This machine keeps its
brightness table in the DSDT; the iMac18,3 project this follows overrides an
SSDT instead.

If someone does want the extra 10% of range, that is the table to fight over.
It is a range question only — it was never the reason brightness did not work.

## Dead ends

| Route | Why it does not work |
|---|---|
| `amdgpu_bl2` / `amdgpu_bl1` sysfs | Writes accepted, panel unchanged (measured) |
| Driving `amdgpu_bl` from a script | Same node. Selection order, not permissions, was the bug |
| `acpi_backlight=native` | The default, and the reason nothing worked. It registers amdgpu's `raw` node |
| `acpi_backlight=firmware` | Never tried. Superseded — `video` works |
| SSDT adding `_BCL`/`_BCM` to `GFX0` | **Impossible.** Reserved names, `Error 6105` |
| Compiling an override against the live DSDT | `Error 6161`/`6164` — ACPICA does not link across DefinitionBlocks |
| DSDT override via `acpi_table_upgrade` | Built and correct; the kernel does not apply DSDT replacement |
| `acpi_call` kernel module | **Removed from upstream Linux.** No `CONFIG_ACPI_CALL`, no Kconfig entry, no `acpi_call.c` in the 7.2.7 tree, not packaged |
| libacpi (userspace AML) | `zypper search libacpi` → "No matching items found" |
| `acpiexec` (ships with `acpica`) | Runs AML in userspace with its own namespace; cannot drive real hardware |
| Blaming `video.ko` missing from the initramfs | **Disproved.** `video` is loaded (81920, used by `amdgpu` and `i915`) and registers `video0`/`video1` — it just could not create a backlight in `native` mode |
| `rd.driver.blacklist=efi-framebuffer` | Not honoured for DRM drivers by dracut |
| `modprobe.blacklist=efi-framebuffer` | **Wrong parameter name.** The kernel takes `module_blacklist=` |

`efi-framebuffer` is *not* in `modules.builtin`, yet it loads anyway, so that
blacklist name is still unverified.

## Method notes

- **`dmesg` as a normal user returns nothing at all.** Any conclusion drawn
  from an empty read is worthless — several were drawn that way before this was
  noticed. Read it as root.
- Both ACPI video devices report the same `v4l` name
  (`FaceTime HD Camera (Built-in)`), so the name is no help for telling them
  apart. Use `max_brightness`: 89 is the panel, 100 is the iGPU.

## After the fix

- Brightness persists across reboot via `systemd-backlight@`, which saves to
  `/var/lib/systemd/backlight/pci-0000:01:00.0:backlight:acpi_video0`.
- KDE's slider works on its own now. `/usr/local/bin/imac-brightness` is no
  longer needed for that, but remains useful for an exact level, `min`/`max`,
  and use without a desktop session. It drives `acpi_video0` and prints a
  percentage.
- Both helper scripts select the panel by preferring an `acpi_video*` node
  whose `max_brightness` is not 100, and demote `amdgpu_bl*` to last resort.
  That preference order is the actual fix; the scripts are incidental.

## Related

- [`docs/tiled-5k.md`](tiled-5k.md) — the panel's tiled mode, and the amdgpu
  firmware load that makes Plymouth impossible
- [`docs/recovery.md`](recovery.md)
- [`docs/troubleshooting.md`](troubleshooting.md)