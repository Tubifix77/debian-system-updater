# Changelog

## v1.7.0 — 2026-09-27

### Added
- **Settings screen in the terminal**, in the same ASCII style as the rest. Press TAB at the end of a run, or start it with `--settings`. It shows the six settings (language, firmware updates, security-support check, yellow warning, red alarm, personal reminder), each with a line saying what the current choice does. Keys 1–6 change a setting, G/S saves, N/R resets to the defaults and A/Q cancels (asking first if anything changed); the Danish and the English keys both work. On a terminal it opens like an editor, so the report comes back when it closes, and its screens never go into the log.
- The settings file is written safely: comments and lines edited by hand are kept, settings at their default are left out, the file is replaced in one step, and the personal reminder is quoted so it can never run as code.
- Unit tests for the screen, driven by typed keys, and for the settings file. Integration tests that type into a real terminal with `script`: `--settings`, and a full interactive run where TAB, a change and saving work end to end without the screen reaching the log.

### Changed
- The end of an interactive run now says "Press ENTER to exit or TAB for settings".
- The warning thresholds from the settings file are checked (whole days); invalid values fall back to the defaults.
- README (English and Danish): the settings screen, and an "Out of scope on purpose" section explaining why language package managers (pip, Cargo, Ruby gems) and editor extensions are left to tools like topgrade.

---

## v1.6.1 — 2026-09-27

### Fixed
- The lines above and below the header and the report title were 50 characters and stopped in the middle of the time. They are now 57, so the longest title (ending at column 54) fits with a 3-character margin. The width is one constant (`LINE_WIDTH`), and a unit test fails if a title ever outgrows it.

### Changed
- The README (English and Danish) now leads with what the script adds: a one-line summary, the questions the report answers, a real example, a comparison with apt on its own and with topgrade, "Built to be trusted", and a quick start. Badges for CI, supported releases, ShellCheck and the license.
- CI enforces ShellCheck at every severity, not only warnings.
- New GitHub description and topics.

---

## v1.6.0 — 2026-09-27

### Changed
- **Restructured along the Google Shell Style Guide:** one function per step and a `main` function, a header comment on every non-trivial function, `local` variables, `readonly` constants, `[[ … ]]` and `(( … ))`, 2-space indentation, and error messages on STDERR. The behaviour and the report are unchanged.
- The script can be loaded (sourced) without running, which the unit tests use. Executed, or piped into bash, it runs as before.
- `--lang` without a value now stops with exit code 2 instead of being ignored.
- ShellCheck now reports no findings at any severity; the last two notes (`ls` on fixed system paths) are gone.

### Added
- **Unit tests** in `tests/unit_tests.sh` (56 checks) for language detection, options, release and date lookup, the countdown, apt and Flatpak counting, the firmware JSON and Secure Boot logic, security-support parsing and the nightly-updates summary. They need no root. CI runs them in Debian 12 and 13 containers.

### Fixed before release
- `/etc/os-release` is now read in a fresh bash process with an empty environment. During the restructure, a read-only `VERSION` constant clashed with the `VERSION` line in os-release, and the release showed as "unknown system". The integration tests and a test run on the Debian 12 laptop caught it before release; a unit test with a complete os-release file now guards against it.

### Tested
- Debian 12 laptop: the report is identical to v1.5, apart from the version number.
- Local Docker and GitHub Actions: ShellCheck, the unit tests and the integration tests on Debian 12 and Debian 13.

---

## v1.5.0 — 2026-09-27

### Added
- **Automated tests and CI.** `tests/run_tests.sh` runs the real script in several scenarios: English and Danish, the fallback table and `distro-info-data` dates, settings-file overrides, the warning and "support ended" branches, an unreachable package source, option handling and the root check. GitHub Actions runs ShellCheck and the tests in clean Debian 12 and 13 containers on every push. The tests refuse to run outside a throwaway container or VM (`UPDATER_TESTS=1`).
- **Support dates from Debian's own `distro-info-data`** (`/usr/share/distro-info/debian.csv`, columns found by name) when it is installed; the built-in table is now only a fallback. The report says where the dates came from ("Dates from: ...").
- **Setting `FIRMWARE_UPDATES`**: `ask` (default), `install`, `check` or `off`. With `ask`, interactive runs ask before installing firmware and `--auto` runs only report.
- **Setting `INSTALL_SECURITY_SUPPORT`**: `yes` (default) or `no`.
- Git tags for every release from v1.0.0 to v1.5.0, and a GitHub release for v1.5.0.

