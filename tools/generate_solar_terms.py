#!/usr/bin/env python3
"""Generate CalStitch's solar-term dates and UTC instants; no network calls."""
import argparse
from collections import defaultdict
from contextlib import closing

from datetime import datetime, timezone, timedelta
import hashlib
from pathlib import Path
from zoneinfo import ZoneInfo

import skyfield
from skyfield import almanac, almanac_east_asia
from skyfield.api import load, load_file

FIRST, LAST = 1901, 2100
EPHEMERIS_SHA256 = "c1c7feeab882263fc493a9d5a5b2ddd71b54826cdf65d8d17a76126b260a49f2"
TERM_ORDER = tuple((19 + offset) % 24 for offset in range(24))
TAIPEI = ZoneInfo("Asia/Taipei")
UTC8 = timezone(timedelta(hours=8))


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("ephemeris", type=Path, help="Official NASA/JPL de440s.bsp")
    args.add_argument("table", type=Path)
    args.add_argument("--instants", type=Path, help="Optional UTC epoch millisecond table")
    args.add_argument("--audit", type=Path, help="Optional CSV of crossing instants and local dates")
    options = args.parse_args()
    if skyfield.__version__ != "1.53":
        raise SystemExit("Use Skyfield 1.53 for reproducible regeneration.")
    with options.ephemeris.open("rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != EPHEMERIS_SHA256:
            raise SystemExit("Unexpected SHA-256 for the JPL ephemeris.")
    with closing(load_file(str(options.ephemeris))) as ephemeris:
        ts = load.timescale(builtin=True)
        t0 = ts.from_datetime(datetime(FIRST, 1, 1, tzinfo=TAIPEI))
        t1 = ts.from_datetime(datetime(LAST + 1, 1, 1, tzinfo=TAIPEI))
        times, indices = almanac.find_discrete(t0, t1, almanac_east_asia.solar_terms(ephemeris))
        moments = times.utc_datetime()
        rows = defaultdict(list)
        audit = ["taipei_date,term_index,term,utc,taipei,fixed_utc8_date"]
        for moment, index in zip(moments, indices, strict=True):
            taipei = moment.astimezone(TAIPEI)
            index = int(index)
            rows[taipei.year].append((index, taipei.month, taipei.day, round(moment.timestamp() * 1_000)))
            fixed = moment.astimezone(UTC8)
            name = almanac_east_asia.SOLAR_TERMS_ZHT[index]
            audit.append(f"{taipei.date()},{index},{name},{moment.isoformat()},{taipei.isoformat()},{fixed.date()}")
    if set(rows) != set(range(FIRST, LAST + 1)):
        raise SystemExit("Years missing or outside range.")
    output = []
    instants = []
    for year in range(FIRST, LAST + 1):
        terms = rows[year]
        if tuple(index for index, _, _, _ in terms) != TERM_ORDER:
            raise SystemExit(f"{year}: incorrect or incomplete solar-term order.")
        if any(month != ordinal // 2 + 1 for ordinal, (_, month, _, _) in enumerate(terms)):
            raise SystemExit(f"{year}: solar term outside its expected month.")
        output.append(f"{year}:" + "".join(f"{day:02d}" for _, _, day, _ in terms))
        instants.append(f"{year}:" + ",".join(str(ms) for _, _, _, ms in terms))
    # Never write a partial table if the kernel or year validation fails.
    options.table.write_text("\n".join(output) + "\n", encoding="ascii")
    if options.instants:
        options.instants.write_text("\n".join(instants) + "\n", encoding="ascii")
    if options.audit:
        options.audit.write_text("\n".join(audit) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
