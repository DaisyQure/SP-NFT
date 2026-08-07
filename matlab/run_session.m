function run_session(scheme_name, duration_sec)
% 跑一次训练 session
%
% 用法：
%   run_session('simulation', 90);
%   run_session('attention', 90);
%   run_session('relax', 90);
%   run_session('monitor', 90);
%
% 如果 duration_sec 不传，MATLAB 会在 Unity 发来 session_start marker 后
% 自动采纳 marker.value 作为 session 时长（让 Unity 决定 session 长度）。

if nargin < 1, scheme_name = 'attention'; end
if nargin < 2
    duration_sec = -1;   % -1 表示等待 Unity 通知
    auto_duration = true;
else
    auto_duration = false;
end

addpath('eeg', 'features', 'schemes', 'server', 'utils');
cfg = config();

scheme = feval(['scheme_' scheme_name]);
fprintf('[Session] Mode: %s (%s)\n', scheme.name, scheme.description);

eeg_handle = eeg_init(cfg);

server = tcpserver("0.0.0.0", cfg.server.port);
configureTerminator(server, "LF");
fprintf('[Server] Listening on port %d; waiting for Unity...\n', cfg.server.port);
while ~server.Connected
    pause(0.1);
end
fprintf('[Server] Connected: %s:%d\n', server.ClientAddress, server.ClientPort);

mk = marker_open(scheme.name);
slog = session_log_open(scheme.name);
nft_shared('reset');
nft_shared('set_active', true);
if auto_duration
    session_log_write(slog, 'Session', sprintf('scheme=%s duration=AUTO server=%s:%d', ...
        scheme.name, server.ClientAddress, server.ClientPort));
else
    session_log_write(slog, 'Session', sprintf('scheme=%s duration=%ds server=%s:%d', ...
        scheme.name, duration_sec, server.ClientAddress, server.ClientPort));
end

last_marker_count = 0;
window_open_since = struct();
window_open_count = struct();
window_open_total = struct();
window_open_max = struct();
value_sum = struct();
value_count = struct();
for k = 1:length(scheme.feedback_types)
    fb_type = scheme.feedback_types{k};
    window_open_since.(fb_type) = NaN;
    window_open_count.(fb_type) = 0;
    window_open_total.(fb_type) = 0;
    window_open_max.(fb_type) = 0;
    value_sum.(fb_type) = 0;
    value_count.(fb_type) = 0;
end

% 行为事件计数（用于 session 摘要）
behavior_counts = struct( ...
    'enemy_spawn',      0, ...
    'enemy_hit',        0, ...
    'enemy_missed',     0, ...
    'enemy_hit_player', 0, ...
    'shot_fired',       0, ...
    'coin_spawn',       0, ...
    'coin_collected',   0, ...
    'action_window_open',  0, ...
    'action_window_close', 0);

