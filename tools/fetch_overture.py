#!/usr/bin/env python3
"""Download Overture Maps places for a bounding box into data/overture/<name>.csv.gz.

The game never talks to Overture while running: this is run once by a developer
and the file is committed. The server loads it into the database at boot
(see lib/overture.rb).

    pip install duckdb
    python3 tools/fetch_overture.py [--out DIR] [--nearest N] NAME WEST SOUTH EAST NORTH [RELEASE]

    python3 tools/fetch_overture.py mississauga -79.80 43.52 -79.62 43.69

The running app uses this same script (with --out, into a temporary folder) to
fetch the area around a new player; see lib/overture.rb.

Releases are listed at https://docs.overturemaps.org/ (default: the one below).
Overture Places are CDLA-Permissive-2.0 licensed; see the README for credit.
"""
import csv, gzip, os, re, sys, json
import duckdb

DEFAULT_RELEASE = '2026-10-21.0'
PER_TILE = 3

def main(argv):
    argv = list(argv)
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'overture')
    if '--out' in argv:
        i = argv.index('--out')
        out_dir = argv[i + 1]
        del argv[i:i + 2]
    nearest = 0
    if '--nearest' in argv:
        i = argv.index('--nearest')
        nearest = int(argv[i + 1])
        del argv[i:i + 2]
    if len(argv) < 6:
        sys.exit(__doc__)
    name = argv[1]
    west, south, east, north = map(float, argv[2:6])
    release = argv[6] if len(argv) > 6 else DEFAULT_RELEASE
    if not re.fullmatch(r'[A-Za-z0-9_-]+', name) or not re.fullmatch(r'\d{4}-\d\d-\d\d\.\d+', release):
        sys.exit('bad name or release')
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f'{name}.csv.gz')

    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2'; "
                "SET memory_limit='256MB'; SET threads=2;")
    rows = con.execute(f"""
        SELECT id,
               names.primary                    AS name,
               basic_category                   AS category,
               taxonomy.hierarchy[1]            AS grp,
               taxonomy.primary                 AS taxonomy,
               round(confidence, 3)             AS confidence,
               round(bbox.xmin, 6)              AS lng,
               round(bbox.ymin, 6)              AS lat
        FROM read_parquet('s3://overturemaps-us-west-2/release/{release}/theme=places/type=place/*',
                          hive_partitioning=1)
        WHERE bbox.xmin BETWEEN ? AND ? AND bbox.ymin BETWEEN ? AND ?
          AND names.primary IS NOT NULL
          AND coalesce(operating_status, 'open') <> 'permanently_closed'
        -- the game shows one building per 0.001-degree tile; keep the few most trusted
        QUALIFY row_number() OVER (PARTITION BY round(bbox.xmin * 1000), round(bbox.ymin * 1000)
                                   ORDER BY confidence DESC, id) <= {PER_TILE}
        ORDER BY lng, lat, id
    """, [west, east, south, north]).fetchall()
    if nearest > 0:  # keep only the places closest to the middle of the box
        mid_lng, mid_lat = (west + east) / 2, (south + north) / 2
        rows = sorted(rows, key=lambda r: (r[6] - mid_lng) ** 2 + (r[7] - mid_lat) ** 2)[:nearest]
        rows.sort(key=lambda r: (r[6], r[7], r[0]))

    with gzip.open(path, 'wt', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['id', 'name', 'category', 'group', 'taxonomy', 'confidence', 'lng', 'lat'])
        w.writerows(rows)
    meta = {'name': name, 'release': release, 'west': west, 'south': south, 'east': east,
            'north': north, 'rows': len(rows)}
    with open(path[:-len('.csv.gz')] + '.json', 'w') as f:
        json.dump(meta, f, indent=2); f.write('\n')
    print(f'{len(rows)} places -> {path}')

if __name__ == '__main__':
    main(sys.argv)
