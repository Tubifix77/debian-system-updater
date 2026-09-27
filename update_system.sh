#!/bin/bash
# Debian System Updater v1.4
# Complete maintenance of Debian 12 and 13 with coloured output, a log and a final report.
# The script detects the Debian release and the language (Danish or English) by itself.
#
# Usage:
#   sudo bash update_system.sh                 # interactive, waits for ENTER at the end
#   sudo bash update_system.sh --auto          # non-interactive, for cron / automation
#   sudo bash update_system.sh --lang=en       # force the language (da or en)
#   bash update_system.sh --help
#
# Changes: see CHANGELOG.md

# ─── Settings ─────────────────────────────────────────────────────────────────
LOG_FILE="/var/log/debian-updater.log"
LOG_MAX_BYTES=5242880   # rotate the log (to .1) when it exceeds 5 MB
LTS_WARN_DAYS=30        # yellow warning at this many days left (or fewer)
LTS_ALARM_DAYS=7        # red alarm at this many days left (or fewer)
LTS_END_NOTE=""         # your own reminder next to the warnings (empty = built-in text)
UI_LANG=""              # da or en (empty = follow the system language)

# Support dates per Debian release. Add a line when a new release comes out.
# Sources: https://www.debian.org/releases/<codename>/ and https://wiki.debian.org/LTS
# (for bookworm the release page says full support until 2026-07-11, while the LTS
#  wiki gives LTS from 2026-06-11; the end date 2028-06-30 is the same in both).
#   version  codename   full support until   LTS until
DEBIAN_RELEASES="
12 bookworm 2026-07-11 2028-06-30
13 trixie   2028-08-09 2030-06-30
"

# Personal settings (for example LTS_END_NOTE or UI_LANG) can go in this optional
# file, so they survive when the script is updated.
CONFIG_FILE="/etc/default/debian-system-updater"

# ─── Colours and helpers ──────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
fail() { echo -e "${RED}✗ $*${NC}"; }
step() { echo -e "${BOLD}$*${NC}"; }
line() { echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"; }
row()  { printf "  %-32s %s\n" "$1" "$2"; }                        # label, value
rowc() { echo -e "  $(printf '%-32s' "$1") ${2}${3}${NC}"; }        # label, colour, value

# ─── Language ─────────────────────────────────────────────────────────────────
# Danish when the system language is Danish, otherwise English. Read before
# LC_ALL is overridden below. Can be forced with --lang or UI_LANG in the settings file.
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
    da*) DETECTED_LANG=da ;;
    *)   DETECTED_LANG=en ;;
esac
UI_LANG=${UI_LANG:-$DETECTED_LANG}
L() { if [ "$UI_LANG" = da ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }   # L "dansk" "english"

usage() {
    if [ "$UI_LANG" = da ]; then
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

# ─── Options ──────────────────────────────────────────────────────────────────
AUTO=false; CLI_LANG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --auto)    AUTO=true ;;
        --lang=*)  CLI_LANG=${1#--lang=} ;;
        --lang)    shift; CLI_LANG=${1:-} ;;
        -h|--help) [ -n "$CLI_LANG" ] && UI_LANG=$CLI_LANG; usage; exit 0 ;;
        *)         echo "$(L "Ukendt tilvalg: $1" "Unknown option: $1")" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
case "$CLI_LANG" in
    ""|da|en) ;;
    *) echo "$(L "--lang skal være da eller en" "--lang must be da or en")" >&2; exit 2 ;;
esac
[ -n "$CLI_LANG" ] && UI_LANG=$CLI_LANG

# ─── Root check ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}$(L "Fejl: Dette script skal køres med sudo!" "Error: this script must be run with sudo!")${NC}"
    exit 1
fi

# ─── Which Debian release? ────────────────────────────────────────────────────
# Read in a subshell so os-release cannot overwrite the script's own variables.
IFS='|' read -r OS_ID OS_VERSION_ID OS_PRETTY < <(
    . /etc/os-release 2>/dev/null
    printf '%s|%s|%s\n' "${ID:-}" "${VERSION_ID:-}" "${PRETTY_NAME:-}"
)
RELEASE_KNOWN=false; REGULAR_END=""; LTS_END=""
if [ "$OS_ID" = "debian" ]; then
    REL_LINE=$(awk -v v="$OS_VERSION_ID" '$1 == v' <<< "$DEBIAN_RELEASES")
    if [ -n "$REL_LINE" ]; then
        read -r _ _ REGULAR_END LTS_END <<< "$REL_LINE"
    fi
fi
# Personal settings are read last so they can override everything above
# (including REGULAR_END and LTS_END for a release that is not in the table).
# A --lang option still wins over UI_LANG from the file.
# shellcheck source=/dev/null
[ -r "$CONFIG_FILE" ] && . "$CONFIG_FILE"
[ -n "$CLI_LANG" ] && UI_LANG=$CLI_LANG
case "$UI_LANG" in da|en) ;; *) UI_LANG=$DETECTED_LANG ;; esac
[ -n "$LTS_END" ] && RELEASE_KNOWN=true
OS_PRETTY=${OS_PRETTY:-$(L "ukendt system" "unknown system")}
[ -z "$LTS_END_NOTE" ] && LTS_END_NOTE=$(L "Planlæg skiftet til den næste Debian-udgave i god tid: https://www.debian.org/releases/" \
                                            "Plan the move to the next Debian release in good time: https://www.debian.org/releases/")

