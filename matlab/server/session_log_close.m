function session_log_close(log)
% 关闭 session 文本日志

if isempty(log) || ~isfield(log, 'fid') || log.fid == -1
    return;
end

try
    fprintf(log.fid, '# end_ts=%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fclose(log.fid);
    fprintf('[SessionLog] Closed: %s\n', log.path);
catch err
    fprintf('[SessionLog] Close error: %s\n', err.message);
end
end
