function nft_session_finalize(ctx)
% 收尾一个 session: 写摘要, 关闭日志, 释放资源
% 由 GUI 在 phase=finished 时调用一次

if isempty(ctx) || ~isfield(ctx, 'phase')
    return;
end

% --- 先告诉 Unity 停止小游戏 (在关掉 server 之前) ---
% ISSUES 3: Unity 不再自计时, 起止由 MATLAB 驱动. session_stop 让 Unity 立即
% 卸载当前游戏场景, 回到 MainMenu 待机.
try
    if isfield(ctx, 'server') && ~isempty(ctx.server) ...
            && isfield(ctx, 'scheme') && isfield(ctx.scheme, 'name')
        ctx.seq = ctx.seq + 1;
        ctx.perf.last_session_stop_send_abs_ts = posixtime(datetime('now', 'TimeZone', 'local'));
        ctx.perf.last_session_stop_send_seq = ctx.seq;
        tcp_send_message(ctx.server, ctx.seq, 'session_stop', 0, ...
            ctx.scheme.name, 'finalize');
        fprintf('[Session] Sent session_stop to Unity.\n');
        pause(0.15);
        ctx.mk = marker_poll(ctx.server, ctx.mk);
        [ctx, ack_captured] = capture_session_stop_ack(ctx);
        if ack_captured
            fprintf('[Session] Received session_stop_ack.\n');
        end
    end
catch err
    fprintf('[Session] Failed to send session_stop: %s\n', err.message);
end

try
    if ~isempty(ctx.t0)
        session_time = toc(ctx.t0);
    else
        session_time = 0;
    end

    % 收尾最后一个未关闭的 phase (session 自然结束或 Stop 中断)
    if isfield(ctx, 'paradigm') && isfield(ctx.paradigm, 'current_phase') ...
            && ~isempty(ctx.paradigm.current_phase) && isfield(ctx, 'recorder')
        try
            ctx.recorder = recorder_event(ctx.recorder, ...
                'source', 'matlab', 'kind', 'phase', ...
                'key',    sprintf('phase_%s_end', lower(ctx.paradigm.current_phase)), ...
                'value',  ctx.paradigm.trial_idx, 'info', 'session_finalize');
            if strcmp(ctx.paradigm.current_phase, 'B')
                ctx.recorder = recorder_event(ctx.recorder, ...
                    'source', 'matlab', 'kind', 'trial', ...
                    'key',    'trial_end', 'value', ctx.paradigm.trial_idx, ...
                    'info',   'session_finalize');
            end
        catch
        end
    end

    fprintf('[Session] Complete: sent=%d, markers=%d, duration=%.1f s.\n', ...
        ctx.seq, ctx.mk.count, session_time);
    session_log_write(ctx.slog, 'Summary', sprintf('session=%.1fs sent=%d markers=%d', ...
        session_time, ctx.seq, ctx.mk.count));

    for k = 1:length(ctx.scheme.feedback_types)
        ft = ctx.scheme.feedback_types{k};
        if ctx.value_count.(ft) > 0
            avg_value = ctx.value_sum.(ft) / ctx.value_count.(ft);
        else
            avg_value = 0;
        end
        open_ratio = ctx.window_open_total.(ft) / max(session_time, eps);
        fprintf('[Summary] %-20s avg=%.3f open_count=%d ratio=%.2f max_open=%.1fs\n', ...
            ft, avg_value, ctx.window_open_count.(ft), open_ratio, ctx.window_open_max.(ft));
        session_log_write(ctx.slog, 'Summary', sprintf('%s avg=%.3f open_count=%d ratio=%.2f max_open=%.1fs', ...
            ft, avg_value, ctx.window_open_count.(ft), open_ratio, ctx.window_open_max.(ft)));
    end

    if isfield(ctx, 'perf')
        log_perf_summary(ctx.slog, 'phase_ack_latency_ms', ctx.perf.phase_ack_latency_ms);
        log_perf_summary(ctx.slog, 'session_stop_ack_latency_ms', ctx.perf.session_stop_ack_latency_ms);
        log_perf_summary(ctx.slog, 'phase_ack_transport_ms', ctx.perf.phase_ack_transport_ms);
        log_perf_summary(ctx.slog, 'session_stop_ack_transport_ms', ctx.perf.session_stop_ack_transport_ms);
        log_perf_summary(ctx.slog, 'tcp_connected_transport_ms', ctx.perf.tcp_connected_transport_ms);
        log_perf_summary(ctx.slog, 'unity_sync_transport_ms', ctx.perf.unity_sync_transport_ms);
        log_perf_summary(ctx.slog, 'unity_marker_transport_ms', ctx.perf.unity_marker_transport_ms);
    end

    if isfield(ctx, 'behavior_counts')
        bc = ctx.behavior_counts;
        fprintf('[Behavior] enemy_spawn=%d hit=%d missed=%d shot_fired=%d coin_collected=%d window_open=%d\n', ...
            bc.enemy_spawn, bc.enemy_hit, bc.enemy_missed, bc.shot_fired, ...
            bc.coin_collected, bc.action_window_open);
        session_log_write(ctx.slog, 'Behavior', sprintf('enemy_spawn=%d hit=%d coin=%d window_open=%d', ...
            bc.enemy_spawn, bc.enemy_hit, bc.coin_collected, bc.action_window_open));
    end