# ─── Mode ─────────────────────────────────────────────────────────────────────
# apt, dpkg and flatpak must answer in English, otherwise the report cannot count
# anything: with a Danish system language v1.1 always showed "0 packages upgraded".
# The script's own messages follow UI_LANG.
export LC_ALL=C.UTF-8

# In --auto mode nobody is at the keyboard. Without this, a debconf question or a
# config-file conflict would make the run hang forever. With it, dpkg/debconf pick
# the safe default answer: keep the current config file (the new one is saved next
# to it as *.dpkg-dist). Interactive runs ask as usual.
APT_OPTS=()
if $AUTO; then
    export DEBIAN_FRONTEND=noninteractive
    APT_OPTS=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
fi

# ─── Log ──────────────────────────────────────────────────────────────────────
if [ -f "$LOG_FILE" ] && [ "$(stat -c %s "$LOG_FILE")" -gt "$LOG_MAX_BYTES" ]; then
    mv -f "$LOG_FILE" "$LOG_FILE.1"
fi
START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
START_EPOCH=$(date +%s)

# All output (stdout + stderr) goes to the screen and the log file in real time
exec > >(tee -a "$LOG_FILE") 2>&1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ─── Counters ─────────────────────────────────────────────────────────────────
ERRORS=0
SOURCES_STATUS="OK"
APT_UPGRADED=0; APT_INSTALLED=0; APT_REMOVED=0; APT_KEPT=0; KEPT_LIST=""
AUTOREMOVED=0
FP_APP_UPD=0; FP_APP_NEW=0; FP_APP_REM=0
FP_RT_UPD=0;  FP_RT_NEW=0;  FP_RT_REM=0
FLATPAK_INSTALLED=false
FIRMWARE_STATUS=$(L "fwupd ikke installeret" "fwupd not installed")
SUPPORT_STATUS=$(L "ukendt" "unknown"); SUPPORT_COUNT=0; SUPPORT_ENDED=0; SUPPORT_LIMITED=0
UU_STATUS=$(L "ikke aktiv" "not active")

# ─── Header ───────────────────────────────────────────────────────────────────
echo ""
line
echo -e "${CYAN}${BOLD}  Debian System Updater v1.4  │  ${START_TIME}    ${NC}"
echo -e "${CYAN}${BOLD}  ${OS_PRETTY}${NC}"
line
echo ""
if [ "$OS_ID" != "debian" ]; then
    warn "$(L "Scriptet er lavet til Debian 12 og 13, men systemet er: ${OS_PRETTY}." \
              "This script is made for Debian 12 and 13, but this system is: ${OS_PRETTY}.")"
    warn "$(L "Fortsætter med apt, Flatpak og firmware; sikkerhedsstatus og support-ur springes over." \
              "Continuing with apt, Flatpak and firmware; security status and the support clock are skipped.")"
    echo ""
elif ! $RELEASE_KNOWN; then
    warn "$(L "${OS_PRETTY} står ikke i scriptets datotabel (DEBIAN_RELEASES) — alt andet kører, men support-uret vises ikke." \
              "${OS_PRETTY} is not in the script's date table (DEBIAN_RELEASES). Everything else runs, but the support clock is not shown.")"
    echo ""
fi

# ─── Disk space pre-check ─────────────────────────────────────────────────────
# Stops below 1 GB, warns below 2 GB
ROOT_FREE_KB=$(df / | awk 'NR==2 {print $4}')
ROOT_FREE_H=$(df -h / | awk 'NR==2 {print $4}')

if [ "$ROOT_FREE_KB" -lt 1048576 ]; then
    fail "$(L "Diskplads kritisk: ${ROOT_FREE_H} ledig. Afbryder for at undgå skade." \
              "Disk space critical: ${ROOT_FREE_H} free. Stopping to avoid damage.")"
    exit 1
elif [ "$ROOT_FREE_KB" -lt 2097152 ]; then
    warn "$(L "Lav diskplads: ${ROOT_FREE_H} ledig — fortsætter med forsigtighed." \
              "Low disk space: ${ROOT_FREE_H} free. Continuing carefully.")"
else
    ok "$(L "Diskplads OK: ${ROOT_FREE_H} ledig" "Disk space OK: ${ROOT_FREE_H} free")"
fi
echo ""

# ─── Step 1: Repair package dependencies ──────────────────────────────────────
step "$(L "[1/8] Reparerer pakke-afhængigheder..." "[1/8] Repairing package dependencies...")"
dpkg --configure -a || {
    fail "$(L "dpkg --configure -a fejlede. Afslutter." "dpkg --configure -a failed. Stopping.")"; exit 1
}
apt-get "${APT_OPTS[@]}" --fix-broken install -y || {
    fail "$(L "fix-broken fejlede. Afslutter." "fix-broken failed. Stopping.")"; exit 1
}
ok "$(L "Færdig" "Done")"; echo ""

