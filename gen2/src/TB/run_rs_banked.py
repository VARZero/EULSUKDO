#!/usr/bin/env python3
"""RS banked queue checks plus integrated scheduler regressions (WSL/Linux)."""
import argparse
import hashlib
import json
from concurrent.futures import ThreadPoolExecutor
from run_prm_pipeline import ROOT, run, CASES as ALL_CASES

CASES = [(top, params) for top, params in ALL_CASES if top.startswith('tb_scheduler_')]
for d, issue, size in [(3, 5, 128), (2, 5, 17), (1, 1, 1), (4, 7, 33), (3, 5, 8)]:
    CASES.append(('tb_ready_station', dict(DECODE=d, ISSUE=issue, RS_FIFO=size)))
for w, r, n in [(8, 3, 128), (7, 1, 128), (3, 5, 17), (1, 1, 1), (8, 3, 8)]:
    CASES.append(('tb_rs_banked_queue', dict(WRITES=w, READS=r, ENTRIES=n)))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--output', type=type(ROOT), default=ROOT / 'build/rs_banked_regression')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = [p for folder in ('RTL', 'TB') for p in (ROOT / 'src' / folder).glob('*.sv')]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        records = list(pool.map(lambda case: run(case, args.output), CASES))
    assert all(hashlib.sha256(p.read_bytes()).hexdigest() == hashes[str(p.relative_to(ROOT))] for p in sources)
    (args.output / 'source_hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
    (args.output / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
    print(f'{sum(r["passed"] for r in records)}/{len(records)} passed', flush=True)
    raise SystemExit(any(not r['passed'] for r in records))
