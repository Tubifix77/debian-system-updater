#!/bin/bash
# Unit tests for the functions in update_system.sh.
#
# The tests source the script (which then does not run), use temporary files
# only and need no root, so they are safe to run anywhere:
#   bash tests/unit_tests.sh
# The firmware JSON tests need python3; without it they are reported as skipped.
set -u

cd "$(dirname "$0")/.." || exit 2
# shellcheck source=/dev/null
. ./update_system.sh

PASSES=0
FAILS=0
SKIPS=0
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

# check DESCRIPTION COMMAND... : passes when the command succeeds
check() {
  local desc=$1
  shift
  if "$@"; then
    echo "PASS  ${desc}"
    PASSES=$(( PASSES + 1 ))
  else
    echo "FAIL  ${desc}"
    FAILS=$(( FAILS + 1 ))
  fi
}

# eq ACTUAL EXPECTED : succeeds when both are equal, otherwise shows the difference
eq() {
  if [[ "$1" == "$2" ]]; then
    return 0
  fi
  echo "      expected: '$2'"
  echo "      actual:   '$1'"
  return 1
}

echo "== Unit tests for update_system.sh v${UPDATER_VERSION}"

# ─── Language ─────────────────────────────────────────────────────────────────
lang_for() {   # lang_for "VAR=value ..." : UI_LANG that detect_language picks
  (
    unset LC_ALL LC_MESSAGES LANG
    for assignment in "$@"; do
      export "${assignment?}"
    done
    UI_LANG=""
    detect_language
    echo "${UI_LANG}"
  ) 2>/dev/null   # bash warns when a test locale is not installed; not relevant here
}
check "LANG=da_DK.UTF-8 gives Danish"       eq "$(lang_for LANG=da_DK.UTF-8)" da
check "LANG=en_US.UTF-8 gives English"      eq "$(lang_for LANG=en_US.UTF-8)" en
check "no locale at all gives English"      eq "$(lang_for)" en
check "LC_ALL wins over LANG"               eq "$(lang_for LANG=da_DK.UTF-8 LC_ALL=C.UTF-8)" en
check "LC_MESSAGES wins over LANG"          eq "$(lang_for LANG=en_US.UTF-8 LC_MESSAGES=da_DK.UTF-8)" da
UI_LANG=da
check "t picks Danish"                      eq "$(t dansk english)" dansk
UI_LANG=en
check "t picks English"                     eq "$(t dansk english)" english

# ─── Options ──────────────────────────────────────────────────────────────────
opts() {   # opts ARGS... : "auto=... lang=..." after parse_options
  ( UI_LANG=en; parse_options "$@"; echo "auto=${AUTO} lang=${CLI_LANG}" ) 2>/dev/null
}
check "no options"                          eq "$(opts)" "auto=false lang="
check "--auto"                              eq "$(opts --auto)" "auto=true lang="
check "--lang=da"                           eq "$(opts --lang=da)" "auto=false lang=da"
check "--lang en --auto (two words)"        eq "$(opts --lang en --auto)" "auto=true lang=en"
( UI_LANG=en; parse_options --help ) > /dev/null 2>&1
check "--help exits 0"                      eq "$?" 0
( UI_LANG=en; parse_options --bogus ) > /dev/null 2>&1
check "an unknown option exits 2"           eq "$?" 2
( UI_LANG=en; parse_options --lang=xx ) > /dev/null 2>&1
check "a bad --lang value exits 2"          eq "$?" 2
( UI_LANG=en; parse_options --lang ) > /dev/null 2>&1
check "--lang without a value exits 2"      eq "$?" 2
check "--lang=en --help shows English help" eq "$( ( UI_LANG=da; parse_options --lang=en --help ) | head -1 | cut -d: -f1)" "Usage"