# ─── Step 2: Update package lists ─────────────────────────────────────────────
step "$(L "[2/8] Opdaterer pakkelister..." "[2/8] Updating package lists...")"
# Error-Mode=any: a package source that cannot be fetched (for example a network
# error) counts as an error. Plain apt only warns and returns 0, so v1.1 showed a
# green tick even when the security archive was not fetched.
apt-get update -o APT::Update::Error-Mode=any 2>&1 | tee "$TMP/update.txt"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    fail "$(L "En eller flere pakkekilder kunne ikke hentes — fortsætter med de pakkelister, der findes:" \
              "One or more package sources could not be fetched. Continuing with the package lists available:")"
    grep -E '^(W|E): ' "$TMP/update.txt" | sed 's/^/    /'
    SOURCES_STATUS=$(L "FEJL — en eller flere kilder blev ikke hentet (se log)" \
                       "ERROR — one or more sources were not fetched (see log)")
    ((ERRORS++))
else
    ok "$(L "Pakkelister opdateret" "Package lists updated")"
fi
echo ""

# ─── Step 3: Full system upgrade ──────────────────────────────────────────────
step "$(L "[3/8] Fuld systemopgradering..." "[3/8] Full system upgrade...")"
apt-get "${APT_OPTS[@]}" full-upgrade -y 2>&1 | tee "$TMP/upgrade.txt"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    fail "$(L "Opgradering fejlede. Afslutter." "Upgrade failed. Stopping.")"; ((ERRORS++)); exit 1
fi
# apt's summary line: "N upgraded, N newly installed, N to remove and N not upgraded."
APT_UPGRADED=$(grep -oP '\d+(?= upgraded,)'        "$TMP/upgrade.txt" | tail -1)
APT_INSTALLED=$(grep -oP '\d+(?= newly installed)' "$TMP/upgrade.txt" | tail -1)
APT_REMOVED=$(grep -oP '\d+(?= to remove)'         "$TMP/upgrade.txt" | tail -1)
APT_KEPT=$(grep -oP '\d+(?= not upgraded)'         "$TMP/upgrade.txt" | tail -1)
APT_UPGRADED=${APT_UPGRADED:-0}; APT_INSTALLED=${APT_INSTALLED:-0}
APT_REMOVED=${APT_REMOVED:-0};   APT_KEPT=${APT_KEPT:-0}
# Packages apt did NOT upgrade, typically because they are on hold (apt-mark).
# A package on hold gets no security fixes either, so this must be visible.
KEPT_LIST=$(awk '/^The following packages have been kept back:/ {f=1; next}
                 f && /^[^ ]/ {f=0}
                 f {printf "%s ", $0}' "$TMP/upgrade.txt" | tr -s ' ' | sed 's/^ //; s/ $//')
if [ "$APT_KEPT" -gt 0 ]; then
    warn "$(L "$APT_KEPT pakke(r) blev holdt tilbage og fik IKKE opdateringer: $KEPT_LIST" \
              "$APT_KEPT package(s) were kept back and did NOT get updates: $KEPT_LIST")"
    L "   Se hvilke pakker der er på hold med: apt-mark showhold" \
      "   See which packages are on hold with: apt-mark showhold"; echo
fi
ok "$(L "Opgradering fuldført" "Upgrade complete")"; echo ""

# ─── Step 4: Flatpak ──────────────────────────────────────────────────────────
step "$(L "[4/8] Flatpak-apps..." "[4/8] Flatpak apps...")"
if command -v flatpak &> /dev/null; then
    FLATPAK_INSTALLED=true
    # Snapshot before/after (ref + active commit). Changed commit = updated,
    # new ref = installed, missing ref = removed. Independent of language and of
    # flatpak's screen output (v1.1 counted line numbers and missed number 10 and up).
    fp_snapshot() { flatpak list "$1" --columns=ref,active 2>/dev/null | sort -t $'\t' -k1,1; }
    fp_count() {   # $1 = before, $2 = after  ->  "updated new removed"
        local upd new rem
        upd=$(join -t $'\t' "$1" "$2" | awk -F'\t' '$2 != $3' | wc -l)
        new=$(join -t $'\t' -v2 "$1" "$2" | wc -l)
        rem=$(join -t $'\t' -v1 "$1" "$2" | wc -l)
        echo "$upd $new $rem"
    }
    fp_snapshot --app     > "$TMP/app_before.txt"
    fp_snapshot --runtime > "$TMP/rt_before.txt"

    flatpak update -y --noninteractive 2>&1 | tee "$TMP/flatpak.txt"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        warn "$(L "Flatpak returnerede en fejl." "Flatpak returned an error.")"; ((ERRORS++))
    fi

    fp_snapshot --app     > "$TMP/app_after.txt"
    fp_snapshot --runtime > "$TMP/rt_after.txt"
    read -r FP_APP_UPD FP_APP_NEW FP_APP_REM < <(fp_count "$TMP/app_before.txt" "$TMP/app_after.txt")
    read -r FP_RT_UPD  FP_RT_NEW  FP_RT_REM  < <(fp_count "$TMP/rt_before.txt"  "$TMP/rt_after.txt")

    # Components Flathub has declared end-of-life get no more updates
    FP_EOL=$(flatpak list --all --columns=ref,options 2>/dev/null | awk -F'\t' '$2 ~ /eol/ {print $1}' | tr '\n' ' ')
    [ -n "$FP_EOL" ] && warn "$(L "Flatpak-komponenter der er end-of-life (ingen opdateringer mere): $FP_EOL" \
                                  "Flatpak components that are end-of-life (no more updates): $FP_EOL")"
    ok "$(L "Flatpak tjekket" "Flatpak checked")"
else
    L "Flatpak er ikke installeret — springer over." "Flatpak is not installed. Skipping."; echo
fi
echo ""

# ─── Step 5: Remove unused packages ───────────────────────────────────────────
step "$(L "[5/8] Fjerner ubrugte pakker..." "[5/8] Removing unused packages...")"
apt-get "${APT_OPTS[@]}" autoremove --purge -y 2>&1 | tee "$TMP/autoremove.txt"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    warn "$(L "autoremove returnerede en fejl. Fortsætter..." "autoremove returned an error. Continuing...")"; ((ERRORS++))
fi
AUTOREMOVED=$(grep -oP '\d+(?= to remove)' "$TMP/autoremove.txt" | tail -1)
AUTOREMOVED=${AUTOREMOVED:-0}
ok "$(L "Oprydning fuldført" "Cleanup complete")"; echo ""

# ─── Step 6: Clear the package cache ──────────────────────────────────────────
step "$(L "[6/8] Rydder pakke-cache..." "[6/8] Clearing the package cache...")"
apt-get clean || {
    warn "$(L "Cache-oprydning fejlede. Fortsætter..." "Cache cleanup failed. Continuing...")"; ((ERRORS++))
}
ok "$(L "Cache ryddet" "Cache cleared")"; echo ""

# ─── Step 7: Firmware (fwupd) ─────────────────────────────────────────────────
step "$(L "[7/8] Firmware-opdateringer (fwupd)..." "[7/8] Firmware updates (fwupd)...")"
# In a container (WSL, Docker, LXC ...) the fwupd service never starts (its unit
# has ConditionVirtualization=!container); the firmware belongs to the host.
# Same test systemd uses; otherwise fwupdmgr waits 25 seconds in vain.
FW_CONTAINER=$(systemd-detect-virt --container 2>/dev/null)
if command -v fwupdmgr &> /dev/null && [ -n "$FW_CONTAINER" ] && [ "$FW_CONTAINER" != "none" ]; then
    L "Kører i en container ($FW_CONTAINER) — firmware opdateres på værtsmaskinen. Springer over." \
      "Running in a container ($FW_CONTAINER); firmware is updated on the host. Skipping."; echo
    FIRMWARE_STATUS=$(L "sprunget over (container: $FW_CONTAINER)" "skipped (container: $FW_CONTAINER)")
elif command -v fwupdmgr &> /dev/null; then
    # --no-unreported-check: never send reports to LVFS on its own
    # --no-metadata-check:   metadata is refreshed explicitly right below
    # --no-reboot-check:     never ask for or start a reboot; the report says so
    # fwupdmgr uses exit code 2 for "nothing to do"; that is not an error.
    FW_FLAGS=(-y --no-unreported-check --no-metadata-check)
    FW_NOTE=""
    # Metadata (which firmware versions exist) comes from LVFS. Debian's
    # fwupd-refresh.timer also does this daily, but hides errors; here they show.
    fwupdmgr refresh "${FW_FLAGS[@]}" 2>&1 | tee "$TMP/fw_refresh.txt"
    FW_REFRESH_RC=${PIPESTATUS[0]}
    if [ "$FW_REFRESH_RC" -ne 0 ] && [ "$FW_REFRESH_RC" -ne 2 ]; then
        warn "$(L "Firmware-metadata fra LVFS kunne ikke hentes (kode $FW_REFRESH_RC) — tjekker med de data, der allerede findes." \
                  "Firmware metadata from LVFS could not be fetched (code $FW_REFRESH_RC). Checking with the data already present.")"
        FW_NOTE=$(L " (metadata kunne ikke hentes — se log)" " (metadata could not be fetched, see log)"); ((ERRORS++))
    fi
    # Full output goes to a temp file; the screen shows one line per device.
    # (fwupd colours its text even in files; the colour codes are removed before parsing)
    fwupdmgr get-updates "${FW_FLAGS[@]}" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$TMP/fw.txt"
    FW_RC=${PIPESTATUS[0]}
    case "$FW_RC" in
        0)  # at least one device has an update on LVFS
            # Hardware check: is Secure Boot on? Updates to the Secure Boot lists
            # (db/dbx) mean nothing while Secure Boot is off, and on older machines
            # they often cannot be installed (too little space in the UEFI variable store).
            SB_STATE="unknown"
            SB_VAR=$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | head -1)
            if [ -n "$SB_VAR" ]; then
                case "$(od -An -tu1 -j4 -N1 "$SB_VAR" 2>/dev/null | tr -d ' ')" in
                    1) SB_STATE="on" ;;
                    0) SB_STATE="off" ;;
                esac
            fi
            # One line per device: name, current version, new version, any rejection by the firmware
            awk '
                function flush() { if (name != "") printf "%s\t%s\t%s\t%s\n", name, cur, new, err }
                /^[│ ]*[├└]─[^:]+:$/ { hdr = $0; sub(/^[│ ]*[├└]─/, "", hdr); sub(/:$/, "", hdr); next }
                /Device ID:/       { flush(); name = hdr; cur = ""; new = ""; err = ""; next }
                /Current version:/ { if (name != "" && cur == "") { cur = $0; sub(/.*Current version: */, "", cur) }; next }
                /New version:/     { if (name != "" && new == "") { new = $0; sub(/.*New version: */, "", new) }; next }
                /Update Error:/    { if (name != "") { err = $0; sub(/.*Update Error: */, "", err) }; next }
                END { flush() }
            ' "$TMP/fw.txt" > "$TMP/fw_devices.tsv"
            FW_DEVICES=$(grep -c . "$TMP/fw_devices.tsv")
            FW_BLOCKED=$(awk -F'\t' '$4 != ""' "$TMP/fw_devices.tsv" | wc -l)
            FW_BLOCKED_SB=$(awk -F'\t' '$4 != "" && $1 ~ /UEFI dbx|UEFI CA|UEFI db|KEK|PCA|Signature Database/' "$TMP/fw_devices.tsv" | wc -l)
            FW_READY=$((FW_DEVICES - FW_BLOCKED))
            FW_REASON=$(awk -F'\t' '$4 != "" {print $4}' "$TMP/fw_devices.tsv" | sed 's/,.*//' | sort -u | paste -sd ';')
            awk -F'\t' -v rej="$(L "afvist af firmwaren" "rejected by the firmware")" '
                { line = "  • " $1 ": " ($2 == "" ? "?" : $2) " → " ($3 == "" ? "?" : $3)
                  if ($4 != "") line = line "  (" rej ": " $4 ")"
                  print line }' "$TMP/fw_devices.tsv"
            FIRMWARE_STATUS=""
            if [ "$FW_DEVICES" -eq 0 ]; then
                cat "$TMP/fw.txt"
                FIRMWARE_STATUS=$(L "opdateringer fundet, men output kunne ikke tolkes — se log" \
                                    "updates found, but the output could not be parsed (see log)")
                warn "$FIRMWARE_STATUS"
            fi
            # Only install what the firmware will actually accept
            if [ "$FW_READY" -gt 0 ]; then
                fwupdmgr update "${FW_FLAGS[@]}" --no-reboot-check 2>&1 | tee "$TMP/fw_update.txt"
                FW_UPD_RC=${PIPESTATUS[0]}
                if grep -q 'Successfully installed firmware' "$TMP/fw_update.txt"; then
                    FIRMWARE_STATUS=$(L "$FW_READY enhed(er) opdateret — se log" "$FW_READY device(s) updated (see log)")
                    ok "$(L "Firmware opdateret" "Firmware updated")"
                    FW_REBOOT=true
                elif [ "$FW_UPD_RC" -eq 0 ] || [ "$FW_UPD_RC" -eq 2 ]; then
                    FIRMWARE_STATUS=$(L "$FW_READY enhed(er) har opdateringer, men de blev ikke installeret — se log" \
                                        "$FW_READY device(s) have updates, but they were not installed (see log)")
                    warn "$FIRMWARE_STATUS"
                else
                    FIRMWARE_STATUS=$(L "FEJL ved opdatering (kode $FW_UPD_RC)" "ERROR during update (code $FW_UPD_RC)")
                    fail "$(L "Firmware-opdatering fejlede (kode $FW_UPD_RC)." "Firmware update failed (code $FW_UPD_RC).")"; ((ERRORS++))
                fi
            fi
            # Devices the firmware rejects
            if [ "$FW_BLOCKED" -gt 0 ]; then
                if [ "$FW_BLOCKED_SB" -eq "$FW_BLOCKED" ] && [ "$SB_STATE" = "off" ]; then
                    FW_BLOCKED_NOTE=$(L "ingen relevante (Secure Boot-lister kan ikke opdateres, og Secure Boot er slået fra)" \
                                        "none relevant (Secure Boot lists cannot be updated, and Secure Boot is off)")
                    L "  Secure Boot er slået fra på denne maskine, så de manglende db/dbx-opdateringer er uden betydning." \
                      "  Secure Boot is off on this machine, so the missing db/dbx updates do not matter."; echo
                    ok "$(L "Firmware tjekket" "Firmware checked")"
                else
                    FW_BLOCKED_NOTE=$(L "$FW_BLOCKED enhed(er) kan ikke opdateres: ${FW_REASON:-se log}" \
                                        "$FW_BLOCKED device(s) cannot be updated: ${FW_REASON:-see log}")
                    if [ "$FW_BLOCKED_SB" -gt 0 ] && [ "$SB_STATE" = "on" ]; then
                        FW_BLOCKED_NOTE="$FW_BLOCKED_NOTE$(L " — Secure Boot er slået TIL, så det bør undersøges" \
                                                             " — Secure Boot is ON, so this should be looked into")"
                    fi
                    warn "$FW_BLOCKED_NOTE"
                fi
                FIRMWARE_STATUS="${FIRMWARE_STATUS:+$FIRMWARE_STATUS; }$FW_BLOCKED_NOTE"
            fi
            [ -z "$FIRMWARE_STATUS" ] && FIRMWARE_STATUS=$(L "ingen opdateringer tilgængelige" "no updates available")
            FIRMWARE_STATUS="$FIRMWARE_STATUS$FW_NOTE" ;;
        2)
            FIRMWARE_STATUS="$(L "ingen opdateringer tilgængelige" "no updates available")${FW_NOTE}"
            ok "$(L "Firmware er ajour" "Firmware is up to date")" ;;
        *)
            FIRMWARE_STATUS=$(L "FEJL (kode $FW_RC)" "ERROR (code $FW_RC)")
            warn "$(L "fwupdmgr get-updates fejlede (kode $FW_RC)." "fwupdmgr get-updates failed (code $FW_RC).")"; ((ERRORS++)) ;;
    esac
