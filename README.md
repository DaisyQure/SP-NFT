# SP-NFT public repository candidate

This package is a candidate public release for the SP-NFT MATLAB--Unity3D research software platform.

## What is included

- `matlab/`: MATLAB control, EEG-compatible input, feature processing, paradigms, recording, and reporting code.
- `scripts/`: Week 2 batch validation, session aggregation, and figure-data generation scripts.
- `examples/sessions/`: one valid simulated-input session for each mode (`simulation`, `attention`, `relax`, `monitor`).
- `examples/aggregate/`: statistics for the four included public example sessions.
- `reported_week2_summary/`: aggregate summary reported in the manuscript for the full 40-session Week 2 cohort; raw directories for that cohort are not included.
- `figure_data/`: ACK latency points and summary used for Figure 5.
- `figures/`: Figure 5/6/7 generated from the included example sessions.
- `unity_source_candidate/`: a minimal Unity 2022.3 simulation smoke project with project-specific scripts, three required scenes, primitive-only weapon/arm placeholders, build scripts, packages, and project settings.

## Important release boundary

The Unity candidate deliberately excludes `Library/`, `Logs/`, `Builds/`, `UserSettings/`, Cowsins assets, Microsoft YaHei assets, local audio, textures, and other third-party demonstration resources. The simulation weapon and arms use author-created Unity primitives. The only bundled font is Liberation Sans from TextMesh Pro Essentials, redistributed under the included SIL Open Font License; the required TMP shaders are covered by the included Unity Companion License notice. Review `THIRD_PARTY_NOTICES.md` for details.

The current validation uses simulated EEG only. The example sessions are software proof-of-function records and are not human EEG or training-efficacy evidence. The four public sessions are examples for file/schema reproduction; the manuscript's 40-session descriptive statistics are provided separately as an aggregate report.

## MATLAB smoke validation

From MATLAB, run:

```matlab
cd('path/to/SP-NFT_public_repository_candidate/matlab');
addpath(genpath(pwd));
```

Open `unity_source_candidate/` in Unity 2022.3.62f3c1 and run `Week2SmokePlayerBuild.BuildWindowsSmokePlayer` to create the simulation smoke player. The full dual-end smoke run requires this player and local TCP port 5555. Configure the player path through an environment variable instead of editing a machine-specific path:

PowerShell:

```powershell
$env:SPNFT_UNITY_PLAYER = 'C:\path\to\SPNFT_Smoke.exe'
```

The public MATLAB scripts use relative repository paths and temporary log paths. See `UNITY_SMOKE_VALIDATION.md` for the final validation evidence and smoke arguments.

The Python aggregation script accepts `SPNFT_SESSION_ROOT` and `SPNFT_OUTPUT_ROOT` environment variables. For the included example sessions, the default paths are `examples/sessions` and `examples/aggregate`.

## Data layout

Each example session contains `events_log.csv`, `timeseries_rec.csv`, `meta.json`, `performance_summary.csv`, `report/summary.csv`, `report/report.html`, and the three report images used by the figure-generation example.

## Before publication

Replace the placeholder repository citation in the manuscript with the public URL, release tag, license, and archived DOI. Do not publish participant-identifying data or unlicensed third-party assets.
