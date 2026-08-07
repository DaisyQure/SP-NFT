function varargout = nft_shared(action, varargin)
% NFT 系统共享数据中间层
% 让 run_session.m (后台逻辑) 和 nft_monitor_ui.m (GUI) 解耦通信
%
% 用法:
%   nft_shared('reset')                              % 清空共享数据
%   nft_shared('push', struct(...))                  % 写入一帧数据
%   data = nft_shared('latest')                      % 读取最新一帧
%   nft_shared('add_marker', evt, scene, value)      % 写入一条 marker
%   markers = nft_shared('drain_markers')            % 读取并清空待处理 marker
%   active = nft_shared('is_active')                 % session 是否在跑
%   nft_shared('set_active', true/false)             % 设置 session 状态
%   nft_shared('threshold_event', trial, old, new, hr, dir)  % 记录一次阈值评估
%   hist = nft_shared('threshold_history')           % 取阈值历史 [n x 5]
%                                                     % 列: trial old new hitrate dir(1=raise,2=lower,0=hold)
%
% 共享数据结构:
%   appdata.nft.latest = struct(
%       't', 当前 session 时间 (秒)
%       'scheme', 当前 scheme 名
%       'attention', 'relaxation', 'simulation_intensity' (0-1)
%       'stress', 'fatigue', 'emotion', 'workload' (0-1, 派生量)
%       'theta', 'alpha', 'smr', 'beta' (实时频段功率)
%       'window_open', logical
%       'window_reason', 字符串
%       'sent', 已发送反馈数
%       'markers_count', 已收到 marker 数
%   )
%   appdata.nft.markers_pending = cell array of strings
%   appdata.nft.active = true/false

    KEY = 'nft';

    switch lower(action)
        case 'reset'
            empty_state = struct();
            empty_state.latest = init_latest_struct();
            empty_state.markers_pending = {};
            empty_state.active = false;
            empty_state.threshold_history = zeros(0, 5);   % [trial old new hitrate dirCode]
            setappdata(0, KEY, empty_state);

        case 'push'
            data = varargin{1};
            state = getappdata(0, KEY);
            if isempty(state)
                state = struct('latest', init_latest_struct(), ...
                               'markers_pending', {}, ...
                               'active', true);
            end
            state.latest = merge_struct(state.latest, data);
            setappdata(0, KEY, state);

        case 'latest'
            state = getappdata(0, KEY);
            if isempty(state)
                varargout{1} = init_latest_struct();
            else
                varargout{1} = state.latest;
            end

        case 'add_marker'
            evt = varargin{1};
            if length(varargin) >= 2, scene = varargin{2}; else, scene = ''; end
            if length(varargin) >= 3, value = varargin{3}; else, value = 0; end
            ts = datestr(now, 'HH:MM:SS.FFF');
            line = sprintf('[%s] %s  scene=%s  value=%.3f', ts, evt, scene, value);
            state = getappdata(0, KEY);
            if isempty(state)
                state = struct('latest', init_latest_struct(), ...
                               'markers_pending', {{}}, 'active', false);
            end
            state.markers_pending{end+1} = line;
            setappdata(0, KEY, state);

        case 'drain_markers'
            state = getappdata(0, KEY);
            if isempty(state) || isempty(state.markers_pending)
                varargout{1} = {};
                return;
            end
            varargout{1} = state.markers_pending;
            state.markers_pending = {};
            setappdata(0, KEY, state);

        case 'is_active'
            state = getappdata(0, KEY);
            if isempty(state)
                varargout{1} = false;
            else
                varargout{1} = state.active;
            end

        case 'set_active'
            flag = varargin{1};
            state = getappdata(0, KEY);
            if isempty(state)
                state = struct('latest', init_latest_struct(), ...
                               'markers_pending', {{}}, 'active', flag, ...
                               'threshold_history', zeros(0, 5));
            else
                state.active = flag;
            end
            setappdata(0, KEY, state);

        case 'threshold_event'
            % 记录一次阈值评估事件
            trial   = varargin{1};
            oldT    = varargin{2};
            newT    = varargin{3};
            hitrate = varargin{4};
            dir_str = varargin{5};   % 'raise' / 'lower' / 'hold'
            switch lower(dir_str)
                case 'raise', dirCode = 1;
                case 'lower', dirCode = 2;
                otherwise,    dirCode = 0;
            end
            state = getappdata(0, KEY);
            if isempty(state)
                state = struct('latest', init_latest_struct(), ...
                               'markers_pending', {{}}, 'active', false, ...
                               'threshold_history', zeros(0, 5));
            end
            if ~isfield(state, 'threshold_history')
                state.threshold_history = zeros(0, 5);
            end
            state.threshold_history(end+1, :) = [trial, oldT, newT, hitrate, dirCode];
            setappdata(0, KEY, state);

        case 'threshold_history'
            state = getappdata(0, KEY);
            if isempty(state) || ~isfield(state, 'threshold_history')
                varargout{1} = zeros(0, 5);
            else
                varargout{1} = state.threshold_history;
            end

        otherwise
            error('nft_shared: unknown action %s', action);
    end
end


function s = init_latest_struct()
    s.t = 0;
    s.scheme = '-';
    s.attention = 0.5;
    s.relaxation = 0.5;
    s.simulation_intensity = 0.5;
    s.stress = 0.3;
    s.fatigue = 0.3;
    s.emotion = 0.5;
    s.workload = 0.4;
    s.theta = 0;
    s.alpha = 0;
    s.smr = 0;
    s.beta = 0;
    s.window_open = false;
    s.window_reason = '';
    s.sent = 0;
    s.markers_count = 0;
end


function out = merge_struct(base, update)
    out = base;
    fnames = fieldnames(update);
    for i = 1:length(fnames)
        out.(fnames{i}) = update.(fnames{i});
    end
end
