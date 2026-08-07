function scheme = scheme_attention()
% 注意力集中式：降 theta、增 SMR/beta1，目标通道 C3/Cz/C4

scheme.name = 'attention';
scheme.description = 'Attention-focused SP-NFT';
scheme.channels = {'C3', 'Cz', 'C4'};
scheme.bands = struct( ...
    'theta', [4 8], ...
    'smr',   [12 15], ...
    'beta1', [15 20]);
scheme.feedback_types = {'attention'};
scheme.score_fn = @score_attention;

% --- A-B-A-B 指导语 ---
scheme.instruction_a = 'Remain still, fixate on the cross, and do not perform any specific task.';
scheme.instruction_b = 'Focus your attention to move the vehicle forward.';

end

function val = score_attention(powers, baseline)
% 反馈值：SMR 上升好，theta 下降好

theta_ratio = powers.theta / baseline.theta;
smr_ratio   = powers.smr   / baseline.smr;
beta1_ratio = powers.beta1 / baseline.beta1;

raw = (smr_ratio + beta1_ratio) / 2 - theta_ratio;

val = sigmoid_norm(raw, 0, 1.5);

val = struct('attention', val);

end
