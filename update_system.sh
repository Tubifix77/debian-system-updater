#!/bin/bash
# Debian System Updater v1.2
# Komplet vedligeholdelse af Debian 12-systemet med farveoutput, log og afsluttende rapport.
#
# Brug:
#   sudo bash update_system.sh           # interaktiv — venter på ENTER til sidst
#   sudo bash update_system.sh --auto    # ikke-interaktiv — til cron / automation
#
# Ændringer: se CHANGELOG.md

# ─── Indstillinger ────────────────────────────────────────────────────────────
LOG_FILE="/var/log/debian-updater.log"
LOG_MAX_BYTES=5242880   # roter loggen (til .1) når den overstiger 5 MB

# Debian 12 "bookworm" får LTS-sikkerhedsopdateringer til og med denne dato
# (kilde: https://wiki.debian.org/LTS). Herefter kommer der ingen rettelser.
LTS_END="2028-06-30"
LTS_WARN_DAYS=30        # gul advarsel når der er så mange dage (eller færre) tilbage
LTS_ALARM_DAYS=7        # rød alarm når der er så mange dage (eller færre) tilbage
LTS_END_NOTE="Valg herefter: nyere Debian (GT 730M kører der kun på den åbne nouveau-driver), nyt grafikkort/pc, eller hold maskinen væk fra internettet."

