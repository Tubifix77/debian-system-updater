#!/bin/bash
# Debian System Updater v1.1
# Komplet vedligeholdelse af Debian-systemet med farveoutput, log og afsluttende rapport.
#
# Brug:
#   sudo bash update_system.sh           # interaktiv — venter på ENTER til sidst
#   sudo bash update_system.sh --auto    # ikke-interaktiv — til cron / automation

# ─── Farver ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ─── Root-check ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Fejl: Dette script skal køres med sudo!${NC}"
    exit 1
fi

# ─── Opsætning ────────────────────────────────────────────────────────────────
LOG_FILE="/var/log/debian-updater.log"
START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# Al output (stdout + stderr) skrives til skærm og logfil i realtid
exec > >(tee -a "$LOG_FILE") 2>&1

# Tælle-variabler
ERRORS=0
APT_UPGRADED=0; APT_INSTALLED=0; APT_REMOVED=0; FLATPAK_UPDATED=0

# ─── Header ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}${BOLD}  Debian System Updater  │  ${START_TIME}         ${NC}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
echo ""

# ─── Diskplads pre-check ──────────────────────────────────────────────────────
# Afbryder ved < 1 GB, advarer ved < 2 GB
ROOT_FREE_KB=$(df / | awk 'NR==2 {print $4}')
ROOT_FREE_H=$(df -h / | awk 'NR==2 {print $4}')

if [ "$ROOT_FREE_KB" -lt 1048576 ]; then
    echo -e "${RED}✗ Diskplads kritisk: ${ROOT_FREE_H} ledig. Afbryder for at undgå skade.${NC}"
    exit 1
elif [ "$ROOT_FREE_KB" -lt 2097152 ]; then
    echo -e "${YELLOW}⚠ Lav diskplads: ${ROOT_FREE_H} ledig — fortsætter med forsigtighed.${NC}"
else
    echo -e "${GREEN}✓ Diskplads OK: ${ROOT_FREE_H} ledig${NC}"
fi
echo ""

# ─── Trin 1: Reparér pakke-afhængigheder ─────────────────────────────────────
echo -e "${BOLD}[1/6] Reparerer pakke-afhængigheder...${NC}"
apt-get --fix-broken install -y || {
    echo -e "${RED}✗ fix-broken fejlede. Afslutter.${NC}"; ((ERRORS++)); exit 1
}
echo -e "${GREEN}✓ Færdig${NC}"; echo ""

# ─── Trin 2: Opdatér pakkelister ─────────────────────────────────────────────
echo -e "${BOLD}[2/6] Opdaterer pakkelister...${NC}"
apt-get update || {
    echo -e "${RED}✗ apt-get update fejlede. Afslutter.${NC}"; exit 1
}
echo -e "${GREEN}✓ Pakkelister opdateret${NC}"; echo ""

# ─── Trin 3: Fuld systemopgradering ──────────────────────────────────────────
echo -e "${BOLD}[3/6] Fuld systemopgradering...${NC}"
UPGRADE_TMP=$(mktemp)
apt-get full-upgrade -y | tee "$UPGRADE_TMP"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo -e "${RED}✗ Opgradering fejlede. Afslutter.${NC}"
    ((ERRORS++)); rm -f "$UPGRADE_TMP"; exit 1
fi
# Parse apt-statistik fra opgraderingsoutput
APT_UPGRADED=$(grep -oP '\d+(?= upgraded)'        "$UPGRADE_TMP" | tail -1)
APT_INSTALLED=$(grep -oP '\d+(?= newly installed)' "$UPGRADE_TMP" | tail -1)
APT_UPGRADED=${APT_UPGRADED:-0}; APT_INSTALLED=${APT_INSTALLED:-0}
rm -f "$UPGRADE_TMP"
echo -e "${GREEN}✓ Opgradering fuldført${NC}"; echo ""

# ─── Trin 4: Flatpak ─────────────────────────────────────────────────────────
echo -e "${BOLD}[4/6] Flatpak-apps...${NC}"
if command -v flatpak &> /dev/null; then
    FLATPAK_TMP=$(mktemp)
    flatpak update -y | tee "$FLATPAK_TMP"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo -e "${YELLOW}⚠ Flatpak returnerede en fejl.${NC}"; ((ERRORS++))
    fi
    # Nummererede linjer i flatpak-outputtet svarer til én app pr. linje
    FLATPAK_UPDATED=$(grep -cP '^\s+\d+\.' "$FLATPAK_TMP" 2>/dev/null || echo 0)
    FLATPAK_UPDATED=${FLATPAK_UPDATED:-0}
    rm -f "$FLATPAK_TMP"
    echo -e "${GREEN}✓ Flatpak tjekket${NC}"
