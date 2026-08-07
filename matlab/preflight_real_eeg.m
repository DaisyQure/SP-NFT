function result = preflight_real_eeg()
% Validate the Neuracle data stream before running a participant session.

root_dir = fileparts(mfilename('fullpath'));
old_dir = pwd;
cleanup_dir = onCleanup(@() cd(old_dir));
cd(root_dir);
addpath('API', 'eeg', 'features');

cfg = config();
cfg.eeg.use_simulation = false;
result = struct('passed', false, 'eyes_open_alpha', NaN, ...
    'eyes_closed_alpha', NaN, 'alpha_ratio', NaN, 'message', '');
handle = [];

fprintf('\n=== Neuracle real EEG preflight ===\n');
fprintf('Endpoint: %s:%d | channels: %d | fs: %d Hz\n', ...
    cfg.eeg.ip, cfg.eeg.port, cfg.eeg.n_channels, cfg.eeg.fs);
fprintf('Start EEG Recorder and its data service before continuing.\n\n');

try
    handle = eeg_init(cfg);
    cleanup_eeg = onCleanup(@() eeg_close(handle)); %#ok<NASGU>

    fprintf('[1/3] Checking 10 consecutive two-second windows...\n');
    for k = 1:10
        data = eeg_get_window(handle, 2);
        validate_window(data, cfg, k);
        fprintf('  Window %02d: SD median %.4f, range %.4f to %.4f\n', ...
            k, median(std(double(data), 0, 2)), min(data, [], 'all'), max(data, [], 'all'));
        pause(0.25);
    end

    fprintf('\n[2/3] Keep eyes OPEN and look at a fixed point for 20 seconds.\n');
    countdown(5);
    open_data = collect_segment(handle, 20, cfg.eeg.fs, cfg.eeg.n_channels);

    fprintf('\n[3/3] Close eyes, relax, and remain still for 20 seconds.\n');
    countdown(5);
    closed_data = collect_segment(handle, 20, cfg.eeg.fs, cfg.eeg.n_channels);

    alpha_band = struct('alpha', [8 13]);
    posterior = {'Pz', 'POz', 'O1', 'O2'};
    open_power = extract_band_power(open_data, cfg.eeg.fs, ...
        cfg.eeg.montage, posterior, alpha_band);
    closed_power = extract_band_power(closed_data, cfg.eeg.fs, ...
        cfg.eeg.montage, posterior, alpha_band);

    result.eyes_open_alpha = open_power.alpha;
    result.eyes_closed_alpha = closed_power.alpha;
    result.alpha_ratio = closed_power.alpha / max(open_power.alpha, eps);
    result.passed = true;
    result.message = 'Stream integrity checks passed.';

    fprintf('\nPASS: Real EEG stream integrity checks passed.\n');
    fprintf('Posterior alpha: eyes open %.6g, eyes closed %.6g, ratio %.3f\n', ...
        result.eyes_open_alpha, result.eyes_closed_alpha, result.alpha_ratio);
    if result.alpha_ratio <= 1
        fprintf(['NOTE: Closed-eye alpha did not exceed open-eye alpha. This does not ' ...
            'invalidate the stream, but montage, reference, impedance, and artifacts should be reviewed.\n']);
    end
catch err
    result.message = err.message;
    fprintf(2, '\nFAIL: %s\n', err.message);
    fprintf(2, 'Check EEG Recorder, data service port, channel count, sample rate, and toolbox support.\n');
end

clear cleanup_dir;
end

function validate_window(data, cfg, index)
expected_samples = round(2 * cfg.eeg.fs);
if ~isequal(size(data), [cfg.eeg.n_channels, expected_samples])
    error('Window %d has size %dx%d; expected %dx%d.', index, ...
        size(data, 1), size(data, 2), cfg.eeg.n_channels, expected_samples);
end
if any(~isfinite(data), 'all')
    error('Window %d contains NaN or Inf.', index);
end
channel_sd = std(double(data), 0, 2);
if all(channel_sd < eps)
    error('Window %d is constant across all channels.', index);
end
if nnz(channel_sd < eps) > 2
    error('Window %d contains more than two flat channels.', index);
end
end

function segment = collect_segment(handle, duration_sec, fs, n_channels)
chunk_sec = 2;
n_chunks = ceil(duration_sec / chunk_sec);
segment = zeros(n_channels, n_chunks * chunk_sec * fs);
write_pos = 1;
for k = 1:n_chunks
    pause(chunk_sec);
    chunk = eeg_get_window(handle, chunk_sec);
    n = size(chunk, 2);
    segment(:, write_pos:write_pos+n-1) = chunk;
    write_pos = write_pos + n;
    fprintf('  Collected %d/%d seconds\n', min(k * chunk_sec, duration_sec), duration_sec);
end
segment = segment(:, 1:duration_sec * fs);
end

function countdown(seconds)
for k = seconds:-1:1
    fprintf('  Starting in %d...\n', k);
    pause(1);
end
end
