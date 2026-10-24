#!/usr/bin/env python3
"""Read completed LSQ implementation reports; separate fresh builds from fixed-route STA."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def timing(path):
    text = path.read_text()
    tail = text.split('| Design Timing Summary', 1)[1]
    values = next(line.split() for line in tail.splitlines()
                  if re.match(r'^\s+-?\d+\.\d+\s+-?\d+\.\d+', line))
    names = ['wns_ns', 'tns_ns', 'setup_failing_endpoints', 'setup_total_endpoints',
             'whs_ns', 'ths_ns', 'hold_failing_endpoints', 'hold_total_endpoints',
             'wpws_ns', 'tpws_ns', 'pulse_failing_endpoints', 'pulse_total_endpoints']
    if len(values) != len(names):
        raise ValueError(f'Unexpected timing table: {path}')
    record = dict(zip(names, map(float, values)))
    record['timing_met'] = all(record[k] >= 0 for k in ['wns_ns', 'whs_ns', 'wpws_ns']) and all(
        record[k] == 0 for k in ['setup_failing_endpoints', 'hold_failing_endpoints', 'pulse_failing_endpoints'])
    if record['timing_met'] != ('All user specified timing constraints are met.' in text):
        raise ValueError(f'Timing checks disagree: {path}')
    return record


def stage(output, name):
    result = timing(output / f'{name}_timing_summary.rpt')
    util = (output / f'{name}_utilization.rpt').read_text()
    for label, key in [('Slice LUTs', 'luts'), ('Slice Registers', 'ff'), ('Block RAM Tile', 'bram_tiles')]:
        result[key] = float(re.search(r'^\| '+label+r'\*?\s+\|\s*([\d.]+)', util, re.M)[1])
    check = (output / f'{name}_check_timing.rpt').read_text()
    for label in ['no_clock', 'unconstrained_internal_endpoints', 'loops', 'latch_loops']:
        result[label] = int(re.search(r'checking '+label+r' \((\d+)\)', check)[1])
    details = {}
    for line in (output / f'{name}_summary.txt').read_text().splitlines():
        if ': ' in line:
            k, v = line.split(': ', 1)
            details[k] = v
    result['critical_path_and_netlist'] = details
    result['top_level_hierarchy'] = {}
    for line in (output / f'{name}_hierarchy.rpt').read_text().splitlines():
        if line.startswith('|   ') and not line.startswith('|    '):
            cells = [cell.strip() for cell in line.split('|')[1:-1]]
            if len(cells) == 10 and cells[2].isdigit():
                result['top_level_hierarchy'][cells[0]] = dict(
                    luts=int(cells[2]), ff=int(cells[6]),
                    bram_tiles=int(cells[7])+int(cells[8])/2)
    for direction in ['from', 'to']:
        path = output / f'{name}_lsq_{direction}.rpt'
        if path.exists():
            report = path.read_text()
            result[f'lsq_{direction}_slack_ns'] = float(re.search(r'Slack \(\w+\)\s*:\s*(-?[\d.]+)ns', report)[1])
    result['drc'] = []
    for line in (output / f'{name}_drc.rpt').read_text().splitlines():
        match = re.match(r'^\|\s*(\S+)\s*\|\s*(Warning|Critical Warning|Error)\s*\|\s*(.*?)\s*\|\s*(\d+)\s*\|', line)
        if match:
            rule, severity, description, count = match.groups()
            result['drc'].append(dict(rule=rule, severity=severity, description=description, reported_count=int(count)))
    return result


def summarize(output):
    manifest = json.loads((output / 'manifest.json').read_text())
    if manifest.get('vivado_exit') != 0 or 'COMPLETE' not in (output / 'status.txt').read_text():
        raise ValueError('Implementation did not complete successfully')
    for name, digest in manifest['synthesis_source_hashes'].items():
        if hashlib.sha256((output / 'source' / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f'Synthesis snapshot changed: {name}')
    result = dict(manifest=manifest, stages={s: stage(output, s) for s in ['synth', 'placed', 'routed']})
    route = (output / 'routed_route_status.rpt').read_text()
    result['route'] = {}
    for label, key in [('routable nets', 'routable_nets'), ('fully routed nets', 'fully_routed_nets'),
                       ('nets with routing errors', 'routing_error_nets')]:
        result['route'][key] = int(re.search(re.escape(label)+r'\.+\s*:\s*(\d+)', route)[1])
    route = result['route']
    route['complete'] = route['routable_nets'] == route['fully_routed_nets'] and route['routing_error_nets'] == 0
    routed = result['stages']['routed']
    result['fresh_build_pass'] = route['complete'] and routed['timing_met'] and all(
        routed[k] == 0 for k in ['no_clock', 'unconstrained_internal_endpoints', 'loops', 'latch_loops']) and not any(
        r['severity'] in ['Error', 'Critical Warning'] for r in routed['drc']) and all(
        routed['critical_path_and_netlist'][k] == '0' for k in ['Latches', 'Black boxes'])
    result['fixed_route_sweep'] = []
    for row in csv.DictReader((output / 'sweep/results.csv').open()):
        record = {k: float(v) for k, v in row.items()}
        tag = row['mhz'].replace('.', 'p')
        record.update(timing(output / 'sweep' / f'{tag}mhz_timing_summary.rpt'))
        result['fixed_route_sweep'].append(record)
    result['fixed_route_best_measured_mhz'] = max(
        row['mhz'] for row in result['fixed_route_sweep'] if row['timing_met'])
    (output / 'results.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = summarize(args.output)
    print(json.dumps({k: v for k, v in result.items() if k != 'manifest'}, indent=2))