else
    echo "Flatpak er ikke installeret — springer over."
fi
echo ""

# ─── Trin 5: Fjern ubrugte pakker ────────────────────────────────────────────
echo -e "${BOLD}[5/6] Fjerner ubrugte pakker...${NC}"
AUTOREMOVE_TMP=$(mktemp)
apt-get autoremove --purge -y | tee "$AUTOREMOVE_TMP"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo -e "${YELLOW}⚠ autoremove returnerede en fejl. Fortsætter...${NC}"; ((ERRORS++))
fi
APT_REMOVED=$(grep -oP '\d+(?= to remove)' "$AUTOREMOVE_TMP" | tail -1)
APT_REMOVED=${APT_REMOVED:-0}
rm -f "$AUTOREMOVE_TMP"
echo -e "${GREEN}✓ Oprydning fuldført${NC}"; echo ""

# ─── Trin 6: Ryd pakke-cache ─────────────────────────────────────────────────
echo -e "${BOLD}[6/6] Rydder pakke-cache...${NC}"
apt-get clean || {
    echo -e "${YELLOW}⚠ Cache-oprydning fejlede. Fortsætter...${NC}"; ((ERRORS++))
}
echo -e "${GREEN}✓ Cache ryddet${NC}"; echo ""

# ─── Firmware (valgfri) ───────────────────────────────────────────────────────
if command -v fwupdmgr &> /dev/null; then
    echo -e "${BOLD}[+] Firmware-opdateringer...${NC}"
    fwupdmgr get-updates 2>&1 || true
    fwupdmgr update -y 2>&1 || {
        echo -e "${YELLOW}⚠ Firmware-opdatering fejlede.${NC}"; ((ERRORS++))
    }
    echo -e "${GREEN}✓ Firmware tjekket${NC}"; echo ""
fi

# ─── Reboot-check ─────────────────────────────────────────────────────────────
REBOOT_NEEDED=false
[ -f /var/run/reboot-required ] && REBOOT_NEEDED=true

# ─── Diskplads efter ──────────────────────────────────────────────────────────
ROOT_FREE_H_AFTER=$(df -h / | awk 'NR==2 {print $4}')
END_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# ─── Slutrapport ──────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}${BOLD}  RAPPORT  │  ${END_TIME}                         ${NC}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
printf "  %-30s %s\n" "Pakker opgraderet:"  "$APT_UPGRADED"
printf "  %-30s %s\n" "Pakker installeret:" "$APT_INSTALLED"
printf "  %-30s %s\n" "Pakker ryddet op:"   "$APT_REMOVED"
printf "  %-30s %s\n" "Flatpaks opdateret:" "$FLATPAK_UPDATED"
printf "  %-30s %s\n" "Diskplads ledig:"    "$ROOT_FREE_H_AFTER"
if [ "$ERRORS" -gt 0 ]; then
    echo -e "  $(printf '%-30s' 'Fejl:')${RED}${BOLD}${ERRORS} — tjek log for detaljer${NC}"
else
    echo -e "  $(printf '%-30s' 'Fejl:')${GREEN}${BOLD}Ingen${NC}"
fi
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"

# ─── Reboot-advarsel ──────────────────────────────────────────────────────────
if [ "$REBOOT_NEEDED" = true ]; then
    echo ""
    echo -e "${YELLOW}${BOLD}  ⚠  GENSTART PÅKRÆVET${NC}"
    echo -e "${YELLOW}     En ny kerne eller systemkomponent er installeret.${NC}"
    echo -e "${YELLOW}     Kør: sudo reboot${NC}"
fi

echo ""
echo -e "  📋 Fuld log: ${BOLD}${LOG_FILE}${NC}"
echo ""

# ─── Afslut ───────────────────────────────────────────────────────────────────
[[ "$1" == "--auto" ]] && exit 0
read -p "Tryk ENTER for at afslutte..."

