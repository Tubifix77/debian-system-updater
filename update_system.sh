#!/bin/bash
#
# Debian System Updater
#
# Complete maintenance of Debian 12 and 13: repairs, apt, Flatpak, cleanup,
# firmware and security status, with coloured output, a log and a final report.
# The script detects the Debian release and the language (Danish or English).
#
# Usage:
#   sudo bash update_system.sh              # interactive, waits for ENTER at the end
#   sudo bash update_system.sh --auto       # non-interactive, for cron / automation
#   sudo bash update_system.sh --lang=en    # force the language (da or en)
#   bash update_system.sh --help
#
# Settings: /etc/default/debian-system-updater (see README.md)
# Changes:  CHANGELOG.md
#
# Upper-case globals are constants, user settings or the state collected for
# the final report. Function-local variables are lower case.

# ─── Constants ────────────────────────────────────────────────────────────────
readonly UPDATER_VERSION="1.6.1"
readonly CONFIG_FILE="/etc/default/debian-system-updater"
readonly LINE_WIDTH=57   # the longest title ends at column 54; 3 characters of margin
readonly RED='\033[0;31m' YELLOW='\033[1;33m' GREEN='\033[0;32m'
readonly CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'

# Fallback support dates, used when distro-info-data is not installed.
# Sources: https://www.debian.org/releases/<codename>/ and https://wiki.debian.org/LTS
# (distro-info-data and the release pages give full support for bookworm until
#  2026-07-11; the LTS wiki gives LTS from 2026-06-11; all agree on 2028-06-30).
#   version  codename   full support until   LTS until
readonly DEBIAN_RELEASES="
12 bookworm 2026-07-11 2028-06-30
13 trixie   2028-08-09 2030-06-30
"

# ─── Settings (defaults; each can be overridden in CONFIG_FILE) ───────────────
LOG_FILE="/var/log/debian-updater.log"
LOG_MAX_BYTES=5242880          # rotate the log (to .1) when it exceeds 5 MB
LTS_WARN_DAYS=30               # yellow warning at this many days left (or fewer)
LTS_ALARM_DAYS=7               # red alarm at this many days left (or fewer)
LTS_END_NOTE=""                # own reminder next to the warnings (empty: built-in)
UI_LANG=""                     # da or en (empty: follow the system language)
INSTALL_SECURITY_SUPPORT=yes   # yes: install debian-security-support if missing
FIRMWARE_UPDATES=ask           # ask (never in --auto), install, check or off
DISTRO_INFO_CSV="/usr/share/distro-info/debian.csv"   # Debian's release dates

# ─── Output helpers ───────────────────────────────────────────────────────────
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
fail() { echo -e "${RED}✗ $*${NC}" >&2; }
step() { echo -e "${BOLD}$*${NC}"; }
line() {
  local bar
  printf -v bar '%*s' "${LINE_WIDTH}" ''
  echo -e "${CYAN}${BOLD}${bar// /═}${NC}"
}
row()  { printf '  %-32s %s\n' "$1" "$2"; }                    # label, value
rowc() { echo -e "  $(printf '%-32s' "$1") ${2}${3}${NC}"; }    # label, colour, value
add_error() { (( ERRORS += 1 )); }

#######################################
# Chooses the Danish or the English version of a text ("t" for translate).
# Globals:
#   UI_LANG
# Arguments:
#   Danish text, English text
# Outputs:
#   The chosen text on STDOUT, without a trailing newline.
#######################################
t() {
  if [[ "${UI_LANG}" == "da" ]]; then
    printf '%s' "$1"
  else
    printf '%s' "$2"
  fi
}

#######################################
# Prints the command-line help in the current language.
# Globals:
#   UI_LANG
# Outputs:
#   The help text on STDOUT.
#######################################
usage() {
  if [[ "${UI_LANG}" == "da" ]]; then
    cat <<'EOT'
Brug: sudo bash update_system.sh [--auto] [--lang=da|en]
  --auto         ikke-interaktiv (til cron): ingen spørgsmål, ingen ENTER til sidst
  --lang=da|en   sprog for beskederne (standard: systemsproget)
  --help         vis denne hjælp
EOT
  else
    cat <<'EOT'
Usage: sudo bash update_system.sh [--auto] [--lang=da|en]
  --auto         non-interactive (for cron): no prompts, no ENTER at the end
  --lang=da|en   language of the messages (default: the system language)
  --help         show this help
EOT
  fi
}

# ─── Setup ────────────────────────────────────────────────────────────────────

#######################################
# Picks the message language from the system locale: Danish when the first of
# LC_ALL, LC_MESSAGES and LANG that is set starts with "da", otherwise English.
# Must run before setup_mode overrides LC_ALL.
# Globals:
#   LC_ALL, LC_MESSAGES, LANG (read); DETECTED_LANG, UI_LANG (set)
#######################################
detect_language() {
  case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
    da*) DETECTED_LANG=da ;;
    *) DETECTED_LANG=en ;;
  esac
  UI_LANG=${UI_LANG:-${DETECTED_LANG}}
}

#######################################
# Parses the command line.
# Globals:
#   AUTO, CLI_LANG (set); UI_LANG (set when --lang comes before --help)
# Arguments:
#   The script's arguments.
# Outputs:
#   Help on STDOUT; errors and help on STDERR for a bad option.
# Returns:
#   Exits 0 after --help, 2 after an unknown option or a bad --lang value.
#######################################
parse_options() {
  AUTO=false
  CLI_LANG=""
  while (( $# > 0 )); do
    case "$1" in
      --auto) AUTO=true ;;
      --lang=*) CLI_LANG=${1#--lang=} ;;
      --lang)
        shift
        CLI_LANG=${1:-?}
        ;;
      -h | --help)
        [[ -n "${CLI_LANG}" ]] && UI_LANG=${CLI_LANG}
        usage
        exit 0
        ;;
      *)
        { t "Ukendt tilvalg: $1" "Unknown option: $1"; echo; usage; } >&2
        exit 2
        ;;
    esac
    shift
  done
  case "${CLI_LANG}" in
    "" | da | en) ;;
    *)
      { t "--lang skal være da eller en" "--lang must be da or en"; echo; } >&2
      exit 2
      ;;
  esac
  if [[ -n "${CLI_LANG}" ]]; then
    UI_LANG=${CLI_LANG}
  fi
}

#######################################
# Stops unless the script runs as root.
# Outputs:
#   An error on STDERR.
# Returns:
#   Exits 1 when not root.
#######################################
require_root() {
  if (( EUID != 0 )); then
    echo -e "${RED}$(t "Fejl: Dette script skal køres med sudo!" \
                       "Error: this script must be run with sudo!")${NC}" >&2
    exit 1
  fi
}

