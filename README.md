# debian-system-updater

🇩🇰 [Dansk version](README.da.md)

One Bash script that keeps a Debian 12 or Debian 13 system fully up to date: a "Windows Update" for Debian.

## Why

Debian has no single "update everything" button. Keeping a desktop current means apt, Flatpak and firmware updates, cleaning up, and knowing when your release stops getting security fixes. This script runs the whole chain with one command and ends with a clear report.

It also tells you the things Debian keeps quiet about: which packages are on hold and therefore get no security fixes, which installed packages the security team no longer patches, whether the nightly automatic updates are running, and how many days of security support your release has left.

## Supported releases

| Release | Full security support until | LTS until | Tested with |
|---|---|---|---|
| Debian 12 "bookworm" | 2026-07-11 | 2028-06-30 | apt 2.6 |
| Debian 13 "trixie" | 2028-08-09 | 2030-06-30 | apt 3.0 |

The same script runs on both. It reads `/etc/os-release` and looks up the dates in a small table (`DEBIAN_RELEASES`) at the top of the script, so a new release is one line to add. On a release that is not in the table everything else still runs; only the support clock is missing.

The dates come from [debian.org/releases](https://www.debian.org/releases/) and [wiki.debian.org/LTS](https://wiki.debian.org/LTS). For bookworm the release page says full support until 2026-07-11, while the LTS wiki gives LTS from 2026-06-11. The end date 2028-06-30 is the same in both.

## Language

Messages are in Danish when the system language is Danish (`LANG=da_*`) and in English otherwise. You can force a language with `--lang=da` or `--lang=en`, or with `UI_LANG` in the settings file. apt's own output in the log is always English, because the report reads apt's summary line.

## What the script does

0. **Pre-check** — checks disk space and stops below 1 GB free
1. **Repair** — `dpkg --configure -a` and `apt-get --fix-broken install`
2. **apt-get update** — fetches the package lists; a source that cannot be fetched is shown in red (plain apt only warns)
3. **apt-get full-upgrade** — full system upgrade; packages that are kept back are listed by name
4. **flatpak update** — updates Flatpak apps and runtimes, if Flatpak is installed
5. **apt-get autoremove --purge** — removes unused packages and their configuration
6. **apt-get clean** — clears downloaded .deb files
7. **Firmware** — fetches LVFS metadata and applies firmware updates via `fwupdmgr`, if fwupd is installed. It never reboots on its own and never sends reports to LVFS. Skipped in containers (WSL, Docker, LXC).
8. **Security status** — installs `debian-security-support` once and shows which installed packages have lost or have limited security support
9. **Report** — a summary of all of the above, the support clock, a restart notice and the path to the log

## Usage

```bash
sudo bash update_system.sh               # interactive
sudo bash update_system.sh --auto        # non-interactive (cron / automation)
sudo bash update_system.sh --lang=en     # force English (or --lang=da for Danish)
bash update_system.sh --help
```

Or make it executable once:

```bash
chmod +x update_system.sh
sudo ./update_system.sh
```

### What `--auto` does

Without `--auto` the script behaves like a normal terminal run. If a package asks a question (typically "your config file was changed, keep yours or take the package's new one?"), it waits for your answer, and at the end it waits for ENTER.

With `--auto` nobody is at the keyboard, so the script:

- sets `DEBIAN_FRONTEND=noninteractive`, so debconf never asks but uses the default answer
- gives dpkg `--force-confdef --force-confold`, so a config-file conflict is resolved by **keeping your current file** (the package's new version is saved next to it as `*.dpkg-dist`)
- skips the final ENTER and exits with code 1 if there were errors

Without this, a cron run can hang forever on a question nobody sees.

## Personal settings

To change the warning thresholds, the language or your own reminder for the support clock, put them in `/etc/default/debian-system-updater`. The file is optional and is not overwritten when you download a new version of the script. Example:

```bash
# /etc/default/debian-system-updater
UI_LANG=en
LTS_WARN_DAYS=60
LTS_END_NOTE="The old NVIDIA card only works with Debian 12. Plan: new graphics card or new PC."
```

## Example report

From a run on a Debian 12 laptop:

```
══════════════════════════════════════════════════
  REPORT  │  2026-09-27 15:18:32  │  duration 0m 11s
══════════════════════════════════════════════════
  Package sources:                 OK
  Packages upgraded:               0
  Packages newly installed:        0
  Packages removed:                0
  Packages kept back:              0
  Packages on hold:                1 — heroic
  Flatpak apps updated:            0  (new: 0, removed: 0)
  Flatpak runtimes updated:        0  (new: 0, removed: 0)
  Firmware:                        none relevant (Secure Boot lists cannot be updated, and Secure Boot is off)
  Security support:                2 WITHOUT support (intel-mediasdk mbedtls), 7 limited
  Automatic updates:               active — 11 nightly runs / 21 packages in this month's log, last 2026-09-26
  Free disk space:                 24G
  Errors:                          None
══════════════════════════════════════════════════

  🗓  Debian 12 LTS: security updates until 2028-06-30 — 641 days left

  📋 Full log: /var/log/debian-updater.log
```

On Debian 13, which still has full support, the clock shows both phases:

```
  🗓  Debian 13: full security support until 2028-08-09 (681 days), then LTS until 2030-06-30 — 1371 days left
```

What the lines mean:

- **Packages kept back** — packages apt wanted to upgrade but was not allowed to (usually because they are on hold). They get no security fixes either, so this should normally be 0.
- **Packages on hold** — everything `apt-mark showhold` lists.
- **Firmware** — one line per device with the current and the new version. "cannot be updated" means fwupd found something on LVFS, but the machine's firmware rejected it; fwupd's reason is shown (on older machines usually too little space in the UEFI variable store). The script reads the Secure Boot state from the firmware itself: if only the Secure Boot lists (db/dbx) are rejected and Secure Boot is off, this does not matter and shows as "none relevant". If Secure Boot is on, you get a warning.
- **Security support** — from `check-support-status`. "WITHOUT support" is serious: remove the package if you don't use it. "limited" is for information (typically "only for trusted content").
- **Automatic updates** — whether `unattended-upgrades` runs at night. If it does, it is normal that a manual run finds few or no Debian updates: they are already installed.

## Support clock

At the bottom of the report you can see how long your Debian release gets security updates. While the release has full support, both dates are shown; during the LTS period only the end date. A month before the move to LTS a yellow note appears, because LTS does not cover every package (step 8 shows which).

The warnings count down to the end date: yellow at 30 days or fewer (`LTS_WARN_DAYS`), red at 7 days or fewer (`LTS_ALARM_DAYS`) and after the date. Both thresholds and the reminder text `LTS_END_NOTE` can be set in your settings file.

## Log

The script writes all output to `/var/log/debian-updater.log` (rotated to `.1` at 5 MB). To read it:

```bash
tail -100 /var/log/debian-updater.log
```

## Requirements

- Debian 12 (bookworm) or Debian 13 (trixie)
- Root rights (`sudo`)
- Flatpak and fwupd are optional and detected automatically (`sudo apt-get install fwupd` for the firmware step)
- `debian-security-support` is installed automatically the first time if it is missing
- No dependencies beyond standard Debian tools

In a container (WSL, Docker, LXC) the firmware step is skipped, because the firmware belongs to the host and the fwupd service does not start there.

If you use an application firewall such as OpenSnitch, `/usr/bin/fwupdmgr` must be allowed to reach the internet, otherwise the firmware metadata cannot be fetched. The script shows this as a warning in the report.

## License

[MIT](LICENSE). You may use, change and share the script freely, also commercially, as long as the copyright notice and the license text stay with it. It comes without any warranty.
