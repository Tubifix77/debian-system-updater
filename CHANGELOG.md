# Changelog

## v1.2.0 — 2026-09-18

### Rettet
- **Rapporten viste altid 0 opgraderede pakker** på systemer med dansk sprog, fordi apt's statuslinje blev læst på engelsk. Scriptet kører nu med `LC_ALL=C.UTF-8`, så apt/dpkg/flatpak svarer på engelsk (scriptets egne beskeder er stadig danske).
- **Pakker der blev holdt tilbage** ("kept back", typisk pakker på hold) blev aldrig vist. Rapporten viser nu antal og navne, og hvilke pakker der er sat på hold med `apt-mark`.
- **Flatpak-tælleren** talte linjenumre i skærmoutputtet og missede derfor nr. 10 og op, talte runtimes og fjernelser med som apps, og skrev et ekstra "0" på dage uden opdateringer. Tælles nu ved at sammenligne installerede refs/commits før og efter, opdelt i apps og runtimes (opdateret / nye / fjernet).
- **`apt-get update` fik grønt flueben, selv når en kilde ikke kunne hentes** (apt melder kun en advarsel ved netværksfejl og returnerer 0). Kører nu med `APT::Update::Error-Mode=any`; fejlende kilder vises i rødt og tælles som fejl, mens opgraderingen fortsætter med de lister, der findes.

### Tilføjet
- **Sikkerhedsstatus (trin 8):** installerer `debian-security-support`, hvis den mangler, og kører `check-support-status`. Rapporten skelner mellem pakker UDEN sikkerhedssupport og pakker med begrænset support.
- **LTS-ur:** Debian 12 får sikkerhedsopdateringer til 2028-06-30. Rapporten viser altid dage tilbage, gul advarsel ved ≤ 30 dage (`LTS_WARN_DAYS`), rød alarm ved ≤ 7 dage (`LTS_ALARM_DAYS`) og efter datoen. Egen huskeseddel i `LTS_END_NOTE`.
- **Automatiske opdateringer:** rapporten viser, om `unattended-upgrades` er aktiv, og hvor mange natlige kørsler/pakker der er i denne måneds apt-log. Det forklarer, hvorfor en manuel kørsel ofte finder få opdateringer.
- **Firmware (trin 7):** `fwupdmgr refresh` → `get-updates` → `update` med `--no-reboot-check` (genstarter aldrig af sig selv), `--no-unreported-check` (sender ingen rapporter til LVFS) og `--no-metadata-check`. Returkode 2 ("intet at gøre") behandles ikke længere som fejl. Hardware-tjek: scriptet læser Secure Boot-status fra firmwaren, viser én linje pr. enhed med nuværende og ny version, installerer kun det firmwaren vil tage imod, og viser afviste opdateringer med fwupd's begrundelse (fx for lidt plads i UEFI-variabellageret). Er det kun Secure Boot-listerne (db/dbx), der afvises, og Secure Boot er slået fra, bliver det en neutral note i stedet for en advarsel; er Secure Boot slået til, advares der.
- **`--auto` er nu reelt ikke-interaktivt:** `DEBIAN_FRONTEND=noninteractive` og dpkg `--force-confdef --force-confold`, så et debconf-spørgsmål eller en konfigurationsfil-konflikt ikke kan få en cron-kørsel til at hænge. Interaktive kørsler spørger som hidtil.
- `dpkg --configure -a` før fix-broken (fuldfører en afbrudt installation).
- Genstart-tjek sammenligner også kørende kerne med nyeste installerede kerne (filen `/var/run/reboot-required` oprettes kun af visse pakker).
- Advarsel om Flatpak-komponenter, der er markeret end-of-life.
- Varighed i rapporten, log-rotation ved 5 MB, returkode 1 hvis der var fejl (til cron).
- `.gitattributes` sikrer LF-linjeskift i `.sh`-filer ved checkout på Windows.

### Ændret
- Trin er nu [1/8] … [8/8]. Rapporten har fået linjerne Pakkekilder, Pakker holdt tilbage, Fastholdte pakker (hold), Flatpak-runtimes, Firmware, Sikkerhedssupport (LTS) og Automatiske opdateringer.

---

## v1.1.0 — 2026-06-18

### Tilføjet
- Farveoutput: grøn/gul/rød igennem alle trin
- Automatisk logging til `/var/log/debian-updater.log` i realtid
- Tidsstempler på start og slut
- Diskplads pre-check: afbryder ved < 1 GB ledig, advarer ved < 2 GB
- Notifikation hvis genstart er påkrævet (`/var/run/reboot-required`)
- **Afsluttende rapport** med antal opgraderede pakker, Flatpaks, ryddede pakker og fejl
- `--auto` flag til cron/automation (springer den afsluttende `read -p` over)
- Betinget firmware-opdatering via `fwupdmgr` (hvis installeret)
- Fejlhåndtering på `fix-broken`-trinnet (manglede i v1.0.0)
- Tempfiler bruges til at parse statistik uden at miste realtidsoutput

### Ændret
- Alle kritiske trin viser nu `✓ Færdig` eller `✗ Fejl` eksplicit
- Trin er nu nummererede [1/6] ... [6/6] for overblik

---

## v1.0.0 — 2026-06-18

### Første udgivelse
- Root-check via `$EUID`
- Trinvis opdateringskæde: fix-broken → update → full-upgrade → flatpak → autoremove --purge → clean
- Fejlhåndtering med `exit 1` på kritiske trin
- Betinget Flatpak-understøttelse via `command -v` check