#######################################
# Reads the optional settings file and checks its values. A --lang option wins
# over UI_LANG from the file; invalid values fall back to the defaults.
# Globals:
#   CONFIG_FILE, CLI_LANG, DETECTED_LANG (read); the settings, REGULAR_END,
#   LTS_END (may be set by the file); LTS_END_NOTE (built-in text if empty)
#######################################
load_settings() {
  REGULAR_END=""
  LTS_END=""
  if [[ -r "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    . "${CONFIG_FILE}"
  fi
  if [[ -n "${CLI_LANG}" ]]; then
    UI_LANG=${CLI_LANG}
  fi
  case "${UI_LANG}" in da | en) ;; *) UI_LANG=${DETECTED_LANG} ;; esac
  case "${INSTALL_SECURITY_SUPPORT}" in yes | no) ;; *) INSTALL_SECURITY_SUPPORT=yes ;; esac
  case "${FIRMWARE_UPDATES}" in ask | install | check | off) ;; *) FIRMWARE_UPDATES=ask ;; esac
  if [[ -z "${LTS_END_NOTE}" ]]; then
    LTS_END_NOTE=$(t "Planlæg skiftet til den næste Debian-udgave i god tid: https://www.debian.org/releases/" \
                     "Plan the move to the next Debian release in good time: https://www.debian.org/releases/")
  fi
}

#######################################
# Reads the distribution from os-release. The file is sourced in a fresh bash
# process with an empty environment: it sets names like VERSION and NAME, which
# must neither overwrite nor clash with this script's (read-only) variables.
# Globals:
#   OS_ID, OS_VERSION_ID, OS_PRETTY (set)
# Arguments:
#   Path of the os-release file (normally /etc/os-release).
#######################################
detect_release() {
  local file=$1
  # shellcheck disable=SC2016  # the inner bash expands these, not this one
  IFS='|' read -r OS_ID OS_VERSION_ID OS_PRETTY < <(
    env -i bash -c '. "$1" 2>/dev/null
      printf "%s|%s|%s\n" "${ID:-}" "${VERSION_ID:-}" "${PRETTY_NAME:-}"' _ "${file}"
  )
  OS_PRETTY=${OS_PRETTY:-$(t "ukendt system" "unknown system")}
}

