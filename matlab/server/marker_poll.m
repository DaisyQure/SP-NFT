function mk = marker_poll(server, mk)
% 非阻塞地把 Unity 发来的 marker 全部读出并写入 CSV
% 每次 run_session 主循环都调用一次

mk.new_events = strings(0, 1);
mk.new_values = zeros(0, 1);
mk.new_scenes = strings(0, 1);
mk.new_infos = strings(0, 1);
mk.new_unity_ts = zeros(0, 1);
mk.new_recv_ts = zeros(0, 1);
mk.new_seqs = zeros(0, 1);

n = server.NumBytesAvailable;
if n > 0
    raw   = read(server, n, "uint8");
    chunk = char(reshape(raw, 1, []));
    mk.buffer = [mk.buffer, chunk];
end

while true
    idx = find(mk.buffer == newline, 1);
    if isempty(idx)
        break;
    end
    line = strtrim(mk.buffer(1:idx-1));
    mk.buffer = mk.buffer(idx+1:end);
    if ~isempty(line)
        mk = log_one_marker(mk, line);
    end
end
end

function mk = log_one_marker(mk, line)
try
    m = jsondecode(line);
    recv_ts = posixtime(datetime('now', 'TimeZone', 'local'));

    seq   = get_or(m, 'seq',   -1);
    uts   = get_or(m, 'ts',    0);
    evt   = get_or(m, 'evt',   '');
    scene = get_or(m, 'scene', '');
    val   = get_or(m, 'value', 0);
    info  = get_or(m, 'info',  '');

    fprintf(mk.fid, '%.6f,%.6f,%d,%s,%s,%.4f,%s\n', ...
        recv_ts, uts, round(seq), evt, scene, val, info);
    mk.count = mk.count + 1;

    mk.last_event = evt;
    mk.last_scene = scene;
    mk.last_value = val;
    mk.last_info = info;
    mk.last_seq = round(seq);
    mk.last_unity_ts = uts;
    mk.last_recv_ts = recv_ts;
    mk.new_events(end+1, 1) = string(evt);
    mk.new_values(end+1, 1) = val;
    mk.new_scenes(end+1, 1) = string(scene);
    mk.new_infos(end+1, 1) = string(info);
    mk.new_unity_ts(end+1, 1) = uts;
    mk.new_recv_ts(end+1, 1) = recv_ts;
    mk.new_seqs(end+1, 1) = round(seq);

    fprintf('[Marker] #%d  %-20s scene=%-14s value=%.3f\n', ...
        round(seq), evt, scene, val);
catch err
    fprintf('[Marker] Parse failed: %s | %s\n', line, err.message);
end
end

function v = get_or(s, name, default)
if isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = default;
end
end
