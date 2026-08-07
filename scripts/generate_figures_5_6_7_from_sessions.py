import csv
import html
import json
import math
import os
import re
from pathlib import Path

import pandas as pd
from PIL import Image, ImageDraw, ImageFont


REPO_ROOT = Path(__file__).resolve().parent.parent
SESSION_ROOT = Path(os.environ.get("SPNFT_SESSION_ROOT", REPO_ROOT / "examples" / "sessions"))
OUT_DIR = Path(os.environ.get("SPNFT_FIGURE_OUTPUT_ROOT", REPO_ROOT / "figures"))
DATA_DIR = Path(os.environ.get("SPNFT_FIGURE_DATA_ROOT", REPO_ROOT / "figure_data"))

COLORS = {
    "navy": "#1F4E79",
    "teal": "#2A9D8F",
    "orange": "#E76F51",
    "gray": "#333333",
    "light": "#F3F6F8",
    "grid": "#D5DEE6",
    "phase_a": "#EEF3F7",
    "phase_b": "#FFF3ED",
}


def ensure_dirs():
    OUT_DIR.mkdir(exist_ok=True)
    DATA_DIR.mkdir(exist_ok=True)


def latest_sessions():
    """Select one reproducible example session per mode from the valid Week 2 cohort."""
    detail_path = REPO_ROOT / "examples" / "aggregate" / "week2_session_detail.csv"
    if not detail_path.is_file():
        raise RuntimeError(f"Missing aggregated Week 2 detail: {detail_path}")
    detail = pd.read_csv(detail_path)
    valid = detail[(detail["week2_cohort"] == 1) & (detail["valid_session"] == 1)]
    required = ["simulation", "attention", "relax", "monitor"]
    by_mode = {}
    for mode in required:
        rows = valid[valid["mode"] == mode].sort_values("session")
        if rows.empty:
            raise RuntimeError(f"Missing valid Week 2 session for: {mode}")
        session = Path(rows.iloc[0]["session_dir"])
        by_mode[mode] = session if session.is_absolute() else REPO_ROOT / session
    return by_mode


def read_events(session):
    return pd.read_csv(session / "events_log.csv")


def read_timeseries(session):
    return pd.read_csv(session / "timeseries_rec.csv")


def collect_latency_points(sessions):
    rows = []
    for mode, session in sessions.items():
        ev = read_events(session)
        lat = ev[(ev["kind"] == "latency") & ev["key"].isin(["phase_ack_latency_ms", "session_stop_ack_latency_ms"])]
        for _, r in lat.iterrows():
            ack_type = "Phase ACK" if r["key"] == "phase_ack_latency_ms" else "Stop ACK"
            rows.append({
                "mode": mode,
                "ack_type": ack_type,
                "latency_ms": float(r["value"]),
                "session": session.name,
            })
    df = pd.DataFrame(rows)
    if df.empty:
        raise RuntimeError("No ACK latency rows found in events_log.csv files")
    return df


def collect_week2_latency_points():
    """Collect the full cohort when available; otherwise use public examples."""
    detail_path = REPO_ROOT / "reported_week2_summary" / "week2_session_detail.csv"
    detail = pd.read_csv(detail_path)
    valid = detail[(detail["week2_cohort"] == 1) & (detail["valid_session"] == 1)]
    rows = []
    for _, item in valid.sort_values(["mode", "session"]).iterrows():
        session = Path(item["session_dir"])
        if not session.is_absolute():
            session = REPO_ROOT / session
        if not (session / "events_log.csv").is_file():
            continue
        ev = read_events(session)
        lat = ev[(ev["kind"] == "latency") & ev["key"].isin(["phase_ack_latency_ms", "session_stop_ack_latency_ms"])]
        for _, r in lat.iterrows():
            rows.append({
                "mode": item["mode"],
                "ack_type": "Phase ACK" if r["key"] == "phase_ack_latency_ms" else "Stop ACK",
                "latency_ms": float(r["value"]),
                "session": item["session"],
            })
    if rows:
        return pd.DataFrame(rows)
    print("Full 40-session raw cohort is not included; Figure 5 uses the four public example sessions.")
    return collect_latency_points(latest_sessions())


def save_latency_data(df):
    out = DATA_DIR / "Figure5_ack_latency_points.csv"
    df.to_csv(out, index=False, encoding="utf-8-sig")
    summary = df.groupby(["mode", "ack_type"])["latency_ms"].agg(["count", "mean", "std", "min", "median", "max"]).reset_index()
    summary.to_csv(DATA_DIR / "Figure5_ack_latency_summary.csv", index=False, encoding="utf-8-sig")