#######################################
# Finds the support dates for the detected release: the settings file wins,
# then Debian's own distro-info-data (columns found by header name), then the
# fallback table DEBIAN_RELEASES.
# Globals:
#   OS_ID, OS_VERSION_ID, DISTRO_INFO_CSV, DEBIAN_RELEASES (read);
#   REGULAR_END, LTS_END, DATE_SOURCE, RELEASE_KNOWN (set)
#######################################
lookup_support_dates() {
  local rel_line
  DATE_SOURCE=""
  if [[ -n "${LTS_END}" ]]; then
    DATE_SOURCE=$(t "indstillingsfilen" "the settings file")
  elif [[ "${OS_ID}" == "debian" && -n "${OS_VERSION_ID}" ]]; then
    if [[ -r "${DISTRO_INFO_CSV}" ]]; then
      IFS='|' read -r REGULAR_END LTS_END < <(awk -F, -v v="${OS_VERSION_ID}" '
        NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
        col["version"] && col["eol"] && col["eol-lts"] && $col["version"] == v {
          print $col["eol"] "|" $col["eol-lts"]; exit
        }' "${DISTRO_INFO_CSV}")
      if [[ -n "${LTS_END}" ]]; then
        DATE_SOURCE="distro-info-data (${DISTRO_INFO_CSV})"
      fi
    fi
    if [[ -z "${LTS_END}" ]]; then
      rel_line=$(awk -v v="${OS_VERSION_ID}" '$1 == v' <<< "${DEBIAN_RELEASES}")
      if [[ -n "${rel_line}" ]]; then
        read -r _ _ REGULAR_END LTS_END <<< "${rel_line}"
        DATE_SOURCE=$(t "scriptets indbyggede tabel" "the script's built-in table")
      fi
    fi
  fi
  RELEASE_KNOWN=false
  if [[ -n "${LTS_END}" ]]; then
    RELEASE_KNOWN=true
  fi
}

#######################################
# Makes apt, dpkg and flatpak answer in English (the report parses their
# output; with a Danish locale v1.1 always showed "0 packages upgraded") and,
# in --auto mode, makes dpkg/debconf take the safe default answers: keep the
# current config file (the new one is saved as *.dpkg-dist). Without this a
# cron run could hang forever on a question nobody sees.
# Globals:
#   AUTO (read); LC_ALL, DEBIAN_FRONTEND (exported); APT_OPTS (set)
#######################################
setup_mode() {
  export LC_ALL=C.UTF-8
  APT_OPTS=()
  if [[ "${AUTO}" == true ]]; then
    export DEBIAN_FRONTEND=noninteractive
    APT_OPTS=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
  fi
}

#######################################
# Rotates the log if needed and sends all further output (STDOUT and STDERR)
# to the screen and the log file in real time. Creates the temp directory.
# Globals:
#   LOG_FILE, LOG_MAX_BYTES (read); START_TIME, START_EPOCH, TMP (set)
#######################################
start_log() {
  if [[ -f "${LOG_FILE}" ]] && (( $(stat -c %s "${LOG_FILE}") > LOG_MAX_BYTES )); then
    mv -f "${LOG_FILE}" "${LOG_FILE}.1"
  fi
  START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
  START_EPOCH=$(date +%s)
  exec > >(tee -a "${LOG_FILE}") 2>&1
  TMP=$(mktemp -d)
  trap 'rm -rf "${TMP}"' EXIT
}

#######################################
# Sets the state collected for the final report to its starting values.
# Globals:
#   The report state (set).
#######################################
init_counters() {
  ERRORS=0
  SOURCES_STATUS="OK"
  APT_UPGRADED=0; APT_INSTALLED=0; APT_REMOVED=0; APT_KEPT=0; KEPT_LIST=""
  AUTOREMOVED=0
  FP_APP_UPD=0; FP_APP_NEW=0; FP_APP_REM=0
  FP_RT_UPD=0; FP_RT_NEW=0; FP_RT_REM=0
  FLATPAK_INSTALLED=false
  FIRMWARE_STATUS=$(t "fwupd ikke installeret" "fwupd not installed")
  FW_REBOOT=false
  SUPPORT_STATUS=$(t "ukendt" "unknown")
  SUPPORT_COUNT=0; SUPPORT_ENDED=0; SUPPORT_LIMITED=0; SUPPORT_ENDED_LIST=""
  UU_STATUS=$(t "ikke aktiv" "not active")
}

#######################################
# Prints the header and a warning for an unsupported or unknown release.
# Globals:
#   UPDATER_VERSION, START_TIME, OS_ID, OS_PRETTY, RELEASE_KNOWN (read)
# Outputs:
#   The header on STDOUT.
#######################################
print_header() {
  echo ""
  line
  echo -e "${CYAN}${BOLD}  Debian System Updater v${UPDATER_VERSION}  │  ${START_TIME}${NC}"
  echo -e "${CYAN}${BOLD}  ${OS_PRETTY}${NC}"
  line
  echo ""
  if [[ "${OS_ID}" != "debian" ]]; then
    warn "$(t "Scriptet er lavet til Debian 12 og 13, men systemet er: ${OS_PRETTY}." \
              "This script is made for Debian 12 and 13, but this system is: ${OS_PRETTY}.")"
    warn "$(t "Fortsætter med apt, Flatpak og firmware; sikkerhedsstatus og support-ur springes over." \
              "Continuing with apt, Flatpak and firmware; security status and the support clock are skipped.")"
    echo ""
  elif [[ "${RELEASE_KNOWN}" != true ]]; then
    warn "$(t "${OS_PRETTY} står ikke i scriptets datotabel (DEBIAN_RELEASES) — alt andet kører, men support-uret vises ikke." \
              "${OS_PRETTY} is not in the script's date table (DEBIAN_RELEASES). Everything else runs, but the support clock is not shown.")"
    echo ""
  fi
}

# ─── Pre-check and steps 1-6: apt and Flatpak ─────────────────────────────────

#######################################
# Checks the free space on /: stops below 1 GB, warns below 2 GB.
# Outputs:
#   The result on STDOUT (STDERR when stopping).
# Returns:
#   Exits 1 when the disk is critically full.
#######################################
check_disk_space() {
  local free_kb free_h
  free_kb=$(df / | awk 'NR==2 {print $4}')
  free_h=$(df -h / | awk 'NR==2 {print $4}')
  if (( free_kb < 1048576 )); then
    fail "$(t "Diskplads kritisk: ${free_h} ledig. Afbryder for at undgå skade." \
              "Disk space critical: ${free_h} free. Stopping to avoid damage.")"
    exit 1
  elif (( free_kb < 2097152 )); then
    warn "$(t "Lav diskplads: ${free_h} ledig — fortsætter med forsigtighed." \
              "Low disk space: ${free_h} free. Continuing carefully.")"
  else
    ok "$(t "Diskplads OK: ${free_h} ledig" "Disk space OK: ${free_h} free")"
  fi
  echo ""
}

#######################################
# Step 1: finishes interrupted installations and repairs dependencies.
# Globals:
#   APT_OPTS (read)
# Returns:
#   Exits 1 when a repair fails.
#######################################
step_repair() {
  step "$(t "[1/8] Reparerer pakke-afhængigheder..." "[1/8] Repairing package dependencies...")"
  if ! dpkg --configure -a; then
    fail "$(t "dpkg --configure -a fejlede. Afslutter." "dpkg --configure -a failed. Stopping.")"
    exit 1
  fi
  if ! apt-get "${APT_OPTS[@]}" --fix-broken install -y; then
    fail "$(t "fix-broken fejlede. Afslutter." "fix-broken failed. Stopping.")"
    exit 1
  fi
  ok "$(t "Færdig" "Done")"
  echo ""
}

#######################################
# Step 2: updates the package lists. With APT::Update::Error-Mode=any a source
# that cannot be fetched counts as an error; plain apt only warns and returns
# 0, so v1.1 showed a green tick even when the security archive was missing.
# Globals:
#   TMP (read); SOURCES_STATUS, ERRORS (set)
#######################################
step_update_lists() {
  local rc
  step "$(t "[2/8] Opdaterer pakkelister..." "[2/8] Updating package lists...")"
  apt-get update -o APT::Update::Error-Mode=any 2>&1 | tee "${TMP}/update.txt"
  rc=${PIPESTATUS[0]}
  if (( rc != 0 )); then
    fail "$(t "En eller flere pakkekilder kunne ikke hentes — fortsætter med de pakkelister, der findes:" \
              "One or more package sources could not be fetched. Continuing with the package lists available:")"
    grep -E '^(W|E): ' "${TMP}/update.txt" | sed 's/^/    /'
    SOURCES_STATUS=$(t "FEJL — en eller flere kilder blev ikke hentet (se log)" \
                       "ERROR — one or more sources were not fetched (see log)")
    add_error
  else
    ok "$(t "Pakkelister opdateret" "Package lists updated")"
  fi
  echo ""
}

#######################################
# Reads apt-get's summary line
#   "N upgraded, N newly installed, N to remove and N not upgraded."
# and the package list after "The following packages have been kept back:".
# Globals:
#   APT_UPGRADED, APT_INSTALLED, APT_REMOVED, APT_KEPT, KEPT_LIST (set)
# Arguments:
#   File with apt-get's output (produced with LC_ALL=C.UTF-8).
#######################################
parse_apt_summary() {
  local file=$1
  APT_UPGRADED=$(grep -oP '\d+(?= upgraded,)' "${file}" | tail -1)
  APT_INSTALLED=$(grep -oP '\d+(?= newly installed)' "${file}" | tail -1)
  APT_REMOVED=$(grep -oP '\d+(?= to remove)' "${file}" | tail -1)
  APT_KEPT=$(grep -oP '\d+(?= not upgraded)' "${file}" | tail -1)
  APT_UPGRADED=${APT_UPGRADED:-0}
  APT_INSTALLED=${APT_INSTALLED:-0}
  APT_REMOVED=${APT_REMOVED:-0}
  APT_KEPT=${APT_KEPT:-0}
  KEPT_LIST=$(awk '/^The following packages have been kept back:/ {f = 1; next}
                   f && /^[^ ]/ {f = 0}
                   f {printf "%s ", $0}' "${file}" | tr -s ' ' | sed 's/^ //; s/ $//')
}

#######################################
# Step 3: full system upgrade. Packages that apt keeps back (usually because
# they are on hold) get no security fixes either, so they are named.
# Globals:
#   APT_OPTS, TMP (read); the apt counters, ERRORS (set)
# Returns:
#   Exits 1 when the upgrade fails.
#######################################
step_full_upgrade() {
  local rc
  step "$(t "[3/8] Fuld systemopgradering..." "[3/8] Full system upgrade...")"
  apt-get "${APT_OPTS[@]}" full-upgrade -y 2>&1 | tee "${TMP}/upgrade.txt"
  rc=${PIPESTATUS[0]}
  if (( rc != 0 )); then
    fail "$(t "Opgradering fejlede. Afslutter." "Upgrade failed. Stopping.")"
    add_error
    exit 1
  fi
  parse_apt_summary "${TMP}/upgrade.txt"
  if (( APT_KEPT > 0 )); then
    warn "$(t "${APT_KEPT} pakke(r) blev holdt tilbage og fik IKKE opdateringer: ${KEPT_LIST}" \
              "${APT_KEPT} package(s) were kept back and did NOT get updates: ${KEPT_LIST}")"
    t "   Se hvilke pakker der er på hold med: apt-mark showhold" \
      "   See which packages are on hold with: apt-mark showhold"
    echo
  fi
  ok "$(t "Opgradering fuldført" "Upgrade complete")"
  echo ""
}

#######################################
# Lists installed Flatpak refs with their active commit, sorted by ref.
# Arguments:
#   --app or --runtime
# Outputs:
#   "ref<TAB>commit" lines on STDOUT.
#######################################
fp_snapshot() {
  flatpak list "$1" --columns=ref,active 2>/dev/null | sort -t $'\t' -k1,1
}

#######################################
# Compares two Flatpak snapshots: a changed commit counts as updated, a new ref
# as installed and a missing ref as removed. This works in any language and
# does not depend on flatpak's screen output (v1.1 counted its line numbers).
# Arguments:
#   Snapshot file before, snapshot file after (both sorted by ref).
# Outputs:
#   "updated new removed" on STDOUT.
#######################################
fp_count() {
  local updated new removed
  updated=$(join -t $'\t' "$1" "$2" | awk -F'\t' '$2 != $3' | wc -l)
  new=$(join -t $'\t' -v2 "$1" "$2" | wc -l)
  removed=$(join -t $'\t' -v1 "$1" "$2" | wc -l)
  echo "${updated} ${new} ${removed}"
}

#######################################
# Step 4: updates Flatpak apps and runtimes and counts the changes.
# Globals:
#   TMP (read); FLATPAK_INSTALLED, the FP_* counters, ERRORS (set)
#######################################
step_flatpak() {
  local rc eol
  step "$(t "[4/8] Flatpak-apps..." "[4/8] Flatpak apps...")"
  if ! command -v flatpak &> /dev/null; then
    t "Flatpak er ikke installeret — springer over." "Flatpak is not installed. Skipping."
    echo
    echo ""
    return 0
  fi
  FLATPAK_INSTALLED=true
  fp_snapshot --app > "${TMP}/app_before.txt"
  fp_snapshot --runtime > "${TMP}/rt_before.txt"
  flatpak update -y --noninteractive 2>&1 | tee "${TMP}/flatpak.txt"
  rc=${PIPESTATUS[0]}
  if (( rc != 0 )); then
    warn "$(t "Flatpak returnerede en fejl." "Flatpak returned an error.")"
    add_error
  fi
  fp_snapshot --app > "${TMP}/app_after.txt"
  fp_snapshot --runtime > "${TMP}/rt_after.txt"
  read -r FP_APP_UPD FP_APP_NEW FP_APP_REM < <(fp_count "${TMP}/app_before.txt" "${TMP}/app_after.txt")
  read -r FP_RT_UPD FP_RT_NEW FP_RT_REM < <(fp_count "${TMP}/rt_before.txt" "${TMP}/rt_after.txt")
  # Components that Flathub has declared end-of-life get no more updates
  eol=$(flatpak list --all --columns=ref,options 2>/dev/null \
        | awk -F'\t' '$2 ~ /eol/ {print $1}' | tr '\n' ' ')
  if [[ -n "${eol}" ]]; then
    warn "$(t "Flatpak-komponenter der er end-of-life (ingen opdateringer mere): ${eol}" \
              "Flatpak components that are end-of-life (no more updates): ${eol}")"
  fi
  ok "$(t "Flatpak tjekket" "Flatpak checked")"
  echo ""
}

#######################################
# Step 5: removes packages that nothing needs any more, with their config.
# Globals:
#   APT_OPTS, TMP (read); AUTOREMOVED, ERRORS (set)
#######################################
step_autoremove() {
  local rc
  step "$(t "[5/8] Fjerner ubrugte pakker..." "[5/8] Removing unused packages...")"
  apt-get "${APT_OPTS[@]}" autoremove --purge -y 2>&1 | tee "${TMP}/autoremove.txt"
  rc=${PIPESTATUS[0]}
  if (( rc != 0 )); then
    warn "$(t "autoremove returnerede en fejl. Fortsætter..." "autoremove returned an error. Continuing...")"
    add_error
  fi
  AUTOREMOVED=$(grep -oP '\d+(?= to remove)' "${TMP}/autoremove.txt" | tail -1)
  AUTOREMOVED=${AUTOREMOVED:-0}
  ok "$(t "Oprydning fuldført" "Cleanup complete")"
  echo ""
}

#######################################
# Step 6: clears downloaded .deb files.
# Globals:
#   ERRORS (set on failure)
#######################################
step_clean_cache() {
  step "$(t "[6/8] Rydder pakke-cache..." "[6/8] Clearing the package cache...")"
  if ! apt-get clean; then
    warn "$(t "Cache-oprydning fejlede. Fortsætter..." "Cache cleanup failed. Continuing...")"
    add_error
  fi
  ok "$(t "Cache ryddet" "Cache cleared")"
  echo ""
}

# ─── Step 7: firmware ─────────────────────────────────────────────────────────

#######################################
# Turns the output of `fwupdmgr get-updates --json` (fwupdmgr's manual points to
# --json for parsing) into one line per device that has an update. Devices
# without releases are skipped.
# Arguments:
#   JSON file.
# Outputs:
#   "name<TAB>current version<TAB>new version<TAB>rejection reason<TAB>plugin"
#   lines on STDOUT.
# Returns:
#   Non-zero when python3 fails or the JSON cannot be read.
#######################################
fw_summarise() {
  python3 - "$1" <<'PYEOF'
import json, sys

def clean(value):
    return str(value or "").replace("\t", " ").replace("\n", " ")

with open(sys.argv[1]) as handle:
    data = json.load(handle)
for device in data.get("Devices", []):
    releases = device.get("Releases") or []
    if releases:
        fields = (device.get("Name"), device.get("Version"), releases[0].get("Version"),
                  device.get("UpdateError"), device.get("Plugin"))
        print("\t".join(clean(field) for field in fields))
PYEOF
}

#######################################
# Reads the Secure Boot state from the firmware (byte 5 of the SecureBoot
# EFI variable; the first 4 bytes are its attributes).
# Arguments:
#   The efivars directory (normally /sys/firmware/efi/efivars).
# Outputs:
#   "on", "off" or "unknown" on STDOUT.
#######################################
secure_boot_state() {
  local dir=$1
  local vars=("${dir}"/SecureBoot-*)
  if [[ -e "${vars[0]}" ]]; then
    case "$(od -An -tu1 -j4 -N1 "${vars[0]}" 2>/dev/null | tr -d ' ')" in
      1) echo "on"; return 0 ;;
      0) echo "off"; return 0 ;;
    esac
  fi
  echo "unknown"
}