# ─── Farver og hjælpefunktioner ───────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
fail() { echo -e "${RED}✗ $*${NC}"; }
step() { echo -e "${BOLD}$*${NC}"; }
line() { echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"; }
row()  { printf "  %-32s %s\n" "$1" "$2"; }

# ─── Root-check ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Fejl: Dette script skal køres med sudo!${NC}"
    exit 1
fi

# ─── Tilstand ─────────────────────────────────────────────────────────────────
AUTO=false
[[ "$1" == "--auto" ]] && AUTO=true

# apt, dpkg og flatpak skal svare på engelsk, ellers kan rapporten ikke tælle
# noget: med dansk systemsprog viste v1.1 altid "0 pakker opgraderet".
# Scriptets egne beskeder er stadig på dansk.
export LC_ALL=C.UTF-8

# I --auto-tilstand sidder der ingen ved tastaturet. Uden dette ville et
# debconf-spørgsmål eller en konflikt i en konfigurationsfil få kørslen til at
# hænge for evigt. Med det vælger dpkg/debconf det sikre standardsvar: behold
# den nuværende konfigurationsfil (den nye gemmes ved siden af som *.dpkg-dist).
# Interaktive kørsler spørger som hidtil.
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

# Al output (stdout + stderr) skrives til skærm og logfil i realtid
exec > >(tee -a "$LOG_FILE") 2>&1
TEE_PID=$!

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ─── Tællere ──────────────────────────────────────────────────────────────────
ERRORS=0
SOURCES_STATUS="OK"
APT_UPGRADED=0; APT_INSTALLED=0; APT_REMOVED=0; APT_KEPT=0; KEPT_LIST=""
AUTOREMOVED=0
FP_APP_UPD=0; FP_APP_NEW=0; FP_APP_REM=0
FP_RT_UPD=0;  FP_RT_NEW=0;  FP_RT_REM=0
FLATPAK_INSTALLED=false
FIRMWARE_STATUS="fwupd ikke installeret"
SUPPORT_STATUS="ukendt"; SUPPORT_COUNT=0
UU_STATUS="ikke aktiv"

# ─── Header ───────────────────────────────────────────────────────────────────
echo ""
line
echo -e "${CYAN}${BOLD}  Debian System Updater v1.2  │  ${START_TIME}    ${NC}"
line
echo ""

# ─── Diskplads pre-check ──────────────────────────────────────────────────────
# Afbryder ved < 1 GB, advarer ved < 2 GB
ROOT_FREE_KB=$(df / | awk 'NR==2 {print $4}')
ROOT_FREE_H=$(df -h / | awk 'NR==2 {print $4}')

if [ "$ROOT_FREE_KB" -lt 1048576 ]; then
    fail "Diskplads kritisk: ${ROOT_FREE_H} ledig. Afbryder for at undgå skade."
    exit 1
elif [ "$ROOT_FREE_KB" -lt 2097152 ]; then
    warn "Lav diskplads: ${ROOT_FREE_H} ledig — fortsætter med forsigtighed."
else
    ok "Diskplads OK: ${ROOT_FREE_H} ledig"
fi
echo ""

# ─── Trin 1: Reparér pakke-afhængigheder ─────────────────────────────────────
step "[1/8] Reparerer pakke-afhængigheder..."
dpkg --configure -a || {
    fail "dpkg --configure -a fejlede. Afslutter."; exit 1
}
apt-get "${APT_OPTS[@]}" --fix-broken install -y || {
    fail "fix-broken fejlede. Afslutter."; exit 1
}
ok "Færdig"; echo ""

# ─── Trin 2: Opdatér pakkelister ─────────────────────────────────────────────
step "[2/8] Opdaterer pakkelister..."
# Error-Mode=any: en pakkekilde der ikke kan hentes (fx netværksfejl) tæller
# som en fejl. Standard-apt giver kun en advarsel og returnerer 0, så v1.1
# viste et grønt flueben, selv hvis sikkerhedsarkivet ikke blev hentet.
apt-get update -o APT::Update::Error-Mode=any 2>&1 | tee "$TMP/update.txt"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    fail "En eller flere pakkekilder kunne ikke hentes — fortsætter med de pakkelister, der findes:"
    grep -E '^(W|E): ' "$TMP/update.txt" | sed 's/^/    /'
    SOURCES_STATUS="FEJL — en eller flere kilder blev ikke hentet (se log)"
    ((ERRORS++))
else
    ok "Pakkelister opdateret"
fi
echo ""

# ─── Trin 3: Fuld systemopgradering ──────────────────────────────────────────
step "[3/8] Fuld systemopgradering..."
apt-get "${APT_OPTS[@]}" full-upgrade -y 2>&1 | tee "$TMP/upgrade.txt"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    fail "Opgradering fejlede. Afslutter."; ((ERRORS++)); exit 1
fi
# apt's statuslinje: "N upgraded, N newly installed, N to remove and N not upgraded."
APT_UPGRADED=$(grep -oP '\d+(?= upgraded,)'        "$TMP/upgrade.txt" | tail -1)
APT_INSTALLED=$(grep -oP '\d+(?= newly installed)' "$TMP/upgrade.txt" | tail -1)
APT_REMOVED=$(grep -oP '\d+(?= to remove)'         "$TMP/upgrade.txt" | tail -1)
APT_KEPT=$(grep -oP '\d+(?= not upgraded)'         "$TMP/upgrade.txt" | tail -1)
APT_UPGRADED=${APT_UPGRADED:-0}; APT_INSTALLED=${APT_INSTALLED:-0}
APT_REMOVED=${APT_REMOVED:-0};   APT_KEPT=${APT_KEPT:-0}
# Pakker apt IKKE opgraderede — typisk fordi de er sat "on hold" med apt-mark.
# En pakke på hold får heller ikke sikkerhedsrettelser, så det skal være synligt.
KEPT_LIST=$(awk '/^The following packages have been kept back:/ {f=1; next}
                 f && /^[^ ]/ {f=0}
                 f {printf "%s ", $0}' "$TMP/upgrade.txt" | tr -s ' ' | sed 's/^ //; s/ $//')
if [ "$APT_KEPT" -gt 0 ]; then
    warn "$APT_KEPT pakke(r) blev holdt tilbage og fik IKKE opdateringer: $KEPT_LIST"
    echo "   Se hvilke pakker der er på hold med: apt-mark showhold"
fi
ok "Opgradering fuldført"; echo ""

# ─── Trin 4: Flatpak ─────────────────────────────────────────────────────────
step "[4/8] Flatpak-apps..."
if command -v flatpak &> /dev/null; then
    FLATPAK_INSTALLED=true
    # Øjebliksbillede før/efter (ref + aktiv commit). Ændret commit = opdateret,
    # ny ref = installeret, forsvundet ref = fjernet. Uafhængigt af sprog og
    # af flatpaks skærmoutput (v1.1 talte linjenumre og missede nr. 10 og op).
    fp_snapshot() { flatpak list "$1" --columns=ref,active 2>/dev/null | sort -t $'\t' -k1,1; }
    fp_count() {   # $1 = før, $2 = efter  →  "opdateret nye fjernet"
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
        warn "Flatpak returnerede en fejl."; ((ERRORS++))
    fi

    fp_snapshot --app     > "$TMP/app_after.txt"
    fp_snapshot --runtime > "$TMP/rt_after.txt"
    read -r FP_APP_UPD FP_APP_NEW FP_APP_REM < <(fp_count "$TMP/app_before.txt" "$TMP/app_after.txt")
    read -r FP_RT_UPD  FP_RT_NEW  FP_RT_REM  < <(fp_count "$TMP/rt_before.txt"  "$TMP/rt_after.txt")

    # Komponenter som Flathub har erklæret end-of-life får ingen opdateringer mere
    FP_EOL=$(flatpak list --all --columns=ref,options 2>/dev/null | awk -F'\t' '$2 ~ /eol/ {print $1}' | tr '\n' ' ')
    [ -n "$FP_EOL" ] && warn "Flatpak-komponenter der er end-of-life (ingen opdateringer mere): $FP_EOL"
    ok "Flatpak tjekket"
else
    echo "Flatpak er ikke installeret — springer over."
fi
echo ""

# ─── Trin 5: Fjern ubrugte pakker ────────────────────────────────────────────
step "[5/8] Fjerner ubrugte pakker..."
apt-get "${APT_OPTS[@]}" autoremove --purge -y 2>&1 | tee "$TMP/autoremove.txt"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    warn "autoremove returnerede en fejl. Fortsætter..."; ((ERRORS++))
fi
AUTOREMOVED=$(grep -oP '\d+(?= to remove)' "$TMP/autoremove.txt" | tail -1)
AUTOREMOVED=${AUTOREMOVED:-0}
ok "Oprydning fuldført"; echo ""

# ─── Trin 6: Ryd pakke-cache ─────────────────────────────────────────────────
step "[6/8] Rydder pakke-cache..."
apt-get clean || {
    warn "Cache-oprydning fejlede. Fortsætter..."; ((ERRORS++))
}
ok "Cache ryddet"; echo ""

# ─── Trin 7: Firmware (fwupd) ────────────────────────────────────────────────
step "[7/8] Firmware-opdateringer (fwupd)..."
if command -v fwupdmgr &> /dev/null; then
    # --no-unreported-check: send aldrig rapporter til LVFS af sig selv
    # --no-metadata-check:   vi opdaterer metadata eksplicit lige herunder
    # --no-reboot-check:     spørg/genstart aldrig — rapporten nederst siger til
    # fwupdmgr bruger returkode 2 for "intet at gøre"; det er ikke en fejl.
    FW_FLAGS=(-y --no-unreported-check --no-metadata-check)
    FW_NOTE=""
    # Metadata (hvilke firmware-versioner der findes) hentes fra LVFS. Debians
    # fwupd-refresh.timer gør det også dagligt, men skjuler fejl — her vises de.
    fwupdmgr refresh "${FW_FLAGS[@]}" 2>&1 | tee "$TMP/fw_refresh.txt"
    FW_REFRESH_RC=${PIPESTATUS[0]}
    if [ "$FW_REFRESH_RC" -ne 0 ] && [ "$FW_REFRESH_RC" -ne 2 ]; then
        warn "Firmware-metadata fra LVFS kunne ikke hentes (kode $FW_REFRESH_RC) — tjekker med de data, der allerede findes."
        FW_NOTE=" (metadata kunne ikke hentes — se log)"; ((ERRORS++))
    fi
    # Fuldt output gemmes i en tempfil; på skærmen vises én linje pr. enhed.
    # (fwupd farvelægger sin tekst selv i filer; farvekoderne fjernes før tolkning)
    fwupdmgr get-updates "${FW_FLAGS[@]}" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$TMP/fw.txt"
    FW_RC=${PIPESTATUS[0]}
    case "$FW_RC" in
        0)  # mindst én enhed har en opdatering på LVFS
            # Hardware-tjek: er Secure Boot slået til? Opdateringer af Secure Boot-
            # listerne (db/dbx) betyder intet, når Secure Boot er slået fra, og på
            # ældre maskiner kan de ofte ikke installeres (for lidt plads i UEFI-lageret).
            SB_STATE="ukendt"
            SB_VAR=$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | head -1)
            if [ -n "$SB_VAR" ]; then
                case "$(od -An -tu1 -j4 -N1 "$SB_VAR" 2>/dev/null | tr -d ' ')" in
                    1) SB_STATE="til" ;;
                    0) SB_STATE="fra" ;;
                esac
            fi
            # Én linje pr. enhed: navn, nuværende version, ny version, evt. afvisning fra firmwaren
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
            awk -F'\t' '{ line = "  • " $1 ": " ($2 == "" ? "?" : $2) " → " ($3 == "" ? "?" : $3)
                          if ($4 != "") line = line "  (afvist af firmwaren: " $4 ")"
                          print line }' "$TMP/fw_devices.tsv"
            FIRMWARE_STATUS=""
            if [ "$FW_DEVICES" -eq 0 ]; then
                cat "$TMP/fw.txt"
                FIRMWARE_STATUS="opdateringer fundet, men output kunne ikke tolkes — se log"
                warn "$FIRMWARE_STATUS"
            fi
            # Installér kun det, firmwaren faktisk vil tage imod
            if [ "$FW_READY" -gt 0 ]; then
                fwupdmgr update "${FW_FLAGS[@]}" --no-reboot-check 2>&1 | tee "$TMP/fw_update.txt"
                FW_UPD_RC=${PIPESTATUS[0]}
                if grep -q 'Successfully installed firmware' "$TMP/fw_update.txt"; then
                    FIRMWARE_STATUS="$FW_READY enhed(er) opdateret — se log"; ok "Firmware opdateret"
                    FW_REBOOT=true
                elif [ "$FW_UPD_RC" -eq 0 ] || [ "$FW_UPD_RC" -eq 2 ]; then
                    FIRMWARE_STATUS="$FW_READY enhed(er) har opdateringer, men de blev ikke installeret — se log"
                    warn "$FIRMWARE_STATUS"
                else
                    FIRMWARE_STATUS="FEJL ved opdatering (kode $FW_UPD_RC)"
                    fail "Firmware-opdatering fejlede (kode $FW_UPD_RC)."; ((ERRORS++))
                fi
            fi
            # Enheder firmwaren afviser
            if [ "$FW_BLOCKED" -gt 0 ]; then
                if [ "$FW_BLOCKED_SB" -eq "$FW_BLOCKED" ] && [ "$SB_STATE" = "fra" ]; then
                    FW_BLOCKED_NOTE="ingen relevante (Secure Boot-lister kan ikke opdateres, og Secure Boot er slået fra)"
                    echo "  Secure Boot er slået fra på denne maskine, så de manglende db/dbx-opdateringer er uden betydning."
                    ok "Firmware tjekket"
                else
                    FW_BLOCKED_NOTE="$FW_BLOCKED enhed(er) kan ikke opdateres: ${FW_REASON:-se log}"
                    if [ "$FW_BLOCKED_SB" -gt 0 ] && [ "$SB_STATE" = "til" ]; then
                        FW_BLOCKED_NOTE="$FW_BLOCKED_NOTE — Secure Boot er slået TIL, så det bør undersøges"
                    fi
                    warn "$FW_BLOCKED_NOTE"
                fi
                FIRMWARE_STATUS="${FIRMWARE_STATUS:+$FIRMWARE_STATUS; }$FW_BLOCKED_NOTE"
            fi
            [ -z "$FIRMWARE_STATUS" ] && FIRMWARE_STATUS="ingen opdateringer tilgængelige"
            FIRMWARE_STATUS="$FIRMWARE_STATUS$FW_NOTE" ;;
        2)
            FIRMWARE_STATUS="ingen opdateringer tilgængelige${FW_NOTE}"; ok "Firmware er ajour" ;;
        *)
            FIRMWARE_STATUS="FEJL (kode $FW_RC)"
            warn "fwupdmgr get-updates fejlede (kode $FW_RC)."; ((ERRORS++)) ;;
    esac