def svg_header(w, h):
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',
        '<rect width="100%" height="100%" fill="white"/>',
        '<style><![CDATA['
        'text{font-family:Arial,Helvetica,sans-serif;fill:#333333}'
        '.title{font-size:28px;font-weight:700}'
        '.label{font-size:18px}'
        '.small{font-size:15px}'
        '.panel{font-size:21px;font-weight:700}'
        ']]></style>',
    ]


def svg_footer():
    return ["</svg>"]


def line(x1, y1, x2, y2, color="#333333", width=2, dash=None):
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
    return f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{color}" stroke-width="{width}"{dash_attr}/>'


def circle(x, y, r, color, stroke="white", width=1.5):
    return f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{color}" stroke="{stroke}" stroke-width="{width}"/>'


def text(x, y, s, cls="label", anchor="middle"):
    return f'<text x="{x:.1f}" y="{y:.1f}" class="{cls}" text-anchor="{anchor}">{html.escape(str(s))}</text>'


def polyline(points, color, width=3):
    pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in points)
    return f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"/>'


def make_figure5(df):
    w, h = 1800, 1100
    ml, mr, mt, mb = 150, 80, 130, 160
    plot_w, plot_h = w - ml - mr, h - mt - mb
    modes = ["simulation", "attention", "relax", "monitor"]
    labels = ["Simulation", "Attention", "Relaxation", "Monitoring"]
    max_y = max(180, math.ceil(df["latency_ms"].max() / 20) * 20)

    parts = svg_header(w, h)
    parts.append(text(w / 2, 55, "Single-session acknowledgement latency validation", "title"))
    parts.append(text(w / 2, 92, "Simulated EEG platform validation runs; raw ACK latency points are shown.", "small"))

    # grid and axes
    for val in range(0, int(max_y) + 1, 20):
        y = mt + plot_h - (val / max_y) * plot_h
        parts.append(line(ml, y, w - mr, y, COLORS["grid"], 1))
        parts.append(text(ml - 18, y + 5, val, "small", "end"))
    parts.append(line(ml, mt, ml, mt + plot_h, COLORS["gray"], 2))
    parts.append(line(ml, mt + plot_h, w - mr, mt + plot_h, COLORS["gray"], 2))

    jitter = {
        "Phase ACK": -25,
        "Stop ACK": 25,
    }
    color = {
        "Phase ACK": COLORS["navy"],
        "Stop ACK": COLORS["orange"],
    }
    group_gap = plot_w / len(modes)
    for i, mode in enumerate(modes):
        cx = ml + group_gap * (i + 0.5)
        parts.append(text(cx, mt + plot_h + 42, labels[i], "label"))
        subset_mode = df[df["mode"] == mode]
        for ack_type in ["Phase ACK", "Stop ACK"]:
            vals = list(subset_mode[subset_mode["ack_type"] == ack_type]["latency_ms"])
            if not vals:
                continue
            xs = []
            for j, val in enumerate(vals):
                offset = jitter[ack_type] + (j - (len(vals)-1)/2) * 7
                x = cx + offset
                y = mt + plot_h - (val / max_y) * plot_h
                parts.append(circle(x, y, 8, color[ack_type]))
                xs.append(x)
            mean_val = sum(vals) / len(vals)
            y_mean = mt + plot_h - (mean_val / max_y) * plot_h
            parts.append(line(cx + jitter[ack_type] - 38, y_mean, cx + jitter[ack_type] + 38, y_mean, "#111111", 4))

    # labels
    parts.append(text(ml + plot_w / 2, h - 48, "Training mode", "label"))
    parts.append(f'<text x="42" y="{mt + plot_h/2:.1f}" class="label" transform="rotate(-90 42,{mt + plot_h/2:.1f})" text-anchor="middle">Acknowledgement latency (ms)</text>')

    # legend
    lx, ly = w - 420, 145
    parts.append(circle(lx, ly, 8, COLORS["navy"]))
    parts.append(text(lx + 24, ly + 6, "Phase ACK", "small", "start"))
    parts.append(circle(lx + 170, ly, 8, COLORS["orange"]))
    parts.append(text(lx + 194, ly + 6, "Stop ACK", "small", "start"))
    parts.append(text(w - 80, h - 32, "ACK latency does not represent complete EEG-to-scene feedback latency.", "small", "end"))

    parts.extend(svg_footer())
    out = OUT_DIR / "Figure5_ack_latency_validation.svg"
    out.write_text("\n".join(parts), encoding="utf-8")
    return out


