function scheme = scheme_relax()
% 放松式:增 alpha,降 beta,目标通道 Pz/POz/Oz(后部 alpha 最强)

scheme.name = 'relax';
scheme.description = 'Relaxation-training SP-NFT';
scheme.channels = {'Pz', 'POz', 'O1', 'O2'};
scheme.bands = struct( ...
    'alpha', [8 13], ...
    'beta1', [15 20], ...
    'beta2', [20 30]);
scheme.feedback_types = {'relaxation'};
scheme.score_fn = @score_relax;

% --- A-B-A-B 指导语 ---
scheme.instruction_a = 'Remain still, fixate on the cross, and breathe naturally.';
scheme.instruction_b = 'Breathe slowly and deeply, and gradually relax.';

end

function val = score_relax(powers, baseline)
% alpha 升好,beta 降好
alpha_ratio = powers.alpha / baseline.alpha;
beta1_ratio = powers.beta1 / baseline.beta1;
beta2_ratio = powers.beta2 / baseline.beta2;

% alpha 上升,beta 下降 → 放松度高
raw = alpha_ratio - (beta1_ratio + beta2_ratio) / 2;

val_relax = sigmoid_norm(raw, 0, 1.5);
val = struct('relaxation', val_relax);

end