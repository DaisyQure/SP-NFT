function nft_console()
% NFT 实验流程总控台
% 交互式让实验员选择训练方案，然后启动对应 session。
% Unity 端必须已经在运行并准备好连接。
%
% 用法：直接在 MATLAB 命令行输入
%   >> nft_console
%
% 这是面向实验员的入口，封装了 run_session 的常用调用。

fprintf('\n');
fprintf('====================================================\n');
fprintf(' SP-NFT Experiment Console\n');
fprintf(' Four user-experience-oriented neurofeedback modes\n');
fprintf('====================================================\n');
fprintf('  1) simulation   - Simulation training\n');
fprintf('  2) attention    - Attention training\n');
fprintf('  3) relax        - Relaxation training\n');
fprintf('  4) monitor      - Monitoring mode\n');
fprintf('  0) Exit\n');
fprintf('----------------------------------------------------\n');

choice = input('Select a training mode (1-4, 0 to exit): ');
if isempty(choice) || choice == 0
    fprintf('[Console] Exited.\n');
    return;
end

scheme_map = {'simulation', 'attention', 'relax', 'monitor'};
if choice < 1 || choice > length(scheme_map)
    fprintf('[Console] Invalid selection.\n');
    return;
end
scheme_name = scheme_map{choice};

fprintf('[Console] Selected mode: %s\n', scheme_name);
duration_input = input('Session duration in seconds (leave empty to follow Unity): ');

if isempty(duration_input)
    fprintf('[Console] Starting %s (duration follows Unity).\n', scheme_name);
    run_session(scheme_name);
else
    fprintf('[Console] Starting %s (%d s).\n', scheme_name, duration_input);
    run_session(scheme_name, duration_input);
end

fprintf('[Console] Session ended.\n');
end
