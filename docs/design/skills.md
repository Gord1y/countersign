# Skills

Countersign 0.3.0 plans a Skills pane over the shared agent setup (`Gord1y/countersign-skills`).
This note covers the `ApprovalCore` groundwork, which no command or window uses yet.

## The catalog

The setup describes what it ships in one file, `catalog.json`. Its contract is countersign-skills'
`docs/catalog.md`: schema version 1, a `skills` list, a `rules` list and an `agents` list. A new
field does not bump the schema version, so Countersign ignores keys it does not know.
`SkillCatalog` parses it.

Countersign reads the file from two places: a pinned countersign-skills release, and each
addition, which is another folder laid out the same way, at `<folder>/catalog.json`.

- **One malformed entry fails the whole catalog.** The generator writes the file and CI checks it,
  so a bad entry means a corrupt or hand-edited file. A partial list would look complete and hide
  what is missing, so the reader reports the first problem and returns no list.
- **`path` must stay inside its folder.** A loader resolves `path` against the folder the catalog
  came from, and an addition is someone else's folder. An absolute path, an empty path or a `..`
  component is rejected, so a catalog can never point a loader at a file outside its own folder.
- **`agents` stays as the catalog's strings, not `Host`.** The setup has no Cursor, and it may add
  agents Countersign does not know. Mapping to `Host` would drop those entries or force a release
  to show them.
- **A missing list is an empty list.** A catalog with only a schema version is valid; a list that is
  present but not an array is not.
