function recorder_close(rec)
% 关闭 recorder, 把 end_ts / 计数 写到 meta.json, 关 fid.
%
% rec : recorder_open 返回的状态(可能已被 recorder_push/event 更新)

if isempty(rec) || ~isfield(rec, 'ts_fid')
    return;
end

% --- 关 fid ---
try, if rec.ts_fid ~= -1, fclose(rec.ts_fid); end, catch, end
try, if rec.ev_fid ~= -1, fclose(rec.ev_fid); end, catch, end

% --- 补 meta.json ---
try
    end_abs = posixtime(datetime('now', 'TimeZone', 'local'));
    meta = struct();
    meta.scheme        = rec.scheme_name;
    meta.subject       = rec.subject;
    meta.start_ts      = rec.start_wallclock;
    meta.start_abs_ts  = rec.start_abs_ts;
    meta.end_ts        = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    meta.end_abs_ts    = end_abs;
    meta.duration_sec  = end_abs - rec.start_abs_ts;
    meta.ts_columns    = rec.ts_columns;
    meta.ts_row_count  = rec.ts_row_count;
    meta.ev_row_count  = rec.ev_row_count;
    if isfield(rec, 'perf_summary_path')
        meta.performance_summary = rec.perf_summary_path;
    end
    meta.recording_convention = '_rec=time series, _log=event; see docs/RECORDING_CONVENTION.md';

    fid = fopen(rec.meta_path, 'w');
    if fid ~= -1
        try
            fprintf(fid, '%s', jsonencode(meta, 'PrettyPrint', true));
        catch
            fprintf(fid, '%s', jsonencode(meta));
        end
        fclose(fid);
    end
catch err
    fprintf('[Recorder] Failed to write metadata while closing: %s\n', err.message);
end

fprintf('[Recorder] Session archived: %s (rec_rows=%d, log_rows=%d)\n', ...
    rec.session_dir, rec.ts_row_count, rec.ev_row_count);
end
