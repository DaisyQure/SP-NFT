function results = week2_batch_smoke(n_repeats, varargin)
% Run reproducible dual-end simulated-input validation sessions.
% The first argument is the number of sessions per mode.
if nargin < 1 || isempty(n_repeats)
    n_repeats = 1;
end

opts = struct( ...
    'player_exe', getenv('SPNFT_UNITY_PLAYER'), ...
    'unity_log', fullfile(tempdir, 'spnft_unity_week2_smoke.log'), ...
    'wait_for_unity_sec', 60, ...
    'baseline_sec', 3, ...
    'n_trials', 4, ...
    'phase_a_dur', 5, ...
    'phase_b_dur', 10, ...
    'timeout_margin_sec', 30, ...
    'modes', {{'simulation', 'attention', 'relax', 'monitor'}});
opts = parse_opts(opts, varargin{:});

root = getenv('SPNFT_MATLAB_ROOT');
if isempty(root)
    this_file = mfilename('fullpath');
    root = fullfile(fileparts(fileparts(this_file)), 'matlab');
end
if isempty(opts.player_exe)
    error('Set SPNFT_UNITY_PLAYER to the built SPNFT_Smoke executable.');
end
cd(root);
addpath('eeg', 'features', 'schemes', 'server', 'utils', 'recorder', 'report');

modes = opts.modes;
results = struct('mode', {}, 'repeat', {}, 'passed', {}, 'session_dir', {}, 'errors', {}, 'warnings', {});
idx = 0;

for m = 1:numel(modes)
    for r = 1:n_repeats
        mode = modes{m};
        fprintf('\n[Week2] Starting %s repeat %d/%d\n', mode, r, n_repeats);
        cmd = sprintf('start "" "%s" -batchmode -nographics -logFile "%s" -spnftAutoScene %s -spnftQuitOnSessionStop', ...
            opts.player_exe, opts.unity_log, mode);
        try
            result = smoke_dual_end(mode, ...
                'unity_command', cmd, ...
                'unity_log_path', opts.unity_log, ...
                'wait_for_unity_sec', opts.wait_for_unity_sec, ...
                'baseline_sec', opts.baseline_sec, ...
                'n_trials', opts.n_trials, ...
                'phase_a_dur', opts.phase_a_dur, ...
                'phase_b_dur', opts.phase_b_dur, ...
                'timeout_margin_sec', opts.timeout_margin_sec);
        catch err
            result = struct('passed', false, 'session_dir', '', 'errors', {{err.message}}, 'warnings', {{}});
        end
        idx = idx + 1;
        results(idx).mode = mode;
        results(idx).repeat = r;
        results(idx).passed = result.passed;
        results(idx).session_dir = result.session_dir;
        results(idx).errors = result.errors;
        results(idx).warnings = result.warnings;
        fprintf('[Week2] %s repeat %d passed=%d session=%s\n', mode, r, result.passed, result.session_dir);
    end
end

save(fullfile('logs', 'week2_batch_results.mat'), 'results');
write_results_csv(results, fullfile('logs', 'week2_batch_results.csv'));
fprintf('[Week2] Saved results to logs/week2_batch_results.mat and .csv\n');
end

function opts = parse_opts(opts, varargin)
for i = 1:2:length(varargin)
    if i + 1 > length(varargin), break; end
    if isfield(opts, varargin{i}), opts.(varargin{i}) = varargin{i+1}; end
end
end

function write_results_csv(results, path)
fid = fopen(path, 'w');
fprintf(fid, 'mode,repeat,passed,session_dir,errors,warnings\n');
for i = 1:numel(results)
    errors = strjoin(results(i).errors, ' || ');
    warnings = strjoin(results(i).warnings, ' || ');
    fprintf(fid, '%s,%d,%d,"%s","%s","%s"\n', results(i).mode, results(i).repeat, results(i).passed, ...
        results(i).session_dir, errors, warnings);
end
fclose(fid);
end
