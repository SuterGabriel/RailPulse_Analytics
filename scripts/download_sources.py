"""Download the two open data sources into data/raw/.

Sources
-------
1. Actual data (Ist-Daten v2), one CSV per operating day, from opentransportdata.swiss.
   The CKAN page lists each daily file with a unique resource id, so the page is
   scraped for links matching the requested dates.
2. Passenger frequency per station and year from data.sbb.ch (single CSV export).

Usage
-----
    python scripts/download_sources.py --from 2026-09-07 --to 2026-09-13

Files that already exist in data/raw/ are skipped.
"""

from __future__ import annotations

import argparse
import re
import sys
import urllib.error
import urllib.request
from datetime import date, timedelta
from pathlib import Path

ISTDATEN_PAGE = "https://data.opentransportdata.swiss/dataset/ist-daten-v2"
FREQUENCY_URL = (
    "https://data.sbb.ch/api/explore/v2.1/catalog/datasets/passagierfrequenz"
    "/exports/csv?delimiter=%3B"
)
RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"   # override with --data-dir
# The data portal rejects requests without a browser-like user agent.
HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; RailPulseAnalytics/0.1)"}


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def download_to(url: str, target: Path, retries: int = 3) -> None:
    """Stream to <name>.part and rename on success, so an interrupted download
    never leaves a truncated file that a later run would treat as complete."""
    if target.exists():
        print(f"skip   {target.name} (exists)")
        return
    part = target.with_suffix(target.suffix + ".part")
    for attempt in range(1, retries + 1):
        print(f"get    {target.name} (try {attempt}) ...", end="", flush=True)
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=600) as resp, open(part, "wb") as out:
                while chunk := resp.read(1 << 20):
                    out.write(chunk)
            part.replace(target)
            print(f" {target.stat().st_size / 1e6:,.0f} MB")
            return
        except (OSError, urllib.error.URLError) as exc:
            print(f" failed: {exc}")
            part.unlink(missing_ok=True)
    raise SystemExit(f"giving up on {target.name} after {retries} attempts")


def istdaten_links() -> dict[date, str]:
    """Map operating day -> download URL, scraped from the dataset page."""
    html = fetch(ISTDATEN_PAGE).decode("utf-8", errors="replace")
    pattern = r'https://[^"]+/download/(\d{4}-\d{2}-\d{2})_istdaten\.csv'
    return {date.fromisoformat(d): m for m, d in
            ((m.group(0), m.group(1)) for m in re.finditer(pattern, html))}


def daterange(start: date, end: date):
    for i in range((end - start).days + 1):
        yield start + timedelta(days=i)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--from", dest="start", type=date.fromisoformat, required=True)
    ap.add_argument("--to", dest="end", type=date.fromisoformat, required=True)
    ap.add_argument("--skip-frequency", action="store_true")
    ap.add_argument("--data-dir", type=Path, default=RAW_DIR,
                    help="target folder (default: data/raw next to this repo)")
    args = ap.parse_args()

    raw_dir: Path = args.data_dir
    raw_dir.mkdir(parents=True, exist_ok=True)

    links = istdaten_links()
    missing = [d for d in daterange(args.start, args.end) if d not in links]
    if missing:
        print("not on the dataset page (older days live in the monthly archive):",
              ", ".join(d.isoformat() for d in missing), file=sys.stderr)

    for day in daterange(args.start, args.end):
        if day in links:
            download_to(links[day], raw_dir / f"{day.isoformat()}_istdaten.csv")

    if not args.skip_frequency:
        download_to(FREQUENCY_URL, raw_dir / "passagierfrequenz.csv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
