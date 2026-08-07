function rec = recorder_event(rec, varargin)
% 写一条事件到 events_log.csv. 给 marker / 阶段切换 / 阈值 / 试次 / 被试 等
% 所有非时序型记录提供统一入口.
%
% 用法 (name-value):
%   recorder_event(rec, 'source','unity', 'kind','marker', ...
%                       'key','coin_collected', 'value',1, 'info','Game_Attention')
%
% 可选 name-value:
%   source : 'matlab' / 'unity' / 'system'        (default 'matlab')
%   kind   : 'marker' / 'phase' / 'threshold' / 'trial' / 'metric' / 'subject' / ... (default 'misc')
%   key    : 事件名/键名 (必填语义, 不填写 'event')
%   value  : 数值, 默认 0
%   info   : 任意字符串备注, 默认 ''
%   t_session_sec : session 内时间, 默认根据当前时间和 rec.start_abs_ts 算
%   abs_ts        : 绝对 POSIX 秒, 默认当前时间

if isempty(rec) || ~isfield(rec, 'ev_fid') || rec.ev_fid == -1
    return;
end

p = parse_kv(varargin);
src   = field_or(p, 'source', 'matlab');
kind  = field_or(p, 'kind',   'misc');
key   = field_or(p, 'key',    'event');
val   = field_or(p, 'value',  0);
info  = field_or(p, 'info',   '');

now_abs = field_or(p, 'abs_ts', posixtime(datetime('now', 'TimeZone', 'local')));
t_sess  = field_or(p, 't_session_sec', now_abs - rec.start_abs_ts);

fprintf(rec.ev_fid, '%.4f,%.6f,%s,%s,%s,%s,%s\n', ...
    t_sess, now_abs, ...
    csv_escape(src), csv_escape(kind), csv_escape(key), ...
    format_value(val), csv_escape(info));
rec.ev_row_count = rec.ev_row_count + 1;
end


function p = parse_kv(args)
p = struct();
for i = 1:2:length(args)-1
    p.(args{i}) = args{i+1};
end
end


function v = field_or(s, name, default)
if isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = default;
end
end


function s = csv_escape(x)
if isstring(x), x = char(x); end
if isnumeric(x), x = num2str(x); end
if ~ischar(x), x = ''; end
s = strrep(x, ',', ';');
s = strrep(s, newline, ' ');
s = strrep(s, char(13), ' ');
end


function s = format_value(v)
if islogical(v)
    s = sprintf('%d', double(v));
elseif isnumeric(v) && isscalar(v)
    if isnan(v)
        s = '';
    elseif v == round(v) && abs(v) < 1e9
        s = sprintf('%d', int64(v));
    else
        s = sprintf('%.4f', double(v));
    end
elseif ischar(v) || isstring(v)
    s = csv_escape(v);
else
    s = '';
end
end
