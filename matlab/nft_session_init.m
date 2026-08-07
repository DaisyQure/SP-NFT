function ctx = nft_session_init(scheme_name, duration_sec, subject_meta, auto_report, paradigm_override, baseline_duration_sec)
% 创建一个 session 上下文 (state machine 的初始状态)
% 由 GUI 在用户点 Start 时调用一次
%
% 输入:
%   scheme_name           : 'attention' / 'simulation' / 'relax' / 'monitor'
%   duration_sec          : session 反馈阶段时长 (秒). 当 paradigm 启用时, 实际总时长
%                           由 n_trials*(phase_a_dur+phase_b_dur) 决定, 此参数仅作保底
%   subject_meta          : (可选) struct, 字段 id name sex age handedness note
%   auto_report           : (可选) bool, finalize 时是否自动调 generate_report (默认 true)
%   paradigm_override     : (可选) struct, 字段 n_trials/phase_a_dur/phase_b_dur,
%                           不传则取 cfg.paradigm 默认
%   baseline_duration_sec : (可选) 本次会话的基线时长覆盖值（秒）
%
% 返回:
%   ctx : session 上下文 struct, 包含所有运行时状态
%         其中 ctx.phase ∈ {'waiting_unity', 'baseline', 'running', 'finished'}
%         在 running 内 ctx.paradigm.current_phase ∈ {'A','B'}

if nargin < 1, scheme_name = 'attention'; end
if nargin < 2, duration_sec = 90; end
if nargin < 3, subject_meta = struct('id', 'anon'); end
if nargin < 4, auto_report = true; end
if nargin < 5, paradigm_override = struct(); end
if nargin < 6, baseline_duration_sec = []; end

addpath('eeg', 'features', 'schemes', 'server', 'utils', 'recorder', 'report');

ctx.scheme_name = scheme_name;
ctx.duration_sec = duration_sec;
ctx.subject_meta = subject_meta;
ctx.auto_report = auto_report;
ctx.phase = 'init';
ctx.error = '';

try
    ctx.cfg = config();
    if ~isempty(baseline_duration_sec)
        ctx.cfg.baseline.duration_sec = baseline_duration_sec;
    end
    ctx.scheme = feval(['scheme_' scheme_name]);
    fprintf('[Session] Mode: %s (%s)\n', ctx.scheme.name, ctx.scheme.description);

    % --- 合并 paradigm 默认与 GUI 覆盖 ---
    ctx.paradigm = ctx.cfg.paradigm;
    pf = fieldnames(paradigm_override);
    for i = 1:length(pf)
        ctx.paradigm.(pf{i}) = paradigm_override.(pf{i});
    end
    ctx.paradigm.trial_idx = 0;
    ctx.paradigm.current_phase = '';   % 'A' or 'B', 进入 running 后由 step 设
    ctx.paradigm.phase_t0 = [];
    fprintf('[Paradigm] n_trials=%d phase_a=%ds phase_b=%ds\n', ...
        ctx.paradigm.n_trials, ctx.paradigm.phase_a_dur, ctx.paradigm.phase_b_dur);

    ctx.eeg_handle = eeg_init(ctx.cfg);

    ctx.server = tcpserver("0.0.0.0", ctx.cfg.server.port);
    configureTerminator(ctx.server, "LF");
    fprintf('[Server] Listening on port %d; waiting for Unity...\n', ctx.cfg.server.port);

    ctx.mk = marker_open(ctx.scheme.name);
    ctx.slog = session_log_open(ctx.scheme.name);
    session_log_write(ctx.slog, 'Session', sprintf('scheme=%s duration=%ds baseline=%ds (GUI-driven)', ...
        ctx.scheme.name, duration_sec, ctx.cfg.baseline.duration_sec));

    ctx.recorder = recorder_open(ctx.scheme.name, subject_meta, ctx.cfg);

    nft_shared('reset');
    nft_shared('set_active', true);

    ctx.seq = 0;
    ctx.period = 1 / ctx.cfg.feedback.update_hz;
    ctx.next_report = 2;
    ctx.last_marker_count = 0;
    ctx.baseline = [];
    ctx.at = [];
    ctx.t0 = [];
    ctx.baseline_t0 = [];
    ctx.perf = struct( ...
        'last_phase_send_abs_ts', NaN, ...
        'last_phase_send_seq', -1, ...
        'last_phase_label', '', ...
        'last_phase_trial_idx', 0, ...
        'last_session_stop_send_abs_ts', NaN, ...
        'last_session_stop_send_seq', -1, ...
        'phase_ack_latency_ms', [], ...
        'session_stop_ack_latency_ms', [], ...
        'phase_ack_transport_ms', [], ...
        'session_stop_ack_transport_ms', [], ...
        'tcp_connected_transport_ms', [], ...
        'unity_sync_transport_ms', [], ...
        'unity_marker_transport_ms', []);

    ctx.window_open_since = struct();
    ctx.window_open_count = struct();
    ctx.window_open_total = struct();
    ctx.window_open_max = struct();
    ctx.value_sum = struct();
    ctx.value_count = struct();
    for k = 1:length(ctx.scheme.feedback_types)
        ft = ctx.scheme.feedback_types{k};
        ctx.window_open_since.(ft) = NaN;
        ctx.window_open_count.(ft) = 0;
        ctx.window_open_total.(ft) = 0;
        ctx.window_open_max.(ft)   = 0;
        ctx.value_sum.(ft) = 0;
        ctx.value_count.(ft) = 0;
    end

    ctx.behavior_counts = struct( ...
        'enemy_spawn',         0, ...
        'enemy_hit',           0, ...
        'enemy_missed',        0, ...
        'enemy_hit_player',    0, ...
        'shot_fired',          0, ...
        'coin_spawn',          0, ...
        'coin_collected',      0, ...
        'action_window_open',  0, ...
        'action_window_close', 0);

    ctx.phase = 'waiting_unity';
catch err
    ctx.error = err.message;
    ctx.phase = 'finished';
    fprintf('[Session] Initialization failed: %s\n', err.message);
end
end
