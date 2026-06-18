# Changelog

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