catch err
    fprintf('[Session] Finalization error: %s\n', err.message);
end

% 清理资源
try
    nft_shared('set_active', false);
catch
end
try
    marker_close(ctx.mk);
catch
end
try
    session_log_close(ctx.slog);
catch
end
try
    clear ctx.server;
catch
end
try
    eeg_close(ctx.eeg_handle);
catch
end

% 关闭 recorder, 拷贝旧日志到 session 文件夹, 自动触发报告
session_dir = '';
try
    if isfield(ctx, 'recorder') && ~isempty(ctx.recorder)
        session_dir = ctx.recorder.session_dir;
        recorder_close(ctx.recorder);
    end
catch err
    fprintf('[Session] recorder_close error: %s\n', err.message);
end

if ~isempty(session_dir) && exist(session_dir, 'dir')
    try
        if isfield(ctx, 'mk') && isfield(ctx.mk, 'path') && exist(ctx.mk.path, 'file')
            copyfile(ctx.mk.path, fullfile(session_dir, 'markers.csv'));
        end
        if isfield(ctx, 'slog') && isfield(ctx.slog, 'path') && exist(ctx.slog.path, 'file')
            copyfile(ctx.slog.path, fullfile(session_dir, 'session.log'));
        end
        if isfield(ctx, 'perf')
            perf_summary_path = fullfile(session_dir, 'performance_summary.csv');
            write_perf_summary_csv(perf_summary_path, ctx.perf);
        end
    catch err
        fprintf('[Session] Failed to copy legacy log into the session directory: %s\n', err.message);
    end

    if isfield(ctx, 'auto_report') && ctx.auto_report
        try
            generate_report(session_dir);
        catch err
            fprintf('[Session] Automatic report generation failed: %s\n', err.message);
        end
    end
end
end

function log_perf_summary(slog, metric_name, values)
if isempty(values)
    return;
end
try
    session_log_write(slog, 'Performance', sprintf('%s N=%d mean=%.3f std=%.3f min=%.3f median=%.3f max=%.3f', ...
        metric_name, numel(values), mean(values), std(values), min(values), median(values), max(values)));
catch
end
end

function write_perf_summary_csv(path, perf)
fid = fopen(path, 'w');
if fid == -1
    return;
end
fprintf(fid, 'metric,N,mean,std,min,median,max\n');
write_one(fid, 'phase_ack_latency_ms', perf.phase_ack_latency_ms);
write_one(fid, 'session_stop_ack_latency_ms', perf.session_stop_ack_latency_ms);
write_one(fid, 'phase_ack_transport_ms', perf.phase_ack_transport_ms);
write_one(fid, 'session_stop_ack_transport_ms', perf.session_stop_ack_transport_ms);
write_one(fid, 'tcp_connected_transport_ms', perf.tcp_connected_transport_ms);
write_one(fid, 'unity_sync_transport_ms', perf.unity_sync_transport_ms);
write_one(fid, 'unity_marker_transport_ms', perf.unity_marker_transport_ms);
fclose(fid);
end

function write_one(fid, metric_name, values)
if isempty(values)
    fprintf(fid, '%s,0,,,,,\n', metric_name);
    return;
end
fprintf(fid, '%s,%d,%.4f,%.4f,%.4f,%.4f,%.4f\n', ...
    metric_name, numel(values), mean(values), std(values), min(values), median(values), max(values));
end

function [ctx, ack_captured] = capture_session_stop_ack(ctx)
ack_captured = false;
if isempty(ctx) || ~isfield(ctx, 'mk') || isempty(ctx.mk) || ~isfield(ctx, 'perf')
    return;
end
for i = 1:length(ctx.mk.new_events)
    evt = string(ctx.mk.new_events(i));
    if evt ~= "session_stop_ack"
        continue;
    end
    evt_recv_ts = ctx.mk.new_recv_ts(i);
    evt_unity_ts = ctx.mk.new_unity_ts(i);
    evt_seq = ctx.mk.new_seqs(i);
    evt_info = char(ctx.mk.new_infos(i));
    ack_ms = (evt_recv_ts - ctx.perf.last_session_stop_send_abs_ts) * 1000;
    ctx.perf.session_stop_ack_latency_ms(end+1) = ack_ms;
    transport_ms = NaN;
    if evt_unity_ts > 0 && evt_recv_ts > 0
        transport_ms = (evt_recv_ts - evt_unity_ts) * 1000;
        ctx.perf.session_stop_ack_transport_ms(end+1) = transport_ms;
        ctx.perf.unity_sync_transport_ms(end+1) = transport_ms;
        ctx.perf.unity_marker_transport_ms(end+1) = transport_ms;
    end
    ctx.recorder = recorder_event(ctx.recorder, ...
        'source', 'unity', 'kind', 'sync', ...
        'key',    'session_stop_ack', 'value', 0, ...
        'abs_ts', evt_recv_ts, ...
        'info',   sprintf('unity_ts=%.6f | recv_ts=%.6f | seq=%d | info=%s', ...
            evt_unity_ts, evt_recv_ts, evt_seq, evt_info));
    if ~isnan(transport_ms)
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
    try
        session_log_write(ctx.slog, 'Event', sprintf('session_stop_ack recv_ts=%.6f latency_ms=%.3f info=%s', ...
            evt_recv_ts, ack_ms, evt_info));
    catch
    end
    ack_captured = true;
end
end
