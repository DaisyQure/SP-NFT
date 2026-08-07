function out_path = generate_report(session_dir)
% 读一个 session 文件夹里的 timeseries_rec.csv / events_log.csv / meta.json,
% 生成 report/ 下的图表与 HTML 报告. 自动浏览器打开.
%
% 输入:
%   session_dir : (可选)目标 session 文件夹路径.
%                 不传则取 logs/sessions/ 下最新创建的一个.
%
% 输出:
%   out_path    : 生成的 report.html 绝对路径

addpath('recorder');

if nargin < 1 || isempty(session_dir)
    session_dir = locate_latest_session();
    if isempty(session_dir)
        error('[Report] No session was found. Run a session first or specify session_dir.');
    end
end
if ~exist(session_dir, 'dir')
    error('[Report] Directory does not exist: %s', session_dir);
end

ts_path   = fullfile(session_dir, 'timeseries_rec.csv');
ev_path   = fullfile(session_dir, 'events_log.csv');
meta_path = fullfile(session_dir, 'meta.json');

report_dir = fullfile(session_dir, 'report');
if ~exist(report_dir, 'dir'), mkdir(report_dir); end

% --- 1. 读 meta ---
meta = read_meta(meta_path);

% --- 2. 读时序 ---
[ts_tbl, ts_cols] = read_timeseries(ts_path);

% --- 3. 读事件 ---
ev_tbl = read_events(ev_path);

% --- 4. 画时序图 ---
fig_ts_path = fullfile(report_dir, 'fig_timeseries.png');
plot_timeseries(ts_tbl, ts_cols, ev_tbl, fig_ts_path);

% --- 5. 画Distribution Histograms ---
fig_hist_path = fullfile(report_dir, 'fig_distribution.png');
plot_distribution(ts_tbl, ts_cols, fig_hist_path);

% --- 6. Threshold History图(若有相关事件) ---
fig_thr_path = '';
if ~isempty(ev_tbl) && any(strcmp(ev_tbl.kind, 'threshold'))
    fig_thr_path = fullfile(report_dir, 'fig_threshold.png');
    plot_threshold(ev_tbl, fig_thr_path);
end

% --- 7. 阶段/停止/链路性能图(若有相关事件) ---
fig_perf_path = '';
if ~isempty(ev_tbl) && any(strcmp(ev_tbl.key, 'phase_ack_latency_ms') | strcmp(ev_tbl.key, 'session_stop_ack_latency_ms'))
    fig_perf_path = fullfile(report_dir, 'fig_performance.png');
    plot_performance(ev_tbl, fig_perf_path);
end

% --- 8. 统计表 summary.csv ---
summary_path = fullfile(report_dir, 'summary.csv');
write_summary(ts_tbl, ts_cols, ev_tbl, summary_path);

% --- 9. HTML 拼装 ---
out_path = fullfile(report_dir, 'report.html');
write_html(out_path, meta, ts_tbl, ts_cols, ev_tbl, ...
    fig_ts_path, fig_hist_path, fig_thr_path, fig_perf_path, summary_path);

fprintf('[Report] Generated: %s\n', out_path);
if ~strcmpi(getenv('SPNFT_SKIP_OPEN_REPORT'), '1')
    try
        web(out_path, '-browser');
    catch
        fprintf('[Report] web() could not open the report. Open the HTML file shown above manually.\n');
    end
end
end


% =================================================================
%                         IO Helpers
% =================================================================

function dir_path = locate_latest_session()
base = fullfile('logs', 'sessions');
dir_path = '';
if ~exist(base, 'dir'), return; end
d = dir(base);
d = d([d.isdir] & ~startsWith({d.name}, '.'));
if isempty(d), return; end
[~, ix] = max([d.datenum]);
dir_path = fullfile(base, d(ix).name);
end


function meta = read_meta(meta_path)
meta = struct();
if ~exist(meta_path, 'file'), return; end
try
    txt = fileread(meta_path);
    meta = jsondecode(txt);
catch err
    fprintf('[Report] Failed to read meta.json: %s\n', err.message);
end
end


function [tbl, cols] = read_timeseries(ts_path)
tbl = table();
cols = {};
if ~exist(ts_path, 'file'), return; end
try
    tbl = readtable(ts_path, 'PreserveVariableNames', true);
