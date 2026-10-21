#!/usr/bin/env python3
"""Extra FCL capacity and IST notification-reset checks; use with run_ist_prefetch.py."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
from run_prm_pipeline import ROOT, run

CASES = [('tb_flow_control_logic', dict(DECODE=d, WINDOWS=w, RANGE=r))
         for d, w, r in [(1, 1, 2), (3, 3, 5), (2, 8, 16)]]
CASES.append(('tb_ist_notify_reset', {}))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--only', choices=['all', 'notify'], default='all')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/ist_boundary_regression')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = [p for folder in ('RTL', 'TB') for p in (ROOT / 'src' / folder).glob('*.sv')]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    cases = CASES if args.only == 'all' else CASES[-1:]
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        records = list(pool.map(lambda case: run(case, args.output), cases))
    if any(hashlib.sha256(p.read_bytes()).hexdigest() != hashes[str(p.relative_to(ROOT))] for p in sources):
        raise RuntimeError('Sources changed during regression')
    (args.output / 'source_hashes.json').write_text(json.dumps(hashes, indent=2)+'\n')
    (args.output / 'results.json').write_text(json.dumps(records, indent=2)+'\n')
    print(f'{sum(r["passed"] for r in records)}/{len(records)} passed', flush=True)
    raise SystemExit(any(not r['passed'] for r in records))
