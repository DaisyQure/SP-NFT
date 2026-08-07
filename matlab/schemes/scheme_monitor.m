function scheme = scheme_monitor()
% 监测引导式:同时输出多个反馈值,UI 端做仪表盘
% 用全脑通道,提取多个频段,用于实时监测

scheme.name = 'monitor';
scheme.description = 'Multidimensional monitoring';
scheme.channels = {'Fz', 'Cz', 'Pz', 'C3', 'C4'};
scheme.bands = struct( ...
    'theta', [4 8], ...
    'alpha', [8 13], ...
    'smr',   [12 15], ...
    'beta1', [15 20]);
scheme.feedback_types = {'attention', 'relaxation', 'simulation_intensity'};
scheme.score_fn = @score_monitor;

% --- A-B-A-B 指导语 ---
scheme.instruction_a = 'Remain still and breathe naturally.';
scheme.instruction_b = 'Regulate your state according to the prompt.';

end

function val = score_monitor(powers, baseline)
% 同时输出 attention / relaxation / simulation_intensity,不做训练
theta_r = powers.theta / baseline.theta;
alpha_r = powers.alpha / baseline.alpha;
smr_r   = powers.smr   / baseline.smr;
beta1_r = powers.beta1 / baseline.beta1;

attention  = sigmoid_norm((smr_r + beta1_r)/2 - theta_r, 0, 0.8);
relaxation = sigmoid_norm(alpha_r - beta1_r, 0, 0.8);
simulation_intensity = sigmoid_norm(1 - alpha_r * 0.5, 0, 0.8);

val = struct( ...
    'attention',            attention, ...
    'relaxation',           relaxation, ...
    'simulation_intensity', simulation_intensity);

end