catch
    tbl = readtable(ts_path);
end
if isempty(tbl), return; end
all_cols = tbl.Properties.VariableNames;
rec_cols = all_cols(endsWith(all_cols, '_rec'));
% 只保留**数值列**给绘图/统计 (字符串列如 phase_rec 走事件标注路径, 不画线)
cols = {};
for i = 1:length(rec_cols)
    cn = rec_cols{i};
    v = tbl.(cn);
    if isnumeric(v) || islogical(v)
        cols{end+1} = cn; %#ok<AGROW>
    end
end
end


function tbl = read_events(ev_path)
tbl = table();
if ~exist(ev_path, 'file'), return; end
try
    tbl = readtable(ev_path, 'Delimiter', ',', 'TextType', 'string');
catch
    try
        tbl = readtable(ev_path);
    catch
    end
end
end


% =================================================================
%                            Plots
% =================================================================

function plot_timeseries(ts_tbl, ts_cols, ev_tbl, out_png)
if isempty(ts_tbl) || isempty(ts_cols)
    write_placeholder_png(out_png, 'No _rec data columns');
    return;
end
n = length(ts_cols);
t = ts_tbl.t_session_sec;
fig = figure('Visible','off', 'Position',[100 100 1100 180*max(n,1)+60], ...
             'Color',[1 1 1]);
% 阶段竖线(若有 phase 事件)
phase_events = [];
trial_events = [];
if ~isempty(ev_tbl) && any(strcmp(ev_tbl.Properties.VariableNames, 'kind'))
    phase_events = ev_tbl(strcmp(ev_tbl.kind, 'phase'), :);
    trial_events = ev_tbl(strcmp(ev_tbl.kind, 'trial'), :);
end
for i = 1:n
    ax = subplot(n, 1, i);
    y = ts_tbl.(ts_cols{i});
    plot(ax, t, y, 'LineWidth', 1.2);
    grid(ax, 'on');
    ylabel(ax, ts_cols{i}, 'Interpreter', 'none');
    if i == n
        xlabel(ax, 'Session Time (s)');
    else
        set(ax, 'XTickLabel', []);
    end
    hold(ax, 'on');
    plot_event_lines(ax, phase_events, [0.3 0.6 0.9]);
    plot_event_lines(ax, trial_events, [0.6 0.6 0.6]);
end
sgtitle('Time Series (_rec columns)');
exportgraphics(fig, out_png, 'Resolution', 120);
close(fig);
end


function plot_event_lines(ax, evt_subset, color)
if isempty(evt_subset), return; end
yl = ylim(ax);
for k = 1:height(evt_subset)
    x = evt_subset.t_session_sec(k);
    plot(ax, [x x], yl, ':', 'Color', color, 'LineWidth', 0.8);
end
end


function plot_distribution(ts_tbl, ts_cols, out_png)
if isempty(ts_tbl) || isempty(ts_cols)
    write_placeholder_png(out_png, 'No _rec data columns');
    return;
end
n = length(ts_cols);
cols_per_row = min(3, n);
rows = ceil(n / cols_per_row);
fig = figure('Visible','off', 'Position',[100 100 cols_per_row*340 rows*240+60], ...
             'Color',[1 1 1]);
for i = 1:n
    ax = subplot(rows, cols_per_row, i);
    y = ts_tbl.(ts_cols{i});
    y = y(~isnan(y));
    if isempty(y)
        title(ax, sprintf('%s (no data)', ts_cols{i}), 'Interpreter','none');
        continue;
    end
    histogram(ax, y, min(30, max(5, round(sqrt(length(y))))));
    title(ax, ts_cols{i}, 'Interpreter','none');
    grid(ax, 'on');
end
sgtitle('Distribution Histograms');
exportgraphics(fig, out_png, 'Resolution', 120);
close(fig);
end


function plot_threshold(ev_tbl, out_png)
thr = ev_tbl(strcmp(ev_tbl.kind, 'threshold'), :);
if isempty(thr)
    write_placeholder_png(out_png, 'No threshold events');
    return;