else
    L "fwupd er ikke installeret — springer over.  (Installér med: sudo apt-get install fwupd)" \
      "fwupd is not installed. Skipping.  (Install with: sudo apt-get install fwupd)"; echo
fi
echo ""

# ─── Step 8: Security status ──────────────────────────────────────────────────
step "$(L "[8/8] Sikkerhedsstatus for ${OS_PRETTY}..." "[8/8] Security status for ${OS_PRETTY}...")"
# debian-security-support shows which installed packages Debian's security and
# LTS teams no longer (fully) fix. Otherwise you never find out.
if [ "$OS_ID" != "debian" ]; then
    L "Ikke et Debian-system — springer over." "Not a Debian system. Skipping."; echo
    SUPPORT_STATUS=$(L "sprunget over (ikke Debian)" "skipped (not Debian)")
elif ! dpkg-query -W -f='${Status}' debian-security-support 2>/dev/null | grep -q "install ok installed"; then
    L "Installerer debian-security-support (viser pakker uden sikkerhedssupport)..." \
      "Installing debian-security-support (shows packages without security support)..."; echo
    apt-get "${APT_OPTS[@]}" install -y debian-security-support 2>&1 || {
        warn "$(L "Kunne ikke installere debian-security-support." "Could not install debian-security-support.")"; ((ERRORS++))
    }