# ─── Release and support dates ────────────────────────────────────────────────
# A complete os-release as Debian ships it. It sets VERSION and NAME too, which
# once clashed with a read-only VERSION constant in the script (v1.6.0 before release).
cat > "${WORK}/os-release" <<'EOF'
PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
NAME="Debian GNU/Linux"
VERSION_ID="13"
VERSION="13 (trixie)"
VERSION_CODENAME=trixie
DEBIAN_VERSION_FULL=13.5
ID=debian
HOME_URL="https://www.debian.org/"
SUPPORT_URL="https://www.debian.org/support"
BUG_REPORT_URL="https://bugs.debian.org/"
EOF
UI_LANG=en
detect_release "${WORK}/os-release"
check "os-release: ID"                      eq "${OS_ID}" debian
check "os-release: VERSION_ID"              eq "${OS_VERSION_ID}" 13
check "os-release: PRETTY_NAME"             eq "${OS_PRETTY}" "Debian GNU/Linux 13 (trixie)"
check "os-release: the script's variables are untouched" \
  eq "${UPDATER_VERSION}|${UI_LANG}" "$(sed -n 's/^readonly UPDATER_VERSION="\(.*\)"/\1/p' update_system.sh)|en"
detect_release "${WORK}/missing"
check "missing os-release: unknown system"  eq "${OS_PRETTY}" "unknown system"

dates() {   # dates OS_ID VERSION_ID CSV [LTS_END preset] : "full|lts|source|known"
  (
    OS_ID=$1; OS_VERSION_ID=$2
    # shellcheck disable=SC2034  # read by lookup_support_dates
    DISTRO_INFO_CSV=$3
    REGULAR_END=""; LTS_END=${4:-}; UI_LANG=en
    lookup_support_dates
    echo "${REGULAR_END}|${LTS_END}|${DATE_SOURCE}|${RELEASE_KNOWN}"
  )
}
csv="${WORK}/debian.csv"
printf '%s\n' 'version,codename,series,created,release,eol,eol-lts,eol-elts' \
  '12,Bookworm,bookworm,2021-08-14,2023-06-10,2026-07-11,2028-06-30,2033-06-30' \
  '13,Trixie,trixie,2023-06-10,2025-08-09,2028-08-09,2030-06-30,2035-06-30' \
  '14,Forky,forky,2025-08-09,,,,' > "${csv}"
reordered="${WORK}/reordered.csv"
printf '%s\n' 'eol-lts,codename,eol,version' '2030-06-30,Trixie,2028-08-09,13' > "${reordered}"
check "dates for 12 from distro-info-data" \
  eq "$(dates debian 12 "${csv}")" "2026-07-11|2028-06-30|distro-info-data (${csv})|true"
check "dates for 13 from distro-info-data" \
  eq "$(dates debian 13 "${csv}")" "2028-08-09|2030-06-30|distro-info-data (${csv})|true"
check "CSV columns are found by name" \
  eq "$(dates debian 13 "${reordered}")" "2028-08-09|2030-06-30|distro-info-data (${reordered})|true"
check "fallback table without distro-info-data" \
  eq "$(dates debian 13 "${WORK}/missing.csv")" "2028-08-09|2030-06-30|the script's built-in table|true"
check "no dates for a release nobody knows" \
  eq "$(dates debian 14 "${csv}")" "|||false"
check "the settings file wins" \
  eq "$(dates debian 13 "${csv}" 2031-01-31)" "|2031-01-31|the settings file|true"
check "no dates for other distributions" \
  eq "$(dates ubuntu 24.04 "${csv}")" "|||false"

countdown() {   # countdown FULL_END LTS_END TODAY : "full days|lts days"
  (
    REGULAR_END=$1; LTS_END=$2; RELEASE_KNOWN=true
    compute_countdown "$(date -d "$3" +%s)"
    echo "${REGULAR_DAYS_LEFT}|${LTS_DAYS_LEFT}"
  )
}
check "countdown during full support"       eq "$(countdown 2028-08-09 2030-06-30 2026-09-27)" "682|1372"
check "countdown during LTS"                eq "$(countdown 2026-07-11 2028-06-30 2026-09-27)" "-78|642"
check "countdown after the end"             eq "$(countdown 2018-01-01 2020-01-01 2020-01-11)" "-740|-10"

# ─── apt ──────────────────────────────────────────────────────────────────────
cat > "${WORK}/apt.txt" <<'EOF'
Reading package lists...
Calculating upgrade...
The following packages have been kept back:
  tzdata nvidia-detect
The following packages will be upgraded:
  base-files bash
