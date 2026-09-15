# Build journal

Short, factual log of the build: goal of each work block, outcome, pitfalls,
takeaways. Newest entry first.

## 2026-09-16 · Warehouse built, first data quality findings

**Goal:** Run the layered model end to end on one week of data and let the
DQ checks judge the result.

**Outcome:** 1.24 M stop events in RAW, 1.13 M scheduled arrivals in the fact
table, punctuality 93 %, cancellation 2 %, average delay 0.75 min. Seven of
eight checks green on the first run.

**Pitfalls:**

- Snowsight runs only the statement under the cursor unless everything is
  selected. A `GRANT` ran before its `CREATE ROLE` and failed; rerunning the
  whole script was harmless because every statement is idempotent.
- The upload dialog on the Snowsight home page loads straight into a table
  and guesses types. The stage upload lives on the stage's own page in the
  catalog.
- Snowflake trial accounts default to the Los Angeles time zone; `_LOADED_AT`
  looked nine hours off until `ALTER ACCOUNT SET TIMEZONE`.
- The DQ check for implausible delays caught 100 rows: 90 were a source
  defect (actual time stamped with the operating day for trips after
  midnight, exactly 24 h early), 10 were sensor artefacts. Decision recorded
  in [ADR-002](decisions/ADR-002-measured-arrivals-only.md): repair the
  known pattern in STAGING, exclude the rest via a plausibility window, keep
  the excluded rows visible through `measurement_issue`.

**Takeaways:** A DQ check that fails on the first run is doing its job. The
useful reaction is to look at the rows, separate patterns from noise, and
turn the decision into code and a written record.

## 2026-09-16 · Source data acquired and profiled

**Goal:** Download a week of actual data plus the passenger frequency file,
understand both schemas, reduce volume before touching Snowflake.

**Outcome:** `scripts/download_sources.py` scrapes the daily file links from the
data portal (each day has a random resource id, so there is no stable URL
pattern) and fetches the frequency export. `scripts/filter_istdaten.py` keeps
only rail rows and gzips them: 660 MB → 3 MB per day. Schemas documented in
[data-sources.md](data-sources.md).

**Pitfalls:**

- The data portal answers `403` to plain scripted requests; a user agent header is required.
- The dataset page only lists the current month; older days live in monthly ZIP archives.
- A day file was still downloading while the filter ran and produced a truncated row. The filter now counts and skips malformed rows instead of crashing.
- The UIC key is `8502113.0` in one source and `8502113` in the other. Casting happens in STAGING, never by editing the files.

**Takeaways:** Profile before modelling. One day holds 2.6 M rows, but 93% are
bus and tram. Deciding the scope (rail, all operators) up front keeps the
warehouse small and the operator dimension meaningful.


## 2026-09-15 · Project setup

**Goal:** Repository skeleton, licensing, documentation structure.

**Outcome:** Folder layout, `.gitignore` (raw data and secrets excluded), MIT
licence for code, README outline, decision log and this journal.

**Takeaways:** Decide upfront what never enters a public repo: raw data files,
credentials, Power BI cache. A sample data set keeps the project runnable for
readers without the full downloads.
