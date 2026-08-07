function y = sigmoid_norm(x, bias, scale)
% 把任意实数压到 0~1，便于反馈呈现
% bias：x 取多少时输出 0.5
% scale：x 偏离 bias 多少时显著饱和（小 → 陡，大 → 缓）
if nargin < 2, bias = 0; end
if nargin < 3, scale = 1; end
y = 1 ./ (1 + exp(-(x - bias) / scale));
end