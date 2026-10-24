#!/usr/bin/env python3
"""Two-FIFO LSQ unit tests and scheduler option on/off regressions (WSL/Linux)."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from run_prm_pipeline import ROOT, run, CASES as BASE_CASES

CASES = [(top, params) for top, params in BASE_CASES if top.startswith('tb_scheduler_')]
for depth, orders, lanes in [(1, 1, 1), (2, 2, 1), (7, 2, 3), (8, 3, 2), (17, 4, 5)]:
    CASES.append(('tb_load_store_queue', dict(DEPTH=depth, ORDERS=orders, LANES=lanes)))
for d, w, r, u, writes in [(3, 3, 5, 3, 0), (2, 3, 5, 3, 1), (1, 1, 2, 1, 1)]:
    CASES.append(('tb_scheduler_flow', dict(DECODE=d, WINDOWS=w, RANGE=r, UPDATES=u, WRITES=writes, LSQ=1)))
for d, depth, path, seed in [(2, 7, 2, 13), (3, 3, 1, 29), (1, 1, 2, 43)]:
    CASES.append(('tb_scheduler_stress', dict(DECODE=d, LSQ=1, LSQ_ENTRIES=depth, LSQ_PATH=path, SEED=seed)))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--unit-only', action='store_true')
    parser.add_argument('--top', choices=sorted({top for top, _ in CASES}))
    parser.add_argument('--output', type=type(ROOT), default=ROOT / 'build/lsq_regression')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = [p for folder in ('RTL', 'TB') for p in (ROOT / 'src' / folder).glob('*.sv')]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    cases = [c for c in CASES if c[0] == 'tb_load_store_queue'] if args.unit_only else CASES
    if args.top:
        cases = [c for c in cases if c[0] == args.top]
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        records = list(pool.map(lambda case: run(case, args.output), cases))
    if any(hashlib.sha256(p.read_bytes()).hexdigest() != hashes[str(p.relative_to(ROOT))] for p in sources):
        raise RuntimeError('RTL/test sources changed during regression')
    (args.output / 'source_hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
    (args.output / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
    print(f'{sum(r["passed"] for r in records)}/{len(records)} passed', flush=True)
    raise SystemExit(any(not r['passed'] for r in records))