fi
if [ "$OS_ID" != "debian" ]; then
    :
elif command -v check-support-status &> /dev/null; then
    check-support-status > "$TMP/support.txt" 2>&1
    # Format: "* Source:name, ended on DATE ..." = support ended (serious)
    #         "* Source:name"                    = limited support (for information)
    SUPPORT_ENDED=$(grep -c '^\* Source:.*, ended on ' "$TMP/support.txt")
    SUPPORT_COUNT=$(grep -c '^\* Source:' "$TMP/support.txt")
    SUPPORT_LIMITED=$((SUPPORT_COUNT - SUPPORT_ENDED))
    SUPPORT_ENDED_LIST=$(grep -oP '^\* Source:\K[^,]+(?=, ended on )' "$TMP/support.txt" | tr '\n' ' ' | sed 's/ $//')
    # Short summary on screen: source package + reason (full list: check-support-status)
    fmt_support() {   # $1 = ended | limited
        awk -v want="$1" '
            /^\* Source:/  { src = substr($0, 10); kind = (src ~ /, ended on /) ? "ended" : "limited" }
            /^  Details:/ && src != "" { if (kind == want) { print "  • " src; print "      " substr($0, 12) } src = "" }
        ' "$TMP/support.txt"
    }
    if [ "$SUPPORT_ENDED" -gt 0 ]; then
        echo -e "${YELLOW}$(L "Sikkerhedssupport er OPHØRT for (fjern dem, hvis du ikke bruger dem):" \
                              "Security support has ENDED for (remove them if you don't use them):")${NC}"
        fmt_support ended
    fi
    if [ "$SUPPORT_LIMITED" -gt 0 ]; then
        L "Begrænset sikkerhedssupport (typisk kun til betroet indhold):" \
          "Limited security support (usually only for trusted content):"; echo
        fmt_support limited
    fi
    [ "$SUPPORT_COUNT" -gt 0 ] && { L "Berørte pakker og detaljer: kør  check-support-status" \
                                      "Affected packages and details: run  check-support-status"; echo; }
    if [ "$SUPPORT_ENDED" -gt 0 ]; then
        SUPPORT_STATUS=$(L "$SUPPORT_ENDED UDEN support ($SUPPORT_ENDED_LIST), $SUPPORT_LIMITED med begrænset" \
                           "$SUPPORT_ENDED WITHOUT support ($SUPPORT_ENDED_LIST), $SUPPORT_LIMITED limited")
        warn "$(L "Pakker uden sikkerhedssupport: $SUPPORT_ENDED_LIST" "Packages without security support: $SUPPORT_ENDED_LIST")"
    elif [ "$SUPPORT_LIMITED" -gt 0 ]; then
        SUPPORT_STATUS=$(L "ingen uden support, $SUPPORT_LIMITED med begrænset support" \
                           "none without support, $SUPPORT_LIMITED with limited support")
        ok "$SUPPORT_STATUS"
    else
        SUPPORT_STATUS=$(L "alle installerede pakker er dækket" "all installed packages are covered")
        ok "$SUPPORT_STATUS"
    fi
else
    SUPPORT_STATUS=$(L "ukendt (debian-security-support mangler)" "unknown (debian-security-support missing)")
fi

# Countdown: full security support -> LTS -> end
NOW_EPOCH=$(date +%s)
LTS_DAYS_LEFT=0; REGULAR_DAYS_LEFT=-1
if $RELEASE_KNOWN; then
    LTS_DAYS_LEFT=$(( ($(date -d "$LTS_END" +%s) - NOW_EPOCH) / 86400 ))
    [ -n "$REGULAR_END" ] && REGULAR_DAYS_LEFT=$(( ($(date -d "$REGULAR_END" +%s) - NOW_EPOCH) / 86400 ))
fi

# Automatic updates (unattended-upgrades) usually install most security fixes
# at night. That is why a manual run often finds only a few.
if dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q "install ok installed" \
   && systemctl is-enabled apt-daily-upgrade.timer &> /dev/null; then
    UU_LOG=/var/log/apt/history.log
    UU_RUNS=$(grep -c '^Commandline: /usr/bin/unattended-upgrade' "$UU_LOG" 2>/dev/null)
    UU_PKGS=$(awk '/^Commandline: \/usr\/bin\/unattended-upgrade/ {f=1; next}
                   /^Start-Date/ {f=0}
                   f && /^Upgrade:/ {n += gsub(/\),/, "") + 1}
                   END {print n+0}' "$UU_LOG" 2>/dev/null)
    UU_LAST=$(grep -B1 '^Commandline: /usr/bin/unattended-upgrade' "$UU_LOG" 2>/dev/null \
              | grep -oP '^Start-Date: \K\S+' | tail -1)
    UU_STATUS=$(L "aktiv — ${UU_RUNS:-0} natlige kørsler / ${UU_PKGS:-0} pakker i denne måneds log, senest ${UU_LAST:-ukendt}" \
                  "active — ${UU_RUNS:-0} nightly runs / ${UU_PKGS:-0} packages in this month's log, last ${UU_LAST:-unknown}")
fi
echo ""

# ─── Packages on hold ─────────────────────────────────────────────────────────
HELD_COUNT=$(apt-mark showhold 2>/dev/null | grep -c .)
HELD_SHOW=$(apt-mark showhold 2>/dev/null | head -8 | tr '\n' ' ' | sed 's/ $//')
[ "$HELD_COUNT" -gt 8 ] && HELD_SHOW="$HELD_SHOW … (+$((HELD_COUNT - 8)) $(L "flere" "more"))"

# ─── Reboot check ─────────────────────────────────────────────────────────────
REBOOT_NEEDED=false; REBOOT_REASON=""
if [ -f /var/run/reboot-required ]; then
    REBOOT_NEEDED=true
    REBOOT_REASON=$(L "systemet har markeret, at en genstart er påkrævet" "the system has flagged that a restart is required")
fi
RUNNING_KERNEL=$(uname -r)
NEWEST_KERNEL=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -1)
if [ -n "$NEWEST_KERNEL" ] && [ "$NEWEST_KERNEL" != "$RUNNING_KERNEL" ]; then
    REBOOT_NEEDED=true
    REBOOT_REASON=$(L "kører kerne $RUNNING_KERNEL, men nyeste installerede er $NEWEST_KERNEL" \
                      "running kernel $RUNNING_KERNEL, but the newest installed is $NEWEST_KERNEL")
