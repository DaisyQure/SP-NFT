function cfg = config()
% 全局配置中心。所有可调参数都从这里出,不要散落各处。

% ==== EEG 设备 ====
cfg.eeg.use_simulation = true;
cfg.eeg.device         = 'Neuracle';
cfg.eeg.ip             = '127.0.0.1';
cfg.eeg.port           = 8712;
cfg.eeg.fs             = 1000;
cfg.eeg.n_channels     = 32;

cfg.eeg.montage = { ...
    'Fp1','Fp2','F7','F3','Fz','F4','F8', ...
    'FC5','FC1','FC2','FC6', ...
    'T7','C3','Cz','C4','T8', ...
    'CP5','CP1','CP2','CP6', ...
    'P7','P3','Pz','P4','P8', ...
    'PO7','PO3','POz','PO4','PO8', ...
    'O1','O2'};

cfg.eeg.buffer_sec = 4;

% ==== TCP 服务器（向 Unity 发反馈值）====
cfg.server.port = 5555;

% ==== 反馈频率 ====
cfg.feedback.window_sec = 2;
cfg.feedback.update_hz  = 10;

% ==== 频带定义 ====
cfg.bands.theta  = [4 8];
cfg.bands.alpha  = [8 13];
cfg.bands.smr    = [12 15];
cfg.bands.beta1  = [15 20];
cfg.bands.beta2  = [20 30];

% ==== 基线测量 ====
cfg.baseline.duration_sec = 30;

% ==== 自适应分位数阈值 ====
cfg.adaptive.enable      = true;   % 关掉则退化为固定基线直传（论文对照用）
cfg.adaptive.window_sec  = 30;     % 分位数滑动窗口长度（秒）
cfg.adaptive.target_pct  = 0.70;   % 达标阈值:分位数≥0.70（前30%）算一次"成功"
cfg.adaptive.ema_alpha   = 0.30;   % 反馈值平滑系数(0~1,越大越跟手)
cfg.adaptive.min_samples = 30;     % 窗口样本少于此值时输出0.5(冷启动保护)

% ==== A-B-A-B 实验范式 ====
% A = 静息基线, B = 反馈调节; 一个 A-B = 一个试次
% GUI 可在 Start 之前覆盖这些默认值
cfg.paradigm.n_trials    = 20;
cfg.paradigm.phase_a_dur = 10;     % A 阶段时长(秒)
cfg.paradigm.phase_b_dur = 30;     % B 阶段时长(秒)

% ==== 反馈通道(视觉/听觉/双通道) — DEV_PLAN 三 ====
% GUI 运行时可改; 改后即时下发 TCP type=modality, Unity 端切换显示/合成
cfg.feedback.modality = 'both';      % 'visual' / 'auditory' / 'both'

% ==== Monitor 模式下当前关注目标 ====
% 仅 scheme=monitor 时生效; GUI 可在运行中切换
cfg.monitor.target = 'attention';    % 'attention' / 'relaxation' / 'simulation'

end