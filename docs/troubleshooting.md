# Troubleshooting

> **Status: VERIFIED for the failure modes listed.**
> Every entry here was actually hit on this machine and diagnosed. Entries
> marked BROKEN are known faults with no fix yet, not untested guesses.

Failure modes that cost time on this machine. Several were misdiagnosed before
being understood.

---

## <a id="audio"></a>Audio: distorted at every volume

**Symptom:** distorted and compressed at *every* volume level. Loud at 15%. Below
15% there is no sound at all.

**Why this is informative:** distortion constant across levels is **not**
clipping. Clipping scales with volume. Constant distortion plus a hard
low-volume cutoff points at a **limiter/compressor or a codec effect**, not
headroom.

**Do this first** — it splits the problem cleanly:

```bash
# raw path, bypasses PipeWire entirely
speaker-test -D hw:0,0 -c2 -t sine -f 440 -l1
```

- Clean raw ⇒ the fault is in the 83-node PipeWire chain
- Distorted raw ⇒ codec/amp/driver, and the chain is innocent

**Then check ALSA effects**, particularly on the Cirrus Logic CS8409:

```bash
amixer -c0 contents | grep -iE "limiter|comp|boost|loudness|smart|effect"
```

**And look for a compressor or volume-ramp node in the chain:**

```bash
grep -oiE "name = [a-z0-9_]+" \
  ~/.config/pipewire/pipewire.conf.d/90-imac-speakers.conf | sort -u
```

> [!CAUTION]
> **Do not run `generate-filter-chain.py`.** It still emits the old attenuated
> values and will silently revert the unity-gain fix.

### The earlier misdiagnosis, for the record

The original symptom was near-silence. I read that as broken routing and
"fixed" it by removing all attenuation and raising ALSA `Master` from 3% to
100%. **That was the wrong call.** The quietness was simply extreme attenuation
(~55 dB), not a fault. The correct fix was unity gain *plus* a sensible output
level with headroom protection — and the level was never established, which is
probably the actual remaining problem.

---

## Download produces a 0-byte file

`archive.apache.org` resolves **only** to IPv6 (`2a01:4f9:1a:a084::2`) and this
machine has no IPv6 route. `wget` follows the AAAA record, fails, and leaves an
empty file rather than erroring clearly.

```bash
wget -4 ...     # force IPv4
curl -4 ...
```

Looks like a flaky network; is not.

---

## Bash: `grep -q` returns 141 under `set -o pipefail`

`grep -q` exits at the first match and closes the pipe while the producer is
still writing. Under `pipefail` this surfaces as a **false failure** even though
the match succeeded.

```bash
# WRONG - can report failure on a match
ldconfig -p | grep -q "$soname"

# RIGHT - capture, then test
CACHE=$(ldconfig -p)
HIT=$(printf '%s\n' "$CACHE" | grep -E "	$soname " || true)
[ -n "$HIT" ] && echo present
```

Caused several false "library missing" reports here.

---

## `ldconfig: command not found` under sudo

Under `sudo -S` the PATH may not include `/usr/sbin`. `command -v ldconfig`
fails even though the binary exists at `/usr/sbin/ldconfig`.

Probe several known paths, or use the absolute path.

---

## Kernel version comparisons always mismatch

| Source | Format |
|---|---|
| `uname -r` | `7.2.2-1-default` |
| `rpm -qf` / `rpm -qa` | `7.2.2-1.1` |

The flavour sits in the middle of the uname string, so stripping the suffix
gives `7.2.2-1` — still not `7.2.2-1.1`. String comparison will always fail.
Compare the **version** component only, or `sort -V` the rpm output.

---

## `rpm -q mesa` says "not installed" on a working OpenGL system

openSUSE splits Mesa across `Mesa-dri`, `Mesa-libGL1`, `Mesa-libEGL1`, `libgbm1`,
`libglvnd`. Ask who owns the driver instead:

```bash
rpm -qf /usr/lib64/dri/radeonsi_dri.so    # -> Mesa-dri-<version>
```

