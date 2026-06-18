# debian-system-updater

Et enkelt Bash-script til komplet vedligeholdelse af Debian 12-systemer - et "Windows Update"-alternativ til Debian.

## Baggrund

Andre Linux-distributioner leveres med grafiske opdateringsstyrere. Debian 12 gør ikke. Dette script udfylder det hul med én kommando der udfører hele kæden: reparation af pakker, opdatering, opgradering, Flatpak, oprydning og en klar afsluttende rapport.

## Hvad scriptet gør

1. **Pre-check** — tjekker diskplads og afbryder ved < 1 GB ledig
2. **fix-broken** — reparerer ødelagte pakke-afhængigheder
3. **apt update** — henter nyeste pakkeinformation
4. **apt full-upgrade** — fuld systemopgradering inkl. nye afhængigheder
5. **flatpak update** — opdaterer Flatpak-apps, hvis Flatpak er installeret
6. **apt autoremove --purge** — fjerner ubrugte pakker og tilhørende konfigurationer
7. **apt clean** — rydder op i downloadede .deb-filer
8. **Firmware** — tj ekker og anvender firmware-opdateringer via `fwupdmgr`, hvis installeret
9. **Rapport** — viser en klar oversigt over hvad der skete, og peger på logfilen

## Brug

```bash
sudo bash update_system.sh           # interaktiv
sudo bash update_system.sh --auto    # ikke-interaktiv (cron / automation)
```

Eller gør scriptet eksekverbart én gang:

```bash
chmod +x update_system.sh
sudo ./update_system.sh
```

## Eksempel på slutrapport

```
════════════════════════════════════════════════
  RAPPORT  |  2026-06-18 14:32:07
════════════════════════════════════════════════
  Pakker opgraderet:             14
  Pakker installeret:            2
  Pakker ryddet op:              6
  Flatpaks opdateret:            3
  Diskplads ledig:               16G
  Fejl:                          Ingen
════════════════════════════════════════════════

  📋 Fuld log: /var/log/debian-updater.log
```

## Log

Scriptet logger automatisk al output til `/var/log/debian-updater.log`. Se loggen med:

```bash
cat /var/log/debian-updater.log
# eller de seneste linjer:
tail -50 /var/log/debian-updater.log
```

## Krav

- Debian 12 (Bookworm)
- Kæver root-rettigheder (`sudo`)
- Flatpak og fwupdmgr er valgfrie og detekteres automatisk
- Ingen eksterne afhængigheder ud over standard Debian-værktøjer
