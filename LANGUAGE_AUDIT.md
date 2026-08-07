# Public Release Language Audit

The public release uses English for all participant-facing, operator-facing, and generated content.

## Audited surfaces

- Unity scene text, runtime overlays, status labels, guidance, warnings, and logs
- Unity Inspector `Header` and `Tooltip` labels
- MATLAB operator GUI, command-line console, session diagnostics, and phase instructions
- Generated HTML report headings, metadata labels, plots, placeholders, and messages
- Anonymous example CSV/JSON data and generated HTML reports

Protocol identifiers are intentionally unchanged. Examples include `phase_ack`, `session_stop_ack`, `simulation_intensity`, marker keys, CSV column names, and scene/object interface names.

## Result

The release audit found no Han characters in executable MATLAB string literals, Unity runtime/scene/Inspector text, generated HTML reports, or anonymous example data. Chinese comments may remain in implementation files because they are not rendered, transmitted, or included in generated outputs.

The four bundled example reports were regenerated with the English report generator before packaging.

The final MATLAB-Unity simulation smoke also ran entirely in English and generated an English-only HTML report. Its runtime evidence included four `phase_ack` markers, one `session_stop_ack` marker, feedback-driven rig motion, and two target impact markers.
