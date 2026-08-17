# JSON format and importer rules

The exporter writes schema version 1 as UTF-8 JSON.

## Top-level fields

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Integer version of the export contract. Importers should reject unsupported future versions. |
| `exporterVersion` | Version of the UE4SS exporter that created the file. |
| `gameVersion` | Palworld version when reliably available; currently `null`. |
| `exportedAt` | UTC timestamp in ISO 8601 format. |
| `source` | Describes the runtime platform, access method, and authoritative field. |
| `summary` | Convenience counts for validation and UI feedback. |
| `pals` | Complete Paldeck array, including zero-count species. |
| `unmappedCaptureEntries` | Positive capture records not represented in the Paldeck catalogue. |

## Catalogue-join semantics

`PalCaptureCount.Items` contains only IDs with a recorded positive capture
count. The exporter joins it to `DT_PalMonsterParameter`, resolves names from
`DT_PalNameText`, and supplies zero for an absent catalogue ID.

An importer can use `pals` directly:

```text
captureCount > 0 -> caught
captureCount = 0 -> uncaught
unmappedCaptureEntries -> preserve for diagnostics/future game updates
```

The final rule prevents a webapp from silently discarding IDs introduced by a
game update.

## Validation recommendations

An importer should:

1. Parse the file as JSON.
2. Require `schemaVersion` to equal `1`.
3. Validate against `schema/pal_capture_data.schema.json`.
4. Reject duplicate IDs and negative or non-integer counts.
5. Preserve `unmappedCaptureEntries` even when they are not displayed.
6. Treat the summary as a consistency check rather than the authoritative
   source of individual counts.

The exporter sorts `pals` by Paldeck index and suffix, but importers should use
the explicit fields rather than relying on array order.

## Comparison behaviour

For two valid exports, compare counts by internal ID. A missing ID has a count
of zero. The difference is:

```text
new capture count - old capture count
```

Keep `exportedAt`, `exporterVersion`, and `schemaVersion` alongside comparison
results so future migrations remain possible.