#######################################
# Counts the devices in a firmware summary (see fw_summarise). The Secure Boot
# lists are the devices of fwupd's uefi_db, uefi_dbx, uefi_kek and uefi_pk plugins.
# Globals:
#   FW_DEVICES, FW_BLOCKED, FW_BLOCKED_SB, FW_READY, FW_REASON (set)
# Arguments:
#   Summary file.
#######################################
fw_count_devices() {
  local tsv=$1
  FW_DEVICES=$(grep -c . "${tsv}")
  FW_BLOCKED=$(awk -F'\t' '$4 != ""' "${tsv}" | wc -l)
  FW_BLOCKED_SB=$(awk -F'\t' '$4 != "" && $5 ~ /^uefi_(db|dbx|kek|pk)$/' "${tsv}" | wc -l)
  FW_READY=$(( FW_DEVICES - FW_BLOCKED ))
  FW_REASON=$(awk -F'\t' '$4 != "" {print $4}' "${tsv}" | sed 's/,.*//' | sort -u | paste -sd ';')
}

#######################################
# Shows the devices that have firmware updates, installs the ones the firmware
# accepts according to FIRMWARE_UPDATES, and explains the rejected ones. Updates
# to the Secure Boot lists mean nothing while Secure Boot is off, and on older
# machines they often cannot be installed (too little space in the UEFI store).
# Globals:
#   AUTO, FIRMWARE_UPDATES, TMP (read); FIRMWARE_STATUS, FW_REBOOT, ERRORS (set)
# Arguments:
#   Summary file (see fw_summarise), fwupdmgr flags.
#######################################
fw_handle_devices() {
  local tsv=$1
  shift
  local flags=("$@") sb_state install=false answer rc blocked_note
  sb_state=$(secure_boot_state /sys/firmware/efi/efivars)
  fw_count_devices "${tsv}"
  awk -F'\t' -v rej="$(t "afvist af firmwaren" "rejected by the firmware")" '
    { line = "  • " $1 ": " ($2 == "" ? "?" : $2) " → " ($3 == "" ? "?" : $3)
      if ($4 != "") line = line "  (" rej ": " $4 ")"
      print line }' "${tsv}"
  FIRMWARE_STATUS=""
  if (( FW_READY > 0 )); then
    case "${FIRMWARE_UPDATES}" in
      install) install=true ;;
      ask)
        if [[ "${AUTO}" != true && -t 0 ]]; then
          read -r -p "$(t "Installér ${FW_READY} firmware-opdatering(er) nu? [j/N] " \
                          "Install ${FW_READY} firmware update(s) now? [y/N] ")" answer
          case "${answer}" in [jJyY]*) install=true ;; esac
        fi
        ;;
    esac
    if [[ "${install}" == true ]]; then
      fwupdmgr update "${flags[@]}" --no-reboot-check 2>&1 | tee "${TMP}/fw_update.txt"
      rc=${PIPESTATUS[0]}
      if grep -q 'Successfully installed firmware' "${TMP}/fw_update.txt"; then
        FIRMWARE_STATUS=$(t "${FW_READY} enhed(er) opdateret — se log" "${FW_READY} device(s) updated (see log)")
        ok "$(t "Firmware opdateret" "Firmware updated")"
        FW_REBOOT=true
      elif (( rc == 0 || rc == 2 )); then
        FIRMWARE_STATUS=$(t "${FW_READY} enhed(er) har opdateringer, men de blev ikke installeret — se log" \
                            "${FW_READY} device(s) have updates, but they were not installed (see log)")
        warn "${FIRMWARE_STATUS}"
      else
        FIRMWARE_STATUS=$(t "FEJL ved opdatering (kode ${rc})" "ERROR during update (code ${rc})")
        fail "$(t "Firmware-opdatering fejlede (kode ${rc})." "Firmware update failed (code ${rc}).")"
        add_error
      fi
    else
      FIRMWARE_STATUS=$(t "${FW_READY} enhed(er) kan opdateres — installér med: sudo fwupdmgr update" \
                          "${FW_READY} device(s) can be updated — install with: sudo fwupdmgr update")
      warn "${FIRMWARE_STATUS}"
    fi
  fi
  if (( FW_BLOCKED > 0 )); then
    if (( FW_BLOCKED_SB == FW_BLOCKED )) && [[ "${sb_state}" == "off" ]]; then
      blocked_note=$(t "ingen relevante (Secure Boot-lister kan ikke opdateres, og Secure Boot er slået fra)" \
                       "none relevant (Secure Boot lists cannot be updated, and Secure Boot is off)")
      t "  Secure Boot er slået fra på denne maskine, så de manglende db/dbx-opdateringer er uden betydning." \
        "  Secure Boot is off on this machine, so the missing db/dbx updates do not matter."
      echo
      ok "$(t "Firmware tjekket" "Firmware checked")"
    else
      blocked_note=$(t "${FW_BLOCKED} enhed(er) kan ikke opdateres: ${FW_REASON:-se log}" \
                       "${FW_BLOCKED} device(s) cannot be updated: ${FW_REASON:-see log}")
      if (( FW_BLOCKED_SB > 0 )) && [[ "${sb_state}" == "on" ]]; then
        blocked_note="${blocked_note}$(t " — Secure Boot er slået TIL, så det bør undersøges" \
                                         " — Secure Boot is ON, so this should be looked into")"
      fi
      warn "${blocked_note}"
    fi
    FIRMWARE_STATUS="${FIRMWARE_STATUS:+${FIRMWARE_STATUS}; }${blocked_note}"
  fi
  if [[ -z "${FIRMWARE_STATUS}" ]]; then
    FIRMWARE_STATUS=$(t "ingen opdateringer tilgængelige" "no updates available")
  fi
}