2 upgraded, 1 newly installed, 3 to remove and 2 not upgraded.
EOF
parse_apt_summary "${WORK}/apt.txt"
check "apt: upgraded"                       eq "${APT_UPGRADED}" 2
check "apt: newly installed"                eq "${APT_INSTALLED}" 1
check "apt: to remove"                      eq "${APT_REMOVED}" 3
check "apt: not upgraded"                   eq "${APT_KEPT}" 2
check "apt: kept-back list"                 eq "${KEPT_LIST}" "tzdata nvidia-detect"
printf 'Reading package lists...\n' > "${WORK}/apt-empty.txt"
parse_apt_summary "${WORK}/apt-empty.txt"
check "apt: no summary line gives zeros"    eq "${APT_UPGRADED}/${APT_INSTALLED}/${APT_REMOVED}/${APT_KEPT}/${KEPT_LIST}" "0/0/0/0/"

# ─── Flatpak ──────────────────────────────────────────────────────────────────
printf 'app/a/x86_64/stable\tc1\napp/b/x86_64/stable\tc2\napp/c/x86_64/stable\tc3\n' > "${WORK}/fp-before.txt"
printf 'app/a/x86_64/stable\tc1\napp/b/x86_64/stable\tc9\napp/d/x86_64/stable\tc4\n' > "${WORK}/fp-after.txt"
check "flatpak: updated, new, removed"      eq "$(fp_count "${WORK}/fp-before.txt" "${WORK}/fp-after.txt")" "1 1 1"
check "flatpak: nothing changed"            eq "$(fp_count "${WORK}/fp-before.txt" "${WORK}/fp-before.txt")" "0 0 0"

# ─── Firmware ─────────────────────────────────────────────────────────────────
cat > "${WORK}/fw.json" <<'EOF'
{
  "Devices" : [
    { "Name" : "UEFI CA", "Version" : "2011", "Plugin" : "uefi_db",
      "UpdateError" : "Not enough efivarfs space, requested 16,4 kB and got 239 byte",
      "Releases" : [ { "Version" : "2023" } ] },
    { "Name" : "UEFI dbx", "Version" : "20250507", "Plugin" : "uefi_dbx",
      "UpdateError" : "Not enough efivarfs space, requested 30,7 kB and got 239 byte",
      "Releases" : [ { "Version" : "20260402" }, { "Version" : "20250902" } ] },
    { "Name" : "NVMe SSD", "Version" : "1.0", "Plugin" : "nvme",
      "Releases" : [ { "Version" : "1.1" } ] },
    { "Name" : "Mouse", "Version" : "3", "Plugin" : "logitech_hidpp", "Releases" : [] }
  ]
}
EOF
printf '{ "Devices" : [ ] }\n' > "${WORK}/fw-empty.json"
printf 'not json\n' > "${WORK}/fw-bad.json"
expected_tsv=$(printf '%s\t%s\t%s\t%s\t%s\n' \
  "UEFI CA" 2011 2023 "Not enough efivarfs space, requested 16,4 kB and got 239 byte" uefi_db \
  "UEFI dbx" 20250507 20260402 "Not enough efivarfs space, requested 30,7 kB and got 239 byte" uefi_dbx \
  "NVMe SSD" 1.0 1.1 "" nvme)
if command -v python3 > /dev/null 2>&1; then
  check "firmware JSON: one line per device with an update" \
    eq "$(fw_summarise "${WORK}/fw.json")" "${expected_tsv}"
  check "firmware JSON: no devices gives no lines" \
    eq "$(fw_summarise "${WORK}/fw-empty.json")" ""
  fw_summarise "${WORK}/fw-bad.json" > /dev/null 2>&1
  check "firmware JSON: unreadable JSON fails" [ "$?" -ne 0 ]
else
  echo "SKIP  firmware JSON tests (python3 is not installed)"
  SKIPS=$(( SKIPS + 3 ))
fi
printf '%s\n' "${expected_tsv}" > "${WORK}/fw.tsv"
fw_count_devices "${WORK}/fw.tsv"
check "firmware: devices"                   eq "${FW_DEVICES}" 3
check "firmware: rejected"                  eq "${FW_BLOCKED}" 2
check "firmware: rejected Secure Boot lists" eq "${FW_BLOCKED_SB}" 2
check "firmware: ready to install"          eq "${FW_READY}" 1
check "firmware: rejection reason"          eq "${FW_REASON}" "Not enough efivarfs space"

