function ctx = nft_session_step(ctx)
% 推进 session 一步 (由 GUI 的 timer 每帧调用一次)
% 根据 ctx.phase 执行不同动作:
%   'waiting_unity' : 等 Unity 连接, 连上后转 'baseline'
%   'baseline'      : 测基线 (积累 cfg.baseline.duration_sec 秒)
%   'running'       : 反馈主循环 (每次步进一帧)
%   'finished'      : 已结束, 调用方应停止 timer

if strcmp(ctx.phase, 'finished')
    return;
end

try
    switch ctx.phase

        case 'waiting_unity'
            if ctx.server.Connected
                fprintf('[Server] Connected: %s:%d\n', ctx.server.ClientAddress, ctx.server.ClientPort);
                ctx.baseline_t0 = tic;
                ctx.baseline_acc = struct();
                ctx.baseline_n = 0;
                band_names = fieldnames(ctx.scheme.bands);
                for kk = 1:length(band_names)
                    ctx.baseline_acc.(band_names{kk}) = 0;
                end
                fprintf('[Baseline] Starting %d s baseline acquisition.\n', ctx.cfg.baseline.duration_sec);
                ctx.phase = 'baseline';
            end
            return;

        case 'baseline'
            elapsed = toc(ctx.baseline_t0);
            if elapsed >= ctx.cfg.baseline.duration_sec
                ctx.baseline = struct();
                band_names = fieldnames(ctx.baseline_acc);
                for kk = 1:length(band_names)
                    nm = band_names{kk};
                    if ctx.baseline_n > 0
                        ctx.baseline.(nm) = ctx.baseline_acc.(nm) / ctx.baseline_n;
                    else
                        ctx.baseline.(nm) = 1;
                    end
                end
                fprintf('[Baseline] Complete: %d samples.\n', ctx.baseline_n);
                session_log_write(ctx.slog, 'Baseline', sprintf('captured %gs, n=%d', ...
                    ctx.cfg.baseline.duration_sec, ctx.baseline_n));

                ctx.at = at_init(ctx.scheme.feedback_types, ctx.cfg);
                if ctx.at.enable
                    fprintf('[Adaptive] Enabled (window=%d s, target=%.2f).\n', ...
                        ctx.cfg.adaptive.window_sec, ctx.cfg.adaptive.target_pct);
                end
                ctx.t0 = tic;
                ctx.phase = 'running';
            else
                % 在 baseline 阶段也采一帧, 但只累积基线, 不发反馈
                eeg = eeg_get_window(ctx.eeg_handle, ctx.cfg.feedback.window_sec);
                powers = extract_band_power(eeg, ctx.eeg_handle.fs, ...
                    ctx.cfg.eeg.montage, ctx.scheme.channels, ctx.scheme.bands);
                band_names = fieldnames(powers);
                for kk = 1:length(band_names)
                    nm = band_names{kk};
                    ctx.baseline_acc.(nm) = ctx.baseline_acc.(nm) + powers.(nm);
                end
                ctx.baseline_n = ctx.baseline_n + 1;
            end
            return;

        case 'running'
            if ~ctx.server.Connected
                fprintf('[Session] Unity disconnected.\n');
                ctx.phase = 'finished';
                return;
            end

            % --- A-B-A-B 调度: 进入 running 后立即开 trial 1 / phase A ---
            if isempty(ctx.paradigm.current_phase)
                ctx = paradigm_enter_phase(ctx, 1, 'A');
            else
                % 检查当前 phase 是否到时, 到时则切
                phase_elapsed = toc(ctx.paradigm.phase_t0);
                if strcmp(ctx.paradigm.current_phase, 'A') && ...
                        phase_elapsed >= ctx.paradigm.phase_a_dur
                    ctx = paradigm_end_phase(ctx);
                    ctx = paradigm_enter_phase(ctx, ctx.paradigm.trial_idx, 'B');
                elseif strcmp(ctx.paradigm.current_phase, 'B') && ...
                        phase_elapsed >= ctx.paradigm.phase_b_dur
                    ctx = paradigm_end_phase(ctx);
                    if ctx.paradigm.trial_idx >= ctx.paradigm.n_trials
                        fprintf('[Paradigm] Completed %d trials; ending session.\n', ctx.paradigm.n_trials);
                        ctx.phase = 'finished';
                        return;
                    end
                    ctx = paradigm_enter_phase(ctx, ctx.paradigm.trial_idx + 1, 'A');
                end
            end

            % 保底: paradigm 启用时总时长由 n_trials*(A+B) 决定, 不用 duration_sec 截断
            if toc(ctx.t0) >= ctx.duration_sec && ...
                    (~isfield(ctx, 'paradigm') || ctx.paradigm.n_trials <= 0)
                ctx.phase = 'finished';
                return;
            end

            % --- 取 EEG + 算 score ---
            eeg = eeg_get_window(ctx.eeg_handle, ctx.cfg.feedback.window_sec);
            powers = extract_band_power(eeg, ctx.eeg_handle.fs, ...
                ctx.cfg.eeg.montage, ctx.scheme.channels, ctx.scheme.bands);
            vals = ctx.scheme.score_fn(powers, ctx.baseline);

            % --- 每个反馈类型: 自适应阈值 + 发送 TCP ---
            for k = 1:length(ctx.scheme.feedback_types)
                ft = ctx.scheme.feedback_types{k};
                raw = vals.(ft);
                [ctx.at, value, success] = at_update(ctx.at, ft, raw);

                tcp_send_message(ctx.server, ctx.seq, ft, value, ctx.scheme.name);
                ctx.seq = ctx.seq + 1;

                ctx.value_sum.(ft)   = ctx.value_sum.(ft) + value;
                ctx.value_count.(ft) = ctx.value_count.(ft) + 1;

                if success
                    if isnan(ctx.window_open_since.(ft))
                        ctx.window_open_since.(ft) = toc(ctx.t0);
                        ctx.window_open_count.(ft) = ctx.window_open_count.(ft) + 1;
                        session_log_write(ctx.slog, 'Window', sprintf('%s OPEN at t=%.2fs value=%.3f', ...
                            ft, toc(ctx.t0), value));
                    end
                    open_for = toc(ctx.t0) - ctx.window_open_since.(ft);
                    ctx.window_open_total.(ft) = ctx.window_open_total.(ft) + ctx.period;
                    if open_for > ctx.window_open_max.(ft)
                        ctx.window_open_max.(ft) = open_for;
                    end
                else
                    if ~isnan(ctx.window_open_since.(ft))
                        session_log_write(ctx.slog, 'Window', sprintf('%s CLOSED at t=%.2fs', ...
                            ft, toc(ctx.t0)));
                    end
                    ctx.window_open_since.(ft) = NaN;
                end
            end

            % --- 推数据到共享层 (给 GUI) ---
            push_data = struct();
            push_data.t = toc(ctx.t0);
            push_data.scheme = ctx.scheme.name;
            push_data.sent = ctx.seq;
            push_data.markers_count = ctx.mk.count;
            if isfield(ctx.at.ema, 'attention'),            push_data.attention            = ctx.at.ema.attention; end
            if isfield(ctx.at.ema, 'relaxation'),           push_data.relaxation           = ctx.at.ema.relaxation; end
            if isfield(ctx.at.ema, 'simulation_intensity'), push_data.simulation_intensity = ctx.at.ema.simulation_intensity; end
            if isfield(powers, 'theta'), push_data.theta = powers.theta; end
            if isfield(powers, 'alpha'), push_data.alpha = powers.alpha; end
            if isfield(powers, 'smr'),   push_data.smr   = powers.smr;   end
            if isfield(powers, 'beta1'), push_data.beta  = powers.beta1; end
            if isfield(powers, 'beta'),  push_data.beta  = powers.beta;  end
            primary_fb = ctx.scheme.feedback_types{1};
            push_data.window_open = ctx.at.window_open.(primary_fb);
            nft_shared('push', push_data);

            % --- 推数据到 recorder (按 _rec 后缀约定, 见 docs/RECORDING_CONVENTION.md) ---
            push_rec = struct();
            push_rec.t = push_data.t;
            push_rec.phase_rec = ctx.paradigm.current_phase;
            push_rec.trial_idx_rec = ctx.paradigm.trial_idx;
            for k = 1:length(ctx.scheme.feedback_types)
                ft = ctx.scheme.feedback_types{k};
                if isfield(ctx.at.ema, ft)
                    push_rec.([ft '_rec']) = ctx.at.ema.(ft);
                end
                if isfield(ctx.at.last_pct, ft)
                    push_rec.([ft '_pct_rec']) = ctx.at.last_pct.(ft);
                end
                if isfield(ctx.at.window_open, ft)
                    push_rec.([ft '_window_open_rec']) = double(ctx.at.window_open.(ft));
                end
            end
            band_names = fieldnames(powers);
            for kk = 1:length(band_names)
                bn = band_names{kk};
                push_rec.([bn '_power_rec']) = powers.(bn);
            end
            ctx.recorder = recorder_push(ctx.recorder, push_rec);

            % --- 拉取 Unity marker ---
            ctx.mk = marker_poll(ctx.server, ctx.mk);
            if ctx.mk.count > ctx.last_marker_count
                nE = length(ctx.mk.new_events);
                for i = 1:nE
                    evt = ctx.mk.new_events(i);
                    evt_char = char(evt);
                    % 按索引取该事件本身的 value/scene, 避免被同帧其他 marker 覆写
                    if length(ctx.mk.new_values) >= i
                        evt_val = ctx.mk.new_values(i);
                    else
                        evt_val = ctx.mk.last_value;
                    end
                    if length(ctx.mk.new_scenes) >= i
                        evt_scene = char(ctx.mk.new_scenes(i));
                    else
                        evt_scene = char(ctx.mk.last_scene);
                    end
                    if length(ctx.mk.new_infos) >= i
                        evt_info = char(ctx.mk.new_infos(i));
                    else
                        evt_info = char(ctx.mk.last_info);
                    end
                    if length(ctx.mk.new_unity_ts) >= i
                        evt_unity_ts = ctx.mk.new_unity_ts(i);
                    else
                        evt_unity_ts = ctx.mk.last_unity_ts;
                    end
                    if length(ctx.mk.new_recv_ts) >= i
                        evt_recv_ts = ctx.mk.new_recv_ts(i);
                    else
                        evt_recv_ts = ctx.mk.last_recv_ts;
                    end
                    if length(ctx.mk.new_seqs) >= i
                        evt_seq = ctx.mk.new_seqs(i);
                    else
                        evt_seq = ctx.mk.last_seq;
                    end
                    transport_ms = NaN;
                    if evt_unity_ts > 0 && evt_recv_ts > 0
                        transport_ms = (evt_recv_ts - evt_unity_ts) * 1000;
                    end
                    if isfield(ctx.behavior_counts, evt_char)
                        ctx.behavior_counts.(evt_char) = ctx.behavior_counts.(evt_char) + 1;
                    end
                    if any(evt == ["session_start","session_end","action_window_open","action_window_close", ...
                                   "menu_return","game_over","tcp_connected","tcp_disconnected","monitor_ready", ...
                                   "enemy_spawn","enemy_hit","enemy_missed","enemy_hit_player","shot_fired", ...
                                   "coin_spawn","coin_collected", ...
                                   "trial_start","aim_start","state_above_threshold","state_dropped", ...
                                   "auto_fire","trial_end","threshold_adjusted","threshold_hold", ...
                                   "phase_ack","session_stop_ack"])
                        session_log_write(ctx.slog, 'Event', sprintf('%s scene=%s value=%.3f info=%s unity_ts=%.6f recv_ts=%.6f transport_ms=%.3f', ...
                            evt, evt_scene, evt_val, evt_info, evt_unity_ts, evt_recv_ts, transport_ms));
                        nft_shared('add_marker', evt_char, evt_scene, evt_val);
                    end

                    % --- 写入 recorder 的事件流 ---
                    ev_kind = 'marker';
                    if any(evt == ["trial_start","trial_end"]),                  ev_kind = 'trial';     end
                    if any(evt == ["threshold_adjusted","threshold_hold"]),     ev_kind = 'threshold'; end
                    if any(evt == ["phase_ack","session_stop_ack"]),            ev_kind = 'sync';      end
                    info_parts = {sprintf('scene=%s', evt_scene), sprintf('unity_ts=%.6f', evt_unity_ts), ...
                                  sprintf('recv_ts=%.6f', evt_recv_ts), sprintf('seq=%d', evt_seq)};
                    if ~isnan(transport_ms)
                        info_parts{end+1} = sprintf('transport_ms=%.3f', transport_ms);
                    end
                    if ~isempty(evt_info)
                        info_parts{end+1} = sprintf('info=%s', evt_info);
                    end
                    ctx.recorder = recorder_event(ctx.recorder, ...
                        'source', 'unity', 'kind', ev_kind, ...
                        'key',    evt_char, 'value', evt_val, ...
                        'abs_ts', evt_recv_ts, ...
                        'info',   strjoin(info_parts, ' | '));

                    if ~isnan(transport_ms)
                        ctx.perf.unity_marker_transport_ms(end+1) = transport_ms;
                        if evt == "tcp_connected"
                            ctx.perf.tcp_connected_transport_ms(end+1) = transport_ms;
                            ctx.recorder = recorder_event(ctx.recorder, ...
                                'source', 'system', 'kind', 'latency', ...
                                'key',    'tcp_connected_transport_ms', 'value', transport_ms, ...
                                'abs_ts', evt_recv_ts, ...
                                'info',   sprintf('scene=%s seq=%d endpoint=%s', evt_scene, evt_seq, evt_info));
                        elseif any(evt == ["phase_ack","session_stop_ack"])
                            ctx.perf.unity_sync_transport_ms(end+1) = transport_ms;
                        end
                    end

                    % --- 跟踪当前 trial 索引 (必须先于阈值事件处理) ---
                    if evt == "trial_start"
                        ctx.last_trial_idx = evt_val;
                    end

                    if evt == "phase_ack" && ~isnan(ctx.perf.last_phase_send_abs_ts)
                        ack_ms = (evt_recv_ts - ctx.perf.last_phase_send_abs_ts) * 1000;
                        ctx.perf.phase_ack_latency_ms(end+1) = ack_ms;
                        if ~isnan(transport_ms)
                            ctx.perf.phase_ack_transport_ms(end+1) = transport_ms;
                            ctx.recorder = recorder_event(ctx.recorder, ...
                                'source', 'system', 'kind', 'latency', ...
                                'key',    'phase_ack_transport_ms', 'value', transport_ms, ...
                                'abs_ts', evt_recv_ts, ...
                                'info',   sprintf('phase=%s trial=%d ack_seq=%d unity_phase=%s', ...
                                    ctx.perf.last_phase_label, ctx.perf.last_phase_trial_idx, evt_seq, evt_info));
                        end
                        ctx.recorder = recorder_event(ctx.recorder, ...
                            'source', 'system', 'kind', 'latency', ...
                            'key',    'phase_ack_latency_ms', 'value', ack_ms, ...
                            'abs_ts', evt_recv_ts, ...
                            'info',   sprintf('phase=%s trial=%d send_seq=%d ack_seq=%d unity_phase=%s', ...
                                ctx.perf.last_phase_label, ctx.perf.last_phase_trial_idx, ...
                                ctx.perf.last_phase_send_seq, evt_seq, evt_info));
                    end

                    if evt == "session_stop_ack" && ~isnan(ctx.perf.last_session_stop_send_abs_ts)
                        ack_ms = (evt_recv_ts - ctx.perf.last_session_stop_send_abs_ts) * 1000;
                        ctx.perf.session_stop_ack_latency_ms(end+1) = ack_ms;
                        if ~isnan(transport_ms)
                            ctx.perf.session_stop_ack_transport_ms(end+1) = transport_ms;
                            ctx.recorder = recorder_event(ctx.recorder, ...
                                'source', 'system', 'kind', 'latency', ...
                                'key',    'session_stop_ack_transport_ms', 'value', transport_ms, ...
                                'abs_ts', evt_recv_ts, ...
                                'info',   sprintf('ack_seq=%d reason=%s', evt_seq, evt_info));
                        end
                        ctx.recorder = recorder_event(ctx.recorder, ...
                            'source', 'system', 'kind', 'latency', ...
                            'key',    'session_stop_ack_latency_ms', 'value', ack_ms, ...
                            'abs_ts', evt_recv_ts, ...
                            'info',   sprintf('send_seq=%d ack_seq=%d reason=%s', ...
                                ctx.perf.last_session_stop_send_seq, evt_seq, evt_info));
                    end

                    % --- 阈值调整事件: 解码 payload 写入历史 ---
                    if evt == "threshold_adjusted" || evt == "threshold_hold"
                        if evt == "threshold_adjusted"
                            % payload: 整数=方向 (1=raise,2=lower,0=hold), 小数=新阈值
                            dirCode = floor(evt_val);
                            newT = evt_val - dirCode;
                            if dirCode == 1, dir_str = 'raise';
                            elseif dirCode == 2, dir_str = 'lower';
                            else, dir_str = 'hold'; newT = evt_val;
                            end
                            hist = nft_shared('threshold_history');
                            if size(hist,1) > 0
                                oldT = hist(end, 3);
                            else
                                oldT = 0.65;
                            end
                            hr = -1;   % 抬/降时不直接知道命中率
                        else
                            % threshold_hold: payload 直接是命中率, 阈值不变
                            hist = nft_shared('threshold_history');
                            if size(hist,1) > 0
                                oldT = hist(end, 3);
                            else
                                oldT = 0.65;
                            end
                            newT = oldT;
                            dir_str = 'hold';
                            hr = evt_val;
                        end
                        if ~isfield(ctx, 'last_trial_idx'), ctx.last_trial_idx = 0; end
                        nft_shared('threshold_event', ctx.last_trial_idx, oldT, newT, hr, dir_str);
                    end

                    if evt == "session_end"
                        fprintf('[Session] Unity reported session_end.\n');
                        ctx.phase = 'finished';
                    end
                end
                ctx.last_marker_count = ctx.mk.count;
            end

            % --- 控制台周期报告 ---
            if toc(ctx.t0) >= ctx.next_report
                fprintf('[Monitor] t=%5.1fs  scheme=%s  sent=%d  markers=%d\n', ...
                    toc(ctx.t0), ctx.scheme.name, ctx.seq, ctx.mk.count);
                ctx.next_report = ctx.next_report + 5;
            end
            return;
    end
