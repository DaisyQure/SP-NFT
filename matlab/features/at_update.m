function [at, value, success] = at_update(at, fb_type, raw_score)
% 把一个原始反馈分数喂入自适应阈值,返回 0~1 的自适应反馈值。
%
% 输入:
%   at        : at_init 返回的状态
%   fb_type   : 反馈类型名,如 'simulation_intensity'
%   raw_score : score_fn 算出的原始分数(任意实数,不必预先归一化)
%
% 输出(三个都要接住!at 内部状态有更新):
%   at      : 更新后的状态
%   value   : 0~1 自适应反馈值 = raw 在最近窗口里的分位数,再做 EMA 平滑
%   success : 逻辑值,value 是否达到 target_pct

prev_value = at.ema.(fb_type);

% --- 关掉自适应:直接透传(论文对照模式)---
if ~at.enable
    value   = max(0, min(1, raw_score));
    success = value >= at.target_pct;
    at.last_pct.(fb_type) = value;
    at.window_open.(fb_type) = success;
    at.prev_value.(fb_type) = prev_value;
    at.trend.(fb_type) = local_trend(prev_value, value);
    return;
end

W = at.W;

% --- 1. 把 raw_score 写入该类型的环形缓冲区 ---
i = at.idx.(fb_type);
at.buf.(fb_type)(i) = raw_score;
at.idx.(fb_type)    = mod(i, W) + 1;
at.count.(fb_type)  = min(at.count.(fb_type) + 1, W);

n = at.count.(fb_type);

% --- 2. 冷启动保护:样本太少先不给有意义反馈 ---
if n < at.min_samples
    value = 0.5;
    at.ema.(fb_type) = 0.5;
    at.last_pct.(fb_type) = 0.5;
    at.window_open.(fb_type) = false;
    at.prev_value.(fb_type) = prev_value;
    at.trend.(fb_type) = local_trend(prev_value, value);
    success = false;
    return;
end

% --- 3. 经验分位数:raw_score 在最近 n 个样本里排第几 ---
window = at.buf.(fb_type)(1:n);
pct = sum(window <= raw_score) / n;     % ∈ [0,1]
at.last_pct.(fb_type) = pct;

% --- 4. EMA 平滑,削掉分位数的台阶感 ---
a = at.ema_alpha;
value = a * pct + (1 - a) * at.ema.(fb_type);
at.ema.(fb_type) = value;

% --- 5. 达标判定 ---
success = value >= at.target_pct;
at.window_open.(fb_type) = success;
at.prev_value.(fb_type) = prev_value;
at.trend.(fb_type) = local_trend(prev_value, value);
end

function t = local_trend(prev_value, value)
delta = value - prev_value;
if delta > 0.02
    t = 'rising';
elseif delta < -0.02
    t = 'falling';
else
    t = 'stable';
end
end
