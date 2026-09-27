# debian-system-updater

Et enkelt Bash-script til komplet vedligeholdelse af Debian 12 og Debian 13 — et "Windows Update"-alternativ til Debian.

## Baggrund

Andre Linux-distributioner leveres med grafiske opdateringsstyrere. Debian gør ikke. Dette script udfylder det hul med én kommando, der udfører hele kæden: reparation af pakker, opdatering, opgradering, Flatpak, oprydning, firmware, sikkerhedsstatus og en klar afsluttende rapport.

Scriptet fortæller også de ting, Debian ellers holder for sig selv: hvilke pakker der er sat på hold og derfor ikke får sikkerhedsrettelser, hvilke pakker sikkerhedsholdet ikke længere retter, om de natlige automatiske opdateringer kører, og hvor mange dage der er tilbage af udgavens sikkerhedssupport.

## Understøttede udgaver

| Udgave | Fuld sikkerhedssupport til | LTS til | Testet med |
|---|---|---|---|
| Debian 12 "bookworm" | 2026-07-11 | 2028-06-30 | apt 2.6 |
| Debian 13 "trixie" | 2028-08-09 | 2030-06-30 | apt 3.0 |

Det er det samme script på begge udgaver. Det læser `/etc/os-release` og slår datoerne op i en lille tabel (`DEBIAN_RELEASES`) øverst i scriptet. Når en ny udgave kommer, er det én linje at tilføje. På en udgave, der ikke står i tabellen, kører alt andet som normalt; kun support-uret mangler.