catch err
    fprintf('[Session] Step error: %s\n', err.message);
    ctx.error = err.message;
    ctx.phase = 'finished';
end
end


function ctx = paradigm_enter_phase(ctx, trial_idx, phase_label)
% 进入新 phase: 更新 ctx.paradigm, 下发 TCP phase 消息, 记录 recorder 事件
ctx.paradigm.trial_idx = trial_idx;
ctx.paradigm.current_phase = phase_label;
ctx.paradigm.phase_t0 = tic;

if strcmp(phase_label, 'A')
    phase_code = 0;
    duration_sec = ctx.paradigm.phase_a_dur;
    instruction = '';
    if isfield(ctx.scheme, 'instruction_a'), instruction = ctx.scheme.instruction_a; end
else
    phase_code = 1;
    duration_sec = ctx.paradigm.phase_b_dur;
    instruction = '';
    if isfield(ctx.scheme, 'instruction_b'), instruction = ctx.scheme.instruction_b; end
end

% 下发 phase 边界消息 (info 格式: trial|duration|instruction)
encoded_instruction = encode_instruction_for_tcp(instruction);
info = sprintf('%d|%g|%s', trial_idx, duration_sec, encoded_instruction);
try
    send_abs_ts = posixtime(datetime('now', 'TimeZone', 'local'));
    ctx.perf.last_phase_send_abs_ts = send_abs_ts;
    ctx.perf.last_phase_send_seq = ctx.seq;
    ctx.perf.last_phase_label = phase_label;
    ctx.perf.last_phase_trial_idx = trial_idx;
    tcp_send_message(ctx.server, ctx.seq, 'phase', phase_code, ctx.scheme.name, info);
    ctx.seq = ctx.seq + 1;