end
fig = figure('Visible','off', 'Position',[100 100 900 360], 'Color',[1 1 1]);
plot(thr.t_session_sec, thr.value, '-o', 'LineWidth', 1.5);
grid on; xlabel('Session Time (s)');
ylabel('Threshold'); title('Threshold History');
exportgraphics(fig, out_png, 'Resolution', 120);
close(fig);
end


function plot_performance(ev_tbl, out_png)
perf = ev_tbl(strcmp(ev_tbl.kind, 'latency'), :);
if isempty(perf)
    write_placeholder_png(out_png, 'No performance-validation events');
    return;
end
fig = figure('Visible','off', 'Position',[100 100 1000 420], 'Color',[1 1 1]);
ax = axes(fig);
hold(ax, 'on');
grid(ax, 'on');
keys = unique(perf.key);
colors = lines(length(keys));
labels = strings(length(keys), 1);
for i = 1:length(keys)
    key = keys(i);
    rows = perf(strcmp(perf.key, key), :);
    plot(ax, rows.t_session_sec, rows.value, '-o', 'LineWidth', 1.4, 'Color', colors(i,:));
    labels(i) = performance_label(key);
end
xlabel(ax, 'Session Time (s)');
ylabel(ax, 'Latency (ms)');
title(ax, 'Platform Performance Validation');
legend(ax, cellstr(labels), 'Interpreter', 'none', 'Location', 'best');
exportgraphics(fig, out_png, 'Resolution', 120);
close(fig);
end


function write_placeholder_png(out_png, msg)
fig = figure('Visible','off', 'Position',[100 100 600 200], 'Color',[1 1 1]);
ax = axes(fig, 'Position', [0 0 1 1]); axis(ax, 'off');
text(ax, 0.5, 0.5, msg, 'HorizontalAlignment','center', 'FontSize', 14, 'Color', [0.5 0.5 0.5]);
exportgraphics(fig, out_png, 'Resolution', 100);
close(fig);
end


% =================================================================
%                          Statistics
% =================================================================

function write_summary(ts_tbl, ts_cols, ev_tbl, out_path)
fid = fopen(out_path, 'w');
if fid == -1, return; end
fprintf(fid, 'section,key,N,mean,std,min,median,max\n');
% 时序统计
for i = 1:length(ts_cols)
    cn = ts_cols{i};
    y = ts_tbl.(cn);
    y = y(~isnan(y));
    if isempty(y)
        fprintf(fid, 'rec,%s,0,,,,,\n', cn);
    else
        fprintf(fid, 'rec,%s,%d,%.4f,%.4f,%.4f,%.4f,%.4f\n', ...
            cn, length(y), mean(y), std(y), min(y), median(y), max(y));
    end
end
% 事件计数
if ~isempty(ev_tbl) && any(strcmp(ev_tbl.Properties.VariableNames, 'key'))
    keys = unique(ev_tbl.key);
    for i = 1:length(keys)
        k = char(keys(i));
        c = sum(strcmp(ev_tbl.key, k));
        fprintf(fid, 'log,%s,%d,,,,,\n', k, c);
    end
end
% 性能事件统计
if ~isempty(ev_tbl) && any(strcmp(ev_tbl.Properties.VariableNames, 'kind'))
    perf = ev_tbl(strcmp(ev_tbl.kind, 'latency'), :);
    if ~isempty(perf)
        perf_keys = unique(perf.key);
        for i = 1:length(perf_keys)
            k = perf_keys(i);
            vals = perf.value(strcmp(perf.key, k));
            vals = vals(~isnan(vals));
            if isempty(vals)
                fprintf(fid, 'perf,%s,0,,,,,\n', char(k));
            else
                fprintf(fid, 'perf,%s,%d,%.4f,%.4f,%.4f,%.4f,%.4f\n', ...
                    char(k), length(vals), mean(vals), std(vals), min(vals), median(vals), max(vals));
            end
        end
    end
end
fclose(fid);
end


% =================================================================
%                              HTML
% =================================================================

function write_html(out_path, meta, ts_tbl, ts_cols, ev_tbl, ...
    fig_ts, fig_hist, fig_thr, fig_perf, summary_path)

fid = fopen(out_path, 'w');
if fid == -1, error('[Report] Cannot create %s', out_path); end

