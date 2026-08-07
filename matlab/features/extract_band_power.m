function powers = extract_band_power(eeg, fs, montage, channels, bands)
% 通用频带功率提取（基于 Welch 法）
%
% 输入：
%   eeg      [nChan x nSamples]  EEG 数据
%   fs       采样率
%   montage  cell array，所有通道名称（顺序对应 eeg 的行）
%   channels cell array，要用的通道名，例如 {'C3','Cz','C4'}
%   bands    struct，例如 struct('theta',[4 8],'alpha',[8 13])
%
% 输出：
%   powers   struct，每个频段一个字段，值是所选通道的平均带功率
%
% 例：powers.theta、powers.smr 等

% 找到要用的通道索引
ch_idx = zeros(1, length(channels));
for k = 1:length(channels)
    idx = find(strcmpi(montage, channels{k}), 1);
    if isempty(idx)
        error('[Feature] Channel %s is not present in the montage.', channels{k});
    end
    ch_idx(k) = idx;
end

selected = eeg(ch_idx, :);

% 对每个通道做 Welch，再对要分析的频段积分
% Welch 窗：1 秒，50% 重叠
nfft = min(size(selected,2), fs);
window = hamming(nfft);
noverlap = round(nfft / 2);

% 多通道平均功率谱
[pxx, f] = pwelch(selected', window, noverlap, nfft, fs);
% pxx 是 [nFreqs x nChan]，沿通道平均
pxx_mean = mean(pxx, 2);

% 对每个频带积分
band_names = fieldnames(bands);
powers = struct();
for k = 1:length(band_names)
    name = band_names{k};
    range = bands.(name);
    mask = (f >= range(1)) & (f <= range(2));
    powers.(name) = trapz(f(mask), pxx_mean(mask));
end

end