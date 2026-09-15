# ADR-001 · Layered warehouse: RAW → STAGING → MART

**Status:** accepted · **Date:** 2026-09-15

## Context

Two external CSV sources with different grains, formats and update cycles must be
combined for reporting. Files are reloaded when the publisher corrects them, and
reporting tools should never see half-transformed data.

## Decision

Three schemas in one Snowflake database `RAILANALYTICS`:

| Layer | Purpose | Rule |
|-------|---------|------|
| `RAW` | Source files loaded 1:1, all columns as text, plus load metadata | never edited manually |
| `STAGING` | Typed, cleaned, deduplicated views on RAW | no business logic |
| `MART` | Star schema (facts and dimensions) for reporting | only layer exposed to tools |

## Consequences

- Any transformation can be re-run from RAW without re-downloading files.
- Load errors are visible in RAW metadata (`_LOADED_AT`, `_SOURCE_FILE`).
- Reporting tools get a read-only role scoped to `MART`, nothing else.
- Extra objects and a little duplication compared to a single-schema approach; acceptable for the added traceability.