% 头部
fprintf(fid, '<!doctype html><html><head><meta charset="utf-8">\n');
fprintf(fid, '<title>SP-NFT Session Report</title>\n');
fprintf(fid, '<style>%s</style></head><body>\n', html_css());
fprintf(fid, '<h1>SP-NFT Session Report</h1>\n');

% 元信息
fprintf(fid, '<section class="meta"><h2>Session Information</h2><table>\n');
add_kv(fid, 'Training Mode',       meta_get(meta, 'scheme'));
add_kv(fid, 'Subject ID',       subject_field(meta, 'id'));
add_kv(fid, 'Name',           subject_field(meta, 'name'));
add_kv(fid, 'Sex',           subject_field(meta, 'sex'));
add_kv(fid, 'Age',           subject_field(meta, 'age'));
add_kv(fid, 'Handedness',           subject_field(meta, 'handedness'));
add_kv(fid, 'Notes',           subject_field(meta, 'note'));
add_kv(fid, 'Start Time',       meta_get(meta, 'start_ts'));
add_kv(fid, 'End Time',       meta_get(meta, 'end_ts'));
add_kv(fid, 'Duration (s)',     meta_get(meta, 'duration_sec'));
add_kv(fid, 'Time-series Rows (_rec)', meta_get(meta, 'ts_row_count'));
add_kv(fid, 'Event Rows (_log)', meta_get(meta, 'ev_row_count'));
perf_csv = fullfile(fileparts(out_path), '..', 'performance_summary.csv');
if exist(perf_csv, 'file')
    add_kv(fid, 'Performance Summary File', 'performance_summary.csv');
end
fprintf(fid, '</table></section>\n');

% 时序图
fprintf(fid, '<section><h2>Time-series Curves</h2>\n');
fprintf(fid, '<img src="%s" alt="timeseries">\n', html_relpath(fig_ts, out_path));
fprintf(fid, '</section>\n');

% Distributions
fprintf(fid, '<section><h2>Distributions</h2>\n');
fprintf(fid, '<img src="%s" alt="distribution">\n', html_relpath(fig_hist, out_path));
fprintf(fid, '</section>\n');

% Threshold History(若有)
if ~isempty(fig_thr) && exist(fig_thr, 'file')
    fprintf(fid, '<section><h2>Threshold History</h2>\n');
    fprintf(fid, '<img src="%s" alt="threshold">\n', html_relpath(fig_thr, out_path));
    fprintf(fid, '</section>\n');
end

% Platform Performance Validation(若有)
if ~isempty(fig_perf) && exist(fig_perf, 'file')
    fprintf(fid, '<section><h2>Platform Performance Validation</h2>\n');
    fprintf(fid, '<img src="%s" alt="performance">\n', html_relpath(fig_perf, out_path));
    fprintf(fid, '<p class="hint">Metrics include phase and session_stop acknowledgment latency.</p></section>\n');
end

% 统计表
fprintf(fid, '<section><h2>Statistical Summary</h2>\n');
embed_csv_as_table(fid, summary_path);
fprintf(fid, '<p class="hint">Full CSV: <code>report/summary.csv</code></p></section>\n');

% 平台Performance Summary File
if exist(perf_csv, 'file')
    fprintf(fid, '<section><h2>Platform Performance Summary</h2>\n');
    embed_csv_as_table(fid, perf_csv);
    fprintf(fid, '<p class="hint">Full CSV: <code>performance_summary.csv</code></p></section>\n');
end

% 事件表(取前 100 条)
if ~isempty(ev_tbl)
    fprintf(fid, '<section><h2>Event Log (first 100 rows)</h2>\n');
    embed_table(fid, ev_tbl, 100);
    fprintf(fid, '<p class="hint">Full event log: <code>events_log.csv</code></p></section>\n');
end

fprintf(fid, '<footer>Generated by generate_report.m on %s</footer>\n', ...
    datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '</body></html>\n');
fclose(fid);
end