#######################################
# Refreshes the firmware metadata from LVFS and checks for updates. Debian's
# fwupd-refresh.timer also refreshes daily but hides errors; here they show.
# fwupdmgr uses exit code 2 for "nothing to do", which is not an error.
# Flags: --no-unreported-check never sends reports to LVFS on its own;
# --no-metadata-check because the metadata is refreshed explicitly here;
# --no-reboot-check (on update) never asks for or starts a reboot.
# Globals:
#   TMP (read); FIRMWARE_STATUS, FW_REBOOT, ERRORS (set)
#######################################
firmware_run() {
  local flags=(-y --no-unreported-check --no-metadata-check)
  local note="" rc summary=false
  fwupdmgr refresh "${flags[@]}" 2>&1 | tee "${TMP}/fw_refresh.txt"
  rc=${PIPESTATUS[0]}
  if (( rc != 0 && rc != 2 )); then
    warn "$(t "Firmware-metadata fra LVFS kunne ikke hentes (kode ${rc}) — tjekker med de data, der allerede findes." \
              "Firmware metadata from LVFS could not be fetched (code ${rc}). Checking with the data already present.")"
    note=$(t " (metadata kunne ikke hentes — se log)" " (metadata could not be fetched, see log)")
    add_error
  fi
  # With --json an empty device list means "no updates" and the exit code is 0
  fwupdmgr get-updates --json "${flags[@]}" > "${TMP}/fw.json" 2> "${TMP}/fw.err"
  rc=$?
  if [[ -s "${TMP}/fw.err" ]]; then
    sed 's/\x1b\[[0-9;]*m//g' "${TMP}/fw.err"
  fi
  if (( rc == 0 )) && command -v python3 &> /dev/null \
      && fw_summarise "${TMP}/fw.json" > "${TMP}/fw_devices.tsv" 2> /dev/null; then
    summary=true
  fi
  if (( rc != 0 && rc != 2 )); then
    FIRMWARE_STATUS=$(t "FEJL (kode ${rc})" "ERROR (code ${rc})")
    warn "$(t "fwupdmgr get-updates fejlede (kode ${rc})." "fwupdmgr get-updates failed (code ${rc}).")"
    add_error
  elif (( rc == 0 )) && [[ "${summary}" != true ]]; then
    # No python3 (or unexpected JSON): show fwupd's own text and never install blind
    fwupdmgr get-updates "${flags[@]}" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
    if (( PIPESTATUS[0] == 2 )); then
      FIRMWARE_STATUS="$(t "ingen opdateringer tilgængelige" "no updates available")${note}"
      ok "$(t "Firmware er ajour" "Firmware is up to date")"
    else
      FIRMWARE_STATUS=$(t "opdateringer fundet, men de kan ikke opsummeres uden python3 — installér med: sudo fwupdmgr update" \
                          "updates found, but they cannot be summarised without python3 — install with: sudo fwupdmgr update")
      warn "${FIRMWARE_STATUS}"
    fi
  elif [[ ! -s "${TMP}/fw_devices.tsv" ]]; then
    FIRMWARE_STATUS="$(t "ingen opdateringer tilgængelige" "no updates available")${note}"
    ok "$(t "Firmware er ajour" "Firmware is up to date")"
  else
    fw_handle_devices "${TMP}/fw_devices.tsv" "${flags[@]}"
    FIRMWARE_STATUS="${FIRMWARE_STATUS}${note}"
  fi
}