fi
if [ "${FW_REBOOT:-false}" = true ]; then
    REBOOT_NEEDED=true
    REBOOT_REASON=$(L "en firmware-opdatering fuldføres først ved genstart" "a firmware update only completes after a restart")
fi

# ─── Disk space afterwards ────────────────────────────────────────────────────
ROOT_FREE_H_AFTER=$(df -h / | awk 'NR==2 {print $4}')
END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
DURATION=$(( $(date +%s) - START_EPOCH ))
DURATION_H="$((DURATION / 60))m $((DURATION % 60))s"

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
line
echo -e "${CYAN}${BOLD}  $(L "RAPPORT" "REPORT")  │  ${END_TIME}  │  $(L "varighed" "duration") ${DURATION_H}    ${NC}"
line
if [ "$SOURCES_STATUS" = "OK" ]; then
    row "$(L "Pakkekilder:" "Package sources:")" "OK"
else
    rowc "$(L "Pakkekilder:" "Package sources:")" "$RED" "$SOURCES_STATUS"
fi
row "$(L "Pakker opgraderet:" "Packages upgraded:")"          "$APT_UPGRADED"
row "$(L "Pakker nyinstalleret:" "Packages newly installed:")" "$APT_INSTALLED"
row "$(L "Pakker fjernet:" "Packages removed:")"              "$((APT_REMOVED + AUTOREMOVED))"
if [ "$APT_KEPT" -gt 0 ]; then
    rowc "$(L "Pakker holdt tilbage:" "Packages kept back:")" "$YELLOW" "${APT_KEPT} — ${KEPT_LIST}"
