# Recording Suffix Convention

SP-NFT uses field-name suffixes to determine whether a variable is recorded and at what granularity. Fields carrying either suffix are stored automatically by the `recorder/*` modules; no separate allowlist is required.

This convention applies to structures passed from `nft_session_step.m` to `recorder_push`, as well as to future metrics that should appear in generated reports.

## Suffixes

| Suffix | Meaning | Recording frequency | Output file | Report output |
|---|---|---|---|---|
| `_rec` | Continuous time-series value sampled on each feedback frame | Every frame (10 Hz by default; see `config.m`) | `timeseries_rec.csv` (wide format, one metric per column) | Time-series plots, histograms, and statistics |
| `_log` | Discrete event recorded only when it occurs | Event-triggered (marker, phase transition, threshold adjustment, trial boundary) | `events_log.csv` (long format) | Event counts and timeline annotations |

Fields without either suffix, such as `t`, `scheme`, and `sent`, are treated as contextual values. They are not recorded as standalone metrics or included in report statistics.

## Time-Series Example

```matlab
push.t                     = toc(ctx.t0);          % Shared time column; no suffix
push.attention_rec         = at.ema.attention;     % Adaptive feedback value
push.attention_raw_rec     = vals.attention;       % Raw score
push.theta_rec             = powers.theta;
push.alpha_rec             = powers.alpha;
push.smr_rec               = powers.smr;
push.beta_rec              = powers.beta1;
push.window_open_rec       = at.window_open.attention;   % 0 or 1

recorder_push(ctx.recorder, push);
```

## Event Example

```matlab
recorder_event(ctx.recorder, ...
    'source', 'unity', ...
    'kind',   'marker', ...
    'key',    'coin_collected', ...
    'value',  evt_val, ...
    'info',   evt_scene);
```

## Automatically Added Columns

`recorder_push` prepends the following columns to every row in `timeseries_rec.csv`:

- `t_session_sec`: seconds elapsed within the session, measured from the end of baseline acquisition.
- `abs_ts`: absolute POSIX time in seconds, used for cross-device alignment.

`recorder_event` uses these fixed columns in `events_log.csv`:

`t_session_sec, abs_ts, source, kind, key, value, info`

## Fields May Change During a Session

Not every `_rec` field must be present in every frame. When a new field first appears, the recorder adds a column and leaves earlier rows empty. When a field is absent from a later frame, the recorder writes an empty value. Different output sets from `scheme_simulation`, `scheme_attention`, and `scheme_monitor` therefore coexist as sparse wide tables.

## Adding a Metric

1. Decide whether the metric is continuous (`_rec`) or event-based (`_log`).
2. At the point where it is produced, usually `nft_session_step.m`, add a suffixed field to the push structure or call `recorder_event`.
3. Run a session and inspect `report/report.html`. The metric should appear automatically without changes to the recorder or `generate_report.m`.