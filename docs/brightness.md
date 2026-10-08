# Brightness: what actually controls the panel, and why it does not work yet

> **Status: UNRESOLVED.** The correct control path is identified and an ACPI
> table override that extends it has been built and verified, but it is not
> loaded. Every route that does not require a kernel change is exhausted.
> This page exists so the next attempt starts from the diagnosis rather than
> from `amdgpu_bl*`.

Nothing here is a configuration mistake. Do not spend time on mixer levels,
`acpi_backlight` variants that have already been tried, or the amdgpu sysfs
node — each is documented below with the evidence that closed it.

## Contents

| Section | |
|---|---|
| [The panel has one real control](#the-panel-has-one-real-control) | `ABCM`, and why sysfs cannot reach it |
| [The amdgpu backlight node is a no-op](#the-amdgpu-backlight-node-is-a-no-op) | writes are accepted and ignored |
| [The ACPI table override that would fix it](#the-acpi-table-override-that-would-fix-it) | built and verified, not loaded |
| [Why the override is not loaded](#why-the-override-is-not-loaded) | DSDT vs SSDT |
| [Dead ends](#dead-ends) | `acpi_call`, libacpi, `acpiexec` |
| [What has not been tested](#what-has-not-been-tested) | the honest gaps |

## The panel has one real control

The internal panel is driven by the firmware's own ACPI brightness method. On
this machine (iMac19,1, firmware revision `0x00150001`) the chain is:

```
\_SB.PCI0.PEG0.GFX0          Device (GFX0)
    Method (ABCM, 1)         set brightness, takes a level 0..90
    Method (ABCL, 0)         Return (Package) — the level table
    Method (BSET, 1)         scale 655 * level onto the controller 0..0xFFFF
\_SB.PCI0.PEG0.GFX0.LCD      Device (LCD)
    Method (_BCL, 0)         Return (ABCL ())
    Method (_BCM, 1)         ABCM (Arg0)
    Method (_BQC, 0)         Return (BRTL)
```

`ABCL` returns 92 entries: a two-byte header (`0x50`, `0x32`), then levels
`1..90` (`One`, `0x02` … `0x5A`). Because `BSET` scales by `655 * level`, the
firmware's own maximum of 90 reaches `58950` of `65535` — about **90% of what
macOS can drive**. Apple caps the table below the panel's real range.

There are two `GFX0` devices (one per GPU); both copies of `ABCL` must be
edited together.

## The amdgpu backlight node is a no-op

A DRM backlight is registered and accepts writes:

```
/sys/class/backlight/amdgpu_bl2   current=65535 max=65535 type=raw
$ echo 30000 > /sys/class/backlight/amdgpu_bl2/brightness
$ cat /sys/class/backlight/amdgpu_bl2/brightness
30000
```

The value sticks and **the panel does not change**. This node is amdgpu's DP
auxiliary backlight, which is not what this panel is wired to. The KDE slider
and the `imac-brightness` helper both drive this node, which is why neither
appears to do anything.

Also absent: any `acpi_video*` backlight, and any UPower-visible backlight
device.

## The ACPI table override that would fix it

Extending `ABCL` from levels 1..90 to 1..100 plus 101 removes the firmware cap
and makes `_BCL` return a table the kernel's ACPI video driver will accept. An
override table has been built and verified on the reference machine.

It rewrites both `ABCL` methods and bumps the OEM revision so the kernel
prefers it:

```
before:  ABCL count=0x5C (92)   entries: 92   first: [0x50, 0x32, One, 0x02 …]  last: … 0x5A
after:   ABCL count=0x67 (103)  entries: 103  first: [0x64, 0x32, One, 0x02 …]  last: … 0x65
         OEM Revision 0x00150001 -> 0x00150002
```

`0x65` is 101, which is the controller's true maximum: `BSET` is `655 * level`
up to level 100 and clamps anything above, so 101 is the value macOS reaches.
Level 100 is kept in the list as well — the table's AC default is 100, and
`acpi_video` treats a `_BCL` whose defaults are missing from the level list as
buggy and shifts every entry.

Built size is 30,231 bytes. The rewrite works against the **DSDT** on this
machine, unlike the iMac18,3 project whose table lives in an SSDT — see below.

### What it does not fix by itself

Even if loaded, the override only extends the *range*. Whether an
`acpi_video0` backlight device appears at all depends on the ACPI video driver
finding brightness methods on the video device. Here `_BCL` is on the **`LCD`
child** of `GFX0`, not on `GFX0` itself. That has not been proven to be the
reason no backlight is registered, and it is the first thing to check if the
override ever loads.

## Why the override is not loaded

The file is placed in the initramfs at the root, named for the table
signature, which is the documented mechanism:

```
$ lsinitrd …/initrd-stackC | grep -E '(^|[[:space:]])DSDT$'
-rw-r--r-- 1 root root 30231 DSDT
```

And the kernel is built for it:

```
$ zcat /proc/config.gz | grep CONFIG_ACPI_TABLE_UPGRADE
CONFIG_ACPI_TABLE_UPGRADE=y
```

Yet the live table is unchanged:

```
$ python3 -c "print(hex(int.from_bytes(open('/sys/firmware/acpi/tables/DSDT','rb').read()[0x18:0x1c],'little')))"
0x00150001        # override was 0x00150002
```

The expected cause is **DSDT vs SSDT**. `acpi_table_upgrade()` reads SSDTs out
of the initramfs successfully; the DSDT is consumed directly from firmware
before the initramfs is available. This machine keeps its brightness table in
the DSDT, and the iMac18,3 project — whose method this follows — overrides an
SSDT, which is a different situation.

**Caveat, stated plainly:** the claim that the kernel "did not even try" rests
on a `dmesg` read taken as a normal user, which returns nothing at all. The
table being unchanged was verified; the reason was not. Read the next section
before assuming this is settled.

## Dead ends

| Route | Why it does not work |
|---|---|
| `amdgpu_bl2` / `amdgpu_bl1` sysfs | Writes accepted, panel unchanged (measured) |
| ACPI table override | Built and correct; DSDT replacement not applied by the kernel |
| `acpi_call` kernel module | **Removed from upstream Linux.** No `CONFIG_ACPI_CALL`, no Kconfig entry, no `acpi_call.c` in the 7.2.7 tree, not packaged |
| libacpi (userspace AML) | `zypper search libacpi` → "No matching items found" on this distro |
| `acpiexec` (ships with `acpica`) | Runs AML in userspace with its own namespace; cannot drive real hardware |
| `rd.driver.blacklist=efi-framebuffer` | Not honoured for DRM drivers by dracut |
| `modprobe.blacklist=efi-framebuffer` | **Wrong parameter name.** The kernel takes `module_blacklist=` |

Note that `efi-framebuffer` is *not* in `modules.builtin`, yet it loads anyway,
so the blacklist name is still unverified.

An SSDT route remains plausible and untried: a `Scope()` block that **adds** a
new method delegating to `LCD._BCL`/`_BCM` is legal AML, whereas overriding an
existing method fails with `AE_ALREADY_EXISTS`. That would still need
`acpi_configfs` (present as `acpi_configfs.ko.zst`) plus some way to *invoke*
the method, which is the part with no available implementation.

## What has not been tested

This list is short because several plausible-sounding tests were skipped or
performed invalidly. Do them before spending more time:

1. **`acpi_backlight=video` and `=firmware`.** Only `native` has been tried.
   `video` uses the ACPI video driver's backlight registration — a different
   code path from `native`. One-line cmdline change plus a reboot, and it is
   the cheapest possible test. **Do this first.**
2. **The real DSDT structure.** `_BCL` appeared to be nested under `LCD`
   (lines 6069/6551 with `LCD` at 6062/6544), but the tree was never printed
   properly. If `GFX0` has its own `_BCL`, the "driver can't find brightness"
   theory collapses and something else is responsible.
3. **Kernel messages during override load.** Never observed, for the reason
   above. Run as root.
4. **`CONFIG_ACPI_VIDEO=m`** — the ACPI video driver is a module. Confirm it is
   present in the initramfs, since backlight registration happens at its load.
5. **SSDT naming variants** for the override file. Only the literal name `DSDT`
   has been tried.

## Related

- [`docs/troubleshooting.md`](troubleshooting.md)
- [`docs/recovery.md`](recovery.md)