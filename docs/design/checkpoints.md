# Context checkpoints

How Countersign measures a Claude Code session's context and nudges it toward a deliberate
compaction; read it before changing anything named `Context…`.

## Measuring context

`ContextUsageReader` reads the session transcript, an undocumented file, so every failure means
"unknown": a missing, unreadable or empty file, a line that is not JSON and a row with an
unexpected shape all yield no reading rather than a crash or a guess.

The size of the context is the usage of the latest main-thread `assistant` row:
`input_tokens + cache_creation_input_tokens + cache_read_input_tokens`. Output tokens are not part
of it. A missing field counts as 0, and a field that is not an integer makes the whole row
unusable, so the reader falls back to the row before it. Rows with `isSidechain: true` belong to
subagents and are ignored, since a subagent's context is not the session's. One API response is
written as several `assistant` rows that carry the same usage, so the last one in file order is
the latest.

Transcripts grow without bound, so the reader looks only at the last 512 KiB. When the read did
not start at offset 0, the first line is cut off mid-row and is dropped. If the tail holds no
usable row at all, for example because a long run of tool output pushed the last usage row out of
it, the reader falls back to reading the whole file once.

A compaction writes a `system` row with `subtype: "compact_boundary"`, a `uuid` and
`compactMetadata.postTokens`. When that row comes after the latest main usage row, the next usage
row has not been written yet, so `postTokens` is the best available size. A `postTokens` that is
missing or not an integer is not used as a source. The `uuid` of the latest boundary is reported
as the compaction id, so a caller can tell one compaction from another.

The model comes from the latest `attachment` row whose `attachment.type` is `model`, read from
`attachment.identity.modelId`. A `[1m]` suffix on that id means a 1M-token window. Assistant rows
carry `message.model` without the suffix, so it is only a fallback for the name and never proves
the window size. Since a session can hold more than 200K tokens only with the 1M window, a size
above 200,000 also counts as a 1M window when no identity says so.

The transcript is written asynchronously, so a reading can lag the session by one turn. Treat a
reading as an estimate that is at most one turn old, never as the exact state.
