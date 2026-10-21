#!/usr/bin/env python3
"""Check PRM completion selection, throughput, stalls and reset in WSL/Linux."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
from run_prm_pipeline import ROOT, run

CASES = [('tb_prm_drain_pipeline', dict(PHYREGS=p, UPDATES=u))
         for p, u in [(2, 1), (17, 1), (17, 5), (64, 1), (64, 5), (65, 5)]]

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/prm_drain_regression')
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
