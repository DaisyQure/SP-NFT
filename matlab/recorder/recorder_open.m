function rec = recorder_open(scheme_name, subject_meta, cfg)
% 打开一个 session 记录器:创建 logs/sessions/<stamp>_<scheme>_<subject>/ 目录,
% 打开 timeseries_rec.csv / events_log.csv 两个 fid, 写 meta.json 雏形。
%
% 输入:
%   scheme_name  : 'attention' / 'simulation' / 'relax' / 'monitor'
%   subject_meta : struct, 字段 id name sex age handedness note (除 id 外可空)
%   cfg          : config() 返回值, 用于把配置快照写进 meta.json
%
% 返回 rec:
%   .session_dir       : 该 session 的根目录
%   .ts_path / .ts_fid : timeseries_rec.csv 的路径与文件句柄
%   .ev_path / .ev_fid : events_log.csv 的路径与文件句柄
%   .meta_path         : meta.json 的路径
%   .start_abs_ts      : 起始绝对时间(POSIX 秒), 后续算 t_session_sec 用
%   .ts_columns        : 已经写表头的列名(cell array of char), 含两个公共列在前
%   .ts_row_count      : 已写入的时序行数
%   .ev_row_count      : 已写入的事件行数

if nargin < 2 || isempty(subject_meta), subject_meta = default_subject(); end
if nargin < 3 || isempty(cfg), cfg = config(); end

if ~isfield(subject_meta, 'id') || isempty(subject_meta.id)
    subject_meta.id = 'anon';
end
subject_meta = fill_default_subject(subject_meta);

stamp = datestr(now, 'yyyymmdd_HHMMSS');
safe_id = sanitize_filename(subject_meta.id);
folder_name = sprintf('%s_%s_%s', stamp, scheme_name, safe_id);

base_dir = fullfile('logs', 'sessions');
if ~exist(base_dir, 'dir'), mkdir(base_dir); end
session_dir = fullfile(base_dir, folder_name);
if ~exist(session_dir, 'dir'), mkdir(session_dir); end

rec.session_dir   = session_dir;
rec.scheme_name   = scheme_name;
rec.subject       = subject_meta;
rec.start_abs_ts  = posixtime(datetime('now', 'TimeZone', 'local'));
rec.start_wallclock = datestr(now, 'yyyy-mm-dd HH:MM:SS');

% --- timeseries_rec.csv ---
rec.ts_path = fullfile(session_dir, 'timeseries_rec.csv');
rec.ts_fid  = fopen(rec.ts_path, 'w');
if rec.ts_fid == -1
    error('[Recorder] Cannot create %s.', rec.ts_path);
end
% 表头延后, 等第一帧 push 时再写(那时才知道有哪些 _rec 字段)
rec.ts_columns   = {};   % 初始空, 第一次 push 时填充
rec.ts_row_count = 0;

% --- events_log.csv ---
rec.ev_path = fullfile(session_dir, 'events_log.csv');
rec.ev_fid  = fopen(rec.ev_path, 'w');
if rec.ev_fid == -1
    error('[Recorder] Cannot create %s.', rec.ev_path);
end
fprintf(rec.ev_fid, 't_session_sec,abs_ts,source,kind,key,value,info\n');
rec.ev_row_count = 0;

% --- meta.json (雏形, close 时再补 end_ts/计数) ---
rec.meta_path = fullfile(session_dir, 'meta.json');
meta = struct();
meta.scheme        = scheme_name;
meta.subject       = subject_meta;
meta.start_ts      = rec.start_wallclock;
meta.start_abs_ts  = rec.start_abs_ts;
meta.config_snapshot = cfg;
meta.recording_convention = '_rec=time series, _log=event; see docs/RECORDING_CONVENTION.md';
write_json(rec.meta_path, meta);

% --- 把被试信息作为一条 _log 写进 events ---
rec = recorder_event(rec, 'source', 'system', 'kind', 'subject', ...
    'key', 'enrolled', 'value', 0, ...
    'info', sprintf('id=%s name=%s sex=%s age=%s handedness=%s note=%s', ...
        subject_meta.id, subject_meta.name, subject_meta.sex, ...
        num2str(subject_meta.age), subject_meta.handedness, subject_meta.note));

fprintf('[Recorder] Opened session: %s\n', session_dir);
end


function s = default_subject()
s = struct('id','anon','name','','sex','','age',0,'handedness','','note','');
end


function s = fill_default_subject(s)
defaults = default_subject();
fns = fieldnames(defaults);
for i = 1:length(fns)
    if ~isfield(s, fns{i}) || isempty(s.(fns{i}))
        s.(fns{i}) = defaults.(fns{i});
    end
end
end


function name = sanitize_filename(s)
if isempty(s), name = 'anon'; return; end
name = regexprep(char(s), '[^a-zA-Z0-9_-]', '_');
if isempty(name), name = 'anon'; end
end


function write_json(path, obj)
fid = fopen(path, 'w');
if fid == -1, return; end
try
    fprintf(fid, '%s', jsonencode(obj, 'PrettyPrint', true));
catch
    fprintf(fid, '%s', jsonencode(obj));
end
fclose(fid);
end