#######################################
# Step 7: firmware updates via fwupd, unless switched off, not installed or in
# a container (WSL, Docker, LXC ...), where the fwupd service never starts
# (its unit has ConditionVirtualization=!container) and the firmware belongs
# to the host. Same test systemd uses; otherwise fwupdmgr waits 25 s in vain.
# Globals:
#   FIRMWARE_UPDATES (read); FIRMWARE_STATUS (set)
#######################################
step_firmware() {
  local container
  step "$(t "[7/8] Firmware-opdateringer (fwupd)..." "[7/8] Firmware updates (fwupd)...")"
  container=$(systemd-detect-virt --container 2>/dev/null)
  if [[ "${FIRMWARE_UPDATES}" == "off" ]]; then
    t "Firmware-trinnet er slået fra (FIRMWARE_UPDATES=off i indstillingsfilen)." \
      "The firmware step is switched off (FIRMWARE_UPDATES=off in the settings file)."
    echo
    FIRMWARE_STATUS=$(t "slået fra" "switched off")
  elif ! command -v fwupdmgr &> /dev/null; then
    t "fwupd er ikke installeret — springer over.  (Installér med: sudo apt-get install fwupd)" \
      "fwupd is not installed. Skipping.  (Install with: sudo apt-get install fwupd)"
    echo
  elif [[ -n "${container}" && "${container}" != "none" ]]; then
    t "Kører i en container (${container}) — firmware opdateres på værtsmaskinen. Springer over." \
      "Running in a container (${container}); firmware is updated on the host. Skipping."
    echo
    FIRMWARE_STATUS=$(t "sprunget over (container: ${container})" "skipped (container: ${container})")
  else
    firmware_run
  fi
  echo ""
}

# ─── Step 8: security status ──────────────────────────────────────────────────

#######################################
# Reads the output of check-support-status:
#   "* Source:name, ended on DATE ..."  support ended (serious)
#   "* Source:name"                     limited support (for information)
# Globals:
#   SUPPORT_ENDED, SUPPORT_COUNT, SUPPORT_LIMITED, SUPPORT_ENDED_LIST (set)
# Arguments:
#   File with check-support-status output.
#######################################
parse_support_status() {
  local file=$1
  SUPPORT_ENDED=$(grep -c '^\* Source:.*, ended on ' "${file}")
  SUPPORT_COUNT=$(grep -c '^\* Source:' "${file}")
  SUPPORT_LIMITED=$(( SUPPORT_COUNT - SUPPORT_ENDED ))
  SUPPORT_ENDED_LIST=$(grep -oP '^\* Source:\K[^,]+(?=, ended on )' "${file}" | tr '\n' ' ' | sed 's/ $//')
}

#######################################
# Prints source package and reason for one kind of support problem.
# Arguments:
#   File with check-support-status output, "ended" or "limited".
# Outputs:
#   Two lines per package on STDOUT.
#######################################
print_support_details() {
  awk -v want="$2" '
    /^\* Source:/ { src = substr($0, 10); kind = (src ~ /, ended on /) ? "ended" : "limited" }
    /^  Details:/ && src != "" { if (kind == want) { print "  • " src; print "      " substr($0, 12) } src = "" }
  ' "$1"
}

