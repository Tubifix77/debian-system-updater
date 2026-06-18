#!/bin/bash

# Dette script udfører en komplet vedligeholdelse af Debian-systemet
# Tjekker om scriptet køres med root-privilegier
if [ "$EUID" -ne 0 ]; then 
  echo "Fejl: Dette script skal køres med sudo!"
  exit 1
fi

echo "Starter professionel systemopdatering..."

# 1. Reparation af ødelagte pakker
# Forsøger at rette afhængighedsfejl før selve opdateringen starter
echo "Tjekker og reparerer eventuelle ødelagte pakke-afhængigheder..."
apt --fix-broken install -y

# 2. Opdatering af pakkelister
# Henter nyeste information om tilgængelige pakker
echo "Opdaterer pakkelister..."
apt update || { echo "Fejl under opdatering af pakkelister. Afslutter."; exit 1; }

# 3. Fuld systemopgradering
# Kombinerer 'upgrade' og 'full-upgrade' til én effektiv proces, 
# der håndterer nye afhængigheder korrekt
echo "Udfører fuld systemopgradering..."
apt full-upgrade -y || { echo "Fejl under fuld opgradering. Afslutter."; exit 1; }

# 4. Opdatering af Flatpaks
# Tjekker om flatpak er installeret, og opdaterer i så fald alle apps
if command -v flatpak &> /dev/null; then
    echo "Opdaterer Flatpak-apps..."
    flatpak update -y
else
    echo "Flatpak er ikke installeret - springer over."
fi

# 5. Oprydning af overflødige pakker
# Fjerner pakker der ikke længere er nødvendige og rydder op i konfigurationer
echo "Rydder op i ubrugte pakker..."
apt autoremove --purge -y || { echo "Fejl under oprydning. Fortsætter..."; }

# 6. Oprydning i cache
# Fjerner downloadede .deb filer for at frigøre diskplads
echo "Rydder op i downloaded pakke-arkiver..."
apt clean || { echo "Fejl under oprydning af cache. Fortsætter..."; }

echo "----------------------------------------------"
echo "Systemopdatering og oprydning fuldført!"
echo "----------------------------------------------"
read -p "Tryk ENTER for at afslutte..."
