#!/usr/bin/env python3
import csv
import sys
from pathlib import Path


def main() -> None:
    raw_path = Path(sys.argv[1])
    csv_path = Path(sys.argv[2])
    md_path = Path(sys.argv[3])

    with raw_path.open(newline="", encoding="utf-8") as source:
        rows = list(csv.DictReader(source))

    baseline = {
        (row["slow_latency"], row["workload"]): float(row["ipc"])
        for row in rows
        if row["decode_width"] == "1"
    }
    for row in rows:
        ipc = float(row["ipc"])
        base = baseline[(row["slow_latency"], row["workload"])]
        row["speedup_vs_decode1"] = f"{ipc / base:.3f}"
        row["gain_percent"] = f"{(ipc / base - 1.0) * 100.0:.1f}"

    fields = list(rows[0])
    with csv_path.open("w", newline="", encoding="utf-8") as target:
        writer = csv.DictWriter(target, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    lines = [
        "| Configuration | Decode | Issue ALU+slow | Slow latency | Workload | Cycles | IPC | vs decode1 |",
        "|---|---:|---:|---:|---|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            f"| {row['config']} | {row['decode_width']} | "
            f"{row['issue_alu']}+{row['issue_slow']} | {row['slow_latency']} | "
            f"{row['workload']} | {row['cycles']} | {float(row['ipc']):.3f} | "
            f"{float(row['speedup_vs_decode1']):.2f}x ({float(row['gain_percent']):+.1f}%) |"
        )
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
