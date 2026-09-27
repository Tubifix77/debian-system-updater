# debian-system-updater

[![CI](https://github.com/Tubifix77/debian-system-updater/actions/workflows/ci.yml/badge.svg)](https://github.com/Tubifix77/debian-system-updater/actions/workflows/ci.yml)
[![Debian 12 | 13](https://img.shields.io/badge/Debian-12%20%7C%2013-A81D33?logo=debian&logoColor=white)](#understøttede-udgaver)
[![ShellCheck: clean](https://img.shields.io/badge/ShellCheck-clean-brightgreen)](#bygget-til-at-kunne-stoles-på)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**Én kommando opdaterer alt på Debian 12 og 13 og fortæller dig bagefter det, `apt upgrade` ikke gør: hvilke pakker der har mistet sikkerhedssupport, hvilke opdateringer der blev holdt tilbage, om en pakkekilde fejlede, og hvor mange dage din udgave har sikkerhedssupport tilbage.**

🇬🇧 [English version](README.md)

## Hvorfor

At holde et Debian-skrivebord ajour kræver flere kommandoer, og de advarsler, der betyder noget, drukner i deres output. Dette script kører hele kæden (reparation, apt, Flatpak, oprydning, firmware) og slutter med en rapport på én skærm, der svarer på de spørgsmål, du faktisk har:

- **Blev alt opdateret?** Tal for apt-pakker, Flatpak-apps og -runtimes og firmware.
- **Sidder noget fast?** Tilbageholdte og fastholdte pakker bliver nævnt ved navn. De får heller ikke sikkerhedsrettelser.
- **Svarede alle pakkekilder?** En kilde, der ikke kan nås, vises i rødt og tælles som en fejl. Almindelig apt skriver kun en advarsel og afslutter, som om alt gik godt.
- **Hvilke installerede pakker har mistet sikkerhedssupport?** Direkte fra Debians egne data i `debian-security-support`.
- **Hvor længe får min udgave sikkerhedsopdateringer?** En nedtælling gennem fuld support og LTS med gule og røde advarsler, når slutningen nærmer sig.
- **Kører de natlige automatiske opdateringer?** Den viser, hvad `unattended-upgrades` har installeret i denne måned.
- **Betyder firmware-opdateringerne noget?** Den læser Secure Boot-status og forklarer opdateringer, som firmwaren afviser, i stedet for bare at fejle.

## Eksempel

En rigtig rapport fra en Debian 12-bærbar:

```
═════════════════════════════════════════════════════════
  RAPPORT  │  2026-09-27 16:30:27  │  varighed 0m 12s
═════════════════════════════════════════════════════════
  Pakkekilder:                     OK
  Pakker opgraderet:               0
  Pakker nyinstalleret:            0
  Pakker fjernet:                  0
  Pakker holdt tilbage:            0
  Fastholdte pakker (hold):        1 — heroic
  Flatpak-apps opdateret:          0  (nye: 0, fjernet: 0)
  Flatpak-runtimes opdateret:      0  (nye: 0, fjernet: 0)
  Firmware:                        ingen relevante (Secure Boot-lister kan ikke opdateres, og Secure Boot er slået fra)
  Sikkerhedssupport:               2 UDEN support (intel-mediasdk mbedtls), 7 med begrænset
  Automatiske opdateringer:        aktiv — 11 natlige kørsler / 21 pakker i denne måneds log, senest 2026-09-26
  Diskplads ledig:                 24G
  Fejl:                            Ingen
═════════════════════════════════════════════════════════

  🗓  Debian 12 LTS: sikkerhedsopdateringer til 2028-06-30 — 641 dage tilbage
     Datoer fra: distro-info-data (/usr/share/distro-info/debian.csv)

  📋 Fuld log: /var/log/debian-updater.log
```

På Debian 13, der stadig har fuld support, viser uret begge faser:

```
  🗓  Debian 13: fuld sikkerhedssupport til 2028-08-09 (681 dage), derefter LTS til 2030-06-30 — 1371 dage tilbage
```

## Sammenligning

| | apt alene | [topgrade](https://github.com/topgrade-rs/topgrade) | debian-system-updater |
|---|---|---|---|
| apt-pakker, Flatpak og firmware i én kørsel | kun apt | ✓ | ✓ |
| Også andre værktøjer (Cargo, pip, Ruby gems, VS Code-udvidelser …) | — | ✓ | — |
| Tilbageholdte pakker | midt i apt's output | vises ikke særskilt | nævnt i slutrapporten |
| Installerede pakker, der har mistet sikkerhedssupport | — | — | ✓ |
| Nedtælling til slutningen af udgavens sikkerhedssupport | — | — | ✓ |
| Firmware-rapport, der kender Secure Boot-status | — | — | ✓ |

topgrade er det populære værktøj til at opdatere mange pakkehåndteringer på én gang, og det dækker langt flere værktøjer end dette script. Dets kildekode har ingen kontrol af Debians sikkerhedssupport, supportdatoer, fastholdte pakker eller Secure Boot (tjekket september 2026). Vælg topgrade, hvis du vil have én opdatering til alt; vælg dette script, hvis du kører Debian og vil vide, hvor sundt dit system er, og hvor længe det bliver ved med at være understøttet.

## Bygget til at kunne stoles på

- **Ingen overraskelser.** Det genstarter aldrig af sig selv, spørger før firmware installeres (som standard), sender aldrig rapporter nogen steder hen (`fwupdmgr` kører med `--no-unreported-check`), beholder dine konfigurationsfiler i automatiske kørsler og rører aldrig dine pakkekilder.
- **Testet ved hver ændring.** Hvert push kører ShellCheck, enhedstest af al tolknings- og beslutningslogik og integrationstest, der kører det rigtige script i rene Debian 12- og Debian 13-containere. Hver udgivelse indtil nu er også blevet kørt på en rigtig Debian 12-bærbar.
- **Ren, læsbar kode.** Én dokumenteret funktion pr. trin efter [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html). ShellCheck finder intet på noget niveau, og CI holder det sådan.
- **Debians egne data.** Supportdatoer fra `distro-info-data`, sikkerhedsstatus fra `debian-security-support`, og pakkearbejdet går gennem `apt-get`, som apt's manual anbefaler til scripts.
- **Dansk og engelsk,** valgt ud fra dit systemsprog.
- **MIT-licens.**

## Kom i gang

```bash
git clone https://github.com/Tubifix77/debian-system-updater.git
cd debian-system-updater
sudo bash update_system.sh
```

Eller hent `update_system.sh` fra den [nyeste udgivelse](https://github.com/Tubifix77/debian-system-updater/releases/latest). Til firmware-trinnet skal fwupd installeres én gang:

```bash
sudo apt-get install fwupd
```

## Understøttede udgaver

| Udgave | Fuld sikkerhedssupport til | LTS til | Testet med |
|---|---|---|---|
| Debian 12 "bookworm" | 2026-07-11 | 2028-06-30 | apt 2.6 |
| Debian 13 "trixie" | 2028-08-09 | 2030-06-30 | apt 3.0 |

Det er det samme script på begge udgaver. Det læser `/etc/os-release` og henter supportdatoerne fra Debians egen pakke `distro-info-data` (`/usr/share/distro-info/debian.csv`), når den er installeret, så nye Debian-udgaver virker uden at ændre scriptet. Uden den pakke bruger det en lille indbygget tabel (`DEBIAN_RELEASES`). På en udgave, ingen af dem kender, kører alt andet som normalt; kun support-uret mangler.

Datoerne i tabellen ovenfor kommer fra `distro-info-data`, [debian.org/releases](https://www.debian.org/releases/) og [wiki.debian.org/LTS](https://wiki.debian.org/LTS). For bookworm angiver LTS-wikien LTS fra 2026-06-11, mens udgivelsessiden og `distro-info-data` angiver fuld support til 2026-07-11. Alle er enige om slutdatoen 2028-06-30.

## Hvad scriptet gør

0. **Pre-check** — tjekker diskplads og afbryder ved < 1 GB ledig
1. **Reparation** — `dpkg --configure -a` og `apt-get --fix-broken install`
2. **apt-get update** — henter pakkelister; en kilde der ikke kan hentes vises i rødt
3. **apt-get full-upgrade** — fuld systemopgradering; pakker der holdes tilbage nævnes ved navn
4. **flatpak update** — opdaterer Flatpak-apps og -runtimes, hvis Flatpak er installeret
5. **apt-get autoremove --purge** — fjerner ubrugte pakker og deres konfiguration
6. **apt-get clean** — rydder op i downloadede .deb-filer
7. **Firmware** — henter LVFS-metadata og tjekker for firmware-opdateringer via `fwupdmgr`, hvis fwupd er installeret. Som standard spørger det, før noget installeres (se `FIRMWARE_UPDATES`). Springes over i containere (WSL, Docker, LXC), hvor firmwaren tilhører værtsmaskinen.
8. **Sikkerhedsstatus** — installerer `debian-security-support` én gang (medmindre `INSTALL_SECURITY_SUPPORT=no`) og viser hvilke installerede pakker der har mistet eller har begrænset sikkerhedssupport
9. **Rapport** — alt ovenstående på én skærm, support-uret, genstart-advarsel og sti til logfilen

## Brug

```bash
sudo bash update_system.sh               # interaktiv
sudo bash update_system.sh --auto        # ikke-interaktiv (cron / automation)
sudo bash update_system.sh --lang=en     # engelske beskeder (eller --lang=da for dansk)
bash update_system.sh --help
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
- installerer aldrig firmware, medmindre `FIRMWARE_UPDATES=install` er sat
- springer den afsluttende ENTER over og returnerer 1, hvis der var fejl

Uden dette kan en cron-kørsel hænge for evigt på et spørgsmål, ingen ser.

## Indstillinger

Indstillinger lægges i `/etc/default/debian-system-updater`. Filen er valgfri, og den overskrives ikke, når du henter en ny version af scriptet. Alle linjer er valgfrie:

```bash
# /etc/default/debian-system-updater
UI_LANG=da                    # da eller en (standard: systemsproget)
LTS_WARN_DAYS=60              # gul advarsel så mange dage før slutdatoen (standard 30)
LTS_ALARM_DAYS=7              # rød alarm så mange dage før slutdatoen (standard 7)
LTS_END_NOTE="Det gamle NVIDIA-kort virker kun med Debian 12. Plan: nyt grafikkort eller ny pc."
INSTALL_SECURITY_SUPPORT=no   # installér ikke debian-security-support (standard yes)
FIRMWARE_UPDATES=check        # ask, install, check eller off (standard ask)
```

`FIRMWARE_UPDATES` bestemmer, hvad der sker, når firmwaren vil tage imod en opdatering:

- `ask` — en interaktiv kørsel spørger, før der installeres; en `--auto`-kørsel viser det kun, fordi ingen kan svare
- `install` — installerer uden at spørge, også i `--auto`-kørsler
- `check` — installerer aldrig, viser kun hvad der findes, og hvordan det installeres
- `off` — springer firmware-trinnet over

## Sådan læser du rapporten

- **Pakker holdt tilbage** — pakker apt ville opgradere, men ikke måtte (typisk fordi de er sat på hold). De får heller ikke sikkerhedsrettelser, så tallet bør normalt være 0.
- **Fastholdte pakker (hold)** — alt hvad `apt-mark showhold` viser.
- **Firmware** — én linje pr. enhed med nuværende og ny version. "kan ikke opdateres" betyder, at fwupd fandt noget på LVFS, men maskinens firmware afviste det; fwupd's begrundelse står med (typisk for lidt plads i UEFI-variabellageret på ældre maskiner). Er det kun Secure Boot-listerne (db/dbx), der afvises, og Secure Boot er slået fra, er det uden betydning og vises som "ingen relevante". Er Secure Boot slået til, får du en advarsel.
- **Sikkerhedssupport** — fra `check-support-status`. "UDEN support" er alvorligt: fjern pakken, hvis du ikke bruger den. "Begrænset" er til orientering (typisk "kun til betroet indhold").
- **Automatiske opdateringer** — om `unattended-upgrades` kører om natten. Gør den det, er det normalt, at en manuel kørsel finder få eller ingen Debian-opdateringer: de er allerede installeret.

## Support-uret

Nederst i rapporten står, hvor længe din Debian-udgave får sikkerhedsopdateringer. Så længe udgaven har fuld support, vises begge datoer; i LTS-perioden kun slutdatoen. En måned før overgangen til LTS kommer en gul note, fordi LTS ikke dækker alle pakker (trin 8 viser hvilke). Linjen under uret fortæller, hvor datoerne kommer fra: `distro-info-data`, den indbyggede tabel eller din indstillingsfil.

Advarslerne tæller ned mod slutdatoen: gul ved 30 dage eller færre (`LTS_WARN_DAYS`), rød ved 7 dage eller færre (`LTS_ALARM_DAYS`) og efter datoen. Begge grænser og huskesedlen `LTS_END_NOTE` kan sættes i din egen indstillingsfil.

## Log

Scriptet logger al output til `/var/log/debian-updater.log` (roteres til `.1` ved 5 MB):

```bash
tail -100 /var/log/debian-updater.log
```

apt's eget output i loggen er altid på engelsk, fordi rapporten læser apt's statuslinje.

## Krav

- Debian 12 (bookworm) eller Debian 13 (trixie)
- Root-rettigheder (`sudo`)
- Flatpak og fwupd er valgfrie og detekteres automatisk
- `debian-security-support` installeres automatisk første gang, hvis den mangler
- Ingen afhængigheder ud over standard Debian-værktøjer; python3 bruges til at læse fwupd's JSON-output, når det findes

Bruger du et program-firewall som OpenSnitch, skal `/usr/bin/fwupdmgr` have lov til at gå på nettet, ellers kan firmware-metadata ikke hentes. Scriptet viser det som en advarsel i rapporten.

## Udvikling og test

Scriptet er opbygget med én funktion pr. trin og en `main`-funktion efter [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html). Den eneste bevidste afvigelse er, at nogle danske og engelske beskeder er længere end 80 tegn, fordi opdelte sætninger ville være sværere at læse.

Hvert push kører [CI-workflowet](.github/workflows/ci.yml):

- **ShellCheck** på alle scripts, på alle niveauer.
- **Enhedstest** i `tests/unit_tests.sh` af tolknings- og beslutningslogikken: sprogvalg, tilvalg, udgave og datoopslag, nedtællingen, optælling for apt og Flatpak, firmware-JSON og Secure Boot-logikken, tolkning af sikkerhedssupport og opsummeringen af de natlige opdateringer. De indlæser scriptets funktioner uden at køre det, kræver ikke root og kan køres hvor som helst: `bash tests/unit_tests.sh`.
- **Integrationstest** i `tests/run_tests.sh`, der kører det rigtige script i rene Debian 12- og Debian 13-containere i flere scenarier, blandt andet begge sprog, alle datokilder, advarselsgrenene, en utilgængelig pakkekilde og håndteringen af tilvalg.

Integrationstestene ændrer systemindstillinger, så de nægter at køre andre steder end i en container eller VM, der må smides væk, og kun med `UPDATER_TESTS=1`:

```bash
docker run --rm -v "$PWD:/src" -w /src -e UPDATER_TESTS=1 debian:trixie bash tests/run_tests.sh
```

## Licens

[MIT](LICENSE). Du må frit bruge, ændre og dele scriptet, også kommercielt, så længe copyright-notitsen og licensteksten følger med. Det leveres uden nogen form for garanti.
