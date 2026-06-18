# debian-system-updater

Et enkelt Bash-script til komplet vedligeholdelse af Debian 12-systemer — et "Windows Update"-alternativ til Debian.

## Baggrund

Andre Linux-distributioner leveres med grafiske opdateringsstyrere. Debian 12 gør ikke. Dette script udfylder det hul med én kommando der udfører hele kæden: reparation af pakker, opdatering, opgradering, Flatpak, oprydning.

## Hvad scriptet gør

1. **fix-broken** — reparerer ødelagte pakke-afhængigheder før opdatering starter
2. **apt update** — henter nyeste pakkeinformation
3. **apt full-upgrade** — fuld systemopgradering inkl. nye afhængigheder
4. **flatpak update** — opdaterer Flatpak-apps, hvis Flatpak er installeret
5. **apt autoremove --purge** — fjerner ubrugte pakker og tilhørende konfigurationer
6. **apt clean** — rydder op i downloadede .deb-filer

## Brug

```bash
sudo bash update_system.sh
```

Eller gør scriptet eksekverbart én gang:

```bash
chmod +x update_system.sh
sudo ./update_system.sh
```

## Krav

- Debian 12 (Bookworm) — testet på denne version
- Kræver root-rettigheder (`sudo`)
- Flatpak-opdatering er valgfri og springes automatisk over hvis ikke installeret

## Projekt

Skrevet til personlig brug på Debian 12 laptop som erstatning for en grafisk opdateringsmanager.

