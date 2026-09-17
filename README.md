# debian-system-updater

Et enkelt Bash-script til komplet vedligeholdelse af Debian 12-systemer - et "Windows Update"-alternativ til Debian.

## Baggrund

Andre Linux-distributioner leveres med grafiske opdateringsstyrere. Debian 12 gør ikke. Dette script udfylder det hul med én kommando, der udfører hele kæden: reparation af pakker, opdatering, opgradering, Flatpak, oprydning, firmware, sikkerhedsstatus og en klar afsluttende rapport.

Scriptet fortæller også de ting, Debian ellers holder for sig selv: hvilke pakker der er sat på hold og derfor ikke får sikkerhedsrettelser, hvilke pakker LTS-holdet ikke længere retter, om de natlige automatiske opdateringer kører, og hvor mange dage der er tilbage af Debian 12's sikkerhedssupport.

## Hvad scriptet gør

0. **Pre-check** — tjekker diskplads og afbryder ved < 1 GB ledig
1. **Reparation** — `dpkg --configure -a` og `apt-get --fix-broken install`
2. **apt-get update** — henter pakkelister; en kilde der ikke kan hentes vises i rødt (apt selv giver kun en advarsel)
3. **apt-get full-upgrade** — fuld systemopgradering; pakker der holdes tilbage vises med navn
4. **flatpak update** — opdaterer Flatpak-apps og -runtimes, hvis Flatpak er installeret
5. **apt-get autoremove --purge** — fjerner ubrugte pakker og deres konfiguration
6. **apt-get clean** — rydder op i downloadede .deb-filer
7. **Firmware** — henter LVFS-metadata og anvender firmware-opdateringer via `fwupdmgr`, hvis fwupd er installeret. Genstarter aldrig af sig selv og sender ingen rapporter til LVFS.
8. **Sikkerhedsstatus** — installerer `debian-security-support` (én gang) og viser hvilke installerede pakker der har mistet eller har begrænset sikkerhedssupport under Debian LTS
9. **Rapport** — oversigt over alt ovenstående, LTS-nedtælling, genstart-advarsel og sti til logfilen

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

### Hvad `--auto` gør

Uden `--auto` opfører scriptet sig som en normal terminalkørsel: hvis en pakke stiller et spørgsmål (typisk "din konfigurationsfil er ændret — behold din eller tag pakkens nye?"), venter den på dit svar, og til sidst venter den på ENTER.

Med `--auto` sidder der ingen ved tastaturet, så scriptet:

- sætter `DEBIAN_FRONTEND=noninteractive`, så debconf aldrig stiller spørgsmål, men bruger standardsvaret
- giver dpkg `--force-confdef --force-confold`, så en konfigurationsfil-konflikt løses ved at **beholde din nuværende fil** (pakkens nye version gemmes ved siden af som `*.dpkg-dist`)
- springer den afsluttende ENTER over og returnerer 1, hvis der var fejl

Uden dette kan en cron-kørsel hænge for evigt på et spørgsmål, ingen ser.

## Eksempel på slutrapport

```
══════════════════════════════════════════════════
  RAPPORT  │  2026-09-18 00:22:11  │  varighed 0m 26s
══════════════════════════════════════════════════
  Pakkekilder:                     OK
  Pakker opgraderet:               4
  Pakker nyinstalleret:            0
  Pakker fjernet:                  0
  Pakker holdt tilbage:            0
  Fastholdte pakker (hold):        1 — heroic
  Flatpak-apps opdateret:          0  (nye: 0, fjernet: 0)
  Flatpak-runtimes opdateret:      0  (nye: 0, fjernet: 0)
  Firmware:                        ingen relevante (Secure Boot-lister kan ikke opdateres, og Secure Boot er slået fra)
  Sikkerhedssupport (LTS):         2 UDEN support (intel-mediasdk mbedtls), 7 med begrænset
  Automatiske opdateringer:        aktiv — 7 natlige kørsler / 14 pakker i denne måneds log, senest 2026-09-15
  Diskplads ledig:                 25G
  Fejl:                            Ingen
══════════════════════════════════════════════════

  🗓  Debian 12 LTS: sikkerhedsopdateringer til 2028-06-30 — 650 dage tilbage

  📋 Fuld log: /var/log/debian-updater.log
```

Linjerne betyder:

- **Pakker holdt tilbage** — pakker apt ville opgradere, men ikke måtte (typisk fordi de er sat på hold). De får heller ikke sikkerhedsrettelser, så tallet bør normalt være 0.
- **Fastholdte pakker (hold)** — alt hvad `apt-mark showhold` viser.
- **Firmware** — én linje pr. enhed med nuværende og ny version. "kan ikke opdateres" betyder, at fwupd fandt noget på LVFS, men maskinens firmware afviste det; fwupd's begrundelse står med (typisk for lidt plads i UEFI-variabellageret på ældre maskiner). Scriptet læser selv Secure Boot-status fra firmwaren: er det kun Secure Boot-listerne (db/dbx), der afvises, og Secure Boot er slået fra, er det uden betydning og vises som "ingen relevante". Er Secure Boot slået til, får du en advarsel.
- **Sikkerhedssupport (LTS)** — fra `check-support-status`. "UDEN support" er alvorligt: fjern pakken, hvis du ikke bruger den. "Begrænset" er til orientering (typisk "kun til betroet indhold").
- **Automatiske opdateringer** — om `unattended-upgrades` kører om natten. Gør den det, er det normalt, at en manuel kørsel finder få eller ingen Debian-opdateringer: de er allerede installeret.

## LTS-uret

Debian 12 "bookworm" får sikkerhedsopdateringer fra LTS-holdet til og med **2028-06-30** (kilde: [wiki.debian.org/LTS](https://wiki.debian.org/LTS)). Herefter kommer der ingen rettelser, og maskinen bør skifte til en nyere Debian eller kobles fra internettet.

Rapporten viser altid antal dage tilbage. Øverst i scriptet kan du justere:

```bash
LTS_END="2028-06-30"    # slutdato
LTS_WARN_DAYS=30        # gul advarsel når der er så mange dage eller færre tilbage
LTS_ALARM_DAYS=7        # rød alarm når der er så mange dage eller færre tilbage
LTS_END_NOTE="..."      # din egen huskeseddel, der vises sammen med advarslen
```

## Log

Scriptet logger al output til `/var/log/debian-updater.log` (roteres til `.1` ved 5 MB). Se loggen med:

```bash
tail -100 /var/log/debian-updater.log
```

apt's eget output i loggen er på engelsk, uanset systemets sprog. Det er med vilje: rapportens tællere læser apt's statuslinje, og det virker kun på engelsk. Scriptets egne beskeder er på dansk.

## Krav

- Debian 12 (Bookworm)
- Root-rettigheder (`sudo`)
- Flatpak og fwupd er valgfrie og detekteres automatisk (`sudo apt-get install fwupd` for firmware-trinnet)
- `debian-security-support` installeres automatisk første gang, hvis den mangler
- Ingen eksterne afhængigheder ud over standard Debian-værktøjer

Bruger du et program-firewall som OpenSnitch, skal `/usr/bin/fwupdmgr` have lov til at gå på nettet, ellers kan firmware-metadata ikke hentes. Scriptet viser det som en advarsel i rapporten.