else
    echo "fwupd er ikke installeret — springer over.  (Installér med: sudo apt-get install fwupd)"
fi
echo ""

# ─── Trin 8: Sikkerhedsstatus (Debian LTS) ───────────────────────────────────
step "[8/8] Sikkerhedsstatus for Debian 12 (LTS)..."
# debian-security-support fortæller hvilke installerede pakker LTS-holdet ikke
# (længere) retter sikkerhedshuller i. Ellers opdager man det aldrig.
if ! dpkg-query -W -f='${Status}' debian-security-support 2>/dev/null | grep -q "install ok installed"; then
    echo "Installerer debian-security-support (viser pakker uden sikkerhedssupport)..."
    apt-get "${APT_OPTS[@]}" install -y debian-security-support 2>&1 || {
        warn "Kunne ikke installere debian-security-support."; ((ERRORS++))
    }
fi
SUPPORT_ENDED=0; SUPPORT_LIMITED=0
if command -v check-support-status &> /dev/null; then
    check-support-status > "$TMP/support.txt" 2>&1
    # Format: "* Source:navn, ended on DATO ..." = support ophørt (alvorligt)
    #         "* Source:navn"                    = begrænset support (til orientering)
    SUPPORT_ENDED=$(grep -c '^\* Source:.*, ended on ' "$TMP/support.txt")
    SUPPORT_COUNT=$(grep -c '^\* Source:' "$TMP/support.txt")
    SUPPORT_LIMITED=$((SUPPORT_COUNT - SUPPORT_ENDED))
    SUPPORT_ENDED_LIST=$(grep -oP '^\* Source:\K[^,]+(?=, ended on )' "$TMP/support.txt" | tr '\n' ' ' | sed 's/ $//')
    # Kort oversigt på skærmen: kildepakke + begrundelse (fuld liste: check-support-status)
    fmt_support() {   # $1 = ended | limited
        awk -v want="$1" '
            /^\* Source:/  { src = substr($0, 10); kind = (src ~ /, ended on /) ? "ended" : "limited" }
            /^  Details:/ && src != "" { if (kind == want) { print "  • " src; print "      " substr($0, 12) } src = "" }
        ' "$TMP/support.txt"
    }
    if [ "$SUPPORT_ENDED" -gt 0 ]; then
        echo -e "${YELLOW}Sikkerhedssupport er OPHØRT for (fjern dem, hvis du ikke bruger dem):${NC}"
        fmt_support ended
    fi
    if [ "$SUPPORT_LIMITED" -gt 0 ]; then
        echo "Begrænset sikkerhedssupport (typisk kun til betroet indhold):"
        fmt_support limited
    fi
    [ "$SUPPORT_COUNT" -gt 0 ] && echo "Berørte pakker og detaljer: kør  check-support-status"
    if [ "$SUPPORT_ENDED" -gt 0 ]; then
        SUPPORT_STATUS="$SUPPORT_ENDED UDEN support ($SUPPORT_ENDED_LIST), $SUPPORT_LIMITED med begrænset"
        warn "Pakker uden sikkerhedssupport: $SUPPORT_ENDED_LIST"
    elif [ "$SUPPORT_LIMITED" -gt 0 ]; then
        SUPPORT_STATUS="ingen uden support, $SUPPORT_LIMITED med begrænset support"
        ok "$SUPPORT_STATUS"
    else
        SUPPORT_STATUS="alle installerede pakker er dækket"
        ok "$SUPPORT_STATUS"
    fi