mkdir -p "${WORK}/efi-on" "${WORK}/efi-off" "${WORK}/efi-none"
printf '\x06\x00\x00\x00\x01' > "${WORK}/efi-on/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
printf '\x06\x00\x00\x00\x00' > "${WORK}/efi-off/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
check "Secure Boot on"                      eq "$(secure_boot_state "${WORK}/efi-on")" on
check "Secure Boot off"                     eq "$(secure_boot_state "${WORK}/efi-off")" off
check "Secure Boot unknown without EFI"     eq "$(secure_boot_state "${WORK}/efi-none")" unknown

# ─── Security support ─────────────────────────────────────────────────────────
cat > "${WORK}/support.txt" <<'EOF'
Ended security support for one or more packages

* Source:intel-mediasdk, ended on 2024-11-21 at version 22.5.4-1
  Details: abandoned upstream, upstream does not publish enough information to fix issues.
  Affected binary package:
  - libmfx1:amd64 (installed version: 22.5.4-1)

* Source:mbedtls, ended on 2026-06-12 at version 2.16.9-0.1+deb11u4
  Details: Crypto library difficult to support in the long term
  Affected binary packages:
  - libmbedtls14:amd64 (installed version: 2.28.3-1)

Limited security support for one or more packages

* Source:binutils
  Details: Only suitable for trusted content
  Affected binary packages:
  - binutils (installed version: 2.40-2)

* Source:libsoup3
  Details: Only supported as a client, not as a server
  Affected binary packages:
  - libsoup-3.0-0:amd64 (installed version: 3.2.3-0+deb12u2)
EOF
parse_support_status "${WORK}/support.txt"
check "support: ended"                      eq "${SUPPORT_ENDED}" 2
check "support: limited"                    eq "${SUPPORT_LIMITED}" 2
check "support: names of ended packages"    eq "${SUPPORT_ENDED_LIST}" "intel-mediasdk mbedtls"
check "support: details for ended packages" \
  eq "$(print_support_details "${WORK}/support.txt" ended | head -2)" \
     "$(printf '%s\n' "  • intel-mediasdk, ended on 2024-11-21 at version 22.5.4-1" \
                      "      abandoned upstream, upstream does not publish enough information to fix issues.")"

# ─── Automatic updates ────────────────────────────────────────────────────────
cat > "${WORK}/history.log" <<'EOF'
Start-Date: 2026-09-02  06:25:23
Commandline: /usr/bin/unattended-upgrade
Upgrade: librabbitmq4:amd64 (0.11.0-1+deb12u2, 0.11.0-1+deb12u3)
End-Date: 2026-09-02  06:25:25

Start-Date: 2026-09-05  06:51:00
Commandline: /usr/bin/unattended-upgrade
Upgrade: libpcre2-posix3:amd64 (10.42-1, 10.42-1+deb12u1), libpcre2-8-0:amd64 (10.42-1, 10.42-1+deb12u1)
End-Date: 2026-09-05  06:51:04

Start-Date: 2026-09-09  22:46:28
Commandline: apt-get full-upgrade -y
Upgrade: firefox:amd64 (155.0, 156.0)
End-Date: 2026-09-09  22:47:10
EOF
UI_LANG=en
summarise_unattended_upgrades "${WORK}/history.log"
check "unattended-upgrades: runs, packages and last date" \
  eq "${UU_STATUS}" "active — 2 nightly runs / 3 packages in this month's log, last 2026-09-05"
summarise_unattended_upgrades "${WORK}/missing.log"
check "unattended-upgrades: missing log" \
  eq "${UU_STATUS}" "active — 0 nightly runs / 0 packages in this month's log, last unknown"

# ─── Layout ───────────────────────────────────────────────────────────────────
# The lines above and below the titles must reach past the longest title with a
# margin of at least 3 characters. ASCII "|" stands in for "│" so that the
# lengths are the same in every locale.
header_title="  Debian System Updater v${UPDATER_VERSION}  |  2026-09-27 17:15:43"
report_title="  RAPPORT  |  2026-09-27 17:15:55  |  varighed 59m 59s"
check "line() draws LINE_WIDTH characters"   eq "$(line | grep -o '═' | wc -l)" "${LINE_WIDTH}"
check "the header line is 3+ wider than the title" \
  [ "${LINE_WIDTH}" -ge $(( ${#header_title} + 3 )) ]
check "the report line is 3+ wider than the longest report title" \
  [ "${LINE_WIDTH}" -ge $(( ${#report_title} + 3 )) ]

echo "== ${PASSES} passed, ${FAILS} failed, ${SKIPS} skipped"
(( FAILS == 0 ))