else
    row "$(L "Pakker holdt tilbage:" "Packages kept back:")" "0"
fi
if [ "$HELD_COUNT" -gt 0 ]; then
    rowc "$(L "Fastholdte pakker (hold):" "Packages on hold:")" "$YELLOW" "${HELD_COUNT} — ${HELD_SHOW}"
else
    row "$(L "Fastholdte pakker (hold):" "Packages on hold:")" "0"
fi
if $FLATPAK_INSTALLED; then
    row "$(L "Flatpak-apps opdateret:" "Flatpak apps updated:")" \
        "$FP_APP_UPD  ($(L "nye" "new"): $FP_APP_NEW, $(L "fjernet" "removed"): $FP_APP_REM)"
    row "$(L "Flatpak-runtimes opdateret:" "Flatpak runtimes updated:")" \
        "$FP_RT_UPD  ($(L "nye" "new"): $FP_RT_NEW, $(L "fjernet" "removed"): $FP_RT_REM)"
else
    row "Flatpak:" "$(L "ikke installeret" "not installed")"
fi
row "Firmware:" "$FIRMWARE_STATUS"
if [ "$SUPPORT_ENDED" -gt 0 ]; then
    rowc "$(L "Sikkerhedssupport:" "Security support:")" "$YELLOW" "$SUPPORT_STATUS"
else
    row "$(L "Sikkerhedssupport:" "Security support:")" "$SUPPORT_STATUS"
