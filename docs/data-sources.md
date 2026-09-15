# Data sources

Both sources are open data. Raw files are downloaded with
`scripts/download_sources.py` and are not versioned.

## 1. Actual data (Ist-Daten v2) · opentransportdata.swiss

| | |
|---|---|
| Publisher | Open Data Platform Mobility Switzerland (SBB on behalf of the Federal Office of Transport) |
| Page | <https://data.opentransportdata.swiss/dataset/ist-daten-v2> (current month), monthly archives at <https://archive.opentransportdata.swiss/> |
| Documentation | <https://opentransportdata.swiss/en/cookbook/historic-and-statistics-cookbook/actual-data/> |
| Terms | Open data, free to use with source attribution (see platform terms of use) |
| Grain | One row per **stop event** of a trip on an operating day (arrival and departure in the same row) |
| Format | CSV, `;` delimited, UTF-8, header row, one file per day (~2.6 M rows, ~660 MB) |

Columns (22, all kept in RAW):

| Column | Type in source | Notes |
|---|---|---|
| `BETRIEBSTAG` | `DD.MM.YYYY` | operating day |
| `FAHRT_BEZEICHNER` | text | trip identifier, unique per operating day |
| `BETREIBER_ID`, `BETREIBER_ABK`, `BETREIBER_NAME` | text | operator id, abbreviation (e.g. `SBB`, `BLS`), name |
| `PRODUKT_ID` | enum | `Zug`, `Bus`, `Tram`, `Schiff`, ... |
| `LINIEN_ID`, `LINIEN_TEXT` | text | technical line id, customer-facing line (`IC1`, `S3`) |
| `UMLAUF_ID`, `VERKEHRSMITTEL_TEXT` | text | vehicle rotation, vehicle category (`IC`, `RE`, `S`) |
| `ZUSATZFAHRT_TF` | `true`/`false` | extra trip |
| `FAELLT_AUS_TF` | `true`/`false` | trip cancelled |
| `BPUIC` | 7 digits | stop id (UIC), **join key** to the frequency data |
| `HALTESTELLEN_NAME` | text | stop name |
| `ANKUNFTSZEIT` | `DD.MM.YYYY HH24:MI` | scheduled arrival, empty at the first stop |
| `AN_PROGNOSE` | `DD.MM.YYYY HH24:MI:SS` | actual / forecast arrival |
| `AN_PROGNOSE_STATUS` | enum | `REAL` measured, `GESCHAETZT` estimated, `PROGNOSE` forecast only, `UNBEKANNT` or empty: no information |
| `ABFAHRTSZEIT`, `AB_PROGNOSE`, `AB_PROGNOSE_STATUS` | as above | departure side |
| `DURCHFAHRT_TF` | `true`/`false` | train passes without stopping |
| `SLOID` | text | Swiss Location ID |

Findings from profiling one day (2026-09-09):

- 2,623,743 rows, of which 180,508 are `PRODUKT_ID = 'Zug'`; 71,714 of those are SBB.
- Version 2 includes foreign stops of international trains (e.g. Budapest-Keleti), so stops without a Swiss frequency record are expected.
- Arrival status for SBB trains: 82% `REAL`, the rest forecast, unknown or empty (first stop of a trip has no arrival).

## 2. Passenger frequency · data.sbb.ch

| | |
|---|---|
| Publisher | SBB CFF FFS |
| Page | <https://data.sbb.ch/explore/dataset/passagierfrequenz/> |
| Export | `https://data.sbb.ch/api/explore/v2.1/catalog/datasets/passagierfrequenz/exports/csv?delimiter=%3B` |
| Terms | <https://data.sbb.ch/page/licence> (open data, attribution) |
| Grain | One row per **station and year** (2018, 2022–2025) |
| Format | CSV, `;` delimited, UTF-8 with BOM, 5,724 rows |

Relevant columns:

| Column | Notes |
|---|---|
| `uic` | station UIC number, stored as decimal text (`8502113.0`), **join key** (cast to integer) |
| `bahnhof_gare_stazione` | station name |
| `kt_ct_cantone` | canton |
| `isb_gi` | infrastructure manager (`SBB`, `BLS`, `RhB`, ...) |
| `jahr_annee_anno` | reference year, latest year per station is used |
| `dtv_tjm_tgm` | average daily passengers (all days), used as `passengers_per_day` |
| `dwv_tmjo_tfm` | average weekday passengers |
| `dnwv_tmjno_tmgnl` | average weekend/holiday passengers |
| `geopos` | `lat, lon` |

## Filtering before upload

`scripts/filter_istdaten.py` keeps only rail rows (`PRODUKT_ID = 'Zug'`, all
operators) and writes gzip files of ~3 MB per day to `data/processed/`. All
columns are preserved so the RAW layer still mirrors the source schema. The
filter runs locally because uploading 660 MB per day through the Snowflake web
UI is neither practical nor necessary for the questions asked.