#######################################
# Step 8: shows which installed packages Debian's security and LTS teams no
# longer (fully) fix, using debian-security-support. Otherwise you never find out.
# Globals:
#   OS_ID, OS_PRETTY, INSTALL_SECURITY_SUPPORT, APT_OPTS, TMP (read);
#   the SUPPORT_* state, ERRORS (set)
#######################################
step_security_status() {
  step "$(t "[8/8] Sikkerhedsstatus for ${OS_PRETTY}..." "[8/8] Security status for ${OS_PRETTY}...")"
  if [[ "${OS_ID}" != "debian" ]]; then
    t "Ikke et Debian-system — springer over." "Not a Debian system. Skipping."
    echo
    SUPPORT_STATUS=$(t "sprunget over (ikke Debian)" "skipped (not Debian)")
    return 0
  fi
  if ! dpkg-query -W -f='${Status}' debian-security-support 2>/dev/null | grep -q "install ok installed"; then
    if [[ "${INSTALL_SECURITY_SUPPORT}" == yes ]]; then
      t "Installerer debian-security-support (viser pakker uden sikkerhedssupport; slå fra med INSTALL_SECURITY_SUPPORT=no)..." \
        "Installing debian-security-support (shows packages without security support; switch off with INSTALL_SECURITY_SUPPORT=no)..."
      echo
      if ! apt-get "${APT_OPTS[@]}" install -y debian-security-support 2>&1; then
        warn "$(t "Kunne ikke installere debian-security-support." "Could not install debian-security-support.")"
        add_error
      fi
    else
      t "debian-security-support er ikke installeret (INSTALL_SECURITY_SUPPORT=no) — springer over." \
        "debian-security-support is not installed (INSTALL_SECURITY_SUPPORT=no). Skipping."
      echo
    fi
  fi
  if ! command -v check-support-status &> /dev/null; then
    if [[ "${INSTALL_SECURITY_SUPPORT}" == no ]]; then
      SUPPORT_STATUS=$(t "ikke installeret (INSTALL_SECURITY_SUPPORT=no)" "not installed (INSTALL_SECURITY_SUPPORT=no)")
    else
      SUPPORT_STATUS=$(t "ukendt (debian-security-support mangler)" "unknown (debian-security-support missing)")
    fi
    return 0
  fi
  check-support-status > "${TMP}/support.txt" 2>&1
  parse_support_status "${TMP}/support.txt"
  if (( SUPPORT_ENDED > 0 )); then
    echo -e "${YELLOW}$(t "Sikkerhedssupport er OPHØRT for (fjern dem, hvis du ikke bruger dem):" \
                          "Security support has ENDED for (remove them if you don't use them):")${NC}"
    print_support_details "${TMP}/support.txt" ended
  fi
  if (( SUPPORT_LIMITED > 0 )); then
    t "Begrænset sikkerhedssupport (typisk kun til betroet indhold):" \
      "Limited security support (usually only for trusted content):"
    echo
    print_support_details "${TMP}/support.txt" limited
  fi
  if (( SUPPORT_COUNT > 0 )); then
    t "Berørte pakker og detaljer: kør  check-support-status" \
      "Affected packages and details: run  check-support-status"
    echo
  fi
  if (( SUPPORT_ENDED > 0 )); then
    SUPPORT_STATUS=$(t "${SUPPORT_ENDED} UDEN support (${SUPPORT_ENDED_LIST}), ${SUPPORT_LIMITED} med begrænset" \
                       "${SUPPORT_ENDED} WITHOUT support (${SUPPORT_ENDED_LIST}), ${SUPPORT_LIMITED} limited")
    warn "$(t "Pakker uden sikkerhedssupport: ${SUPPORT_ENDED_LIST}" "Packages without security support: ${SUPPORT_ENDED_LIST}")"
  elif (( SUPPORT_LIMITED > 0 )); then
    SUPPORT_STATUS=$(t "ingen uden support, ${SUPPORT_LIMITED} med begrænset support" \
                       "none without support, ${SUPPORT_LIMITED} with limited support")
    ok "${SUPPORT_STATUS}"
  else
    SUPPORT_STATUS=$(t "alle installerede pakker er dækket" "all installed packages are covered")
    ok "${SUPPORT_STATUS}"
  fi
}

# ─── Status for the report ────────────────────────────────────────────────────

#######################################
# Days until the end of full support and of LTS, rounded towards zero.
# Globals:
#   RELEASE_KNOWN, REGULAR_END, LTS_END (read);
#   LTS_DAYS_LEFT, REGULAR_DAYS_LEFT (set; -1 when there is no REGULAR_END)
# Arguments:
#   "Now" in seconds since the epoch.
#######################################
compute_countdown() {
  local now=$1
  LTS_DAYS_LEFT=0
  REGULAR_DAYS_LEFT=-1
  if [[ "${RELEASE_KNOWN}" == true ]]; then
    LTS_DAYS_LEFT=$(( ($(date -d "${LTS_END}" +%s) - now) / 86400 ))
    if [[ -n "${REGULAR_END}" ]]; then
      REGULAR_DAYS_LEFT=$(( ($(date -d "${REGULAR_END}" +%s) - now) / 86400 ))
    fi
  fi
}

#######################################
# Summarises the nightly runs of unattended-upgrades in apt's history log. They
# usually install most security fixes at night, which is why a manual run often
# finds only a few.
# Globals:
#   UU_STATUS (set)
# Arguments:
#   Path of apt's history log (normally /var/log/apt/history.log).
#######################################
summarise_unattended_upgrades() {
  local log=$1 runs pkgs last
  runs=$(grep -c '^Commandline: /usr/bin/unattended-upgrade' "${log}" 2>/dev/null)
  pkgs=$(awk '/^Commandline: \/usr\/bin\/unattended-upgrade/ {f = 1; next}
              /^Start-Date/ {f = 0}
              f && /^Upgrade:/ {n += gsub(/\),/, "") + 1}
              END {print n + 0}' "${log}" 2>/dev/null)
  last=$(grep -B1 '^Commandline: /usr/bin/unattended-upgrade' "${log}" 2>/dev/null \
         | grep -oP '^Start-Date: \K\S+' | tail -1)
  UU_STATUS=$(t "aktiv — ${runs:-0} natlige kørsler / ${pkgs:-0} pakker i denne måneds log, senest ${last:-ukendt}" \
                "active — ${runs:-0} nightly runs / ${pkgs:-0} packages in this month's log, last ${last:-unknown}")
}

#######################################
# Lists the packages on hold (apt-mark); they get no updates, not even
# security fixes.
# Globals:
#   HELD_COUNT, HELD_SHOW (set)
#######################################
collect_holds() {
  HELD_COUNT=$(apt-mark showhold 2>/dev/null | grep -c .)
  HELD_SHOW=$(apt-mark showhold 2>/dev/null | head -8 | tr '\n' ' ' | sed 's/ $//')
  if (( HELD_COUNT > 8 )); then
    HELD_SHOW="${HELD_SHOW} … (+$(( HELD_COUNT - 8 )) $(t "flere" "more"))"
  fi
}

#######################################
# Decides whether a restart is needed: the reboot-required flag file, a newer
# installed kernel than the running one (the flag file is only created by some
# packages), or a firmware update that completes at the next boot.
# Globals:
#   FW_REBOOT (read); REBOOT_NEEDED, REBOOT_REASON (set)
#######################################
check_reboot() {
  local running newest=""
  local kernels=(/boot/vmlinuz-*)
  REBOOT_NEEDED=false
  REBOOT_REASON=""
  if [[ -f /var/run/reboot-required ]]; then
    REBOOT_NEEDED=true
    REBOOT_REASON=$(t "systemet har markeret, at en genstart er påkrævet" "the system has flagged that a restart is required")
  fi
  running=$(uname -r)
  if [[ -e "${kernels[0]}" ]]; then
    newest=$(printf '%s\n' "${kernels[@]#/boot/vmlinuz-}" | sort -V | tail -1)
  fi
  if [[ -n "${newest}" && "${newest}" != "${running}" ]]; then
    REBOOT_NEEDED=true
    REBOOT_REASON=$(t "kører kerne ${running}, men nyeste installerede er ${newest}" \
                      "running kernel ${running}, but the newest installed is ${newest}")
  fi
  if [[ "${FW_REBOOT}" == true ]]; then
    REBOOT_NEEDED=true
    REBOOT_REASON=$(t "en firmware-opdatering fuldføres først ved genstart" "a firmware update only completes after a restart")
  fi
}

#######################################
# Collects everything the report needs beyond the step results.
# Globals:
#   START_EPOCH (read); countdown, UU_STATUS, holds, reboot state,
#   ROOT_FREE_H_AFTER, END_TIME, DURATION_H (set)
#######################################
collect_status() {
  local duration
  compute_countdown "$(date +%s)"
  if dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q "install ok installed" \
      && systemctl is-enabled apt-daily-upgrade.timer &> /dev/null; then
    summarise_unattended_upgrades /var/log/apt/history.log
  fi
  echo ""
  collect_holds
  check_reboot
  ROOT_FREE_H_AFTER=$(df -h / | awk 'NR==2 {print $4}')
  END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
  duration=$(( $(date +%s) - START_EPOCH ))
  DURATION_H="$(( duration / 60 ))m $(( duration % 60 ))s"
}

# ─── Report ───────────────────────────────────────────────────────────────────

#######################################
# Prints the final report.
# Globals:
#   The report state (read).
# Outputs:
#   The report on STDOUT.
#######################################
print_report() {
  echo ""
  line
  echo -e "${CYAN}${BOLD}  $(t "RAPPORT" "REPORT")  │  ${END_TIME}  │  $(t "varighed" "duration") ${DURATION_H}${NC}"
  line
  if [[ "${SOURCES_STATUS}" == "OK" ]]; then
    row "$(t "Pakkekilder:" "Package sources:")" "OK"
  else
    rowc "$(t "Pakkekilder:" "Package sources:")" "${RED}" "${SOURCES_STATUS}"
  fi
  row "$(t "Pakker opgraderet:" "Packages upgraded:")" "${APT_UPGRADED}"
  row "$(t "Pakker nyinstalleret:" "Packages newly installed:")" "${APT_INSTALLED}"
  row "$(t "Pakker fjernet:" "Packages removed:")" "$(( APT_REMOVED + AUTOREMOVED ))"
  if (( APT_KEPT > 0 )); then
    rowc "$(t "Pakker holdt tilbage:" "Packages kept back:")" "${YELLOW}" "${APT_KEPT} — ${KEPT_LIST}"
  else
    row "$(t "Pakker holdt tilbage:" "Packages kept back:")" "0"
  fi
  if (( HELD_COUNT > 0 )); then
    rowc "$(t "Fastholdte pakker (hold):" "Packages on hold:")" "${YELLOW}" "${HELD_COUNT} — ${HELD_SHOW}"
  else
    row "$(t "Fastholdte pakker (hold):" "Packages on hold:")" "0"
  fi
  if [[ "${FLATPAK_INSTALLED}" == true ]]; then
    row "$(t "Flatpak-apps opdateret:" "Flatpak apps updated:")" \
        "${FP_APP_UPD}  ($(t "nye" "new"): ${FP_APP_NEW}, $(t "fjernet" "removed"): ${FP_APP_REM})"
    row "$(t "Flatpak-runtimes opdateret:" "Flatpak runtimes updated:")" \
        "${FP_RT_UPD}  ($(t "nye" "new"): ${FP_RT_NEW}, $(t "fjernet" "removed"): ${FP_RT_REM})"
  else
    row "Flatpak:" "$(t "ikke installeret" "not installed")"
  fi
  row "Firmware:" "${FIRMWARE_STATUS}"
  if (( SUPPORT_ENDED > 0 )); then
    rowc "$(t "Sikkerhedssupport:" "Security support:")" "${YELLOW}" "${SUPPORT_STATUS}"
  else
    row "$(t "Sikkerhedssupport:" "Security support:")" "${SUPPORT_STATUS}"
  fi
  row "$(t "Automatiske opdateringer:" "Automatic updates:")" "${UU_STATUS}"
  row "$(t "Diskplads ledig:" "Free disk space:")" "${ROOT_FREE_H_AFTER}"
  if (( ERRORS > 0 )); then
    rowc "$(t "Fejl:" "Errors:")" "${RED}${BOLD}" "${ERRORS} — $(t "tjek log for detaljer" "check the log for details")"
  else
    rowc "$(t "Fejl:" "Errors:")" "${GREEN}${BOLD}" "$(t "Ingen" "None")"
  fi
  line
}

#######################################
# Prints how long the release gets security updates: both phases while full
# support lasts, a note a month before LTS starts (LTS does not cover every
# package), and yellow/red warnings towards the end.
# Globals:
#   OS_VERSION_ID, OS_PRETTY, RELEASE_KNOWN, REGULAR_END, LTS_END, the
#   countdown, LTS_WARN_DAYS, LTS_ALARM_DAYS, LTS_END_NOTE, DATE_SOURCE (read)
# Outputs:
#   The support clock on STDOUT.
#######################################
print_support_clock() {
  local label="Debian ${OS_VERSION_ID}"
  echo ""
  if [[ "${RELEASE_KNOWN}" != true ]]; then
    echo -e "  🗓  $(t "Support-ur: ingen datoer for ${OS_PRETTY} (se DEBIAN_RELEASES øverst i scriptet)." \
                    "Support clock: no dates for ${OS_PRETTY} (see DEBIAN_RELEASES at the top of the script).")"
    return 0
  fi
  if (( LTS_DAYS_LEFT < 0 )); then
    echo -e "${RED}${BOLD}  ✗  ${label^^}: $(t "SIKKERHEDSSUPPORT SLUTTEDE ${LTS_END} — for $(( -LTS_DAYS_LEFT )) dage siden." \
                                              "SECURITY SUPPORT ENDED ${LTS_END}, $(( -LTS_DAYS_LEFT )) days ago.")${NC}"
    echo -e "${RED}     $(t "Systemet får IKKE længere sikkerhedsopdateringer." "This system NO LONGER gets security updates.")${NC}"
    echo -e "${RED}     ${LTS_END_NOTE}${NC}"
  elif (( LTS_DAYS_LEFT <= LTS_ALARM_DAYS )); then
    echo -e "${RED}${BOLD}  ⚠  ${label^^}: $(t "SIKKERHEDSSUPPORT SLUTTER OM ${LTS_DAYS_LEFT} DAGE (${LTS_END})!" \
                                              "SECURITY SUPPORT ENDS IN ${LTS_DAYS_LEFT} DAYS (${LTS_END})!")${NC}"
    echo -e "${RED}     $(t "Herefter kommer der ingen sikkerhedsopdateringer." "After that there will be no security updates.")${NC}"
    echo -e "${RED}     ${LTS_END_NOTE}${NC}"
  elif (( LTS_DAYS_LEFT <= LTS_WARN_DAYS )); then
    echo -e "${YELLOW}${BOLD}  ⚠  ${label}: $(t "sikkerhedssupport slutter om ${LTS_DAYS_LEFT} dage (${LTS_END}). Planlæg nu." \
                                                "security support ends in ${LTS_DAYS_LEFT} days (${LTS_END}). Plan now.")${NC}"
    echo -e "${YELLOW}     ${LTS_END_NOTE}${NC}"
  elif (( REGULAR_DAYS_LEFT >= 0 )); then
    echo -e "  🗓  ${label}: $(t "fuld sikkerhedssupport til ${REGULAR_END} (${REGULAR_DAYS_LEFT} dage), derefter LTS til ${LTS_END}" \
                               "full security support until ${REGULAR_END} (${REGULAR_DAYS_LEFT} days), then LTS until ${LTS_END}") — ${BOLD}${LTS_DAYS_LEFT} $(t "dage tilbage" "days left")${NC}"
    if (( REGULAR_DAYS_LEFT <= LTS_WARN_DAYS )); then
      echo -e "${YELLOW}     $(t "Om ${REGULAR_DAYS_LEFT} dage går ${label} over til LTS: ikke alle pakker dækkes. Trin 8 viser hvilke." \
                              "In ${REGULAR_DAYS_LEFT} days ${label} moves to LTS: not all packages are covered. Step 8 shows which.")${NC}"
    fi
  else
    echo -e "  🗓  ${label} LTS: $(t "sikkerhedsopdateringer til ${LTS_END}" "security updates until ${LTS_END}") — ${BOLD}${LTS_DAYS_LEFT} $(t "dage tilbage" "days left")${NC}"
  fi
  if [[ -n "${DATE_SOURCE}" ]]; then
    echo "     $(t "Datoer fra" "Dates from"): ${DATE_SOURCE}"
  fi
}

#######################################
# Prints the restart notice (when needed) and the path of the log.
# Globals:
#   REBOOT_NEEDED, REBOOT_REASON, LOG_FILE (read)
# Outputs:
#   The notice on STDOUT.
#######################################
print_footer() {
  if [[ "${REBOOT_NEEDED}" == true ]]; then
    echo ""
    echo -e "${YELLOW}${BOLD}  ⚠  $(t "GENSTART PÅKRÆVET" "RESTART REQUIRED")${NC}"
    echo -e "${YELLOW}     ${REBOOT_REASON}.${NC}"
    echo -e "${YELLOW}     $(t "Kør" "Run"): sudo reboot${NC}"
  fi
  echo ""
  echo -e "  📋 $(t "Fuld log" "Full log"): ${BOLD}${LOG_FILE}${NC}"
  echo ""
}

#######################################
# Waits for ENTER in interactive runs and exits. tee closes by itself when the
# script ends (no wait on it: bash keeps one end of the pipe open, so a wait
# would hang forever).
# Globals:
#   AUTO, ERRORS (read)
# Returns:
#   Exits 0 without errors, otherwise 1.
#######################################
finish() {
  if [[ "${AUTO}" != true ]]; then
    read -r -p "$(t "Tryk ENTER for at afslutte..." "Press ENTER to exit...")" _
  fi
  if (( ERRORS == 0 )); then
    exit 0
  fi
  exit 1
}

main() {
  detect_language
  parse_options "$@"
  require_root
  load_settings
  detect_release /etc/os-release
  lookup_support_dates
  setup_mode
  start_log
  init_counters
  print_header
  check_disk_space
  step_repair
  step_update_lists
  step_full_upgrade
  step_flatpak
  step_autoremove
  step_clean_cache
  step_firmware
  step_security_status
  collect_status
  print_report
  print_support_clock
  print_footer
  finish
}

# The unit tests source this file to reach its functions; then main must not run.
if (return 0 2>/dev/null); then
  return 0
fi
main "$@"
