# ADR-002 · Punctuality on measured, plausible arrivals only

**Status:** accepted · **Date:** 2026-09-16

## Context

The actual-data feed marks every arrival with a status: `REAL` (measured),
`GESCHAETZT` (estimated from neighbouring measurements), `PROGNOSE` (forecast
only), `UNBEKANNT` or empty. About 14 % of scheduled arrivals in the loaded
week carry no measurement. In addition, the first data quality run found 100
arrivals more than 30 minutes early or 5 hours late:

- ~90 rows, all from one operator, exactly 24 hours early. Trips that cross
  midnight are stamped with the operating day instead of the calendar day.
- ~10 rows with sensor artefacts: identical actual times at consecutive stops,
  or an arrival eleven hours before schedule.

Counting forecast-only rows as "on time" would inflate the punctuality rate;
counting the 24-hour rows as "early" would distort average delay.

## Decision

1. **Measured only.** The punctuality rate and the average delay use rows with
   status `REAL` or `GESCHAETZT` that are not cancelled.
2. **Repair the known day-roll defect in STAGING.** If the actual time is 23 to
   25 hours before the scheduled time, add one day. This is a format repair of
   a documented source defect, not business logic, so it lives in STAGING
   (`fix_day_roll`).
3. **Plausibility window in MART.** Delays outside −30 to +300 minutes are
   treated as not measured. The rows stay in the fact table with
   `measurement_issue = 'implausible'` so their volume is monitored by the DQ
   checks; a jump indicates a feed problem rather than an operational one.

## Consequences

- Every fact row carries `measurement_issue` (`NULL`, `cancelled`,
  `not_measured`, `implausible`). Reports can show the measured share next to
  the punctuality rate, which keeps the KPI honest.
- The thresholds are session variables at the top of `03_mart.sql` and can be
  changed without touching the logic.
- Cancellation rate is unaffected: it uses all scheduled stops.
