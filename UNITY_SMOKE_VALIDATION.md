# Unity simulation smoke validation

Final local validation date: 2026-08-06

Environment:

- Unity 2022.3.62f3c1, Windows 64-bit development player
- MATLAB R2025b, simulated EEG input
- Two A-B trials: baseline 3 s, phase A 2 s, phase B 3 s
- Unity arguments: `-batchmode -nographics -spnftAutoScene simulation -spnftQuitOnSessionStop -spnftSmokeProbe`

Results:

- Primitive placeholder interfaces: PASS
- `phase_ack`: 4 markers captured
- `session_stop_ack`: 1 marker captured
- Feedback-driven motion: PASS; maximum local position delta 0.1118 and rotation delta 16.934 degrees
- Target response: PASS; 2 impact markers created from 2 automatic shots
- Maximum applied simulation intensity: 0.963
- MATLAB output: 124 time-series rows, 47 event rows, 7 performance-summary rows
- Report generation: `report/report.html` and `report/summary.csv` generated successfully
- Report language check: PASS; no Han characters in the generated HTML
- Unity runtime language check: PASS; no Han characters in the player log
- MATLAB process exit code: 0
- Unity player exit code: 0

The smoke probe is inactive unless `-spnftSmokeProbe` is supplied. In smoke mode only, it lowers the firing threshold and hold duration so the simulated-input run deterministically exercises motion and target feedback. Normal experiment settings are unchanged.
