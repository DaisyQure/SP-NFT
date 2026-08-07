"""Aggregate SP-NFT dual-end sessions for Week 2 software validation."""
from __future__ import annotations

import csv
import json
import os
import re
from pathlib import Path

import pandas as pd


REPO_ROOT = Path(__file__).resolve().parent.parent
SESSION_ROOT = Path(os.environ.get("SPNFT_SESSION_ROOT", REPO_ROOT / "examples" / "sessions"))
OUT_ROOT = Path(os.environ.get("SPNFT_OUTPUT_ROOT", REPO_ROOT / "examples" / "aggregate"))
MODE_RE = re.compile(r"^\d{8}_\d{6}_(simulation|attention|relax|monitor)_")
REQUIRED = ["events_log.csv", "timeseries_rec.csv", "meta.json", "performance_summary.csv", "report/summary.csv", "report/report.html"]


def metric_row(perf: pd.DataFrame, name: str):
    rows = perf[perf["metric"].astype(str) == name]
    return None if rows.empty else rows.iloc[0]


def inspect_session(path: Path) -> dict:
    mode_match = MODE_RE.match(path.name)
    mode = mode_match.group(1) if mode_match else path.name if path.name in {"simulation", "attention", "relax", "monitor"} else "unknown"
    missing = [f for f in REQUIRED if not (path / f).is_file()]
    try:
        published_path = path.resolve().relative_to(REPO_ROOT.resolve()).as_posix()
    except ValueError:
        published_path = str(path)
    row = {"session": path.name, "session_dir": published_path, "mode": mode, "missing_files": " || ".join(missing)}
    row["week2_cohort"] = int("_SMOKE_" in path.name or path.name in {"simulation", "attention", "relax", "monitor"})
    row["complete"] = int(not missing)
    try:
        meta = json.loads((path / "meta.json").read_text(encoding="utf-8"))
        row["duration_sec"] = float(meta.get("duration_sec", "nan"))
        row["subject_id"] = meta.get("subject", {}).get("id", "")
    except Exception as exc:
        row["duration_sec"] = float("nan")
        row["subject_id"] = ""
        row["meta_error"] = str(exc)
    try:
        events = pd.read_csv(path / "events_log.csv")
        row["event_rows"] = len(events)
        row["phase_ack_n"] = int(((events["kind"] == "sync") & (events["key"] == "phase_ack")).sum())
        row["stop_ack_n"] = int(((events["kind"] == "sync") & (events["key"] == "session_stop_ack")).sum())
        row["phase_ack_latency_n"] = int(((events["kind"] == "latency") & (events["key"] == "phase_ack_latency_ms")).sum())
        row["stop_ack_latency_n"] = int(((events["kind"] == "latency") & (events["key"] == "session_stop_ack_latency_ms")).sum())
    except Exception as exc:
        row["event_error"] = str(exc)
    try:
        perf = pd.read_csv(path / "performance_summary.csv")
        phase = metric_row(perf, "phase_ack_latency_ms")
        stop = metric_row(perf, "session_stop_ack_latency_ms")
        for prefix, metric in [("phase", phase), ("stop", stop)]:
            if metric is not None:
                for field in ["N", "mean", "std", "min", "median", "max"]:
                    row[f"{prefix}_{field}"] = float(metric[field])
    except Exception as exc:
        row["performance_error"] = str(exc)
    row["valid_session"] = int(
        row.get("complete", 0) == 1
        and row.get("phase_ack_n", 0) == 8
        and row.get("stop_ack_n", 0) == 1
        and row.get("phase_ack_latency_n", 0) == 8
        and row.get("stop_ack_latency_n", 0) == 1
        and row.get("duration_sec", 0) > 0
    )
    return row


def main():
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    sessions = []
    for path in sorted(SESSION_ROOT.iterdir()):
        if path.is_dir() and (MODE_RE.match(path.name) or path.name in {"simulation", "attention", "relax", "monitor"}):
            sessions.append(inspect_session(path))
    detail = pd.DataFrame(sessions)
    if detail.empty:
        raise SystemExit(f"No session folders found below {SESSION_ROOT}")
    detail.to_csv(OUT_ROOT / "week2_session_detail.csv", index=False, encoding="utf-8-sig")

    valid = detail[(detail["valid_session"] == 1) & (detail["week2_cohort"] == 1)].copy()
    if not valid.empty:
        numeric = [c for c in ["phase_mean", "phase_std", "phase_min", "phase_median", "phase_max", "stop_mean", "duration_sec"] if c in valid]
        grouped = valid.groupby("mode")[numeric].agg(["count", "mean", "std", "min", "median", "max"]).reset_index()
        grouped.to_csv(OUT_ROOT / "week2_mode_summary.csv", index=False, encoding="utf-8-sig")
        mode_counts = valid.groupby("mode").size().rename("valid_session_count").reset_index()
        mode_counts.to_csv(OUT_ROOT / "week2_mode_counts.csv", index=False, encoding="utf-8-sig")

    checks = {
        "total_sessions": int(len(detail)),
        "complete_sessions": int(detail["complete"].sum()),
        "incomplete_sessions": int((detail["complete"] == 0).sum()),
        "valid_sessions": int(detail["valid_session"].sum()),
        "invalid_sessions": int((detail["valid_session"] == 0).sum()),
        "week2_attempted_sessions": int(detail["week2_cohort"].sum()),
        "week2_valid_sessions": int(((detail["week2_cohort"] == 1) & (detail["valid_session"] == 1)).sum()),
        "week2_invalid_sessions": int(((detail["week2_cohort"] == 1) & (detail["valid_session"] == 0)).sum()),
        "modes": sorted(detail["mode"].unique().tolist()),
        "all_valid_have_eight_phase_acks": bool((valid.get("phase_ack_n", pd.Series(dtype=float)) == 8).all()) if not valid.empty else False,
        "all_valid_have_one_stop_ack": bool((valid.get("stop_ack_n", pd.Series(dtype=float)) == 1).all()) if not valid.empty else False,
    }
    (OUT_ROOT / "week2_quality_checks.json").write_text(json.dumps(checks, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(checks, ensure_ascii=False, indent=2))
    print(f"detail={OUT_ROOT / 'week2_session_detail.csv'}")


if __name__ == "__main__":
    main()
