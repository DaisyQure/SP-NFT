function log = session_log_open(scheme_name)
% 打开一个 session 文本日志，记录 MATLAB 监控端的关键事件与摘要
% 由 run_session 在 session 开始时调用一次

if ~exist('logs', 'dir')
    mkdir('logs');
end

stamp = datestr(now, 'yyyymmdd_HHMMSS');
log.path = fullfile('logs', sprintf('session_%s_%s.log', scheme_name, stamp));
log.fid = fopen(log.path, 'w');
if log.fid == -1
    error('[SessionLog] Cannot create file: %s.', log.path);
end

fprintf(log.fid, '# Session log\n');
fprintf(log.fid, '# scheme=%s\n', scheme_name);
fprintf(log.fid, '# start_ts=%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));

fprintf('[SessionLog] Opened: %s\n', log.path);
end