try
    baseline = measure_baseline(eeg_handle, scheme, cfg);
    session_log_write(slog, 'Baseline', sprintf('Acquired a %d s baseline', cfg.baseline.duration_sec));

    at = at_init(scheme.feedback_types, cfg);
    if at.enable
        fprintf('[Adaptive] Enabled: window=%d s, target percentile=%.0f%%.\n', ...
            cfg.adaptive.window_sec, cfg.adaptive.target_pct*100);
        session_log_write(slog, 'Adaptive', sprintf('Enabled: window=%d s, target_pct=%.2f', ...
            cfg.adaptive.window_sec, cfg.adaptive.target_pct));
    else
        fprintf('[Adaptive] Disabled (control mode: direct fixed-baseline output).\n');
        session_log_write(slog, 'Adaptive', 'Disabled (direct-output mode)');
    end

    fprintf('[Monitor] MATLAB monitoring is enabled.\n');
    fprintf('[Monitor] Fields: t | type | raw | pct | value | trend | window | open_for | sent | markers\n');

    if auto_duration
        fprintf('[Session] Waiting for Unity session_start to set the duration (600 s fallback).\n');
        duration_sec = 600;
    else
        fprintf('[Session] Starting feedback training for %d s.\n', duration_sec);
    end
    seq = 0;
    period = 1 / cfg.feedback.update_hz;
    t0 = tic;
    next_report = 2;
    duration_adopted = ~auto_duration;
    session_ended_by_unity = false;

    while toc(t0) < duration_sec
        if ~server.Connected
            fprintf('[Session] Unity disconnected.\n');
            session_log_write(slog, 'Session', 'Unity disconnected');
            break;
        end

        eeg = eeg_get_window(eeg_handle, cfg.feedback.window_sec);
        powers = extract_band_power(eeg, eeg_handle.fs, ...
            cfg.eeg.montage, scheme.channels, scheme.bands);
        vals = scheme.score_fn(powers, baseline);

        cycle_lines = strings(1, length(scheme.feedback_types));

        for k = 1:length(scheme.feedback_types)
            fb_type = scheme.feedback_types{k};
            raw = vals.(fb_type);
            [at, value, success] = at_update(at, fb_type, raw);

            tcp_send_message(server, seq, fb_type, value, scheme.name);
            seq = seq + 1;

            value_sum.(fb_type) = value_sum.(fb_type) + value;
            value_count.(fb_type) = value_count.(fb_type) + 1;

            pct = at.last_pct.(fb_type);
            trend = at.trend.(fb_type);
            if success
                if isnan(window_open_since.(fb_type))
                    window_open_since.(fb_type) = toc(t0);
                    window_open_count.(fb_type) = window_open_count.(fb_type) + 1;
                    session_log_write(slog, 'Window', sprintf('%s opened at t=%.2f s, value=%.3f', ...
                        fb_type, toc(t0), value));
                end
                window_state = 'OPEN';
                open_for = toc(t0) - window_open_since.(fb_type);
                window_open_total.(fb_type) = window_open_total.(fb_type) + period;
                if open_for > window_open_max.(fb_type)
                    window_open_max.(fb_type) = open_for;
                end
            else
                if ~isnan(window_open_since.(fb_type))
                    session_log_write(slog, 'Window', sprintf('%s closed at t=%.2f s after %.2f s', ...
                        fb_type, toc(t0), toc(t0) - window_open_since.(fb_type)));
                end
                window_open_since.(fb_type) = NaN;
                window_state = 'CLOSED';
                open_for = 0;
            end

            cycle_lines(k) = sprintf('  %-14s raw=%7.3f  pct=%5.2f  value=%5.2f  trend=%-7s  window=%-6s  open=%4.1fs  sent=%4d  markers=%3d', ...
                fb_type, raw, pct, value, trend, window_state, open_for, seq, mk.count);
        end

        % --- 把当前帧塞进共享 buffer，让 GUI 实时看到 ---
        push_data = struct();
        push_data.t = toc(t0);
        push_data.scheme = scheme.name;
        push_data.sent = seq;
        push_data.markers_count = mk.count;
        if isfield(at.ema, 'attention')
            push_data.attention = at.ema.attention;
        end
        if isfield(at.ema, 'relaxation')
            push_data.relaxation = at.ema.relaxation;
        end
        if isfield(at.ema, 'simulation_intensity')
            push_data.simulation_intensity = at.ema.simulation_intensity;
        end
        % 派生指标 (用于 GUI 6 维显示)
        if isfield(push_data, 'attention')
            push_data.fatigue = max(0, min(1, 1 - push_data.attention));
        end
        if isfield(push_data, 'relaxation')
            push_data.stress = max(0, min(1, 1 - push_data.relaxation));
        end
        if isfield(push_data, 'attention') && isfield(push_data, 'relaxation')
            push_data.emotion = (push_data.attention + push_data.relaxation) / 2;
        end
        if isfield(push_data, 'simulation_intensity')
            push_data.workload = push_data.simulation_intensity;
        end
        % 频段功率 (供波形图显示)
        if isfield(powers, 'theta'), push_data.theta = powers.theta; end
        if isfield(powers, 'alpha'), push_data.alpha = powers.alpha; end
        if isfield(powers, 'smr'),   push_data.smr   = powers.smr;   end
        if isfield(powers, 'beta1'), push_data.beta  = powers.beta1; end
        if isfield(powers, 'beta'),  push_data.beta  = powers.beta;  end
        % 动作窗口状态 (用主反馈类型的状态作为代表)
        primary_fb = scheme.feedback_types{1};
        push_data.window_open = at.window_open.(primary_fb);
        nft_shared('push', push_data);

        mk = marker_poll(server, mk);
        if mk.count > last_marker_count
            fprintf('[Monitor] Received %d new markers (%d total).\n', ...
                mk.count - last_marker_count, mk.count);
            for i = 1:length(mk.new_events)
                evt = mk.new_events(i);
                evt_char = char(evt);
                if isfield(behavior_counts, evt_char)
                    behavior_counts.(evt_char) = behavior_counts.(evt_char) + 1;
                end

                if evt == "session_start" && ~duration_adopted && mk.last_value > 0
                    duration_sec = mk.last_value;
                    duration_adopted = true;
                    fprintf('[Session] Adopted the Unity session duration: %.1f s.\n', duration_sec);
                    session_log_write(slog, 'Session', sprintf('Adopted Unity duration=%.1f s', duration_sec));
                end

                if evt == "session_end"
                    session_ended_by_unity = true;
                    fprintf('[Session] Unity reported session_end; finalizing.\n');
                end

                if any(evt == ["session_start","session_end","action_window_open","action_window_close", ...
                               "menu_return","game_over","tcp_connected","tcp_disconnected","monitor_ready", ...
                               "enemy_spawn","enemy_hit","enemy_missed","enemy_hit_player","shot_fired", ...
                               "coin_spawn","coin_collected"])
                    fprintf('[Event] %-20s scene=%-14s value=%.3f info=%s\n', ...
                        evt, mk.last_scene, mk.last_value, mk.last_info);
                    session_log_write(slog, 'Event', sprintf('%s scene=%s value=%.3f info=%s', ...
                        evt, mk.last_scene, mk.last_value, mk.last_info));
                    nft_shared('add_marker', char(evt), char(mk.last_scene), mk.last_value);
                end
            end
            last_marker_count = mk.count;
        end

        if session_ended_by_unity
            break;
        end

        if toc(t0) >= next_report
            fprintf('[Monitor] t=%5.1fs  scheme=%s  unity=%s  markers=%d\n', ...
                toc(t0), scheme.name, string(server.Connected), mk.count);
            for k = 1:length(cycle_lines)
                fprintf('%s\n', cycle_lines(k));
            end
            next_report = next_report + 2;
        end

        pause(period);
    end

    fprintf('[Session] Complete: sent %d feedback messages and received %d markers.\n', ...
        seq, mk.count);
    fprintf('[Summary] session=%.1fs  sent=%d  markers=%d\n', toc(t0), seq, mk.count);
    session_log_write(slog, 'Summary', sprintf('session=%.1fs sent=%d markers=%d', toc(t0), seq, mk.count));
    for k = 1:length(scheme.feedback_types)
        fb_type = scheme.feedback_types{k};
        avg_value = value_sum.(fb_type) / max(1, value_count.(fb_type));
        open_ratio = window_open_total.(fb_type) / max(toc(t0), eps);
        fprintf('[Summary] %-14s avg_value=%.3f  open_count=%d  open_ratio=%.2f  max_open=%.1fs\n', ...
            fb_type, avg_value, window_open_count.(fb_type), open_ratio, window_open_max.(fb_type));
        session_log_write(slog, 'Summary', sprintf('%s avg_value=%.3f open_count=%d open_ratio=%.2f max_open=%.1fs', ...
            fb_type, avg_value, window_open_count.(fb_type), open_ratio, window_open_max.(fb_type)));
    end

    % 行为事件摘要
    fprintf('[Behavior] enemy_spawn=%d  enemy_hit=%d  enemy_missed=%d  enemy_hit_player=%d  shot_fired=%d\n', ...
        behavior_counts.enemy_spawn, behavior_counts.enemy_hit, ...
        behavior_counts.enemy_missed, behavior_counts.enemy_hit_player, ...
        behavior_counts.shot_fired);
    fprintf('[Behavior] coin_spawn=%d  coin_collected=%d\n', ...
        behavior_counts.coin_spawn, behavior_counts.coin_collected);
    fprintf('[Behavior] action_window open=%d  close=%d\n', ...
        behavior_counts.action_window_open, behavior_counts.action_window_close);

    if behavior_counts.shot_fired > 0
        hit_rate = behavior_counts.enemy_hit / behavior_counts.shot_fired;
        fprintf('[Behavior] shot_hit_rate=%.2f\n', hit_rate);
        session_log_write(slog, 'Behavior', sprintf('shot_hit_rate=%.2f', hit_rate));
    end
    if behavior_counts.enemy_spawn > 0
        kill_rate = behavior_counts.enemy_hit / behavior_counts.enemy_spawn;
        fprintf('[Behavior] enemy_kill_rate=%.2f\n', kill_rate);
        session_log_write(slog, 'Behavior', sprintf('enemy_kill_rate=%.2f', kill_rate));
    end
    if behavior_counts.coin_spawn > 0
        pickup_rate = behavior_counts.coin_collected / behavior_counts.coin_spawn;
        fprintf('[Behavior] coin_pickup_rate=%.2f\n', pickup_rate);
        session_log_write(slog, 'Behavior', sprintf('coin_pickup_rate=%.2f', pickup_rate));
    end

    session_log_write(slog, 'Behavior', sprintf('enemy_spawn=%d enemy_hit=%d enemy_missed=%d enemy_hit_player=%d shot_fired=%d coin_spawn=%d coin_collected=%d window_open=%d window_close=%d', ...
        behavior_counts.enemy_spawn, behavior_counts.enemy_hit, ...
        behavior_counts.enemy_missed, behavior_counts.enemy_hit_player, ...
        behavior_counts.shot_fired, behavior_counts.coin_spawn, ...
        behavior_counts.coin_collected, behavior_counts.action_window_open, ...
        behavior_counts.action_window_close));

catch err
    fprintf('[Session] Error: %s\n', err.message);
    fprintf('%s\n', getReport(err));
    session_log_write(slog, 'Error', err.message);
end

try
    mk = marker_poll(server, mk);
catch
end
nft_shared('set_active', false);
marker_close(mk);
session_log_close(slog);
clear server;
eeg_close(eeg_handle);

end
