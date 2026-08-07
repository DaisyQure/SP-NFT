% Smoke test 第二项: A-B-A-B 状态机 + recorder 联动 (不连 Unity, 不开 EEG)
addpath('recorder','report','utils','server','schemes','features','eeg');

% --- 0. parse 全部改动的文件 ---
files = { ...
    'server/tcp_send_message.m', ...
    'config.m', ...
    'schemes/scheme_attention.m', ...
    'schemes/scheme_simulation.m', ...
    'schemes/scheme_relax.m', ...
    'schemes/scheme_monitor.m', ...
    'nft_session_init.m', ...
    'nft_session_step.m', ...
    'nft_session_finalize.m', ...
    'nft_monitor_ui.m'};
for k = 1:length(files)
    info = checkcode(files{k}, '-string');
    if isempty(info)
        fprintf('OK     %s\n', files{k});
    else
        % 只看错误级别, 忽略 lint 风格提示
        if contains(info, 'Error', 'IgnoreCase', true)
            fprintf('ERROR  %s:\n%s\n', files{k}, info);
        else
            fprintf('OK     %s (style warnings)\n', files{k});
        end
    end
end

% --- 1. 验证 config 含 paradigm ---
cfg = config();
assert(isfield(cfg, 'paradigm'),       'config.paradigm is missing');
assert(cfg.paradigm.n_trials == 20,    'Incorrect default n_trials value');
assert(cfg.paradigm.phase_a_dur == 10, 'Incorrect default phase_a_dur value');
assert(cfg.paradigm.phase_b_dur == 30, 'Incorrect default phase_b_dur value');
fprintf('CFG_PARADIGM_OK\n');

% --- 2. 验证四个 scheme 都有 instruction_a/b ---
for nm = {'attention','simulation','relax','monitor'}
    s = feval(['scheme_' nm{1}]);
    assert(isfield(s,'instruction_a') && ~isempty(s.instruction_a), [nm{1} ' is missing instruction_a']);
    assert(isfield(s,'instruction_b') && ~isempty(s.instruction_b), [nm{1} ' is missing instruction_b']);
end
fprintf('SCHEMES_INSTR_OK\n');

% --- 3. 直接调用 paradigm 辅助函数验证 recorder 事件流 ---
% 模拟一个简短 session: 不真的开 EEG/TCP, 只验证 ctx 结构与 recorder 事件流
subj = struct('id','SMOKE_T2','name','','sex','','age',0,'handedness','','note','paradigm smoke');
rec = recorder_open('attention', subj, cfg);

perf_path = fullfile(rec.session_dir, 'performance_summary.csv');
fid_perf = fopen(perf_path, 'w');
if fid_perf ~= -1
    fprintf(fid_perf, 'metric,N,mean,std,min,median,max\n');
    fprintf(fid_perf, 'phase_ack_latency_ms,2,12.5000,3.5355,10.0000,12.5000,15.0000\n');
    fprintf(fid_perf, 'session_stop_ack_latency_ms,1,18.0000,0.0000,18.0000,18.0000,18.0000\n');
    fprintf(fid_perf, 'phase_ack_transport_ms,2,8.5000,2.1213,7.0000,8.5000,10.0000\n');
    fprintf(fid_perf, 'session_stop_ack_transport_ms,1,11.0000,0.0000,11.0000,11.0000,11.0000\n');
    fprintf(fid_perf, 'tcp_connected_transport_ms,1,300.0000,0.0000,300.0000,300.0000,300.0000\n');
    fprintf(fid_perf, 'unity_sync_transport_ms,3,9.3333,2.0817,7.0000,10.0000,11.0000\n');
    fprintf(fid_perf, 'unity_marker_transport_ms,4,82.0000,145.3575,7.0000,10.5000,300.0000\n');
    fclose(fid_perf);
end

% 构造 mock ctx (只放 paradigm + 必要字段, 跳过 server/eeg)
ctx = struct();
ctx.scheme = scheme_attention();
ctx.recorder = rec;
ctx.seq = 0;
ctx.paradigm = struct('n_trials',3,'phase_a_dur',5,'phase_b_dur',10, ...
    'trial_idx',0,'current_phase','','phase_t0',[]);

% slog 占位, 让 session_log_write 不炸 (它内部有 nil 守卫)
ctx.slog = struct('fid', -1);

