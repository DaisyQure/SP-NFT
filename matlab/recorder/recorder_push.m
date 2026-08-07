function rec = recorder_push(rec, push_struct)
% 把一帧数据写入时序记录(timeseries_rec.csv)与事件记录(events_log.csv)。
% 自动按字段名后缀分流:
%   *_rec  -> 时序行(每帧一行)
%   *_log  -> 单事件行(一次写一行,kind/key/value/info 均从 _log 字段名/值推断)
% 不带后缀的字段(t / scheme / sent / markers_count 等)只用作时间戳上下文,
% 不会单独写入(t 字段会被识别为 session 内时间). 详见 docs/RECORDING_CONVENTION.md.
%
% rec : recorder_open 返回的状态
% push_struct : 任意 struct, 字段名按后缀约定

if isempty(rec) || ~isfield(rec, 'ts_fid') || rec.ts_fid == -1
    return;
end

now_abs = posixtime(datetime('now', 'TimeZone', 'local'));
if isfield(push_struct, 't') && isnumeric(push_struct.t)
    t_sess = push_struct.t;
else
    t_sess = now_abs - rec.start_abs_ts;
end

fns = fieldnames(push_struct);

% --- 1. 把 *_rec 字段收集成时序行 ---
rec_fields = {};
rec_values = {};
for i = 1:length(fns)
    fn = fns{i};
    if endsWith(fn, '_rec')
        rec_fields{end+1} = fn; %#ok<AGROW>
        rec_values{end+1} = push_struct.(fn); %#ok<AGROW>
    end
end

if ~isempty(rec_fields)
    % 第一帧:写表头
    if isempty(rec.ts_columns)
        rec.ts_columns = [{'t_session_sec', 'abs_ts'}, rec_fields];
        fprintf(rec.ts_fid, '%s\n', strjoin(rec.ts_columns, ','));
    else
        % 检查是否有新字段: 有就追加列(为旧行写不了空,只能从这一帧起在新位置出现)
        existing = rec.ts_columns(3:end);
        new_fields = setdiff(rec_fields, existing, 'stable');
        if ~isempty(new_fields)
            rec.ts_columns = [rec.ts_columns, new_fields];
            % 注意: CSV 已写出去无法回填表头, 所以这里只更新内存中的 ts_columns
            % 后续 generate_report 是按行读, 缺失列自然为空. 真要稳定列集请在
            % 第一次 push 时一次性带齐所有 _rec 字段.
        end
    end

    % 写值: 按 ts_columns 顺序, 缺失填空
    out_cells = cell(1, length(rec.ts_columns));
    out_cells{1} = sprintf('%.4f', t_sess);
    out_cells{2} = sprintf('%.6f', now_abs);
    for c = 3:length(rec.ts_columns)
        cn = rec.ts_columns{c};
        idx = find(strcmp(rec_fields, cn), 1);
        if isempty(idx)
            out_cells{c} = '';
        else
            out_cells{c} = format_scalar(rec_values{idx});
        end
    end
    fprintf(rec.ts_fid, '%s\n', strjoin(out_cells, ','));
    rec.ts_row_count = rec.ts_row_count + 1;
end

% --- 2. *_log 字段每个独立写一条事件 ---
for i = 1:length(fns)
    fn = fns{i};
    if endsWith(fn, '_log')
        v = push_struct.(fn);
        rec = recorder_event(rec, ...
            'source', 'matlab', ...
            'kind',   'metric', ...
            'key',    fn, ...
            'value',  scalarize(v), ...
            'info',   '', ...
            't_session_sec', t_sess, ...
            'abs_ts',         now_abs);
    end
end
end


function s = format_scalar(v)
if islogical(v)
    s = sprintf('%d', double(v));
elseif isnumeric(v)
    if isscalar(v)
        if isnan(v)
            s = '';
        elseif v == round(v) && abs(v) < 1e9
            s = sprintf('%d', int64(v));
        else
            s = sprintf('%.4f', double(v));
        end
    else
        s = sprintf('%.4f', double(v(1)));   % 退化:数组只取首元素
    end
elseif ischar(v) || isstring(v)
    s = strrep(char(v), ',', ';');
else
    s = '';
end
end


function v = scalarize(x)
if islogical(x), v = double(x); return; end
if isnumeric(x) && isscalar(x), v = double(x); return; end
if isnumeric(x), v = double(x(1)); return; end
v = 0;
end