function s = html_css()
s = ['body{font-family:Segoe UI,Helvetica,Arial,sans-serif;margin:24px;color:#222;background:#fafafa;}', ...
     'h1{color:#3a3a8a;border-bottom:2px solid #ddd;padding-bottom:6px;}', ...
     'h2{color:#3a3a8a;margin-top:28px;}', ...
     'section{background:#fff;padding:14px 18px;margin:12px 0;border-radius:8px;', ...
     'box-shadow:0 1px 3px rgba(0,0,0,0.08);}' , ...
     'img{max-width:100%;height:auto;border:1px solid #eee;}', ...
     'table{border-collapse:collapse;font-size:13px;}', ...
     'th,td{border:1px solid #ddd;padding:4px 8px;text-align:left;}', ...
     'th{background:#f0f0f5;}', ...
     '.meta table{min-width:380px;}', ...
     '.hint{color:#888;font-size:12px;}', ...
     'footer{margin-top:24px;color:#888;font-size:12px;text-align:center;}'];
end


function add_kv(fid, k, v)
fprintf(fid, '<tr><th>%s</th><td>%s</td></tr>\n', k, html_escape(v));
end


function label = performance_label(key)
key = string(key);
switch key
    case "phase_ack_latency_ms"
        label = "Phase ACK latency";
    case "session_stop_ack_latency_ms"
        label = "Session-stop ACK latency";
    case "phase_ack_transport_ms"
        label = "Phase ACK transport";
    case "session_stop_ack_transport_ms"
        label = "Session-stop ACK transport";
    case "tcp_connected_transport_ms"
        label = "TCP connected transport";
    case "unity_sync_transport_ms"
        label = "Unity sync transport";
    case "unity_marker_transport_ms"
        label = "Unity marker transport";
    otherwise
        label = char(key);
end
end


function v = meta_get(meta, k)
if isstruct(meta) && isfield(meta, k)
    v = meta.(k);
else
    v = '';
end
v = stringify(v);
end


function v = subject_field(meta, k)
if isstruct(meta) && isfield(meta, 'subject') && isstruct(meta.subject) && isfield(meta.subject, k)
    v = stringify(meta.subject.(k));
else
    v = '';
end
end


function s = stringify(v)
if isempty(v), s = ''; return; end
% missing 值 (readtable 对空字符串列产出的 <missing>) → 空字符串
try
    if ismissing(v)
        s = '';
        return;
    end
catch
end
if isstring(v)
    try
        s = char(v);
    catch
        s = '';
    end
    return;
end
if ischar(v), s = v; return; end
if isnumeric(v) && isscalar(v)
    if isnan(v), s = ''; return; end
    if v == round(v), s = sprintf('%d', int64(v)); else, s = sprintf('%.4f', v); end
    return;
end
try
    s = char(jsonencode(v));
catch
    s = '';
end
end


function rel = html_relpath(target, ~)
% 简单实现: 假定 target 在 base_file 同目录或子目录, 取文件名
[~, name, ext] = fileparts(target);
rel = [name, ext];
end


function s = html_escape(x)
if isempty(x), s = ''; return; end
if ~ischar(x) && ~isstring(x), x = stringify(x); end
s = char(x);
s = strrep(s, '&', '&amp;');
s = strrep(s, '<', '&lt;');
s = strrep(s, '>', '&gt;');
end


function embed_csv_as_table(fid, csv_path)
if ~exist(csv_path, 'file')
    fprintf(fid, '<p class="hint">summary.csv does not exist</p>\n');
    return;
end
try
    T = readtable(csv_path, 'TextType', 'string');
    embed_table(fid, T, 1000);
catch err
    fprintf(fid, '<p class="hint">Failed to read summary: %s</p>\n', err.message);
end
end


function embed_table(fid, T, max_rows)
if isempty(T)
    fprintf(fid, '<p class="hint">(empty)</p>\n');
    return;
end
n = min(height(T), max_rows);
cols = T.Properties.VariableNames;
fprintf(fid, '<table><thead><tr>');
for c = 1:length(cols)
    fprintf(fid, '<th>%s</th>', html_escape(cols{c}));
end
fprintf(fid, '</tr></thead><tbody>\n');
for r = 1:n
    fprintf(fid, '<tr>');
    for c = 1:length(cols)
        v = T{r, c};
        fprintf(fid, '<td>%s</td>', html_escape(stringify(extract_one(v))));
    end
    fprintf(fid, '</tr>\n');
end
fprintf(fid, '</tbody></table>\n');
end


function v = extract_one(x)
if iscell(x), v = x{1}; return; end
if istable(x), v = ''; return; end
v = x;
end