### Changed
- **The firmware step reads `fwupdmgr get-updates --json`** instead of parsing the drawn device tree; python3 turns the JSON into one line per device. Without python3 the script shows fwupd's own text and never installs blind. The Secure Boot lists are recognised by fwupd's plugin names (`uefi_db`, `uefi_dbx`, `uefi_kek`, `uefi_pk`) instead of device names.
- Firmware updates are no longer installed without asking by default (see `FIRMWARE_UPDATES`).
- The settings file is read before the release lookup, so it can also set `DISTRO_INFO_CSV`.

### Tested
- Debian 12 laptop: the firmware JSON path with two rejected Secure Boot updates, dates from `distro-info-data`, Danish and English output, no errors.
- GitHub Actions: ShellCheck and the integration tests in Debian 12 and Debian 13 containers.

---

## v1.4.0 — 2026-09-27

### Added
- **English and Danish in one script.** Messages follow the system language: Danish when `LC_ALL`, `LC_MESSAGES` or `LANG` starts with `da`, English otherwise. Force a language with `--lang=da|en` or with `UI_LANG` in `/etc/default/debian-system-updater`; the option wins over the file.
- `--help`. Unknown options now stop with a usage message (exit code 2) instead of being ignored.
- The README is now in English, with a Danish translation in `README.da.md`. Code comments and this changelog are in English.
- MIT license (`LICENSE`).

### Changed
- The built-in reminder text (`LTS_END_NOTE`) follows the language. A personal note in the settings file is shown exactly as written.

### Tested
- Debian 12 laptop with a Danish system language: Danish output identical to v1.3; English output with `LANG=en_US.UTF-8`; `--help`, `--lang=en --help`, an unknown option (exit code 2), a bad `--lang` value (exit code 2) and a run without root (exit code 1).
- Debian 13 (WSL2 test distro): English by auto-detection and Danish with `--lang=da`.
- shellcheck 0.10.0: no warnings.

---

## v1.3.0 — 2026-09-27

### Added
- **Debian 13 "trixie" in the same script.** The script reads `/etc/os-release` and looks up the support dates in the table `DEBIAN_RELEASES` (bookworm and trixie). The header shows the detected release. On a Debian release that is not in the table everything else runs and only the support clock is left out. On a system that is not Debian, the security status and the support clock are skipped with a warning.
- **Two-phase support clock:** full security support and LTS are shown separately ("full security support until 2028-08-09 (681 days), then LTS until 2030-06-30"), with a yellow note 30 days before the move to LTS.
- **Optional settings file** `/etc/default/debian-system-updater` that survives script updates (for example `LTS_END_NOTE` and `LTS_WARN_DAYS`).
- **Container check in the firmware step:** in WSL, Docker and LXC, fwupd is skipped (its service has `ConditionVirtualization=!container` and never starts) instead of waiting 2 × 25 seconds and reporting two errors.

### Changed
- The personal GPU reminder was removed from the script; the default note is generic. A personal note goes in the settings file.
- The report line "Security support (LTS)" is now called "Security support", and step 8 shows the detected release.
- Removed an unused variable (`TEE_PID`); added a shellcheck directive for the optional settings file.

