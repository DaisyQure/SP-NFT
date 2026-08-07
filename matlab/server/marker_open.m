function mk = marker_open(scheme_name)
% 打开一个 marker 日志文件,返回 marker 上下文 struct
% 由 run_session 在 session 开始时调用一次

if ~exist('logs', 'dir')
    mkdir('logs');
end

stamp = datestr(now, 'yyyymmdd_HHMMSS');
mk.path = fullfile('logs', sprintf('markers_%s_%s.csv', scheme_name, stamp));
mk.fid  = fopen(mk.path, 'w');
if mk.fid == -1
    error('[Marker] Cannot create file: %s.', mk.path);
end

fprintf(mk.fid, 'recv_ts_matlab,unity_ts,seq,event,scene,value,info\n');

mk.buffer = '';
mk.count  = 0;
mk.last_event = '';
mk.last_scene = '';
mk.last_value = 0;
mk.last_info = '';
mk.last_seq = -1;
mk.last_unity_ts = 0;
mk.last_recv_ts = 0;
mk.new_events = strings(0, 1);
mk.new_values = zeros(0, 1);
mk.new_scenes = strings(0, 1);
mk.new_infos = strings(0, 1);
mk.new_unity_ts = zeros(0, 1);
mk.new_recv_ts = zeros(0, 1);
mk.new_seqs = zeros(0, 1);

fprintf('[Marker] Reverse channel ready; recording to %s.\n', mk.path);
end
