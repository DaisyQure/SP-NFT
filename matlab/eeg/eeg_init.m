function handle = eeg_init(cfg)
% 初始化 EEG 设备。返回一个 handle 给后续调用使用。
% 切换设备只改这里。

if cfg.eeg.use_simulation
    handle.type = 'sim';
    handle.fs = cfg.eeg.fs;
    handle.n_channels = cfg.eeg.n_channels;
    handle.montage = cfg.eeg.montage;
    handle.t_start = tic;
    fprintf('[EEG] Simulated-input mode.\n');
else
    % 真实 Neuracle 设备
    addpath('api');
    handle.type = 'neuracle';
    handle.fs = cfg.eeg.fs;
    handle.n_channels = cfg.eeg.n_channels;
    handle.server = DataServer( ...
        cfg.eeg.device, ...
        cfg.eeg.n_channels, ...
        cfg.eeg.ip, ...
        cfg.eeg.port, ...
        cfg.eeg.fs, ...
        cfg.eeg.buffer_sec);
    handle.server.Open();
    fprintf('[EEG] Connected to Neuracle at %s:%d.\n', cfg.eeg.ip, cfg.eeg.port);
    
    % 预热：等缓冲填满
    fprintf('[EEG] Waiting for the data buffer to fill...\n');
    pause(cfg.eeg.buffer_sec + 0.5);
end

end