### Tested
- Debian 13 (WSL2 test distro from Debian's own WSL image, 13.5, apt 3.0.3, flatpak 1.16.6, fwupd 2.0.20): 40 upgrades with one package on hold, Flatpak, unattended-upgrades, debian-security-support and an unreachable package source. apt-get's output is unchanged in apt 3.0 (classic summary line and "kept back" list), and `APT::Update::Error-Mode=any` still turns a failing source into an error (exit code 100 instead of 0).
- Debian 12 (bookworm chroot built with debootstrap, apt 2.6.1): 3 upgrades, the same LTS line as before.
- shellcheck 0.10.0: no warnings.

---

## v1.2.0 — 2026-09-18

### Fixed
- **The report always showed 0 upgraded packages** on systems with a Danish language, because apt's summary line was parsed in English. The script now runs with `LC_ALL=C.UTF-8`, so apt/dpkg/flatpak answer in English (the script's own messages stayed Danish).
- **Packages that were kept back** ("kept back", typically packages on hold) were never shown. The report now shows their number and names, and which packages are on hold with `apt-mark`.
- **The Flatpak counter** counted line numbers in the screen output and therefore missed number 10 and up, counted runtimes and removals as apps, and printed an extra "0" on days without updates. It now compares the installed refs/commits before and after, split into apps and runtimes (updated / new / removed).
- **`apt-get update` got a green tick even when a source could not be fetched** (apt only warns on network errors and returns 0). It now runs with `APT::Update::Error-Mode=any`; failing sources are shown in red and counted as errors, while the upgrade continues with the lists that are available.

### Added
- **Security status (step 8):** installs `debian-security-support` if it is missing and runs `check-support-status`. The report separates packages WITHOUT security support from packages with limited support.
- **LTS clock:** Debian 12 gets security updates until 2028-06-30. The report always shows the days left, a yellow warning at ≤ 30 days (`LTS_WARN_DAYS`), a red alarm at ≤ 7 days (`LTS_ALARM_DAYS`) and after the date. Personal reminder in `LTS_END_NOTE`.
- **Automatic updates:** the report shows whether `unattended-upgrades` is active and how many nightly runs/packages are in this month's apt log. That explains why a manual run often finds few updates.
- **Firmware (step 7):** `fwupdmgr refresh` → `get-updates` → `update` with `--no-reboot-check` (never reboots on its own), `--no-unreported-check` (sends no reports to LVFS) and `--no-metadata-check`. Exit code 2 ("nothing to do") is no longer treated as an error. Hardware check: the script reads the Secure Boot state from the firmware, shows one line per device with the current and new version, only installs what the firmware will accept, and shows rejected updates with fwupd's reason (for example too little space in the UEFI variable store). If only the Secure Boot lists (db/dbx) are rejected and Secure Boot is off, this becomes a neutral note instead of a warning; if Secure Boot is on, you get a warning.
- **`--auto` is now truly non-interactive:** `DEBIAN_FRONTEND=noninteractive` and dpkg `--force-confdef --force-confold`, so a debconf question or a config-file conflict cannot make a cron run hang. Interactive runs ask as before.
- `dpkg --configure -a` before fix-broken (completes an interrupted installation).
- The restart check also compares the running kernel with the newest installed kernel (the file `/var/run/reboot-required` is only created by some packages).
- Warning about Flatpak components marked end-of-life.
- Duration in the report, log rotation at 5 MB, exit code 1 if there were errors (for cron).
- `.gitattributes` keeps LF line endings in `.sh` files on checkout on Windows.

### Changed
- Steps are now [1/8] … [8/8]. The report gained the lines Package sources, Packages kept back, Packages on hold, Flatpak runtimes, Firmware, Security support (LTS) and Automatic updates.

---

## v1.1.0 — 2026-06-18

### Added
- Coloured output: green/yellow/red throughout all steps
- Automatic logging to `/var/log/debian-updater.log` in real time
- Timestamps at start and end
- Disk space pre-check: stops below 1 GB free, warns below 2 GB
- Notice when a restart is required (`/var/run/reboot-required`)
- **Final report** with the number of upgraded packages, Flatpaks, removed packages and errors
- `--auto` flag for cron/automation (skips the final `read -p`)
- Conditional firmware update via `fwupdmgr` (if installed)
- Error handling in the `fix-broken` step (missing in v1.0.0)
- Temp files are used to parse statistics without losing real-time output

### Changed
- All critical steps now show `✓ Done` or `✗ Error` explicitly
- Steps are now numbered [1/6] ... [6/6] for an overview

---

## v1.0.0 — 2026-06-18

### First release
- Root check via `$EUID`
- Step-by-step update chain: fix-broken → update → full-upgrade → flatpak → autoremove --purge → clean
- Error handling with `exit 1` on critical steps
- Conditional Flatpak support via a `command -v` check
