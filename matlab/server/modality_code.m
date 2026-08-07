function code = modality_code(name)
% 把 modality 名字翻译成 TCP 下发用的整数 code.
%   visual    → 0
%   auditory  → 1
%   both      → 2
% 大小写不敏感; 未知值默认 2 (both, 最安全).
switch lower(string(name))
    case "visual",   code = 0;
    case "auditory", code = 1;
    case "both",     code = 2;
    otherwise,       code = 2;
end
end
