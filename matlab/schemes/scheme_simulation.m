function scheme = scheme_simulation()
% 模拟式：模拟真实运动过程中大脑神经活动动态变化的 SP-NFT
% 主要监测 C3/Cz/C4 的 mu/beta ERD（事件相关去同步化）

scheme.name = 'simulation';
scheme.description = 'Simulation-based SP-NFT (mu/beta ERD)';
scheme.channels = {'C3', 'Cz', 'C4'};  % 运动皮层中央区域
scheme.bands = struct( ...
    'mu',   [8 13], ...      % mu 节律，运动想象时下降
    'beta', [15 25]);        % beta，精细动作想象时变化
scheme.feedback_types = {'simulation_intensity'};
scheme.score_fn = @score_simulation;

% --- A-B-A-B 指导语 ---
scheme.instruction_a = 'Remain still, fixate on the cross, and breathe naturally.';
scheme.instruction_b = 'Recall and maintain the mental state associated with aiming and firing.';

end

function val = score_simulation(powers, baseline)
% 反馈值：模拟式动作想象的整体激活强度（原始分数,交给自适应阈值归一化）

mu_ratio   = powers.mu   / baseline.mu;
beta_ratio = powers.beta / baseline.beta;

erd_strength = 1 - mu_ratio;
combined = 0.7 * erd_strength + 0.3 * (1 - beta_ratio);

simulation_value = sigmoid_norm(combined, 0, 1.5);

val = struct('simulation_intensity', simulation_value);
end
