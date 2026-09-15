# Build journal

Short, factual log of the build: goal of each work block, outcome, pitfalls,
takeaways. Newest entry first.

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
