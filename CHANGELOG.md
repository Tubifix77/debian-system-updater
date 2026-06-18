# Changelog

## v1.0.0 — 2026-06-18

### Første udgivelse

- Root-check via `$EUID`
- Trinvis opdateringskæde: fix-broken → update → full-upgrade → flatpak → autoremove --purge → clean
- Fejlhåndtering med `exit 1` på kritiske trin
- Betinget Flatpak-understøttelse via `command -v` check
