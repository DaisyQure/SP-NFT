function result = smoke_dual_end(scheme_name, varargin)
% 最小双端自动化烟测。
%
% 用法示例：
%   smoke_dual_end('attention')
%   smoke_dual_end('attention', 'unity_command', ...
%       'start "" "C:\\Path\\To\\Unity.exe" -projectPath "G:\\HXY\\Unity3DProjects\\My project1" -batchmode -nographics -logFile "G:\\HXY\\Unity3DProjects\\My project1\\unity_smoke.log" -spnftAutoScene attention -spnftQuitOnSessionStop')
%
% 说明：
% - 若不传 unity_command，脚本假定 Unity 已手动启动并会主动连接。
% - 默认使用 MATLAB GUI 路径对应的 nft_session_init / step / finalize。
% - 优先用于 attention 模式，其他模式可切换 scheme_name 验证。

if nargin < 1 || isempty(scheme_name)
    scheme_name = 'attention';
end

opts = parse_opts(varargin{:});
addpath('eeg', 'features', 'schemes', 'server', 'utils', 'recorder', 'report');

result = struct();
result.scheme = scheme_name;
result.passed = false;
result.launched_unity = false;
result.session_dir = '';
result.errors = {};
result.warnings = {};
result.summary = struct();
result.unity_log = '';

if ~isempty(opts.unity_command)
    fprintf('[SmokeDual] Launch Unity command...\n%s\n', opts.unity_command);
    [status, cmdout] = system(opts.unity_command); %#ok<ASGLU>
    if status ~= 0
        result.errors{end+1} = sprintf('Unity launch command failed: status=%d', status);
        print_result(result);
        return;
    end
    result.launched_unity = true;
end

if ~isempty(opts.unity_log_path)
    result.unity_log = opts.unity_log_path;
end

subj = struct('id', upper(sprintf('SMOKE_%s', scheme_name)), ...
              'name', '', 'sex', '', 'age', 0, 'handedness', '', ...
              'note', 'dual-end smoke test');
paradigm_override = struct( ...
    'n_trials',    opts.n_trials, ...
    'phase_a_dur', opts.phase_a_dur, ...
    'phase_b_dur', opts.phase_b_dur);

ctx = nft_session_init(scheme_name, opts.duration_guard_sec, subj, true, ...
                       paradigm_override, opts.baseline_sec);
if strcmp(ctx.phase, 'finished') && ~isempty(ctx.error)
    result.errors{end+1} = sprintf('Session init failed: %s', ctx.error);
    print_result(result);
    return;
end

result.session_dir = ctx.recorder.session_dir;
fprintf('[SmokeDual] Session dir: %s\n', result.session_dir);

wait_t0 = tic;
while strcmp(ctx.phase, 'waiting_unity') && toc(wait_t0) < opts.wait_for_unity_sec
    pause(0.05);
    ctx = nft_session_step(ctx);
end
if strcmp(ctx.phase, 'waiting_unity')
    result.errors{end+1} = sprintf('Unity did not connect within %.1f seconds', opts.wait_for_unity_sec);
    if ~isempty(result.unity_log) && exist(result.unity_log, 'file')
        try
            txt = fileread(result.unity_log);
            if contains(txt, '[SmokeAuto] Loaded')
                result.warnings{end+1} = 'Unity smoke runner loaded target scene, but MATLAB still did not receive a TCP connection.';
            elseif contains(txt, 'Loaded scene ''Assets/Scenes/MainMenu.unity''')
                result.warnings{end+1} = 'Unity reached MainMenu, but automatic scene switching likely did not trigger.';
            end
        catch
        end
    end
    try
        ctx.phase = 'finished';
        nft_session_finalize(ctx);
    catch
    end
    print_result(result);
    return;
end

fprintf('[SmokeDual] Unity connected, running session...\n');
session_timeout = opts.baseline_sec + opts.n_trials * (opts.phase_a_dur + opts.phase_b_dur) + opts.timeout_margin_sec;
run_t0 = tic;
while ~strcmp(ctx.phase, 'finished') && toc(run_t0) < session_timeout
    ctx = nft_session_step(ctx);
    pause(0.05);
