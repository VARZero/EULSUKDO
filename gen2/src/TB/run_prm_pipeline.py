#!/usr/bin/env python3
"""Run PRM pipeline regression with Python in WSL/Linux and Verilator installed."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CASES = []


def add(top, **params):
    CASES.append((top, params))


for d, u, depth in [(3, 5, 2), (3, 1, 2), (1, 1, 3), (3, 5, 3)]:
    add('tb_prm_pipeline', DECODE=d, UPDATES=u, DEPTH=depth)
for d, u, p in [(2, 5, 64), (1, 1, 18), (3, 2, 32), (2, 1, 64)]:
    add('tb_physical_register_mapper', DECODE=d, UPDATES=u, PHYREGS=p)
for p, r in [(2, 1), (3, 4), (17, 3), (64, 4), (65, 7), (128, 1)]:
    add('tb_prm_return_selection', PHYREGS=p, RETURNS=r)
for d, w, r, u, writes in [(3, 3, 5, 3, 0), (1, 1, 2, 1, 0),
                          (2, 3, 5, 3, 1), (1, 1, 2, 1, 1)]:
    add('tb_scheduler_flow', DECODE=d, WINDOWS=w, RANGE=r, UPDATES=u, WRITES=writes)
for d, w, r, n, u, seed in [(2, 8, 16, 128, 5, 1), (3, 3, 8, 17, 2, 7),
                           (1, 1, 8, 16, 1, 19)]:
    add('tb_scheduler_stress', DECODE=d, WINDOWS=w, RANGE=r, IST_ENTRIES=n, UPDATES=u, SEED=seed)
for u, seed in [(2, 23), (7, 41)]:
    add('tb_scheduler_stress', DECODE=4, EX_CORES=7, ISSUE=7, IST_ENTRIES=128,
        UPDATES=u, SEED=seed)


def run(case, output):
    top, params = case
    name = top + '__' + '_'.join(f'{k}-{v}' for k, v in params.items())
    record = dict(name=name, parameters=params, passed=False)
    with tempfile.TemporaryDirectory(prefix='prm-pipeline-') as build:
        command = ['verilator', '--binary', '--timing', '--assert', '-Wno-fatal',
                   '--unroll-count', '512', '--top-module', top, '-j', '2', '--Mdir', build]
        command += [f'-G{k}={v}' for k, v in params.items()]
        command += [str(ROOT / 'src/TB' / f'{top}.sv')]
        command += [str(p) for p in sorted((ROOT / 'src/RTL').glob('*.sv'))]
        try:
            with (output / f'{name}.build.log').open('w') as log:
                log.write(' '.join(command) + '\n'); log.flush()
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=600)
            record['build_exit'] = result.returncode
            if result.returncode == 0:
                result = subprocess.run([str(Path(build) / f'V{top}')], capture_output=True, text=True, timeout=120)
                (output / f'{name}.run.log').write_text(result.stdout + result.stderr)
                record['run_exit'] = result.returncode
                record['passed'] = result.returncode == 0 and 'PASS' in result.stdout
        except subprocess.TimeoutExpired:
            record['error'] = 'timeout'
    print(('PASS ' if record['passed'] else 'FAIL ') + name, flush=True)
    return record


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/prm_pipeline_regression')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = [p for folder in ('RTL', 'TB') for p in (ROOT / 'src' / folder).glob('*.sv')]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        records = list(pool.map(lambda case: run(case, args.output), CASES))
    if any(hashlib.sha256(p.read_bytes()).hexdigest() != hashes[str(p.relative_to(ROOT))] for p in sources):
        raise RuntimeError('RTL/test sources changed during regression; rerun against a stable snapshot')
    (args.output / 'source_hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
    (args.output / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
    print(f'{sum(r["passed"] for r in records)}/{len(records)} passed', flush=True)
    raise SystemExit(any(not r['passed'] for r in records))
