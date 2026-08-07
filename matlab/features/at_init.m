function at = at_init(feedback_types, cfg)
% 初始化自适应分位数阈值状态。
% 为每一种反馈类型建一个独立的分位数滑动窗口(环形缓冲区)。
%
% feedback_types : cell 数组,如 {'simulation_intensity'} 或 {'attention','relaxation'}
% cfg            : config() 返回的配置结构体

W = round(cfg.adaptive.window_sec * cfg.feedback.update_hz);  % 窗口样本数

at.enable      = cfg.adaptive.enable;
at.W           = W;
at.target_pct  = cfg.adaptive.target_pct;
at.ema_alpha   = cfg.adaptive.ema_alpha;
at.min_samples = cfg.adaptive.min_samples;
at.types       = feedback_types;

at.buf   = struct();   % 环形缓冲区数据
at.count = struct();   % 已写入的有效样本数
at.idx   = struct();   % 写指针
at.ema   = struct();   % 上一次平滑后的输出
at.last_pct = struct();
at.window_open = struct();
at.prev_value = struct();
at.trend = struct();
at.open_since = struct();

for k = 1:numel(feedback_types)
    t = feedback_types{k};
    at.buf.(t)   = zeros(1, W);
    at.count.(t) = 0;
    at.idx.(t)   = 1;
    at.ema.(t)   = 0.5;
    at.last_pct.(t) = 0.5;
    at.window_open.(t) = false;
    at.prev_value.(t) = 0.5;
    at.trend.(t) = 'stable';
    at.open_since.(t) = NaN;
end
end
