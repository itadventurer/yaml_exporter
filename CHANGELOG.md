# Changelog

All notable changes to this project are documented here.
This project follows [semantic versioning](https://semver.org).

## Unreleased

## v0.2.0

A ground-up rewrite of the export/import engine and its DSL. **Breaking: nothing
from 0.1.0 carries over** — the module, the entry points, and the mapping API are
all new. See the README for the full DSL.

### Changed (breaking)

- **New mixin API.** `include YamlExporter` in the model and declare the mapping
  in a `yaml_structure do … end` block; round-trip with the instance methods
  `#yaml_export` / `#yaml_import`. This replaces 0.1.0's
  `YamlSerializable::YamlExporter.export(object, structure)` / `.import` class
  methods that took an externally built structure — the `YamlSerializable`
  module no longer exists.
- **Ownership-driven DSL.** The mapping is three methods — `attributes`, `one`,
  `many` — where shape decides ownership: a **block** owns the record
  (YamlExporter creates, updates, and destroys records to match the YAML), while
  **`find_by:` without a block** only resolves a reference and never creates or
  destroys the target.

### Added

- `one` associations in three forms: owned (`one :x do … end`), a plain
  reference (`one :x, find_by:`), and `one_reference_of` to reach a relation's
  single record.
- `many` associations: owned lists, `find_by:` reference lists, positional
  lists, `positioned_by:` ordering, and `many … through:` (with or without a
  block).
- Export omits `nil` attributes by default (`yaml_export(omit_nil:)`).
- Text columns export as YAML multiline block scalars, with surrounding
  whitespace stripped and emojis preserved.
- Column-based type inference and a JSON-schema-style description of a structure
  via `.yaml_schema`.

### Docs

- Rewritten README covering the mental model (cardinality × ownership) and every
  DSL form.