% 直接调本地辅助函数模拟 3 个 trial 的 A/B 边界. 用 functions handle 拿不到 local
% function (它们在 nft_session_step.m 里), 改用 manual recorder_event 模拟
for trial = 1:3
    % 模拟 A start
    ctx.paradigm.trial_idx = trial;
    ctx.paradigm.current_phase = 'A';
    ctx.recorder = recorder_event(ctx.recorder, 'source','matlab','kind','phase', ...
        'key','phase_a_start','value',trial,'info','dur=5s');
    ctx.recorder = recorder_event(ctx.recorder, 'source','matlab','kind','trial', ...
        'key','trial_start','value',trial,'info','');
    % 模拟 A 期间 50 帧推送
    for f = 1:50
        push = struct();
        push.t = (trial-1)*15 + f*0.1;
        push.phase_rec = 'A';
        push.trial_idx_rec = trial;
        push.attention_rec = 0.3 + 0.1*sin(f/8);
        push.theta_power_rec = 12 + 0.3*sin(f/10);
        ctx.recorder = recorder_push(ctx.recorder, push);
    end
    % 模拟 A end
    ctx.recorder = recorder_event(ctx.recorder, 'source','matlab','kind','phase', ...
        'key','phase_a_end','value',trial,'info','');
    % 模拟 B start
    ctx.paradigm.current_phase = 'B';
    ctx.recorder = recorder_event(ctx.recorder, 'source','matlab','kind','phase', ...
        'key','phase_b_start','value',trial,'info','dur=10s');
    for f = 1:100
        push = struct();
        push.t = (trial-1)*15 + 5 + f*0.1;
        push.phase_rec = 'B';
        push.trial_idx_rec = trial;
        push.attention_rec = 0.55 + 0.25*sin(f/12);
        push.theta_power_rec = 9 + 0.3*sin(f/10);
        ctx.recorder = recorder_push(ctx.recorder, push);
    end
    % 模拟 B end + trial end
    ctx.recorder = recorder_event(ctx.recorder, 'source','matlab','kind','phase', ...
        'key','phase_b_end','value',trial,'info','');
    ctx.recorder = recorder_event(ctx.recorder, 'source','matlab','kind','trial', ...
        'key','trial_end','value',trial,'info','');
end

ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','phase_ack_latency_ms','value',10,'info','smoke_phase_ack_1');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','phase_ack_latency_ms','value',15,'info','smoke_phase_ack_2');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','session_stop_ack_latency_ms','value',18,'info','smoke_session_stop_ack');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','phase_ack_transport_ms','value',7,'info','smoke_phase_ack_transport_1');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','phase_ack_transport_ms','value',10,'info','smoke_phase_ack_transport_2');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','session_stop_ack_transport_ms','value',11,'info','smoke_session_stop_transport');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','tcp_connected_transport_ms','value',300,'info','smoke_tcp_connect_transport');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','unity_sync_transport_ms','value',7,'info','smoke_sync_transport_1');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','unity_sync_transport_ms','value',10,'info','smoke_sync_transport_2');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','unity_sync_transport_ms','value',11,'info','smoke_sync_transport_3');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','unity_marker_transport_ms','value',7,'info','smoke_marker_transport_1');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','unity_marker_transport_ms','value',10,'info','smoke_marker_transport_2');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','unity_marker_transport_ms','value',11,'info','smoke_marker_transport_3');
ctx.recorder = recorder_event(ctx.recorder, 'source','system','kind','latency', ...
    'key','unity_marker_transport_ms','value',300,'info','smoke_marker_transport_4');

recorder_close(ctx.recorder);
fprintf('REC_DONE %s\n', ctx.recorder.session_dir);

% --- 4. 跑报告 ---
generate_report(ctx.recorder.session_dir);
fprintf('REPORT_OK\n');

% --- 5. 验证 events_log.csv 含 12 个 phase 事件 + 6 个 trial 事件 + 1 个 subject enrolled = 19 行 ---
ev_path = fullfile(ctx.recorder.session_dir, 'events_log.csv');
T = readtable(ev_path);
n_phase = sum(strcmp(string(T.kind), 'phase'));
n_trial = sum(strcmp(string(T.kind), 'trial'));
fprintf('events: total=%d phase=%d trial=%d\n', height(T), n_phase, n_trial);
assert(n_phase == 12, sprintf('Expected 12 phase events; found %d', n_phase));
assert(n_trial == 6,  sprintf('Expected 6 trial events; found %d', n_trial));
fprintf('EVENTS_OK\n');

% --- 6. 验证 timeseries 含 phase_rec + trial_idx_rec 列 ---
ts_path = fullfile(ctx.recorder.session_dir, 'timeseries_rec.csv');
T = readtable(ts_path);
cols = T.Properties.VariableNames;
assert(any(strcmp(cols, 'phase_rec')),     'timeseries is missing the phase_rec column');
assert(any(strcmp(cols, 'trial_idx_rec')), 'timeseries is missing the trial_idx_rec column');
n_A = sum(strcmp(string(T.phase_rec), 'A'));
n_B = sum(strcmp(string(T.phase_rec), 'B'));
fprintf('timeseries: total=%d A=%d B=%d\n', height(T), n_A, n_B);
assert(n_A == 150, sprintf('Expected 150 Phase A rows (3*50); found %d', n_A));
assert(n_B == 300, sprintf('Expected 300 Phase B rows (3*100); found %d', n_B));
fprintf('TIMESERIES_OK\n');

fprintf('ALL_PASSED\n');
