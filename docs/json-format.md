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
| `pals` | Array of internal Pal IDs and their positive capture counts. |

## Sparse-map semantics

`PalCaptureCount.Items` contains only IDs with a recorded positive capture
count. Runtime testing confirmed that catching a previously absent species
adds a new entry to the map.

An importer should join the exported rows to its complete Pal catalogue using
the internal ID:

```text
catalogue ID present in export -> use exported captureCount
catalogue ID absent from export -> captureCount is 0
export ID absent from catalogue -> preserve and flag as unknown/new content
```

The final rule prevents a webapp from silently discarding IDs introduced by a
game update.

## Validation recommendations

An importer should:

1. Parse the file as JSON.
2. Require `schemaVersion` to equal `1`.
3. Validate against `schema/pal_capture_data.schema.json`.
4. Reject duplicate IDs and negative or non-integer counts.
5. Display a warning for unknown IDs while retaining their raw data.
6. Treat the summary as a consistency check rather than the authoritative
   source of individual counts.

The exporter sorts `pals` by ID for deterministic files, but importers should
not rely on array order.

## Comparison behaviour

For two valid exports, compare counts by internal ID. A missing ID has a count
of zero. The difference is:

```text
new capture count - old capture count
```

Keep `exportedAt`, `exporterVersion`, and `schemaVersion` alongside comparison
results so future migrations remain possible.
