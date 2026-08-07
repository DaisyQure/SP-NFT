function baseline = measure_baseline(eeg_handle, scheme, cfg)
% 测被试的基线频带功率（前 baseline.duration_sec 秒）
% 返回的 baseline 是 struct，跟 score_fn 期望的格式一致

fprintf('[Baseline] Starting baseline acquisition. Ask the participant to rest and relax for %d s.\n', ...
    cfg.baseline.duration_sec);

n_samples = 0;
accum = struct();
band_names = fieldnames(scheme.bands);
for k = 1:length(band_names)
    accum.(band_names{k}) = 0;
end

t0 = tic;
period = 1 / cfg.feedback.update_hz;

while toc(t0) < cfg.baseline.duration_sec
    eeg = eeg_get_window(eeg_handle, cfg.feedback.window_sec);
    powers = extract_band_power(eeg, eeg_handle.fs, ...
        cfg.eeg.montage, scheme.channels, scheme.bands);
    
    for k = 1:length(band_names)
        name = band_names{k};
        accum.(name) = accum.(name) + powers.(name);
    end
    n_samples = n_samples + 1;
    
    pause(period);
end

% 平均作为基线
baseline = struct();
for k = 1:length(band_names)
    name = band_names{k};
    baseline.(name) = accum.(name) / n_samples;
end

fprintf('[Baseline] Complete. Baseline values:\n');
disp(baseline);

end