else
    SUPPORT_STATUS="ukendt (debian-security-support mangler)"
fi

# Nedtælling til LTS-slut
LTS_END_EPOCH=$(date -d "$LTS_END" +%s)
LTS_DAYS_LEFT=$(( (LTS_END_EPOCH - $(date +%s)) / 86400 ))

# Automatiske opdateringer (unattended-upgrades) installerer typisk de fleste
# sikkerhedsrettelser om natten. Derfor finder en manuel kørsel ofte kun få.
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
    UU_STATUS="aktiv — ${UU_RUNS:-0} natlige kørsler / ${UU_PKGS:-0} pakker i denne måneds log, senest ${UU_LAST:-ukendt}"
fi
echo ""

# ─── Pakker på hold ───────────────────────────────────────────────────────────
HELD_COUNT=$(apt-mark showhold 2>/dev/null | grep -c .)
HELD_SHOW=$(apt-mark showhold 2>/dev/null | head -8 | tr '\n' ' ' | sed 's/ $//')
[ "$HELD_COUNT" -gt 8 ] && HELD_SHOW="$HELD_SHOW … (+$((HELD_COUNT - 8)) flere)"

# ─── Reboot-check ─────────────────────────────────────────────────────────────
REBOOT_NEEDED=false; REBOOT_REASON=""
if [ -f /var/run/reboot-required ]; then
    REBOOT_NEEDED=true; REBOOT_REASON="systemet har markeret, at en genstart er påkrævet"