end
if ~strcmp(ctx.phase, 'finished')
    result.warnings{end+1} = sprintf('Session timed out after %.1f seconds, forcing finalize', session_timeout);
    ctx.phase = 'finished';
end

nft_session_finalize(ctx);
result = validate_outputs(result);
print_result(result);
end

function opts = parse_opts(varargin)
opts = struct();
opts.unity_command = '';
opts.unity_log_path = '';
opts.wait_for_unity_sec = 20;
opts.n_trials = 2;
opts.phase_a_dur = 2;
opts.phase_b_dur = 3;
opts.baseline_sec = 3;
opts.duration_guard_sec = 120;
opts.timeout_margin_sec = 10;

for i = 1:2:length(varargin)
    if i + 1 > length(varargin)
        break;
    end
    key = varargin{i};
    val = varargin{i+1};
    if isfield(opts, key)
        opts.(key) = val;
    end
end
end

function result = validate_outputs(result)
session_dir = result.session_dir;
required_files = { ...
    fullfile(session_dir, 'events_log.csv'), ...
    fullfile(session_dir, 'timeseries_rec.csv'), ...
    fullfile(session_dir, 'performance_summary.csv'), ...
    fullfile(session_dir, 'report', 'summary.csv'), ...
    fullfile(session_dir, 'report', 'report.html')};

for i = 1:length(required_files)
    if ~exist(required_files{i}, 'file')
        result.errors{end+1} = sprintf('Missing file: %s', required_files{i});
    end
end
if ~isempty(result.errors)
    return;
end

try
    ev = readtable(fullfile(session_dir, 'events_log.csv'), 'TextType', 'string');
    summary = readtable(fullfile(session_dir, 'report', 'summary.csv'), 'TextType', 'string');
    perf = readtable(fullfile(session_dir, 'performance_summary.csv'), 'TextType', 'string');

    result.summary.event_rows = height(ev);
    result.summary.summary_rows = height(summary);
    result.summary.performance_rows = height(perf);

    has_phase_ack = any(ev.key == "phase_ack") || any(summary.key == "phase_ack_latency_ms");
    has_stop_ack = any(ev.key == "session_stop_ack") || any(summary.key == "session_stop_ack_latency_ms");
    has_perf_phase = any(summary.key == "phase_ack_latency_ms");
    has_perf_stop = any(summary.key == "session_stop_ack_latency_ms");

    if ~has_phase_ack
        result.errors{end+1} = 'Missing phase_ack or phase_ack_latency_ms evidence in outputs';
    end
    if ~has_stop_ack
        result.warnings{end+1} = 'Missing session_stop_ack evidence in outputs';
    end
    if ~has_perf_phase
        result.errors{end+1} = 'Missing phase_ack_latency_ms summary row';
    end
    if ~has_perf_stop
        result.warnings{end+1} = 'Missing session_stop_ack_latency_ms summary row';
    end

    result.passed = isempty(result.errors);
catch err
    result.errors{end+1} = sprintf('Output validation failed: %s', err.message);
end
end

function print_result(result)
fprintf('\n[SmokeDual] ===== Result =====\n');
fprintf('scheme: %s\n', result.scheme);
fprintf('session_dir: %s\n', result.session_dir);
fprintf('passed: %d\n', result.passed);
if ~isempty(result.errors)
    fprintf('Errors:\n');
    for i = 1:length(result.errors)
        fprintf('  - %s\n', result.errors{i});
    end
end
if ~isempty(result.warnings)
    fprintf('Warnings:\n');
    for i = 1:length(result.warnings)
        fprintf('  - %s\n', result.warnings{i});
    end
end
if ~isempty(result.unity_log)
    fprintf('unity_log: %s\n', result.unity_log);
end
if isfield(result, 'summary') && ~isempty(fieldnames(result.summary))
    fprintf('Summary:\n');
    fn = fieldnames(result.summary);
    for i = 1:length(fn)
        fprintf('  %s = %s\n', fn{i}, num2str(result.summary.(fn{i})));
    end
end
fprintf('[SmokeDual] ===================\n\n');
end
