# Changelog

## 0.1.0 - 2026-08-17

- Added configurable F8 capture-data export.
- Added the verified WinGDK runtime route through `GetPalPlayerState()` and
  `GetRecordData()`.
- Added support for the `PalCaptureCount.Items` representation confirmed on
  Palworld 1.0.3.
- Added deterministic sorting by internal Pal ID.
- Added schema, timestamp, source, and entry-count metadata.
- Added validation for missing IDs, invalid counts, and duplicate IDs.
- Kept all game access read-only.
