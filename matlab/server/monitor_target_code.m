function code = monitor_target_code(name)
% 把 monitor 模式下"当前关注目标"名字翻译成 TCP 下发用的整数 code.
%   attention            → 0
%   relaxation           → 1
%   simulation / simulation_intensity → 2
switch lower(string(name))
    case "attention",                          code = 0;
    case "relaxation",                         code = 1;
    case {"simulation","simulation_intensity"}, code = 2;
    otherwise,                                  code = 0;
end
end
