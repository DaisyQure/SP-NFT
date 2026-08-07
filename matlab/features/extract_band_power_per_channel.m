function powers = extract_band_power_per_channel(eeg, fs, montage, channels, bands)
% 按通道分别返回各频带功率
% 输出:powers.(band_name).(channel_name) = scalar
% 例:powers.mu.C3, powers.mu.C4

ch_idx = zeros(1, length(channels));
for k = 1:length(channels)
    idx = find(strcmpi(montage, channels{k}), 1);
    if isempty(idx)
        error('[Feature] Channel %s is not present in the montage.', channels{k});
    end
    ch_idx(k) = idx;
end

selected = eeg(ch_idx, :);

nfft = min(size(selected,2), fs);
window = hamming(nfft);
noverlap = round(nfft / 2);

[pxx, f] = pwelch(selected', window, noverlap, nfft, fs);
% pxx 是 [nFreqs x nChan],不要平均

band_names = fieldnames(bands);
powers = struct();
for kb = 1:length(band_names)
    bname = band_names{kb};
    range = bands.(bname);
    mask = (f >= range(1)) & (f <= range(2));
    powers.(bname) = struct();
    for kc = 1:length(channels)
        cname = channels{kc};
        powers.(bname).(cname) = trapz(f(mask), pxx(mask, kc));
    end
end

end