fi
RUNNING_KERNEL=$(uname -r)
NEWEST_KERNEL=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -1)
if [ -n "$NEWEST_KERNEL" ] && [ "$NEWEST_KERNEL" != "$RUNNING_KERNEL" ]; then
    REBOOT_NEEDED=true; REBOOT_REASON="kører kerne $RUNNING_KERNEL, men nyeste installerede er $NEWEST_KERNEL"
fi
if [ "${FW_REBOOT:-false}" = true ]; then
    REBOOT_NEEDED=true; REBOOT_REASON="en firmware-opdatering fuldføres først ved genstart"
fi

# ─── Diskplads efter ──────────────────────────────────────────────────────────
ROOT_FREE_H_AFTER=$(df -h / | awk 'NR==2 {print $4}')
END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
DURATION=$(( $(date +%s) - START_EPOCH ))
DURATION_H="$((DURATION / 60))m $((DURATION % 60))s"

# ─── Slutrapport ──────────────────────────────────────────────────────────────
echo ""
line
echo -e "${CYAN}${BOLD}  RAPPORT  │  ${END_TIME}  │  varighed ${DURATION_H}    ${NC}"
line
if [ "$SOURCES_STATUS" = "OK" ]; then
    row "Pakkekilder:" "OK"
else
    echo -e "  $(printf '%-32s ' 'Pakkekilder:')${RED}${SOURCES_STATUS}${NC}"