Datoerne kommer fra [debian.org/releases](https://www.debian.org/releases/) og [wiki.debian.org/LTS](https://wiki.debian.org/LTS). For bookworm siger udgivelsessiden fuld support til 2026-07-11, mens LTS-wikien angiver LTS fra 2026-06-11. Slutdatoen 2028-06-30 er den samme begge steder.

## Hvad scriptet gør

0. **Pre-check** — tjekker diskplads og afbryder ved < 1 GB ledig
1. **Reparation** — `dpkg --configure -a` og `apt-get --fix-broken install`
2. **apt-get update** — henter pakkelister; en kilde der ikke kan hentes vises i rødt (apt selv giver kun en advarsel)
3. **apt-get full-upgrade** — fuld systemopgradering; pakker der holdes tilbage vises med navn
4. **flatpak update** — opdaterer Flatpak-apps og -runtimes, hvis Flatpak er installeret
5. **apt-get autoremove --purge** — fjerner ubrugte pakker og deres konfiguration
6. **apt-get clean** — rydder op i downloadede .deb-filer
7. **Firmware** — henter LVFS-metadata og anvender firmware-opdateringer via `fwupdmgr`, hvis fwupd er installeret. Genstarter aldrig af sig selv og sender ingen rapporter til LVFS. Springes over i containere (WSL, Docker, LXC).
8. **Sikkerhedsstatus** — installerer `debian-security-support` (én gang) og viser hvilke installerede pakker der har mistet eller har begrænset sikkerhedssupport
9. **Rapport** — oversigt over alt ovenstående, support-ur, genstart-advarsel og sti til logfilen

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

## Egne indstillinger

Vil du ændre advarselsgrænserne eller skrive din egen huskeseddel til support-uret, så læg dem i `/etc/default/debian-system-updater`. Filen er valgfri, og den overskrives ikke, når du henter en ny version af scriptet. Eksempel:

```bash
# /etc/default/debian-system-updater
LTS_WARN_DAYS=60
LTS_END_NOTE="Det gamle NVIDIA-kort virker kun med Debian 12. Plan: nyt grafikkort eller ny pc."
```

## Eksempel på slutrapport

Fra en testkørsel på Debian 13 med 41 ventende opdateringer, hvor én pakke var sat på hold:

```
══════════════════════════════════════════════════
  RAPPORT  │  2026-09-27 09:35:02  │  varighed 0m 49s
══════════════════════════════════════════════════
  Pakkekilder:                     OK
  Pakker opgraderet:               40
  Pakker nyinstalleret:            0
  Pakker fjernet:                  0
  Pakker holdt tilbage:            1 — tzdata
  Fastholdte pakker (hold):        1 — tzdata
  Flatpak:                         ikke installeret
  Firmware:                        fwupd ikke installeret
  Sikkerhedssupport:               alle installerede pakker er dækket
  Automatiske opdateringer:        ikke aktiv
  Diskplads ledig:                 956G
  Fejl:                            Ingen
══════════════════════════════════════════════════

  🗓  Debian 13: fuld sikkerhedssupport til 2028-08-09 (681 dage), derefter LTS til 2030-06-30 — 1371 dage tilbage

  📋 Fuld log: /var/log/debian-updater.log
```

På Debian 12, der allerede er i LTS-perioden, ser support-linjen sådan ud:

```
  🗓  Debian 12 LTS: sikkerhedsopdateringer til 2028-06-30 — 641 dage tilbage
```

Linjerne betyder:

- **Pakker holdt tilbage** — pakker apt ville opgradere, men ikke måtte (typisk fordi de er sat på hold). De får heller ikke sikkerhedsrettelser, så tallet bør normalt være 0.
- **Fastholdte pakker (hold)** — alt hvad `apt-mark showhold` viser.
- **Firmware** — én linje pr. enhed med nuværende og ny version. "kan ikke opdateres" betyder, at fwupd fandt noget på LVFS, men maskinens firmware afviste det; fwupd's begrundelse står med (typisk for lidt plads i UEFI-variabellageret på ældre maskiner). Scriptet læser selv Secure Boot-status fra firmwaren: er det kun Secure Boot-listerne (db/dbx), der afvises, og Secure Boot er slået fra, er det uden betydning og vises som "ingen relevante". Er Secure Boot slået til, får du en advarsel.
- **Sikkerhedssupport** — fra `check-support-status`. "UDEN support" er alvorligt: fjern pakken, hvis du ikke bruger den. "Begrænset" er til orientering (typisk "kun til betroet indhold").
- **Automatiske opdateringer** — om `unattended-upgrades` kører om natten. Gør den det, er det normalt, at en manuel kørsel finder få eller ingen Debian-opdateringer: de er allerede installeret.

## Support-uret

Nederst i rapporten står, hvor længe din Debian-udgave får sikkerhedsopdateringer. Så længe udgaven har fuld support, vises begge datoer; i LTS-perioden kun slutdatoen. En måned før overgangen til LTS kommer en gul note, fordi LTS ikke dækker alle pakker (trin 8 viser hvilke).

Advarslerne tæller ned mod slutdatoen: gul ved 30 dage eller færre (`LTS_WARN_DAYS`), rød ved 7 dage eller færre (`LTS_ALARM_DAYS`) og efter datoen. Begge grænser og huskesedlen `LTS_END_NOTE` kan sættes i din egen indstillingsfil.

## Log

Scriptet logger al output til `/var/log/debian-updater.log` (roteres til `.1` ved 5 MB). Se loggen med:

```bash
tail -100 /var/log/debian-updater.log
```

apt's eget output i loggen er på engelsk, uanset systemets sprog. Det er med vilje: rapportens tællere læser apt's statuslinje, og det virker kun på engelsk. Scriptets egne beskeder er på dansk.

## Krav

- Debian 12 (bookworm) eller Debian 13 (trixie)
- Root-rettigheder (`sudo`)
- Flatpak og fwupd er valgfrie og detekteres automatisk (`sudo apt-get install fwupd` for firmware-trinnet)
- `debian-security-support` installeres automatisk første gang, hvis den mangler
- Ingen eksterne afhængigheder ud over standard Debian-værktøjer

I en container (WSL, Docker, LXC) springes firmware-trinnet over, fordi firmwaren tilhører værtsmaskinen, og fwupd-tjenesten starter slet ikke der.

Bruger du et program-firewall som OpenSnitch, skal `/usr/bin/fwupdmgr` have lov til at gå på nettet, ellers kan firmware-metadata ikke hentes. Scriptet viser det som en advarsel i rapporten.
