function session_log_write(log, tag, line)
% 把一条结构化记录写入 session 日志
% tag : 短标签，例如 'Monitor', 'Event', 'Summary'
% line: 自由文本内容

if isempty(log) || ~isfield(log, 'fid') || log.fid == -1
    return;
end

t = datestr(now, 'HH:MM:SS.FFF');
try
    fprintf(log.fid, '%s [%s] %s\n', t, tag, line);
catch
end
end
