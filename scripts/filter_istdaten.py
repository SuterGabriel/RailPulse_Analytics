"""Reduce the daily actual-data files to rail trips and gzip them for upload.

A single operating day holds roughly 2.6 million stop events, most of them bus
and tram. Only the rows with PRODUKT_ID = 'Zug' are kept (all operators), which
cuts the volume to about 7% while all 22 source columns stay untouched so the
RAW layer in Snowflake still mirrors the publisher's schema.

Usage
-----
    python scripts/filter_istdaten.py                # all files in data/raw/
    python scripts/filter_istdaten.py --day 2026-09-09   # single day
    python scripts/filter_istdaten.py --sample 500       # also refresh data/sample/

Output: data/processed/<day>_istdaten_zug.csv.gz
"""

from __future__ import annotations

import argparse
import csv
import gzip
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "data"
RAW, PROCESSED, SAMPLE = ROOT / "raw", ROOT / "processed", ROOT / "sample"
PRODUCT = "Zug"
DELIM = ";"
csv.field_size_limit(1 << 30)


def filter_file(src: Path, dst: Path) -> tuple[int, int, int]:
    """Return (rows read, rows kept, malformed rows skipped)."""
    kept = total = bad = 0
    with open(src, encoding="utf-8", newline="") as fin, \
            gzip.open(dst, "wt", encoding="utf-8", newline="") as fout:
        reader = csv.reader(fin, delimiter=DELIM)
        writer = csv.writer(fout, delimiter=DELIM, lineterminator="\n")
        header = next(reader)
        writer.writerow(header)
        product_idx = header.index("PRODUKT_ID")
        for row in reader:
            total += 1
            if len(row) != len(header):      # truncated or broken line
                bad += 1
                continue
            if row[product_idx] == PRODUCT:
                writer.writerow(row)
                kept += 1
    return total, kept, bad


def write_sample(src_gz: Path, n: int) -> None:
    SAMPLE.mkdir(parents=True, exist_ok=True)
    with gzip.open(src_gz, "rt", encoding="utf-8", newline="") as fin, \
            open(SAMPLE / "istdaten_sample.csv", "w", encoding="utf-8", newline="") as fout:
        for i, line in enumerate(fin):
            if i > n:
                break
            fout.write(line)
    freq = RAW / "passagierfrequenz.csv"
    if freq.exists():
        with open(freq, encoding="utf-8-sig", newline="") as fin, \
                open(SAMPLE / "passagierfrequenz_sample.csv", "w", encoding="utf-8", newline="") as fout:
            for i, line in enumerate(fin):
                if i > n:
                    break
                fout.write(line)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--day", action="append", metavar="YYYY-MM-DD",
                    help="only process these operating days (repeatable)")
    ap.add_argument("--sample", type=int, metavar="N",
                    help="also write the first N rows of the first file to data/sample/")
    args = ap.parse_args()

    PROCESSED.mkdir(parents=True, exist_ok=True)
    files = sorted(RAW.glob("*_istdaten.csv"))
    if args.day:
        files = [f for f in files if f.name[:10] in args.day]
    if not files:
        print("no files in data/raw/, run download_sources.py first")
        return 1

    for src in files:
        dst = PROCESSED / f"{src.stem}_zug.csv.gz"
        if dst.exists():
            print(f"skip   {dst.name} (exists)")
            continue
        total, kept, bad = filter_file(src, dst)
        print(f"filter {src.name}: {kept:,} of {total:,} rows kept, {bad} malformed "
              f"-> {dst.name} ({dst.stat().st_size / 1e6:.1f} MB)")

    if args.sample:
        first = sorted(PROCESSED.glob("*_zug.csv.gz"))[0]
        write_sample(first, args.sample)
        print(f"sample {args.sample} rows written to {SAMPLE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
