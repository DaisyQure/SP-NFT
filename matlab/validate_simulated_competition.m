function result = validate_simulated_competition()
% Validate the integrated platform with existing simulated EEG sessions.
% This script checks software workflow evidence only, not physiological efficacy.

root = fileparts(mfilename('fullpath'));
session_root = fullfile(root, 'logs', 'sessions');
scheme_root = fullfile(root, 'schemes');

% Make the validator independent of MATLAB's current working directory.
addpath(root);
addpath(scheme_root);

result = struct('pass', true, 'checks', {{}}, 'missing_reports', {{}}, ...
    'session_count', 0, 'report_count', 0);

fprintf('\n=== Simulated EEG competition validation ===\n');
fprintf('Root: %s\n', root);

check('Project root is on MATLAB path', contains(path, root));
check('Scheme directory is on MATLAB path', contains(path, scheme_root));

cfg = config();
check('Simulation mode enabled', cfg.eeg.use_simulation == true);
check('EEG channel count is 32', cfg.eeg.n_channels == 32);
check('EEG sample rate is 1000 Hz', cfg.eeg.fs == 1000);
check('MATLAB-Unity TCP port is 5555', cfg.server.port == 5555);

scheme_names = {'attention', 'relax', 'simulation', 'monitor'};
for i = 1:numel(scheme_names)
    name = scheme_names{i};
    f = str2func(['scheme_' name]);
    scheme = f();
    check(['Scheme exists: ' name], strcmp(scheme.name, name));
    check(['Scheme has score function: ' name], isa(scheme.score_fn, 'function_handle'));
end

dirs = dir(session_root);
dirs = dirs([dirs.isdir]);
dirs = dirs(~ismember({dirs.name}, {'.', '..'}));
result.session_count = numel(dirs);
check('Session directory count is 165', result.session_count == 165);

scheme_counts = struct('attention', 0, 'relax', 0, 'simulation', 0, 'monitor', 0);
report_counts = scheme_counts;
for i = 1:numel(dirs)
    folder = dirs(i).name;
    token = regexp(folder, '^[^_]+_(attention|relax|simulation|monitor)_', 'tokens', 'once');
    if isempty(token)
        continue;
    end
    name = token{1};
    scheme_counts.(name) = scheme_counts.(name) + 1;
    report_file = fullfile(session_root, folder, 'report', 'report.html');
    if isfile(report_file)
        report_counts.(name) = report_counts.(name) + 1;
        result.report_count = result.report_count + 1;
    else
        result.missing_reports{end+1} = folder; %#ok<AGROW>
    end
end

check('All four schemes have sessions', all(struct2array(scheme_counts) > 0));
check('Report count is 161', result.report_count == 161);
check('Report generation rate is at least 97 percent', result.report_count / max(result.session_count, 1) >= 0.97);

representatives = {
    '20260706_112220_attention_S001', ...
    '20260708_121932_simulation_S001', ...
    '20260627_184239_monitor_S001', ...
    '20260704_123600_relax_S001'};
for i = 1:numel(representatives)
    folder = fullfile(session_root, representatives{i});
    required = {fullfile(folder, 'meta.json'), fullfile(folder, 'timeseries_rec.csv'), ...
        fullfile(folder, 'events_log.csv'), fullfile(folder, 'performance_summary.csv')};
    check(['Representative session files: ' representatives{i}], all(cellfun(@isfile, required)));
end

fprintf('\nSession counts by scheme:\n');
for i = 1:numel(scheme_names)
    name = scheme_names{i};
    fprintf('  %-11s %3d sessions, %3d reports\n', name, scheme_counts.(name), report_counts.(name));
end
fprintf('Total: %d sessions, %d reports, %.1f%% report coverage\n', ...
    result.session_count, result.report_count, 100 * result.report_count / max(result.session_count, 1));

fprintf('\nRepresentative latency summaries (phase_ack_latency_ms median):\n');
for i = 1:numel(representatives)
    summary_file = fullfile(session_root, representatives{i}, 'performance_summary.csv');
    median_value = read_metric(summary_file, 'phase_ack_latency_ms', 'median');
    fprintf('  %-38s %8.3f ms\n', representatives{i}, median_value);
end

if ~isempty(result.missing_reports)
    fprintf('\nMissing report files (historical smoke/incomplete sessions):\n');
    for i = 1:numel(result.missing_reports)
        fprintf('  %s\n', result.missing_reports{i});
    end
end

if result.pass
    fprintf('\nPASS: software workflow evidence is internally consistent.\n');
else
    fprintf('\nFAIL: one or more software checks require investigation.\n');
end

    function check(label, condition)
        if condition
            fprintf('[PASS] %s\n', label);
        else
            fprintf('[FAIL] %s\n', label);
            result.pass = false;
        end
        result.checks{end+1} = struct('label', label, 'pass', logical(condition)); %#ok<AGROW>
    end
end

function value = read_metric(file, metric_name, column_name)
value = NaN;
try
    T = readtable(file, 'TextType', 'string');
    row = strcmp(string(T.metric), metric_name);
    if any(row)
        value = T{find(row, 1), column_name};
        if iscell(value)
            value = str2double(string(value));
        end
    end
catch
    value = NaN;
end
end