Assuming "Mesa is missing" from `rpm -q mesa` led to wasted effort installing
packages that were already present.

---

## BLS entries: `kernel-default*` glob matches `-devel`

```bash
rpm -qa 'kernel-default*'     # matches kernel-default-devel too
```

`kernel-default-devel` often sits at a different version, uses no ESP space, and
produces a phantom "a second kernel is installed" warning. Match the package
name exactly:

```bash
rpm -qa kernel-default --qf '%{VERSION}\n'
```

---

## `find /` picks up Btrfs snapshots

On a Btrfs system, `find / -name "*.so"` traverses `/.snapshots/*` and can return
a path inside an old snapshot. Writing such a path into a config produces
something that appears to work but breaks on the next snapshot rotation.

Resolve symlinks properly instead:

```bash
ls -1 /usr/lib64/libpocl.so.2     # not: find / -name 'libpocl.so*'
readlink -f /usr/lib64/libpocl.so.2
```

---

## Reading a value that is not what you wrote it as

`awk -F= '/^Exec/{print $2}'` splits on **every** `=`. For a desktop entry like:

```
Exec=env QT_SCALE_FACTOR=2 /opt/resolve/bin/resolve
```

`$2` is just `env QT_SCALE_FACTOR`. Strip only the prefix:

```bash
sed -n 's/^Exec=//p' file.desktop
```

Same class of bug applies to any `key=value=value` line — kernel cmdlines,
`.desktop` files, `Xsetup` scripts.

---

## Suspecting a missing package that exists

`zypper --non-interactive info X` returning nothing can mean the *search index*
is stale rather than the package being absent. `zypper refresh` first. This sent
the APR investigation down the wrong path initially — `zypper info apr` said
"not found" while `zypper search apr` listed `apr-devel`.

Note that **installing one package in a multi-package `zypper install` can fail
the whole transaction**: requesting a non-existent `libsqlite3-devel` alongside
`libexpat-devel` aborted the transaction and left the header uninstalled, with
no obvious link between the request and the failure. Install dependencies
individually when unsure.

## A kernel update left me with one tile and no speakers

Expected, not a broken update. See **[kernel updates](kernel-updates.md)**. A new
kernel arrives with no CS8409 DKMS module and no patched `amdgpu`, because
`dkms.service` ships disabled and the patched driver only exists inside the
initramfs on the ESP. Fix with `sudo systemctl enable dkms.service`,
`sudo dkms autoinstall`, and a rebuilt patched `amdgpu`.

## Sleeping does nothing / Sleep missing from the power menu

The sleep targets are masked or `sleep.conf` is misconfigured. Check with
`systemctl is-enabled sleep.target suspend.target hibernate.target` — all three
should be `static`, not `masked`. Note that `HandleLidSwitch*` belongs in
`logind.conf`, **not** `sleep.conf`; putting it in `sleep.conf` is silently
ignored. Full detail in **[fixes](fixes.md#sleep--restored-to-stock-and-a-config-file-that-was-doing-nothing)**.

## Bluetooth headphones drop out, or devices never appear

The iMac19,1 Bluetooth is `hci_uart` + `btbcm`, not `btusb`, and this chip does
not support bonding. Set `ClassicBondedOnly=false` under `[Policy]` in
`/etc/bluetooth/main.conf` and set `USBAutosuspend=0` (it defaults to 2 seconds
here, which suspends the internal UART bridge repeatedly). This improves
stability but does not add bonding; a USB dongle is the reliable fix. See
**[fixes](fixes.md#bluetooth--fixed-enough-to-be-usable-but-bonding-does-not-work)**.

## Printer works on the network but not in the print dialog

Almost always a stale queue pointing at an old DHCP address. Check
`lpstat -v` and compare with the printer's real address, and prefer a driverless
queue over a vendor one — an HP LaserJet MFP M141w advertises
`mopria-certified=2.1` and needs no driver. See
**[fixes](fixes.md#printing--airprint-driverless)**.