def downsample(df, max_points=450):
    if len(df) <= max_points:
        return df
    step = math.ceil(len(df) / max_points)
    return df.iloc[::step].copy()


def add_phase_background(parts, ev, xmap, y0, plot_h):
    phases = ev[(ev["kind"] == "phase") & (ev["key"].isin(["phase_a_start", "phase_a_end", "phase_b_start", "phase_b_end"]))]
    starts = {}
    intervals = []
    for _, r in phases.iterrows():
        key = str(r["key"])
        val = int(r["value"])
        if key.endswith("_start"):
            phase = "A" if "_a_" in key else "B"
            starts[(val, phase)] = float(r["t_session_sec"])
        elif key.endswith("_end"):
            phase = "A" if "_a_" in key else "B"
            st = starts.get((val, phase))
            if st is not None:
                intervals.append((st, float(r["t_session_sec"]), phase, val))
    for st, en, ph, trial in intervals:
        x1, x2 = xmap(st), xmap(en)
        fill = COLORS["phase_a"] if ph == "A" else COLORS["phase_b"]
        parts.append(f'<rect x="{x1:.1f}" y="{y0:.1f}" width="{max(1, x2-x1):.1f}" height="{plot_h:.1f}" fill="{fill}" opacity="0.72"/>')


def make_figure6(sim_session):
    ts = read_timeseries(sim_session)
    ev = read_events(sim_session)
    cols = ts.columns
    required = ["t_session_sec", "simulation_intensity_rec", "simulation_intensity_pct_rec", "mu_power_rec", "beta_power_rec"]
    for c in required:
        if c not in cols:
            raise RuntimeError(f"Missing column for Figure 6: {c}")
    ts["t_rel"] = ts["t_session_sec"] - ts["t_session_sec"].min()
    tsd = downsample(ts, 550)

    plot_data = ts[["t_rel", "phase_rec", "trial_idx_rec", "simulation_intensity_rec", "simulation_intensity_pct_rec", "mu_power_rec", "beta_power_rec"]]
    plot_data.to_csv(DATA_DIR / "Figure6_simulated_eeg_feedback_chain_data.csv", index=False, encoding="utf-8-sig")

    w, h = 1800, 1180
    ml, mr, mt, mb = 150, 70, 140, 120
    gap = 90
    panel_h = (h - mt - mb - gap) / 2
    plot_w = w - ml - mr
    tmin, tmax = float(ts["t_rel"].min()), float(ts["t_rel"].max())

    def xmap(t):
        return ml + ((t - tmin) / max(tmax - tmin, 1e-9)) * plot_w

    parts = svg_header(w, h)
    parts.append(text(w / 2, 55, "Simulated EEG proof-of-function validation", "title"))
    parts.append(text(w / 2, 92, "Online feature stream and adaptive feedback output during one closed-loop simulation session.", "small"))

    # event times are absolute session times; align to timeseries t_rel using min t_session.
    ev2 = ev.copy()
    ev2["t_session_sec"] = ev2["t_session_sec"] - ts["t_session_sec"].min()

    # Panel A
    y0 = mt
    add_phase_background(parts, ev2, xmap, y0, panel_h)
    max_power = max(float(ts["mu_power_rec"].max()), float(ts["beta_power_rec"].max()))
    min_power = min(float(ts["mu_power_rec"].min()), float(ts["beta_power_rec"].min()))
    pad = (max_power - min_power) * 0.12 or 0.1
    ymin, ymax = min_power - pad, max_power + pad

    def ymap1(v):
        return y0 + panel_h - ((v - ymin) / max(ymax - ymin, 1e-9)) * panel_h

    for k in range(5):
        val = ymin + (ymax - ymin) * k / 4
        y = ymap1(val)
        parts.append(line(ml, y, w - mr, y, COLORS["grid"], 1))
        parts.append(text(ml - 15, y + 5, f"{val:.2f}", "small", "end"))
    parts.append(polyline([(xmap(r.t_rel), ymap1(r.mu_power_rec)) for r in tsd.itertuples()], COLORS["teal"], 3))
    parts.append(polyline([(xmap(r.t_rel), ymap1(r.beta_power_rec)) for r in tsd.itertuples()], COLORS["orange"], 3))
    parts.append(line(ml, y0, ml, y0 + panel_h, COLORS["gray"], 2))
    parts.append(line(ml, y0 + panel_h, w - mr, y0 + panel_h, COLORS["gray"], 2))
    parts.append(text(ml, y0 - 18, "A", "panel", "start"))
    parts.append(text(ml + 36, y0 - 18, "Simulated EEG band-power features", "label", "start"))

    # Panel B
    y0b = mt + panel_h + gap
    add_phase_background(parts, ev2, xmap, y0b, panel_h)

    def ymap2(v):
        return y0b + panel_h - max(0, min(1, v)) * panel_h

    for val in [0, 0.25, 0.5, 0.75, 1.0]:
        y = ymap2(val)
        parts.append(line(ml, y, w - mr, y, COLORS["grid"], 1))
        parts.append(text(ml - 15, y + 5, f"{val:.2f}", "small", "end"))
    parts.append(polyline([(xmap(r.t_rel), ymap2(r.simulation_intensity_pct_rec)) for r in tsd.itertuples()], COLORS["navy"], 3))
    parts.append(polyline([(xmap(r.t_rel), ymap2(r.simulation_intensity_rec)) for r in tsd.itertuples()], COLORS["teal"], 4))
    parts.append(line(ml, y0b, ml, y0b + panel_h, COLORS["gray"], 2))
    parts.append(line(ml, y0b + panel_h, w - mr, y0b + panel_h, COLORS["gray"], 2))
    parts.append(text(ml, y0b - 18, "B", "panel", "start"))
    parts.append(text(ml + 36, y0b - 18, "Adaptive mapping and smoothed feedback output", "label", "start"))
    parts.append(text(ml + plot_w / 2, h - 48, "Time (s)", "label"))
    parts.append(f'<text x="42" y="{mt + panel_h/2:.1f}" class="label" transform="rotate(-90 42,{mt + panel_h/2:.1f})" text-anchor="middle">Power</text>')
    parts.append(f'<text x="42" y="{y0b + panel_h/2:.1f}" class="label" transform="rotate(-90 42,{y0b + panel_h/2:.1f})" text-anchor="middle">Feedback value</text>')

    # x ticks
    for sec in range(0, int(math.ceil(tmax)) + 1, 10):
        x = xmap(sec)
        parts.append(line(x, y0b + panel_h, x, y0b + panel_h + 9, COLORS["gray"], 1.5))
        parts.append(text(x, y0b + panel_h + 32, sec, "small"))

    # legends
    lx, ly = w - 520, mt + 18
    parts.append(line(lx, ly, lx + 42, ly, COLORS["teal"], 5)); parts.append(text(lx + 54, ly + 5, "Mu power", "small", "start"))
    parts.append(line(lx + 190, ly, lx + 232, ly, COLORS["orange"], 5)); parts.append(text(lx + 244, ly + 5, "Beta power", "small", "start"))
    ly2 = y0b + 18
    parts.append(line(lx, ly2, lx + 42, ly2, COLORS["navy"], 5)); parts.append(text(lx + 54, ly2 + 5, "Quantile-mapped value", "small", "start"))
    parts.append(line(lx + 250, ly2, lx + 292, ly2, COLORS["teal"], 5)); parts.append(text(lx + 304, ly2 + 5, "EMA-smoothed output", "small", "start"))
    parts.append(text(w - 80, h - 24, "Simulated EEG; proof-of-function only.", "small", "end"))

    parts.extend(svg_footer())
    out = OUT_DIR / "Figure6_simulated_eeg_feedback_chain.svg"
    out.write_text("\n".join(parts), encoding="utf-8")
    return out