fi
row "Pakker opgraderet:"    "$APT_UPGRADED"
row "Pakker nyinstalleret:" "$APT_INSTALLED"
row "Pakker fjernet:"       "$((APT_REMOVED + AUTOREMOVED))"
if [ "$APT_KEPT" -gt 0 ]; then
    echo -e "  $(printf '%-32s ' 'Pakker holdt tilbage:')${YELLOW}${APT_KEPT} — ${KEPT_LIST}${NC}"
else
    row "Pakker holdt tilbage:" "0"
fi
if [ "$HELD_COUNT" -gt 0 ]; then
    echo -e "  $(printf '%-32s ' 'Fastholdte pakker (hold):')${YELLOW}${HELD_COUNT} — ${HELD_SHOW}${NC}"
else
    row "Fastholdte pakker (hold):" "0"
fi
if $FLATPAK_INSTALLED; then
    row "Flatpak-apps opdateret:"     "$FP_APP_UPD  (nye: $FP_APP_NEW, fjernet: $FP_APP_REM)"
    row "Flatpak-runtimes opdateret:" "$FP_RT_UPD  (nye: $FP_RT_NEW, fjernet: $FP_RT_REM)"
else
    row "Flatpak:" "ikke installeret"
fi
row "Firmware:" "$FIRMWARE_STATUS"
if [ "$SUPPORT_ENDED" -gt 0 ]; then
    echo -e "  $(printf '%-32s ' 'Sikkerhedssupport (LTS):')${YELLOW}${SUPPORT_STATUS}${NC}"