catch err
    fprintf('[Paradigm] Failed to send phase message: %s\n', err.message);
end

% recorder 事件
ctx.recorder = recorder_event(ctx.recorder, ...
    'source', 'matlab', 'kind', 'phase', ...
    'key',    sprintf('phase_%s_start', lower(phase_label)), ...
    'value',  trial_idx, ...
    'abs_ts', ctx.perf.last_phase_send_abs_ts, ...
    'info',   sprintf('dur=%gs | send_seq=%d', duration_sec, ctx.perf.last_phase_send_seq));

if strcmp(phase_label, 'A')
    ctx.recorder = recorder_event(ctx.recorder, ...
        'source', 'matlab', 'kind', 'trial', ...
        'key',    'trial_start', 'value', trial_idx, 'info', '');
end

% session_log 文本日志
try
    session_log_write(ctx.slog, 'Phase', sprintf('trial=%d phase=%s dur=%gs', ...
        trial_idx, phase_label, duration_sec));
catch
end

fprintf('[Paradigm] Trial %d Phase %s (%gs) instr="%s"\n', ...
    trial_idx, phase_label, duration_sec, instruction);
end


function encoded = encode_instruction_for_tcp(instruction)
% 将 phase instruction 约束到纯 ASCII 负载，彻底绕开 MATLAB/Windows/TCP
% 链路上的中文编码歧义。Unity 端收到后再解码回 UTF-8 文本。
if nargin < 1 || isempty(instruction)
    encoded = '';
    return;
end

utf8_bytes = unicode2native(char(instruction), 'UTF-8');
hex_pairs = upper(reshape(dec2hex(uint8(utf8_bytes), 2).', 1, []));
encoded = ['HEX:' hex_pairs];
end


function ctx = paradigm_end_phase(ctx)
% 结束当前 phase: 记录 recorder 事件
if isempty(ctx.paradigm.current_phase), return; end
phase_label = ctx.paradigm.current_phase;
trial_idx = ctx.paradigm.trial_idx;

ctx.recorder = recorder_event(ctx.recorder, ...
    'source', 'matlab', 'kind', 'phase', ...
    'key',    sprintf('phase_%s_end', lower(phase_label)), ...
    'value',  trial_idx, 'info', '');

if strcmp(phase_label, 'B')
    ctx.recorder = recorder_event(ctx.recorder, ...
        'source', 'matlab', 'kind', 'trial', ...
        'key',    'trial_end', 'value', trial_idx, 'info', '');
end
end