fi
row "$(L "Automatiske opdateringer:" "Automatic updates:")" "$UU_STATUS"
row "$(L "Diskplads ledig:" "Free disk space:")" "$ROOT_FREE_H_AFTER"
if [ "$ERRORS" -gt 0 ]; then
    rowc "$(L "Fejl:" "Errors:")" "${RED}${BOLD}" "${ERRORS} — $(L "tjek log for detaljer" "check the log for details")"
else
    rowc "$(L "Fejl:" "Errors:")" "${GREEN}${BOLD}" "$(L "Ingen" "None")"
fi
line

# ─── Support clock ────────────────────────────────────────────────────────────
echo ""
VER_LABEL="Debian ${OS_VERSION_ID}"
if ! $RELEASE_KNOWN; then
    echo -e "  🗓  $(L "Support-ur: ingen datoer for ${OS_PRETTY} (se DEBIAN_RELEASES øverst i scriptet)." \
                    "Support clock: no dates for ${OS_PRETTY} (see DEBIAN_RELEASES at the top of the script).")"
elif [ "$LTS_DAYS_LEFT" -lt 0 ]; then
    echo -e "${RED}${BOLD}  ✗  ${VER_LABEL^^}: $(L "SIKKERHEDSSUPPORT SLUTTEDE ${LTS_END} — for $(( -LTS_DAYS_LEFT )) dage siden." \
                                                  "SECURITY SUPPORT ENDED ${LTS_END}, $(( -LTS_DAYS_LEFT )) days ago.")${NC}"
    echo -e "${RED}     $(L "Systemet får IKKE længere sikkerhedsopdateringer." "This system NO LONGER gets security updates.")${NC}"
    echo -e "${RED}     ${LTS_END_NOTE}${NC}"
elif [ "$LTS_DAYS_LEFT" -le "$LTS_ALARM_DAYS" ]; then
    echo -e "${RED}${BOLD}  ⚠  ${VER_LABEL^^}: $(L "SIKKERHEDSSUPPORT SLUTTER OM ${LTS_DAYS_LEFT} DAGE (${LTS_END})!" \
                                                  "SECURITY SUPPORT ENDS IN ${LTS_DAYS_LEFT} DAYS (${LTS_END})!")${NC}"
    echo -e "${RED}     $(L "Herefter kommer der ingen sikkerhedsopdateringer." "After that there will be no security updates.")${NC}"
    echo -e "${RED}     ${LTS_END_NOTE}${NC}"
elif [ "$LTS_DAYS_LEFT" -le "$LTS_WARN_DAYS" ]; then
    echo -e "${YELLOW}${BOLD}  ⚠  ${VER_LABEL}: $(L "sikkerhedssupport slutter om ${LTS_DAYS_LEFT} dage (${LTS_END}). Planlæg nu." \
                                                    "security support ends in ${LTS_DAYS_LEFT} days (${LTS_END}). Plan now.")${NC}"
    echo -e "${YELLOW}     ${LTS_END_NOTE}${NC}"
elif [ "$REGULAR_DAYS_LEFT" -ge 0 ]; then
    echo -e "  🗓  ${VER_LABEL}: $(L "fuld sikkerhedssupport til ${REGULAR_END} (${REGULAR_DAYS_LEFT} dage), derefter LTS til ${LTS_END}" \
                                   "full security support until ${REGULAR_END} (${REGULAR_DAYS_LEFT} days), then LTS until ${LTS_END}") — ${BOLD}${LTS_DAYS_LEFT} $(L "dage tilbage" "days left")${NC}"
    if [ "$REGULAR_DAYS_LEFT" -le "$LTS_WARN_DAYS" ]; then
        echo -e "${YELLOW}     $(L "Om ${REGULAR_DAYS_LEFT} dage går ${VER_LABEL} over til LTS: ikke alle pakker dækkes. Trin 8 viser hvilke." \
                                  "In ${REGULAR_DAYS_LEFT} days ${VER_LABEL} moves to LTS: not all packages are covered. Step 8 shows which.")${NC}"
    fi
else
    echo -e "  🗓  ${VER_LABEL} LTS: $(L "sikkerhedsopdateringer til ${LTS_END}" "security updates until ${LTS_END}") — ${BOLD}${LTS_DAYS_LEFT} $(L "dage tilbage" "days left")${NC}"
fi

# ─── Reboot warning ───────────────────────────────────────────────────────────
if [ "$REBOOT_NEEDED" = true ]; then
    echo ""
    echo -e "${YELLOW}${BOLD}  ⚠  $(L "GENSTART PÅKRÆVET" "RESTART REQUIRED")${NC}"
    echo -e "${YELLOW}     ${REBOOT_REASON}.${NC}"
    echo -e "${YELLOW}     $(L "Kør" "Run"): sudo reboot${NC}"
fi

echo ""
echo -e "  📋 $(L "Fuld log" "Full log"): ${BOLD}${LOG_FILE}${NC}"
echo ""

# ─── Finish ───────────────────────────────────────────────────────────────────
if ! $AUTO; then
    read -r -p "$(L "Tryk ENTER for at afslutte..." "Press ENTER to exit...")" _
fi
# tee closes by itself when the script ends (no wait here: bash itself keeps one
# end of the pipe open, so a wait on tee would hang forever).
[ "$ERRORS" -eq 0 ] && exit 0
exit 1
