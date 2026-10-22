# Shotlister engine

The portable core. Everything that must behave identically on macOS, iOS, the MCP
server and eventually the web lives here — data model, change log, numbering,
ordering. No UI, no file system, no network.

Design: [`../design/ARCHITECTURE.html`](../design/ARCHITECTURE.html)

## Running it

```
cargo test
```

## What's here

| Module | Holds |
| --- | --- |
| `store` | Records, the change log, last-writer-wins merge |
| `doc` | The domain API — scenes, shots, placements, days, and every derived value |
| `letters` | Shot letters: skip `I` and `P`, never reflow, freed letters reusable |
| `order` | Sort positions. Moving a row writes one change, not N. |
| `stamp` | Hybrid logical clock — what makes merges deterministic |
| `vocab` | Per-project master lists, and the rule that typing a new value teaches them |
| `query` | Filtering and grouping by scene, day or sequence, with counts |
| `format` | The log's on-disk form. Lines it cannot read are kept, not dropped. |
| `value` | The closed set of field value types |
| `id` | Time-ordered 128-bit ids |

## Shape of it

A record is a bag of named values rather than a fixed struct, and every field
carries the stamp of the write that set it. Two consequences worth knowing:

- **Merging cannot lose work.** Applying the same changes in any order, any
  number of times, lands on the same state. Only writes to the same field
  compete, and the winner is decided the same way on every device.
- **Unknown fields are held, not dropped.** A build that has never heard of a
  field still carries it through. This is the rule that lets an out-of-date
  iPhone edit a project the Mac has already moved on from.

State is derived from the log, never the other way round, which is where history
and undo come from.

## Not here yet

The media pipeline, the exporters, and the sync transports. Next up is media,
since the exporters need frames to place.

Note that nothing in here touches the file system or the network — it is strings
and data in, strings and data out. That is what lets the same code run in a Mac
app, on a phone, and in a browser. Reading files, talking to iCloud and calling
out to a server all belong to the shells around it.
