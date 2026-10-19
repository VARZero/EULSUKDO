#!/usr/bin/env python3
"""Run IST prefetch, allocation and full scheduler tests in WSL/Linux."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from run_prm_pipeline import ROOT, run, CASES as PRM_CASES

CASES = [(top, params) for top, params in PRM_CASES if top.startswith('tb_scheduler_')]
for d, o, u, n, issue, banks in [
    (2, 2, 5, 16, 5, 8), (1, 3, 3, 17, 5, 8), (3, 3, 5, 17, 5, 8),
    (4, 2, 2, 128, 7, 8), (4, 2, 7, 33, 7, 8), (2, 2, 3, 17, 5, 2),
    (1, 2, 2, 8, 1, 1), (2, 2, 2, 3, 3, 8), (3, 2, 5, 128, 5, 8),
]:
    CASES.append(('tb_instruction_state_table', dict(DECODE=d, OPERANDS=o, UPDATES=u,
                  ENTRIES=n, ISSUE=issue, BANKS=banks)))
for n, d, b in [(3, 2, 8), (8, 1, 1), (17, 3, 4), (128, 2, 8),
                (33, 4, 8), (128, 7, 8), (64, 4, 16)]:
    CASES.append(('tb_ist_allocation', dict(ENTRIES=n, DECODE=d, BANKS=b)))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--output', type=type(ROOT), default=ROOT / 'build/ist_prefetch_regression')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = [p for folder in ('RTL', 'TB') for p in (ROOT / 'src' / folder).glob('*.sv')]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        records = list(pool.map(lambda case: run(case, args.output), CASES))
    if any(hashlib.sha256(p.read_bytes()).hexdigest() != hashes[str(p.relative_to(ROOT))] for p in sources):
        raise RuntimeError('Sources changed during regression')
    (args.output / 'source_hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
    (args.output / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
    print(f'{sum(r["passed"] for r in records)}/{len(records)} passed', flush=True)
    raise SystemExit(any(not r['passed'] for r in records))