else
    row "Sikkerhedssupport (LTS):" "$SUPPORT_STATUS"
fi
row "Automatiske opdateringer:" "$UU_STATUS"
row "Diskplads ledig:" "$ROOT_FREE_H_AFTER"
if [ "$ERRORS" -gt 0 ]; then
    echo -e "  $(printf '%-32s ' 'Fejl:')${RED}${BOLD}${ERRORS} — tjek log for detaljer${NC}"
else
    echo -e "  $(printf '%-32s ' 'Fejl:')${GREEN}${BOLD}Ingen${NC}"
fi
line

# ─── LTS-ur ───────────────────────────────────────────────────────────────────
echo ""
if [ "$LTS_DAYS_LEFT" -lt 0 ]; then
    echo -e "${RED}${BOLD}  ✗  DEBIAN 12 LTS SLUTTEDE ${LTS_END} — for $(( -LTS_DAYS_LEFT )) dage siden.${NC}"
    echo -e "${RED}     Systemet får IKKE længere sikkerhedsopdateringer.${NC}"
    echo -e "${RED}     ${LTS_END_NOTE}${NC}"
elif [ "$LTS_DAYS_LEFT" -le "$LTS_ALARM_DAYS" ]; then
    echo -e "${RED}${BOLD}  ⚠  DEBIAN 12 LTS SLUTTER OM ${LTS_DAYS_LEFT} DAGE (${LTS_END})!${NC}"
    echo -e "${RED}     Herefter kommer der ingen sikkerhedsopdateringer.${NC}"
    echo -e "${RED}     ${LTS_END_NOTE}${NC}"
elif [ "$LTS_DAYS_LEFT" -le "$LTS_WARN_DAYS" ]; then
    echo -e "${YELLOW}${BOLD}  ⚠  Debian 12 LTS slutter om ${LTS_DAYS_LEFT} dage (${LTS_END}). Planlæg nu.${NC}"
    echo -e "${YELLOW}     ${LTS_END_NOTE}${NC}"
else
    echo -e "  🗓  Debian 12 LTS: sikkerhedsopdateringer til ${LTS_END} — ${BOLD}${LTS_DAYS_LEFT} dage tilbage${NC}"
fi

# ─── Reboot-advarsel ──────────────────────────────────────────────────────────
if [ "$REBOOT_NEEDED" = true ]; then
    echo ""
    echo -e "${YELLOW}${BOLD}  ⚠  GENSTART PÅKRÆVET${NC}"
    echo -e "${YELLOW}     ${REBOOT_REASON}.${NC}"
    echo -e "${YELLOW}     Kør: sudo reboot${NC}"
fi

echo ""
echo -e "  📋 Fuld log: ${BOLD}${LOG_FILE}${NC}"
echo ""

# ─── Afslut ───────────────────────────────────────────────────────────────────
if ! $AUTO; then
    read -r -p "Tryk ENTER for at afslutte..." _
fi
# tee lukker selv, når scriptet er færdigt (ingen wait her: bash holder selv
# en ende af pipen åben, så et wait på tee ville hænge for evigt).
[ "$ERRORS" -eq 0 ] && exit 0
exit 1
