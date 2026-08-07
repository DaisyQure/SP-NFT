function tcp_send_message(server, seq, type, value, scheme_name, info)
% 发一条反馈/控制消息给 Unity
%
% info 可选, 默认 ''. 仅 type='phase' 用; 写入 JSON 的 info 字段, Unity 端 FeedbackMsg.info 接.
%   type='phase' 时 info 格式: "<trial_idx>|<duration_sec>|<instruction_text>"
%   value=0 表示进入 A 阶段, value=1 表示进入 B 阶段
%
% 重要: 这里显式按 UTF-8 字节发送 JSON, 避免中文 instruction 受 MATLAB /
% Windows 本地默认编码影响, 被 Unity 端解码成替换字符 �。

if nargin < 6, info = ''; end

msg = struct( ...
    'seq',    seq, ...
    'ts',     posixtime(datetime('now', 'TimeZone', 'local')), ...
    'type',   type, ...
    'value',  round(value, 4), ...
    'scheme', scheme_name, ...
    'info',   info);

json_line = [jsonencode(msg) newline];
json_bytes = unicode2native(json_line, 'UTF-8');
write(server, uint8(json_bytes), "uint8");
end