def load_font(size=32, bold=False):
    candidates = [
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
        r"C:\Windows\Fonts\calibrib.ttf" if bold else r"C:\Windows\Fonts\calibri.ttf",
    ]
    for p in candidates:
        if p and os.path.exists(p):
            return ImageFont.truetype(p, size=size)
    return ImageFont.load_default()


def draw_wrapped(draw, text_value, xy, font, fill, max_width, line_gap=8):
    words = text_value.split()
    lines, cur = [], ""
    for word in words:
        test = f"{cur} {word}".strip()
        if draw.textbbox((0, 0), test, font=font)[2] <= max_width or not cur:
            cur = test
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    x, y = xy
    for ln in lines:
        draw.text((x, y), ln, font=font, fill=fill)
        y += font.size + line_gap
    return y


def make_figure7(sim_session):
    report_dir = sim_session / "report"
    ts_img = Image.open(report_dir / "fig_timeseries.png").convert("RGB")
    perf_img = Image.open(report_dir / "fig_performance.png").convert("RGB")
    dist_img = Image.open(report_dir / "fig_distribution.png").convert("RGB")
    meta = json.loads((sim_session / "meta.json").read_text(encoding="utf-8"))

    w, h = 1800, 1300
    img = Image.new("RGB", (w, h), "white")
    draw = ImageDraw.Draw(img)
    font_title = load_font(44, True)
    font_panel = load_font(32, True)
    font_text = load_font(25)
    font_small = load_font(22)

    draw.text((w // 2, 36), "Session-level automated report and record completeness", font=font_title, fill=COLORS["gray"], anchor="ma")
    draw.text((w // 2, 92), "Example generated from a simulated EEG validation session", font=font_small, fill=COLORS["gray"], anchor="ma")

    def paste_panel(src, box, label, title):
        x, y, bw, bh = box
        draw.rectangle((x, y, x + bw, y + bh), fill=COLORS["light"], outline="#D5DEE6", width=2)
        draw.text((x + 18, y + 16), label, font=font_panel, fill=COLORS["navy"])
        draw.text((x + 70, y + 20), title, font=font_text, fill=COLORS["gray"])
        inner = (x + 28, y + 66, bw - 56, bh - 92)
        src2 = src.copy()
        src2.thumbnail((inner[2], inner[3]))
        px = x + 28 + (inner[2] - src2.width) // 2
        py = y + 66 + (inner[3] - src2.height) // 2
        img.paste(src2, (px, py))

    paste_panel(ts_img, (70, 145, 790, 485), "A", "Feedback trajectory")
    paste_panel(perf_img, (940, 145, 790, 485), "B", "Performance summary")
    paste_panel(dist_img, (70, 700, 790, 485), "C", "Feature distribution")

    # Completeness panel
    x, y, bw, bh = 940, 700, 790, 485
    draw.rectangle((x, y, x + bw, y + bh), fill=COLORS["light"], outline="#D5DEE6", width=2)
    draw.text((x + 18, y + 16), "D", font=font_panel, fill=COLORS["navy"])
    draw.text((x + 70, y + 20), "Record completeness", font=font_text, fill=COLORS["gray"])

    files = [
        ("Online time-series features", "timeseries_rec.csv"),
        ("Event log", "events_log.csv"),
        ("Session metadata", "meta.json"),
        ("Performance summary", "performance_summary.csv"),
        ("Report summary", "report/summary.csv"),
        ("Automated HTML report", "report/report.html"),
    ]
    yy = y + 88
    for name, rel in files:
        exists = (sim_session / rel).exists()
        mark = "OK" if exists else "Missing"
        color = COLORS["teal"] if exists else COLORS["orange"]
        draw.rounded_rectangle((x + 38, yy - 4, x + 118, yy + 31), radius=4, fill=color)
        draw.text((x + 78, yy + 1), mark, font=font_small, fill="white", anchor="ma")
        draw.text((x + 140, yy), name, font=font_small, fill=COLORS["gray"])
        yy += 54

    note = (
        "The report was generated from the same session records used for feedback-chain "
        "and event review. Simulated EEG was used; the figure is not evidence of training efficacy."
    )
    draw_wrapped(draw, note, (x + 38, y + 410), font_small, COLORS["gray"], bw - 76, 4)
    draw.text((w - 72, h - 34), f"Session: {meta.get('scheme_name', 'simulation')} | {sim_session.name}", font=font_small, fill=COLORS["gray"], anchor="ra")

    out = OUT_DIR / "Figure7_automated_report_example.png"
    img.save(out, dpi=(300, 300))
    return out


def main():
    ensure_dirs()
    sessions = latest_sessions()
    with (DATA_DIR / "selected_sessions.csv").open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["mode", "session_dir"])
        for mode in ["simulation", "attention", "relax", "monitor"]:
            try:
                published_path = sessions[mode].resolve().relative_to(REPO_ROOT.resolve()).as_posix()
            except ValueError:
                published_path = str(sessions[mode])
            writer.writerow([mode, published_path])

    lat = collect_week2_latency_points()
    save_latency_data(lat)
    fig5 = make_figure5(lat)
    fig6 = make_figure6(sessions["simulation"])
    fig7 = make_figure7(sessions["simulation"])
    print("Generated:")
    print(fig5)
    print(fig6)
    print(fig7)
    print("Data:")
    print(DATA_DIR / "selected_sessions.csv")
    print(DATA_DIR / "Figure5_ack_latency_points.csv")
    print(DATA_DIR / "Figure5_ack_latency_summary.csv")
    print(DATA_DIR / "Figure6_simulated_eeg_feedback_chain_data.csv")


if __name__ == "__main__":
    main()
