# debian-system-updater

[![CI](https://github.com/Tubifix77/debian-system-updater/actions/workflows/ci.yml/badge.svg)](https://github.com/Tubifix77/debian-system-updater/actions/workflows/ci.yml)
[![Debian 12 | 13](https://img.shields.io/badge/Debian-12%20%7C%2013-A81D33?logo=debian&logoColor=white)](#supported-releases)
[![ShellCheck: clean](https://img.shields.io/badge/ShellCheck-clean-brightgreen)](#built-to-be-trusted)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**One command updates everything on Debian 12 and 13, then tells you what `apt upgrade` doesn't: which packages have lost security support, which updates were held back, whether a package source failed, and how many days of security support your release has left.**

🇩🇰 [Dansk version](README.da.md)

## Why

Keeping a Debian desktop current takes several commands, and the warnings that matter get lost in their output. This script runs the whole chain (repairs, apt, Flatpak, cleanup, firmware) and ends with a one-screen report that answers the questions you actually have:

- **Did everything update?** Counts for apt packages, Flatpak apps and runtimes, and firmware.
- **Is anything stuck?** Held-back and held packages are named. They get no security fixes either.
- **Did every package source answer?** An unreachable source is shown in red and counted as an error. Plain apt only prints a warning and exits as if all went well.
- **Which installed packages have lost security support?** Straight from Debian's own `debian-security-support` data.
- **How long will my release get security updates?** A countdown through full support and LTS, with yellow and red warnings as the end approaches.
- **Are the nightly automatic updates running?** It shows what `unattended-upgrades` installed this month.
- **Do the firmware updates matter?** It reads the Secure Boot state and explains updates the firmware rejects, instead of just failing.

## Example

A real report from a Debian 12 laptop:

```
══════════════════════════════════════════════════
  REPORT  │  2026-09-27 15:43:06  │  duration 0m 12s
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
     Dates from: distro-info-data (/usr/share/distro-info/debian.csv)

  📋 Full log: /var/log/debian-updater.log
```

On Debian 13, which still has full support, the clock shows both phases:

```
  🗓  Debian 13: full security support until 2028-08-09 (681 days), then LTS until 2030-06-30 — 1371 days left
```

## How it compares

| | apt on its own | [topgrade](https://github.com/topgrade-rs/topgrade) | debian-system-updater |
|---|---|---|---|
| apt packages, Flatpak and firmware in one run | apt only | ✓ | ✓ |
| Other tools too (Cargo, pip, Ruby gems, VS Code extensions …) | — | ✓ | — |
| Held-back packages | in the middle of apt's output | not reported separately | named in the final report |
| Installed packages that lost security support | — | — | ✓ |
| Countdown to the end of your release's security support | — | — | ✓ |
| Firmware report that knows the Secure Boot state | — | — | ✓ |

topgrade is the popular tool for updating many package managers at once, and it covers far more tools than this script. Its source code has no checks for Debian security support, support dates, held packages or Secure Boot (checked September 2026). Choose topgrade for one updater for everything; choose this script if you run Debian and want to know how healthy your system is and how long it will stay supported.

## Built to be trusted

- **No surprises.** It never reboots on its own, asks before installing firmware (by default), never sends reports anywhere (`fwupdmgr` runs with `--no-unreported-check`), keeps your config files in unattended runs and never touches your package sources.
- **Tested on every change.** Every push runs ShellCheck, unit tests for all parsing and decision logic, and integration tests that run the real script in clean Debian 12 and Debian 13 containers. Every release so far has also been run on a real Debian 12 laptop.
- **Clean, readable code.** One documented function per step, following the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html). ShellCheck finds nothing at any severity, and CI keeps it that way.
- **Debian's own data.** Support dates come from `distro-info-data`, security status from `debian-security-support`, and package work goes through `apt-get`, the interface apt's manual recommends for scripts.
- **English and Danish,** picked from your system language.
- **MIT licensed.**

## Quick start

```bash
git clone https://github.com/Tubifix77/debian-system-updater.git
cd debian-system-updater
sudo bash update_system.sh
```

Or download `update_system.sh` from the [latest release](https://github.com/Tubifix77/debian-system-updater/releases/latest). For the firmware step, install fwupd once:

```bash
sudo apt-get install fwupd
```

## Supported releases

| Release | Full security support until | LTS until | Tested with |
|---|---|---|---|
| Debian 12 "bookworm" | 2026-07-11 | 2028-06-30 | apt 2.6 |
| Debian 13 "trixie" | 2028-08-09 | 2030-06-30 | apt 3.0 |

The same script runs on both. It reads `/etc/os-release` and takes the support dates from Debian's own `distro-info-data` package (`/usr/share/distro-info/debian.csv`) when it is installed, so new Debian releases work without changing the script. Without that package it uses a small built-in table (`DEBIAN_RELEASES`). On a release neither knows, everything else still runs; only the support clock is missing.

The dates in the table above come from `distro-info-data`, [debian.org/releases](https://www.debian.org/releases/) and [wiki.debian.org/LTS](https://wiki.debian.org/LTS). For bookworm the LTS wiki gives LTS from 2026-06-11, while the release page and `distro-info-data` give full support until 2026-07-11. All agree on the end date 2028-06-30.

## What the script does

0. **Pre-check** — checks disk space and stops below 1 GB free
1. **Repair** — `dpkg --configure -a` and `apt-get --fix-broken install`
2. **apt-get update** — fetches the package lists; a source that cannot be fetched is shown in red
3. **apt-get full-upgrade** — full system upgrade; packages that are kept back are named
4. **flatpak update** — updates Flatpak apps and runtimes, if Flatpak is installed
5. **apt-get autoremove --purge** — removes unused packages and their configuration
6. **apt-get clean** — clears downloaded .deb files
7. **Firmware** — refreshes LVFS metadata and checks for firmware updates via `fwupdmgr`, if fwupd is installed. By default it asks before installing anything (see `FIRMWARE_UPDATES`). Skipped in containers (WSL, Docker, LXC), where the firmware belongs to the host.
8. **Security status** — installs `debian-security-support` once (unless `INSTALL_SECURITY_SUPPORT=no`) and shows which installed packages have lost or have limited security support
9. **Report** — everything above on one screen, the support clock, a restart notice and the path to the log

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
- never installs firmware unless `FIRMWARE_UPDATES=install` is set
- skips the final ENTER and exits with code 1 if there were errors

Without this, a cron run can hang forever on a question nobody sees.

## Settings

Settings go in `/etc/default/debian-system-updater`. The file is optional and is not overwritten when you download a new version of the script. Every line is optional:

```bash
# /etc/default/debian-system-updater
UI_LANG=en                    # da or en (default: the system language)
LTS_WARN_DAYS=60              # yellow warning this many days before the end (default 30)
LTS_ALARM_DAYS=7              # red alarm this many days before the end (default 7)
LTS_END_NOTE="The old NVIDIA card only works with Debian 12. Plan: new graphics card or new PC."
INSTALL_SECURITY_SUPPORT=no   # do not install debian-security-support (default yes)
FIRMWARE_UPDATES=check        # ask, install, check or off (default ask)
```

`FIRMWARE_UPDATES` decides what happens when the firmware accepts an update:

- `ask` — an interactive run asks before installing; an `--auto` run only reports, because nobody can answer
- `install` — installs without asking, also in `--auto` runs
- `check` — never installs, only reports what is available and how to install it
- `off` — skips the firmware step

## Reading the report

- **Packages kept back** — packages apt wanted to upgrade but was not allowed to (usually because they are on hold). They get no security fixes either, so this should normally be 0.
- **Packages on hold** — everything `apt-mark showhold` lists.
- **Firmware** — one line per device with the current and the new version. "cannot be updated" means fwupd found something on LVFS, but the machine's firmware rejected it; fwupd's reason is shown (on older machines usually too little space in the UEFI variable store). If only the Secure Boot lists (db/dbx) are rejected and Secure Boot is off, this does not matter and shows as "none relevant". If Secure Boot is on, you get a warning.
- **Security support** — from `check-support-status`. "WITHOUT support" is serious: remove the package if you don't use it. "limited" is for information (typically "only for trusted content").
- **Automatic updates** — whether `unattended-upgrades` runs at night. If it does, it is normal that a manual run finds few or no Debian updates: they are already installed.

## Support clock

At the bottom of the report you can see how long your Debian release gets security updates. While the release has full support, both dates are shown; during the LTS period only the end date. A month before the move to LTS a yellow note appears, because LTS does not cover every package (step 8 shows which). The line below the clock says where the dates came from: `distro-info-data`, the built-in table or your settings file.

The warnings count down to the end date: yellow at 30 days or fewer (`LTS_WARN_DAYS`), red at 7 days or fewer (`LTS_ALARM_DAYS`) and after the date. Both thresholds and the reminder text `LTS_END_NOTE` can be set in your settings file.

## Log

The script writes all output to `/var/log/debian-updater.log` (rotated to `.1` at 5 MB):

```bash
tail -100 /var/log/debian-updater.log
```

apt's own output in the log is always English, because the report reads apt's summary line.

## Requirements

- Debian 12 (bookworm) or Debian 13 (trixie)
- Root rights (`sudo`)
- Flatpak and fwupd are optional and detected automatically
- `debian-security-support` is installed automatically the first time if it is missing
- No dependencies beyond standard Debian tools; python3 is used to read fwupd's JSON output when it is available

If you use an application firewall such as OpenSnitch, `/usr/bin/fwupdmgr` must be allowed to reach the internet, otherwise the firmware metadata cannot be fetched. The script shows this as a warning in the report.

## Development and tests

The script is organised as one function per step with a `main` function, following the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html). The one deliberate deviation is that some Danish and English message strings are longer than 80 characters, because splitting sentences would make them harder to read.

Every push runs the [CI workflow](.github/workflows/ci.yml):

- **ShellCheck** on all scripts, at every severity.
- **Unit tests** in `tests/unit_tests.sh` for the parsing and decision logic: language detection, options, release and date lookup, the countdown, apt and Flatpak counting, the firmware JSON and Secure Boot logic, security-support parsing and the nightly-updates summary. They load the script's functions without running it, need no root and are safe to run anywhere: `bash tests/unit_tests.sh`.
- **Integration tests** in `tests/run_tests.sh`, which run the real script in clean Debian 12 and Debian 13 containers in several scenarios, including both languages, all date sources, the warning branches, an unreachable package source and the option handling.

The integration tests change system settings, so they refuse to run anywhere but a throwaway container or VM with `UPDATER_TESTS=1`:

```bash
docker run --rm -v "$PWD:/src" -w /src -e UPDATER_TESTS=1 debian:trixie bash tests/run_tests.sh
```

## License

[MIT](LICENSE). You may use, change and share the script freely, also commercially, as long as the copyright notice and the license text stay with it. It comes without any warranty.
