# Palworld Capture Exporter

A small, read-only UE4SS Lua mod that exports the local player's Pal capture
counts to JSON. It removes the need to manually tick hundreds of boxes in an
external tracker.

The current proof of concept is tested with **Palworld 1.0.3 on Game Pass /
WinGDK**.

## Status

Version **0.2.0** joins live capture counts to Palworld's runtime Paldeck and
English-name DataTables. The validated v1.0.3 catalogue contains 288 unique
Pal species/forms after duplicate quest, summon, flower, and oil-rig character
rows are collapsed.

This repository currently contains the exporter. The planned webapp and its
Pal/location catalogue will remain separate from the UE4SS runtime code.

## Download and install

1. Download [PalCaptureExporter-WinGDK-v0.2.0.zip](dist/PalCaptureExporter-WinGDK-v0.2.0.zip).
2. Extract it into the folder containing your UE4SS `Mods` directory.
3. Confirm this file exists:

   `Mods\PalCaptureExporter\Scripts\main.lua`

4. Add this line to `Mods\mods.txt`:

   `PalCaptureExporter : 1`

5. Load fully into a Palworld world and press **F8**.

The exporter creates:

`Mods\PalCaptureExporter\pal_capture_data.json`

The UE4SS console reports whether the export succeeded and shows the complete
output path.

If the earlier diagnostic inspector is installed, disable it because both mods
use F8 by default:

`PalCaptureInspector : 0`

## Output

Every Paldeck species/form is represented, including uncaught Pals:

```json
{
  "id": "SheepBall",
  "name": "Lamball",
  "nameKey": "PAL_NAME_SheepBall",
  "paldeckIndex": 1,
  "paldeckSuffix": "",
  "captureCount": 18
}
```

Entries are sorted in Paldeck order. An uncaught Pal has `captureCount: 0`.

`PalCaptureCount.Items` remains the authoritative count source and is a sparse
map. The exporter now performs the zero-fill itself by joining that map to the
runtime catalogue. Capture records outside the Paldeck, such as human and
special Yakushima entries, are retained under `unmappedCaptureEntries`.

See [JSON format and importer rules](docs/json-format.md), the
[JSON Schema](schema/pal_capture_data.schema.json), and the
[sanitised example export](examples/pal_capture_data.example.json).

`gameVersion` is currently `null`. A reliable runtime game-version getter has
not yet been verified, so the exporter avoids inserting a stale hard-coded
value.

## Changing the hotkey

At the top of `Mods\PalCaptureExporter\Scripts\main.lua`, change:

```lua
local HOTKEY = Key.F8
```

For example, use `Key.F9` if F8 conflicts with another mod.

## Runtime architecture

The exporter reads the confirmed live capture route:

```text
PlayerController
  -> GetPalPlayerState()
  -> GetRecordData()
  -> PalCaptureCount.Items
```

On the tested WinGDK build, `PalCaptureCount` is exposed as
`PalPlayerRecordDataRepInfoArrayThreadSafe_IntVal`, with entries available
through its legacy `.Items` array.

It also reads these runtime DataTables:

- `DT_PalMonsterParameter` for the Paldeck roster, indices, and variant flags.
- `DT_PalNameText` for current English in-game labels.

Rows are grouped by their resolved localisation key. This collapses duplicate
quest, summon, flower, and oil-rig actors without maintaining a brittle list of
hard-coded character IDs.

## Safety and privacy

- Calls only read-only getters and property reads.
- Does not modify capture counts, game objects, or save files.
- Writes only `pal_capture_data.json` inside its own mod directory.
- Exports internal Pal IDs and counts; it does not export the player's name,
  account identifier, world identifier, or save path.
- Generated `pal_capture_data.json` files are ignored by Git by default.

## Compatibility

- Confirmed: Palworld 1.0.3, Game Pass / WinGDK, working UE4SS installation.
- Other Palworld storefronts and future game versions are currently untested.

Please include the Palworld version, storefront, UE4SS version, and relevant
console error when reporting a compatibility problem.

## Licence and provenance

Released under the [MIT License](LICENSE).

The implementation was written from original runtime inspection results and
UE4SS interfaces. No source code was copied from another Palworld mod.

Palworld is a trademark of Pocketpair, Inc. This community project is not
affiliated with or endorsed by Pocketpair or the UE4SS project.
