# RailPulse Analytics

End-to-end analytics demo on Swiss public transport punctuality: open data from
[opentransportdata.swiss](https://opentransportdata.swiss) and
[data.sbb.ch](https://data.sbb.ch), modelled in **Snowflake (Azure)**, served through
**Power BI** and a **Streamlit** app, versioned on GitHub.

> Status: work in progress. See [docs/journal.md](docs/journal.md) for the build log.

## 1. Goal and business questions

_TODO_

## 2. Architecture

_TODO_

## 3. Data sources and licences

_TODO_

## 4. Data model

_TODO_

## 5. Dashboards and app

_TODO_

## 6. How to reproduce

_TODO_

## 7. Simplifications and next steps

_TODO_

## Repository layout

```
.
├── snowflake/   SQL scripts, run in numeric order (setup → raw → staging → mart → checks)
├── scripts/     Python helpers for downloading and filtering source files
├── app/         Streamlit app
├── powerbi/     Power BI report (.pbix)
├── data/        Local data (not versioned) and a small sample for tests
└── docs/        Architecture, data model, runbook, decisions, journal
```

## Licence

Code is released under the [MIT licence](LICENSE). The data belongs to its
respective publishers and is used under their open data terms (see section 3).
