function nft_monitor_ui()
% SP-NFT 实验者监控台
% 风格借鉴 EEGFeedbackUI（深色科研主题）
% 适配 4 类Training Mode:simulation / attention / relax / monitor
%
% Step B: 接入 run_session 的真实数据 (通过 nft_shared 共享层)
%   工作流程:
%     1. MATLAB 命令行先打开 GUI:  >> nft_monitor_ui
%     2. 在 GUI 上选 scheme 后点 "Start Session"
%     3. GUI 提示"WAITING run_session", 此时另开 MATLAB 跑:
%        >> run_session('attention', 90)
%     4. GUI 自动检测到 active=true 并显示真实数据
%   或者先跑 run_session, 再打开 GUI 也可以, GUI 会自动接管显示。
%
% 注: 当 nft_shared 没有 active session 时, GUI 会显示 mock 数据预览。

    addpath('server');   % modality_code / monitor_target_code 需要
    cfg_initial = config();
    default_modality = char(string(cfg_initial.feedback.modality));
    default_mon_target = char(string(cfg_initial.monitor.target));
    baseFigureSize = [1280 882];
    layoutState = struct();

    %% ================== 主窗口 ==================
    fig = uifigure('Name', 'SP-NFT Operator Console', ...
                   'Position', [80 20 1280 882], ...
                   'Color', [0.05 0.05 0.1]);
    fig.AutoResizeChildren = 'off';

    %% ================== 标题 ==================
    uilabel(fig, 'Position', [20 832 1240 40], ...
            'Text', 'SP-NFT Operator Console', ...
            'FontSize', 24, 'FontWeight', 'bold', ...
            'FontColor', [1 0.2 0.2], ...
            'HorizontalAlignment', 'center');

    uilabel(fig, 'Position', [20 802 1240 24], ...
            'Text', 'Four user-experience-oriented neurofeedback modes - Operator interface', ...
            'FontSize', 13, ...
            'FontColor', [0.7 0.9 1], ...
            'HorizontalAlignment', 'center');

    %% ================== Subject信息面板 ==================
    subjectPanel = uipanel(fig, 'Position', [20 666 1240 130], ...
                           'BackgroundColor', [0.08 0.08 0.15], ...
                           'BorderType', 'none');

    uilabel(subjectPanel, 'Position', [12 68 60 22], ...
            'Text', 'Subject', 'FontSize', 13, 'FontWeight', 'bold', ...
            'FontColor', [0 1 0.8]);

    uilabel(subjectPanel, 'Position', [80 68 60 22], 'Text', 'Subject ID*', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);
    subjectIdField = uieditfield(subjectPanel, 'text', 'Position', [140 68 100 24], ...
            'Value', 'S001', 'BackgroundColor', [0.1 0.1 0.2], 'FontColor', [0.9 0.95 1]);

    uilabel(subjectPanel, 'Position', [250 68 40 22], 'Text', 'Name', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);
    subjectNameField = uieditfield(subjectPanel, 'text', 'Position', [290 68 110 24], ...
            'BackgroundColor', [0.1 0.1 0.2], 'FontColor', [0.9 0.95 1]);

    uilabel(subjectPanel, 'Position', [410 68 30 22], 'Text', 'Sex', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);
    subjectSexDropdown = uidropdown(subjectPanel, 'Position', [450 68 90 24], ...
            'Items', {'', 'Male', 'Female', 'Other'}, ...
            'ItemsData', {'', 'M', 'F', 'Other'}, 'Value', '', ...
            'BackgroundColor', [0.1 0.1 0.2], 'FontColor', [0.9 0.95 1]);

    uilabel(subjectPanel, 'Position', [550 68 30 22], 'Text', 'Age', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);
    subjectAgeField = uieditfield(subjectPanel, 'numeric', 'Position', [590 68 60 24], ...
            'Value', 0, 'Limits', [0 120], ...
            'BackgroundColor', [0.1 0.1 0.2], 'FontColor', [0.9 0.95 1]);

    uilabel(subjectPanel, 'Position', [660 68 60 22], 'Text', 'Handedness', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);
    subjectHandDropdown = uidropdown(subjectPanel, 'Position', [710 68 90 24], ...
            'Items', {'', 'Right', 'Left', 'Both'}, ...
            'ItemsData', {'', 'Right', 'Left', 'Both'}, 'Value', '', ...
            'BackgroundColor', [0.1 0.1 0.2], 'FontColor', [0.9 0.95 1]);

    uilabel(subjectPanel, 'Position', [810 68 36 22], 'Text', 'Notes', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);
    subjectNoteField = uieditfield(subjectPanel, 'text', 'Position', [850 68 240 24], ...
            'BackgroundColor', [0.1 0.1 0.2], 'FontColor', [0.9 0.95 1]);

    autoReportCheckbox = uicheckbox(subjectPanel, 'Position', [1100 68 130 24], ...
            'Text', 'Automatic Report', 'Value', true, 'FontColor', [0.7 0.9 1]);

    uilabel(subjectPanel, 'Position', [860 36 90 22], 'Text', 'Baseline (s)', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);
    baselineField = uieditfield(subjectPanel, 'numeric', 'Position', [950 36 70 24], ...
            'Value', cfg_initial.baseline.duration_sec, 'Limits', [1 300], 'RoundFractionalValues', 'on', ...
            'BackgroundColor', [0.1 0.1 0.2], 'FontColor', [0.9 0.95 1]);

    % --- Paradigm 行 (A-B-A-B 参数, 运行中锁定) ---
    uilabel(subjectPanel, 'Position', [12 36 80 22], ...
            'Text', 'Paradigm', 'FontSize', 13, 'FontWeight', 'bold', ...
            'FontColor', [0 1 0.8]);

    uilabel(subjectPanel, 'Position', [80 36 60 22], 'Text', 'Trials', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);
    nTrialsField = uieditfield(subjectPanel, 'numeric', 'Position', [140 36 70 24], ...
            'Value', 20, 'Limits', [1 200], 'RoundFractionalValues', 'on', ...
            'BackgroundColor', [0.1 0.1 0.2], 'FontColor', [0.9 0.95 1]);

    uilabel(subjectPanel, 'Position', [220 36 70 22], 'Text', 'Phase A (s)', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);
    phaseAField = uieditfield(subjectPanel, 'numeric', 'Position', [290 36 70 24], ...
            'Value', 10, 'Limits', [1 600], ...
            'BackgroundColor', [0.1 0.1 0.2], 'FontColor', [0.9 0.95 1]);

    uilabel(subjectPanel, 'Position', [370 36 70 22], 'Text', 'Phase B (s)', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);
    phaseBField = uieditfield(subjectPanel, 'numeric', 'Position', [440 36 70 24], ...
            'Value', 30, 'Limits', [1 600], ...
            'BackgroundColor', [0.1 0.1 0.2], 'FontColor', [0.9 0.95 1]);

    uilabel(subjectPanel, 'Position', [520 36 330 22], ...
            'Text', 'Phase A = resting baseline (fixation cross); Phase B = feedback regulation. One A-B cycle is one trial.', ...
            'FontSize', 11, 'FontColor', [0.5 0.65 0.8]);

    % --- Channel 行 (Feedback Modality + monitor target, 运行中可改) ---
    uilabel(subjectPanel, 'Position', [12 100 80 22], ...
            'Text', 'Modality', 'FontSize', 13, 'FontWeight', 'bold', ...
            'FontColor', [0 1 0.8]);

    uilabel(subjectPanel, 'Position', [80 100 70 22], 'Text', 'Feedback Modality', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);
    modalityDropdown = uidropdown(subjectPanel, 'Position', [150 100 100 24], ...
            'Items', {'Visual', 'Auditory', 'Both'}, ...
            'ItemsData', {'visual', 'auditory', 'both'}, ...
            'Value', default_modality, ...
            'BackgroundColor', [0.1 0.1 0.2], 'FontColor', [0.9 0.95 1]);

    uilabel(subjectPanel, 'Position', [270 100 70 22], 'Text', 'Monitoring Target', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);
    monTargetDropdown = uidropdown(subjectPanel, 'Position', [350 100 110 24], ...
            'Items', {'Attention', 'Relaxation', 'Simulation Intensity'}, ...
            'ItemsData', {'attention', 'relaxation', 'simulation'}, ...
            'Value', default_mon_target, 'Enable', 'off', ...
            'BackgroundColor', [0.1 0.1 0.2], 'FontColor', [0.9 0.95 1]);

    uilabel(subjectPanel, 'Position', [470 100 760 22], ...
            'Text', 'The feedback modality can be changed at any time. The monitoring target is available only in monitor mode.', ...
            'FontSize', 11, 'FontColor', [0.5 0.65 0.8]);

    uilabel(subjectPanel, 'Position', [80 8 1140 22], ...
            'Text', '* Required. Data are archived under logs/sessions/<stamp>_<scheme>_<subject_id>/. Paradigm settings are locked during a session.', ...
            'FontSize', 11, 'FontColor', [0.5 0.6 0.7]);

    subjectUi = struct();
    subjectUi.sectionChannel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Modality');
    subjectUi.channelLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Feedback Modality');
    subjectUi.monitorTargetLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Monitoring Target');
    subjectUi.channelHelpLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'The feedback modality can be changed at any time. The monitoring target is available only in monitor mode.');
    if ~isempty(subjectUi.channelHelpLabel)
        subjectUi.channelHelpLabel.Visible = 'off';
    end
    subjectUi.sectionSubject = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Subject');
    subjectUi.idLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Subject ID*');
    subjectUi.nameLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Name');
    subjectUi.sexLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Sex');
    subjectUi.ageLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Age');
    subjectUi.handLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Handedness');
    subjectUi.noteLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Notes');
    subjectUi.sectionParadigm = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Paradigm');
    subjectUi.trialLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Trials');
    subjectUi.phaseALabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Phase A (s)');
    subjectUi.phaseBLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Phase B (s)');
    subjectUi.baselineLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Baseline (s)');
    subjectUi.paradigmHelpLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', 'Phase A = resting baseline (fixation cross); Phase B = feedback regulation. One A-B cycle is one trial.');
    if ~isempty(subjectUi.paradigmHelpLabel)
        subjectUi.paradigmHelpLabel.Visible = 'off';
    end
    subjectUi.footnoteLabel = findall(subjectPanel, 'Type', 'uilabel', 'Text', '* Required. Data are archived under logs/sessions/<stamp>_<scheme>_<subject_id>/. Paradigm settings are locked during a session.');
    if ~isempty(subjectUi.footnoteLabel)
        subjectUi.footnoteLabel.Visible = 'off';
    end

    %% ================== 左：六维Feedback Metrics ==================
    leftPanel = uipanel(fig, 'Position', [20 60 300 600], ...
                        'BackgroundColor', [0.08 0.08 0.15], ...
                        'BorderType', 'none');

    leftTitleLabel = uilabel(leftPanel, 'Position', [20 565 260 25], ...
            'Text', 'Feedback Metrics', ...
            'FontSize', 14, 'FontWeight', 'bold', ...
            'FontColor', [0 1 0.8]);

    metrics = {'Attention', 'Relaxation', 'Stress', 'Fatigue', 'Emotion', 'Workload'};
    metricColors = { [0 1 0.8], [0.4 0.8 1], [1 0.5 0.3], [1 0.7 0.3], [0.8 0.5 1], [0.5 1 0.6] };
    metricLabels = cell(6,1);
    metricValues = cell(6,1);
    metricTracks = cell(6,1);
    metricBars = cell(6,1);

    for i = 1:6
        y = 525 - (i-1)*85;
        metricLabels{i} = uilabel(leftPanel, 'Position', [20 y 100 22], ...
                'Text', metrics{i}, ...
                'FontSize', 13, 'FontColor', [0.7 0.9 1]);
        metricValues{i} = uilabel(leftPanel, 'Position', [180 y 100 22], ...
                'Text', '0.00', ...
                'FontSize', 15, 'FontWeight', 'bold', ...
                'FontColor', metricColors{i}, ...
                'HorizontalAlignment', 'right');
        metricTracks{i} = uipanel(leftPanel, 'Position', [20 y-30 260 20], ...
                'BackgroundColor', [0.1 0.1 0.2], 'BorderType', 'none');
        metricBars{i} = uipanel(leftPanel, 'Position', [20 y-30 1 20], ...
                'BackgroundColor', metricColors{i}, 'BorderType', 'none');
    end

    %% ================== 中：当前方案 + 状态灯 + Marker 事件流 ==================
    centerPanel = uipanel(fig, 'Position', [340 60 380 600], ...
                          'BackgroundColor', [0.08 0.08 0.15], ...
                          'BorderType', 'none');

    idleCenterLayout = struct();
    activeCenterLayout = struct();

    centerTitleLabel = uilabel(centerPanel, 'Position', [20 565 340 25], ...
            'Text', 'Session Status', ...
            'FontSize', 14, 'FontWeight', 'bold', ...
            'FontColor', [0 1 0.8]);

    schemeLabel = uilabel(centerPanel, 'Position', [20 500 340 32], ...
            'Text', 'Training Mode: -', ...
            'FontSize', 18, 'FontWeight', 'bold', ...
            'FontColor', [1 1 1], ...
            'HorizontalAlignment', 'center');

    % 状态灯（用 axes 画圆）
    lightAxes = uiaxes(centerPanel, 'Position', [90 300 200 200]);
    lightAxes.Color = [0.05 0.05 0.1];
    lightAxes.XColor = 'none';
    lightAxes.YColor = 'none';
    lightAxes.XTick = [];
    lightAxes.YTick = [];
    axis(lightAxes, 'equal');
    xlim(lightAxes, [-1.2 1.2]);
    ylim(lightAxes, [-1.2 1.2]);
    hold(lightAxes, 'on');
    theta = linspace(0, 2*pi, 100);
    haloPatch = patch(lightAxes, 1.1*cos(theta), 1.1*sin(theta), [0.3 0.3 0.4], ...
                      'EdgeColor', 'none', 'FaceAlpha', 0.3);
    lightPatch = patch(lightAxes, cos(theta), sin(theta), [0.5 0.5 0.5], ...
                       'EdgeColor', 'none');

    stateWordLabel = uilabel(centerPanel, 'Position', [20 242 340 50], ...
            'Text', 'WAITING', ...
            'FontSize', 30, 'FontWeight', 'bold', ...
            'FontColor', [1 1 1], ...
            'HorizontalAlignment', 'center');

    % Threshold history 小图
    thresholdTitleLabel = uilabel(centerPanel, 'Position', [20 208 340 24], ...
            'Text', 'Threshold History (raise / lower / hold)', ...
            'FontSize', 13, 'FontWeight', 'bold', ...
            'FontColor', [0 1 0.8]);

    thresholdAxes = uiaxes(centerPanel, 'Position', [20 105 340 95]);
    thresholdAxes.Color = [0.05 0.05 0.1];
    thresholdAxes.XColor = [0.3 0.3 0.4];
    thresholdAxes.YColor = [0.3 0.3 0.4];
    thresholdAxes.GridColor = [0.2 0.2 0.3];
    thresholdAxes.GridAlpha = 0.3;
    thresholdAxes.FontSize = 9;
    ylim(thresholdAxes, [0.35 0.95]);
    xlim(thresholdAxes, [0 30]);
    hold(thresholdAxes, 'on');
    thresholdLine = plot(thresholdAxes, NaN, NaN, '-', ...
                         'Color', [1 0.85 0.2], 'LineWidth', 2);
    thresholdMarkers = scatter(thresholdAxes, NaN, NaN, 36, [1 1 1], 'filled');

    % Marker 事件流
    markerTitleLabel = uilabel(centerPanel, 'Position', [20 74 340 22], ...
            'Text', 'Recent Markers', ...
            'FontSize', 13, 'FontWeight', 'bold', ...
            'FontColor', [0 1 0.8]);

    markerTextArea = uitextarea(centerPanel, 'Position', [20 20 340 50], ...
            'FontSize', 11, ...
            'FontColor', [0.7 0.9 1], ...
            'BackgroundColor', [0.05 0.05 0.1], ...
            'Editable', 'off', ...
            'Value', {'[Ready] Waiting for events...'});

    %% ================== 右：EEG 频段波形 ==================
    rightPanel = uipanel(fig, 'Position', [740 60 520 600], ...
                         'BackgroundColor', [0.08 0.08 0.15], ...
                         'BorderType', 'none');

    rightTitleLabel = uilabel(rightPanel, 'Position', [20 565 480 25], ...
            'Text', 'Real-time EEG Band Power', ...
            'FontSize', 14, 'FontWeight', 'bold', ...
            'FontColor', [0 1 0.8]);

    waveAxes = cell(4,1);
    waveLines = cell(4,1);
    waveLabelHandles = cell(4,1);
    waveLabels = {'Theta（4-8Hz）', 'Alpha（8-13Hz）', 'SMR（12-15Hz）', 'Beta（15-30Hz）'};
    waveColors = { [0.8 0.5 1], [0.4 0.8 1], [0 1 0.8], [1 0.7 0.3] };

    for i = 1:4
        y = 410 - (i-1)*130;
        waveLabelHandles{i} = uilabel(rightPanel, 'Position', [20 y+95 200 20], ...
                'Text', waveLabels{i}, ...
                'FontSize', 12, 'FontWeight', 'bold', ...
                'FontColor', waveColors{i});
        waveAxes{i} = uiaxes(rightPanel, 'Position', [20 y 480 100]);
        waveAxes{i}.Color = [0.05 0.05 0.1];
        waveAxes{i}.XColor = [0.3 0.3 0.4];
        waveAxes{i}.YColor = [0.3 0.3 0.4];
        waveAxes{i}.GridColor = [0.2 0.2 0.3];
        waveAxes{i}.GridAlpha = 0.3;
        waveAxes{i}.XTick = [];
        waveAxes{i}.YTick = [];
        ylim(waveAxes{i}, [-1.6 1.6]);
        xlim(waveAxes{i}, [0 500]);
        hold(waveAxes{i}, 'on');
        waveLines{i} = plot(waveAxes{i}, zeros(1,500), ...
                            'Color', waveColors{i}, 'LineWidth', 1.5);
    end

    %% ================== 底部控制栏 ==================
    footerSchemeLabel = uilabel(fig, 'Position', [340 24 100 22], ...
            'Text', 'Training Mode:', ...
            'FontSize', 13, 'FontColor', [0.7 0.9 1]);

    schemeDropdown = uidropdown(fig, 'Position', [420 22 140 28], ...
            'Items', {'Simulation Training', 'Attention Training', 'Relaxation Training', 'Monitoring Mode'}, ...
            'ItemsData', {'simulation', 'attention', 'relax', 'monitor'}, ...
            'Value', 'attention', ...
            'BackgroundColor', [0.1 0.1 0.2], ...
            'FontColor', [0.7 0.9 1]);

    uilabel(fig, 'Position', [40 24 100 22], ...
            'Text', 'Duration (s):', ...
            'FontSize', 13, 'FontColor', [0.7 0.9 1]);

    durationField = uieditfield(fig, 'numeric', 'Position', [130 22 80 28], ...
            'Value', 90, ...
            'Limits', [10 1200], ...
            'BackgroundColor', [0.1 0.1 0.2], ...
            'FontColor', [0.7 0.9 1]);

    startBtn = uibutton(fig, 'Position', [580 20 130 34], ...
            'Text', 'Start Session', ...
            'FontSize', 14, 'FontWeight', 'bold', ...
            'BackgroundColor', [0 0.6 0.4], ...
            'FontColor', [1 1 1]);

    stopBtn = uibutton(fig, 'Position', [720 20 130 34], ...
            'Text', 'Stop', ...
            'FontSize', 14, 'FontWeight', 'bold', ...
            'BackgroundColor', [0.6 0.1 0.1], ...
            'FontColor', [1 1 1], ...
            'Enable', 'off');

    statusLabel = uilabel(fig, 'Position', [870 24 280 22], ...
            'Text', 'Status: Ready', ...
            'FontSize', 12, 'FontColor', [0.7 0.9 1]);

    reportBtn = uibutton(fig, 'Position', [1140 20 120 34], ...
            'Text', 'Generate Report', ...
            'FontSize', 13, 'FontWeight', 'bold', ...
            'BackgroundColor', [0.2 0.35 0.7], ...
            'FontColor', [1 1 1]);

    %% ================== 数据缓冲与定时器 ==================
    bufferSize = 500;
    waveBuffers = cell(4,1);
    for i = 1:4
        waveBuffers{i} = zeros(1, bufferSize);
    end
    markerHistory = {};

    tmr = [];
    sessionCtx = [];  % session state machine 上下文
    prevPhase = '';   % 跟踪 phase 变化, 用于 waiting_unity → baseline 时首次同步 channel

    %% ================== 回调 ==================
    startBtn.ButtonPushedFcn = @(~,~) startTraining();
    stopBtn.ButtonPushedFcn = @(~,~) stopTraining();
    reportBtn.ButtonPushedFcn = @(~,~) onGenerateReport();
    schemeDropdown.ValueChangedFcn = @(~,~) updateMonTargetEnable();
    modalityDropdown.ValueChangedFcn = @(~,~) sendModality();
    monTargetDropdown.ValueChangedFcn = @(~,~) sendMonitorTarget();
    fig.CloseRequestFcn = @(~,~) cleanupAndClose();

    layoutState = capture_layout_state();
    fig.SizeChangedFcn = @(~,~) relayout_ui();

    % 初始联动一次
    updateMonTargetEnable();
    try
        fig.WindowState = 'maximized';
    catch
        screen = get(0, 'ScreenSize');
        fig.Position = [screen(1) screen(2) screen(3) screen(4)];
    end
    drawnow;
    layoutPanels();

    function updateMonTargetEnable()
        isMonitor = strcmp(schemeDropdown.Value, 'monitor');
        if isMonitor
            monTargetDropdown.Enable = 'on';
            monTargetDropdown.Visible = 'on';
            subjectUi.monitorTargetLabel.Visible = 'on';
        else
            monTargetDropdown.Enable = 'off';
            monTargetDropdown.Visible = 'off';
            subjectUi.monitorTargetLabel.Visible = 'off';
        end
        layoutPanels();
    end

    function layoutSubjectPanel()
        panelW = subjectPanel.Position(3);
        panelH = subjectPanel.Position(4);
        sidePad = max(12, round(panelW * 0.015));
        topPad = max(10, round(panelH * 0.08));
        rowGap = max(8, round(panelH * 0.06));
        labelH = 22;
        fieldH = 24;

        row1Y = panelH - topPad - fieldH;
        row2Y = row1Y - fieldH - rowGap;
        row3Y = row2Y - fieldH - rowGap + 4;

        sectionW = 44;
        labelW = 62;
        narrowFieldW = 84;
        mediumFieldW = 106;
        wideFieldW = 168;
        noteFieldW = max(180, round(panelW * 0.22));

        % Row 1: Modality设置
        x = sidePad;
        subjectUi.sectionChannel.Position = [x, row1Y, sectionW, labelH];
        x = x + sectionW + 10;
        subjectUi.channelLabel.Position = [x, row1Y, labelW, labelH];
        x = x + labelW + 6;
        modalityDropdown.Position = [x, row1Y - 2, mediumFieldW, fieldH];
        x = x + mediumFieldW + 18;
        if strcmp(monTargetDropdown.Visible, 'on')
            subjectUi.monitorTargetLabel.Position = [x, row1Y, labelW + 6, labelH];
            x = x + labelW + 12;
            monTargetDropdown.Position = [x, row1Y - 2, mediumFieldW + 8, fieldH];
        end

        % Row 2: Subject信息
        x = sidePad;
        subjectUi.sectionSubject.Position = [x, row2Y, sectionW, labelH];
        x = x + sectionW + 10;
        subjectUi.idLabel.Position = [x, row2Y, labelW + 10, labelH];
        x = x + labelW + 14;
        subjectIdField.Position = [x, row2Y - 2, mediumFieldW + 12, fieldH];
        x = x + mediumFieldW + 24;
        subjectUi.nameLabel.Position = [x, row2Y, 34, labelH];
        x = x + 40;
        subjectNameField.Position = [x, row2Y - 2, wideFieldW - 20, fieldH];
        x = x + wideFieldW;
        subjectUi.sexLabel.Position = [x, row2Y, 30, labelH];
        x = x + 36;
        subjectSexDropdown.Position = [x, row2Y - 2, narrowFieldW, fieldH];
        x = x + narrowFieldW + 14;
        subjectUi.ageLabel.Position = [x, row2Y, 30, labelH];
        x = x + 36;
        subjectAgeField.Position = [x, row2Y - 2, 60, fieldH];
        x = x + 74;
        subjectUi.handLabel.Position = [x, row2Y, 34, labelH];
        x = x + 40;
        subjectHandDropdown.Position = [x, row2Y - 2, narrowFieldW + 10, fieldH];
        x = x + narrowFieldW + 22;
        subjectUi.noteLabel.Position = [x, row2Y, 34, labelH];
        x = x + 40;
        remainingW = panelW - x - sidePad - 120;
        subjectNoteField.Position = [x, row2Y - 2, max(noteFieldW, remainingW), fieldH];
        autoReportCheckbox.Position = [panelW - sidePad - 110, row2Y - 1, 110, fieldH];

        % Row 3: Paradigm参数
        x = sidePad;
        subjectUi.sectionParadigm.Position = [x, row3Y, sectionW, labelH];
        x = x + sectionW + 10;
        subjectUi.trialLabel.Position = [x, row3Y, labelW, labelH];
        x = x + labelW + 6;
        nTrialsField.Position = [x, row3Y - 2, 70, fieldH];
        x = x + 82;
        subjectUi.phaseALabel.Position = [x, row3Y, 64, labelH];
        x = x + 70;
        phaseAField.Position = [x, row3Y - 2, 70, fieldH];
        x = x + 82;
        subjectUi.phaseBLabel.Position = [x, row3Y, 64, labelH];
        x = x + 70;
        phaseBField.Position = [x, row3Y - 2, 70, fieldH];

        if ~isempty(sessionCtx) && any(strcmp(sessionCtx.phase, {'waiting_unity','baseline','running'}))
            nTrialsField.Enable = 'off';
            phaseAField.Enable = 'off';
            phaseBField.Enable = 'off';
            baselineField.Enable = 'off';
        end
    end

    function layoutPanels()
        figPos = fig.Position;
        figW = figPos(3);
        figH = figPos(4);

        outerMargin = max(20, round(figW * 0.014));
        sectionGap = max(20, round(figW * 0.015));
        headerH = max(150, round(figH * 0.17));
        footerH = max(56, round(figH * 0.07));
        titleTop = max(18, round(figH * 0.02));
        titleH = 40;
        subtitleH = 24;
        titleGap = 8;

        figInnerW = figW - 2 * outerMargin;
        bodyBottom = outerMargin + footerH + 10;

        leftW = max(260, round(figInnerW * 0.24));
        centerW = max(360, round(figInnerW * 0.305));
        rightW = figInnerW - leftW - centerW - 2 * sectionGap;
        if rightW < 360
            rightW = 360;
            centerW = max(340, figInnerW - leftW - rightW - 2 * sectionGap);
        end

        headerY = figH - outerMargin - headerH - 70;
        subjectPanel.Position = [outerMargin, headerY, figInnerW, headerH];
        layoutSubjectPanel();

        panelStackGap = max(12, round(figH * 0.012));
        bodyTop = headerY - panelStackGap;
        bodyH = max(220, bodyTop - bodyBottom);

        leftPanel.Position = [outerMargin, bodyBottom, leftW, bodyH];
        centerPanel.Position = [outerMargin + leftW + sectionGap, bodyBottom, centerW, bodyH];
        rightPanel.Position = [centerPanel.Position(1) + centerW + sectionGap, bodyBottom, rightW, bodyH];

        footerY = outerMargin;
        controlGap = 12;
        buttonW = 130;
        buttonH = 34;
        schemeLabelW = 96;
        schemeDropW = 140;
        controlGroupW = schemeLabelW + 8 + schemeDropW + controlGap + buttonW + controlGap + buttonW;
        groupX = max(outerMargin + 220, round((figW - controlGroupW) / 2));

        footerSchemeLabel.Position = [groupX, footerY + 6, schemeLabelW, 22];
        schemeDropdown.Position = [groupX + schemeLabelW + 8, footerY + 2, schemeDropW, 28];
        startBtn.Position = [schemeDropdown.Position(1) + schemeDropW + controlGap, footerY, buttonW, buttonH];
        stopBtn.Position = [startBtn.Position(1) + buttonW + controlGap, footerY, buttonW, buttonH];
        reportBtn.Position = [figW - outerMargin - 120, footerY, 120, buttonH];
        statusLabel.Position = [stopBtn.Position(1) + buttonW + 20, footerY + 6, max(220, reportBtn.Position(1) - (stopBtn.Position(1) + buttonW + 30)), 22];

        applyHeaderTitleLayout(figW, figH, outerMargin, titleTop, titleGap, titleH, subtitleH);
        layoutLeftMetricsPanel();
        applyCenterLayout(~isempty(sessionCtx));
        layoutRightPanel();
    end

    function applyHeaderTitleLayout(figW, figH, outerMargin, titleTop, titleGap, titleH, subtitleH)
        headerTitle = findall(fig, 'Type', 'uilabel', 'Text', 'SP-NFT Operator Console');
        headerSubtitle = findall(fig, 'Type', 'uilabel', 'Text', 'Four user-experience-oriented neurofeedback modes - Operator interface');
        if ~isempty(headerTitle)
            headerTitle.Position = [outerMargin, figH - titleTop - titleH, figW - 2 * outerMargin, titleH];
        end
        if ~isempty(headerSubtitle)
            headerSubtitle.Position = [outerMargin, figH - titleTop - titleH - titleGap - subtitleH, figW - 2 * outerMargin, subtitleH];
        end
    end

    function layoutLeftMetricsPanel()
        panelW = leftPanel.Position(3);
        panelH = leftPanel.Position(4);
        topPad = max(14, round(panelH * 0.025));
        sidePad = max(18, round(panelW * 0.06));
        titleH = max(22, round(panelH * 0.045));
        rowGap = max(10, round(panelH * 0.018));
        rowBlockH = floor((panelH - topPad - titleH - 6 * rowGap - 20) / 6);
        rowBlockH = max(56, rowBlockH);
        valueW = max(64, round(panelW * 0.18));
        labelW = max(82, round(panelW * 0.24));
        trackW = max(120, panelW - sidePad * 2 - valueW - 12);
        barH = max(18, round(rowBlockH * 0.34));

        leftTitleLabel.Position = [sidePad, panelH - topPad - titleH, panelW - 2 * sidePad, titleH];

        startY = panelH - topPad - titleH - 22;
        for ii = 1:6
            yTop = startY - (ii - 1) * (rowBlockH + rowGap);
            labelY = yTop - 22;
            barY = labelY - 28;
            metricLabels{ii}.Position = [sidePad, labelY, labelW, 22];
            metricValues{ii}.Position = [panelW - sidePad - valueW, labelY, valueW, 22];
            metricTracks{ii}.Position = [sidePad, barY, trackW, barH];
            metricBars{ii}.Position = [sidePad, barY, max(1, metricBars{ii}.Position(3)), barH];
        end
    end

    function layoutRightPanel()
        panelW = rightPanel.Position(3);
        panelH = rightPanel.Position(4);
        sidePad = max(18, round(panelW * 0.04));
        topPad = max(14, round(panelH * 0.025));
        titleH = max(22, round(panelH * 0.045));
        blockGap = max(14, round(panelH * 0.024));
        labelH = 20;
        axisH = floor((panelH - topPad - titleH - 4 * (labelH + blockGap) - 20) / 4);
        axisH = max(80, axisH);
        axisW = panelW - 2 * sidePad;

        rightTitleLabel.Position = [sidePad, panelH - topPad - titleH, axisW, titleH];

        currentTop = panelH - topPad - titleH - 18;
        for ii = 1:4
            labelY = currentTop - labelH;
            axisY = labelY - axisH - 6;
            waveLabelHandles{ii}.Position = [sidePad, labelY, min(220, axisW * 0.45), labelH];
            waveAxes{ii}.Position = [sidePad, axisY, axisW, axisH];
            currentTop = axisY - blockGap;
        end
    end

    function applyCenterLayout(isActive)
        %#ok<INUSD>
        panelPos = centerPanel.Position;
        panelW = panelPos(3);
        panelH = panelPos(4);
        sidePad = max(18, round(panelW * 0.05));
        topPad = max(14, round(panelH * 0.025));
        titleH = max(22, round(panelH * 0.045));
        schemeH = max(28, round(panelH * 0.055));
        stateH = max(42, round(panelH * 0.075));
        markerTitleH = 22;
        markerBoxH = max(48, round(panelH * 0.09));
        thresholdTitleH = 24;
        thresholdAxesH = max(80, round(panelH * 0.14));
        verticalGap = max(10, round(panelH * 0.018));

        centerTitleLabel.Position = [sidePad, panelH - topPad - titleH, panelW - 2 * sidePad, titleH];

        schemeY = panelH - topPad - titleH - verticalGap - schemeH;
        schemeLabel.Position = [sidePad, schemeY, panelW - 2 * sidePad, schemeH];

        bottomClusterH = markerTitleH + markerBoxH + thresholdTitleH + thresholdAxesH + 3 * verticalGap;
        availableTop = schemeY - 2 * verticalGap;
        availableH = max(160, availableTop - bottomClusterH);
        circleSize = min(panelW * 0.46, availableH * 0.70);
        circleX = (panelW - circleSize) / 2;
        circleY = bottomClusterH + verticalGap + stateH + verticalGap + max(0, (availableH - circleSize - stateH - verticalGap) / 2);

        lightAxes.Position = [circleX, circleY, circleSize, circleSize];

        stateY = circleY - stateH - verticalGap;
        stateWordLabel.Position = [sidePad, stateY, panelW - 2 * sidePad, stateH];

        thresholdAxesY = markerBoxH + markerTitleH + thresholdTitleH + 2 * verticalGap;
        thresholdTitleLabel.Position = [sidePad, thresholdAxesY + thresholdAxesH + 2, panelW - 2 * sidePad, thresholdTitleH];
        thresholdAxes.Position = [sidePad, thresholdAxesY, panelW - 2 * sidePad, thresholdAxesH];

        markerTitleLabel.Position = [sidePad, markerBoxH + verticalGap, panelW - 2 * sidePad, markerTitleH];
        markerTextArea.Position = [sidePad, topPad, panelW - 2 * sidePad, markerBoxH];
    end

    function refreshMetricBarPositions()
        for ii = 1:length(metricTracks)
            if ~isvalid(metricTracks{ii}) || ~isvalid(metricBars{ii})
                continue;
            end
            metricBars{ii}.Position(1) = metricTracks{ii}.Position(1);
            metricBars{ii}.Position(2) = metricTracks{ii}.Position(2);
            metricBars{ii}.Position(4) = metricTracks{ii}.Position(4);
        end
    end

    function sendModality()
        if isempty(sessionCtx) || ~isfield(sessionCtx, 'server') || isempty(sessionCtx.server)
            return;
        end
        if ~any(strcmp(sessionCtx.phase, {'baseline','running'}))
            return;
        end
        try
            sessionCtx.seq = sessionCtx.seq + 1;
            tcp_send_message(sessionCtx.server, sessionCtx.seq, 'modality', ...
                modality_code(modalityDropdown.Value), sessionCtx.scheme.name, '');
            fprintf('[GUI] Sent modality=%s\n', modalityDropdown.Value);
        catch err
            fprintf('[GUI] Failed to send modality: %s\n', err.message);
        end
    end

    function sendMonitorTarget()
        if isempty(sessionCtx) || ~isfield(sessionCtx, 'server') || isempty(sessionCtx.server)
            return;
        end
        if ~any(strcmp(sessionCtx.phase, {'baseline','running'}))
            return;
        end
        try
            sessionCtx.seq = sessionCtx.seq + 1;
            tcp_send_message(sessionCtx.server, sessionCtx.seq, 'monitor_target', ...
                monitor_target_code(monTargetDropdown.Value), sessionCtx.scheme.name, '');
            fprintf('[GUI] Sent monitor_target=%s\n', monTargetDropdown.Value);
        catch err
            fprintf('[GUI] Failed to send monitor_target: %s\n', err.message);
        end
    end

    function meta = collectSubjectMeta()
        meta = struct();
        meta.id         = strtrim(char(subjectIdField.Value));
        meta.name       = strtrim(char(subjectNameField.Value));
        meta.sex        = char(subjectSexDropdown.Value);
        meta.age        = subjectAgeField.Value;
        meta.handedness = char(subjectHandDropdown.Value);
        meta.note       = strtrim(char(subjectNoteField.Value));
    end

    function setSubjectFieldsEnable(state)
        subjectIdField.Enable      = state;
        subjectNameField.Enable    = state;
        subjectSexDropdown.Enable  = state;
        subjectAgeField.Enable     = state;
        subjectHandDropdown.Enable = state;
        subjectNoteField.Enable    = state;
        autoReportCheckbox.Enable  = state;
        nTrialsField.Enable        = state;
        phaseAField.Enable         = state;
        phaseBField.Enable         = state;
        baselineField.Enable       = state;
    end

    function onGenerateReport()
        try
            addpath('report');
            generate_report();   % 默认取最新 session
            statusLabel.Text = 'Status: Report generated';
            statusLabel.FontColor = [0.4 0.8 1];
        catch err
            statusLabel.Text = sprintf('Status: Report generation failed: %s', err.message);
            statusLabel.FontColor = [1 0.3 0.3];
        end
    end

    function startTraining()
        subj = collectSubjectMeta();
        if isempty(subj.id)
            statusLabel.Text = 'Status: Subject ID is required';
            statusLabel.FontColor = [1 0.3 0.3];
            return;
        end

        startBtn.Enable = 'off';
        stopBtn.Enable = 'on';
        schemeDropdown.Enable = 'off';
        durationField.Enable = 'off';
        setSubjectFieldsEnable('off');
        schemeLabel.Text = sprintf('Training Mode: %s', scheme_display_name(schemeDropdown.Value));
        layoutPanels();

        % --- 启动后台 session (步进式) ---
        paradigm_override = struct( ...
            'n_trials',    nTrialsField.Value, ...
            'phase_a_dur', phaseAField.Value, ...
            'phase_b_dur', phaseBField.Value);
        sessionCtx = nft_session_init(schemeDropdown.Value, durationField.Value, ...
                                      subj, logical(autoReportCheckbox.Value), ...
                                      paradigm_override, baselineField.Value);

        if strcmp(sessionCtx.phase, 'finished') && ~isempty(sessionCtx.error)
            statusLabel.Text = sprintf('Status: Failed to start: %s', sessionCtx.error);
            statusLabel.FontColor = [1 0.3 0.3];
            startBtn.Enable = 'on';
            stopBtn.Enable = 'off';
            schemeDropdown.Enable = 'on';
            durationField.Enable = 'on';
            setSubjectFieldsEnable('on');
            return;
        end

        statusLabel.Text = sprintf('Status: %s session is waiting for Unity...', scheme_display_name(schemeDropdown.Value));
        statusLabel.FontColor = [1 0.75 0.2];
        prevPhase = sessionCtx.phase;   % 初始通常是 'waiting_unity'

        tmr = timer('ExecutionMode', 'fixedRate', ...
                    'Period', 0.05, ...
                    'TimerFcn', @updateData);
        start(tmr);
    end

    function stopTraining()
        if ~isempty(tmr) && isvalid(tmr)
            stop(tmr);
            delete(tmr);
            tmr = [];
        end

        % 收尾 session
        if ~isempty(sessionCtx)
            sessionCtx.phase = 'finished';
            nft_session_finalize(sessionCtx);
            sessionCtx = [];
        end
        prevPhase = '';

        startBtn.Enable = 'on';
        stopBtn.Enable = 'off';
        schemeDropdown.Enable = 'on';
        durationField.Enable = 'on';
        setSubjectFieldsEnable('on');
        statusLabel.Text = 'Status: Stopped';
        statusLabel.FontColor = [0.7 0.9 1];
        lightPatch.FaceColor = [0.5 0.5 0.5];
        stateWordLabel.Text = 'WAITING';
        stateWordLabel.FontColor = [1 1 1];
        layoutPanels();
    end

    function updateData(~,~)
        % --- 1. 驱动 session 步进 (Step C 新逻辑) ---
        if ~isempty(sessionCtx) && ~strcmp(sessionCtx.phase, 'finished')
            sessionCtx = nft_session_step(sessionCtx);

            % 检测 phase 转换 waiting_unity → baseline: Unity 刚连上, 把当前 channel 同步过去
            if strcmp(prevPhase, 'waiting_unity') && ...
                    any(strcmp(sessionCtx.phase, {'baseline','running'}))
                sendModality();
                sendMonitorTarget();
            end
            prevPhase = sessionCtx.phase;

            % 根据 phase 更新 status bar
            switch sessionCtx.phase
                case 'waiting_unity'
                    statusLabel.Text = sprintf('Status: %s is waiting for Unity...', scheme_display_name(sessionCtx.scheme_name));
                    statusLabel.FontColor = [1 0.75 0.2];
                case 'baseline'
                    elapsed = toc(sessionCtx.baseline_t0);
                    statusLabel.Text = sprintf('Status: Acquiring baseline %.0f/%d s (n=%d)', ...
                        elapsed, round(sessionCtx.cfg.baseline.duration_sec), sessionCtx.baseline_n);
                    statusLabel.FontColor = [0.4 0.8 1];
                case 'running'
                    statusLabel.Text = sprintf('Status: Running | Mode=%s | t=%.1f s | Sent=%d | Markers=%d', ...
                        scheme_display_name(sessionCtx.scheme.name), toc(sessionCtx.t0), sessionCtx.seq, sessionCtx.mk.count);
                    statusLabel.FontColor = [0 1 0.5];
                case 'finished'
                    statusLabel.Text = 'Status: Session ended; finalizing...';
                    statusLabel.FontColor = [0.7 0.9 1];
            end

            % 检测 session 自然结束
            if strcmp(sessionCtx.phase, 'finished')
                nft_session_finalize(sessionCtx);
                sessionCtx = [];
                prevPhase = '';
                if ~isempty(tmr) && isvalid(tmr)
                    stop(tmr);
                    delete(tmr);
                    tmr = [];
                end
                startBtn.Enable = 'on';
                stopBtn.Enable = 'off';
                schemeDropdown.Enable = 'on';
                durationField.Enable = 'on';
                setSubjectFieldsEnable('on');
                statusLabel.Text = 'Status: Session complete';
                statusLabel.FontColor = [0.7 0.9 1];
                lightPatch.FaceColor = [0.5 0.5 0.5];
                stateWordLabel.Text = 'COMPLETE';
                stateWordLabel.FontColor = [1 1 1];
                layoutPanels();
                return;
            end
        end

        % --- 2. 读真实数据 / mock 预览 ---
        if nft_shared('is_active')
            data = read_real_data();
        else
            data = nft_mock_data();
        end
        % 同步 scheme 标签
        if isfield(data, 'scheme') && ~isempty(data.scheme)
            schemeLabel.Text = sprintf('Training Mode: %s', scheme_display_name(data.scheme));
        end

        % --- 更新六维指标 ---
        metricFields = {'attention', 'relaxation', 'stress', 'fatigue', 'emotion', 'workload'};
        activeMetric = current_primary_metric(data);
        metricTrackWidth = metricTracks{1}.Position(3);
        for i = 1:6
            val = data.(metricFields{i});           % 0-1 范围
            metricValues{i}.Text = sprintf('%.2f', val);

            isPrimary = strcmp(metricFields{i}, activeMetric);
            if isPrimary
                minVisibleWidth = 12;
            else
                minVisibleWidth = 0;
            end
            barWidth = val * metricTrackWidth;
            if isPrimary
                barWidth = max(minVisibleWidth, barWidth);
                metricBars{i}.Visible = 'on';
                metricBars{i}.BackgroundColor = metricColors{i};
            else
                if barWidth < 8
                    metricBars{i}.Visible = 'off';
                    barWidth = 1;
                else
                    metricBars{i}.Visible = 'on';
                    metricBars{i}.BackgroundColor = metricColors{i} * 0.55;
                end
            end
            metricBars{i}.Position(3) = max(1, barWidth);
        end

        % --- 更新状态灯 ---
        if isfield(data, 'window_open') && data.window_open
            % 真实窗口打开 -> 强制绿
            lightPatch.FaceColor = [0 0.85 0.35];
            stateWordLabel.Text = 'ACT NOW';
            stateWordLabel.FontColor = [0 1 0.5];
        else
            primary = data.attention;  % 默认用 attention 作为主指标
            if primary >= 0.7
                lightPatch.FaceColor = [0 0.85 0.35];
                stateWordLabel.Text = 'ACT NOW';
                stateWordLabel.FontColor = [0 1 0.5];
            elseif primary >= 0.4
                lightPatch.FaceColor = [1 0.75 0.2];
                stateWordLabel.Text = 'READY';
                stateWordLabel.FontColor = [1 0.9 0.5];
            else
                lightPatch.FaceColor = [0.6 0.6 0.7];
                stateWordLabel.Text = 'WAITING';
                stateWordLabel.FontColor = [0.8 0.8 0.9];
            end
        end
        pulseFactor = 1 + 0.05 * sin(now*86400*2);
        haloPatch.Vertices = [1.1*pulseFactor*cos(theta'), 1.1*pulseFactor*sin(theta')];

        % --- 更新波形 ---
        bandFields = {'theta', 'alpha', 'smr', 'beta'};
        for i = 1:4
            waveBuffers{i} = [waveBuffers{i}(2:end), data.(bandFields{i})];
            set(waveLines{i}, 'YData', waveBuffers{i});
        end

        % --- 拉取真实 marker 事件 ---
        new_markers = nft_shared('drain_markers');
        if ~isempty(new_markers)
            for i = 1:length(new_markers)
                markerHistory{end+1} = localize_marker_line(new_markers{i});
            end
            while length(markerHistory) > 25
                markerHistory(1) = [];
            end
            markerTextArea.Value = flip(markerHistory);
        elseif ~nft_shared('is_active') && rand() < 0.02
            % 没真实数据时，模拟事件让界面有动效
            evt = pickRandomEvent();
            ts = datestr(now, 'HH:MM:SS.FFF');
            line = sprintf('[%s] %s (preview)', ts, event_display_name(evt));
            markerHistory{end+1} = line;
            if length(markerHistory) > 25
                markerHistory(1) = [];
            end
            markerTextArea.Value = flip(markerHistory);
        end

        % --- 阈值历史曲线 ---
        hist = nft_shared('threshold_history');
        if ~isempty(hist)
            xs = hist(:,1);                % trial 索引
            ys = hist(:,3);                % 新阈值
            dirs = hist(:,5);              % 方向 1=raise 2=lower 0=hold
            set(thresholdLine, 'XData', xs, 'YData', ys);
            % marker 颜色: raise=绿, lower=红, hold=灰
            cols = zeros(length(dirs), 3);
            for k = 1:length(dirs)
                if dirs(k) == 1
                    cols(k,:) = [0 1 0.5];
                elseif dirs(k) == 2
                    cols(k,:) = [1 0.4 0.4];
                else
                    cols(k,:) = [0.7 0.7 0.7];
                end
            end
            set(thresholdMarkers, 'XData', xs, 'YData', ys, 'CData', cols);
            % 自适应 X 范围
            if max(xs) > 30
                xlim(thresholdAxes, [0 max(xs)+2]);
            end
        end
    end

    function data = read_real_data()
        % 从共享层读真实数据
        d = nft_shared('latest');

        % --- 核心 3 个反馈值 (来自 at.ema) ---
        d.attention            = clamp01_local(d.attention);
        d.relaxation           = clamp01_local(d.relaxation);
        d.simulation_intensity = clamp01_local(d.simulation_intensity);

        % --- 派生 4 个量 (GUI 端总是从核心 3 值重新派生，确保一致性) ---
        % 注意: 如果当前 scheme 只输出某些核心值,
        %       未输出的核心值会保持 nft_shared 的默认 0.5
        %       因此对应派生量也会停在 0.5 不动 (这是预期行为)
        % 想看 6 维全动: 跑 run_session('monitor', ...) 它输出 3 维
        d.stress   = max(0, min(1, 1 - d.relaxation));
        d.fatigue  = max(0, min(1, 1 - d.attention));
        d.emotion  = max(0, min(1, (d.attention + d.relaxation) / 2));
        d.workload = max(0, min(1, d.simulation_intensity));

        % 频段：归一化到 -1.5 ~ 1.5 给波形显示用 (做对数缩放避免数量级跳)
        d.theta = clip_local(safe_log(d.theta), 1.5);
        d.alpha = clip_local(safe_log(d.alpha), 1.5);
        d.smr   = clip_local(safe_log(d.smr),   1.5);
        d.beta  = clip_local(safe_log(d.beta),  1.5);
        data = d;
    end

function evt = pickRandomEvent()
        events = {'session_start', 'action_window_open', 'action_window_close', ...
                  'shot_fired', 'enemy_hit', 'coin_collected', 'monitor_ready'};
        evt = events{randi(length(events))};
    end

    function name = scheme_display_name(key)
        switch char(string(key))
            case 'simulation'
                name = 'Simulation Training';
            case 'attention'
                name = 'Attention Training';
            case 'relax'
                name = 'Relaxation Training';
            case 'monitor'
                name = 'Monitoring Mode';
            otherwise
                name = char(string(key));
        end
    end

    function name = event_display_name(evt)
        switch char(string(evt))
            case 'session_start'
                name = 'Session Started';
            case 'action_window_open'
                name = 'Action Window Opened';
            case 'action_window_close'
                name = 'Action Window Closed';
            case 'shot_fired'
                name = 'Shot Fired';
            case 'enemy_hit'
                name = 'Target Hit';
            case 'coin_collected'
                name = 'Coin Collected';
            case 'monitor_ready'
                name = 'Monitoring Ready';
            case 'session_end'
                name = 'Session Ended';
            case 'trial_start'
                name = 'Trial Started';
            case 'trial_end'
                name = 'Trial Ended';
            case 'threshold_adjusted'
                name = 'Threshold Adjusted';
            case 'threshold_hold'
                name = 'Threshold Held';
            case 'state_above_threshold'
                name = 'State Above Threshold';
            case 'state_dropped'
                name = 'State Dropped';
            case 'aim_start'
                name = 'Aiming Started';
            case 'auto_fire'
                name = 'Automatic Fire';
            case 'enemy_spawn'
                name = 'Target Appeared';
            case 'enemy_missed'
                name = 'Target Missed';
            case 'enemy_hit_player'
                name = 'Player Hit';
            case 'coin_spawn'
                name = 'Coin Appeared';
            case 'menu_return'
                name = 'Returned to Menu';
            case 'game_over'
                name = 'Game Ended';
            case 'tcp_connected'
                name = 'TCP Connected';
            case 'tcp_disconnected'
                name = 'TCP Disconnected';
            otherwise
                name = char(string(evt));
        end
    end

    function metric = current_primary_metric(data)
        switch schemeDropdown.Value
            case 'relax'
                metric = 'relaxation';
            case 'simulation'
                metric = 'workload';
            case 'monitor'
                switch monTargetDropdown.Value
                    case 'relaxation'
                        metric = 'relaxation';
                    case 'simulation'
                        metric = 'workload';
                    otherwise
                        metric = 'attention';
                end
            otherwise
                metric = 'attention';
        end

        if nargin >= 1 && isfield(data, 'scheme') && ~isempty(data.scheme)
            switch char(string(data.scheme))
                case 'relax'
                    metric = 'relaxation';
                case 'simulation'
                    metric = 'workload';
                case 'monitor'
                    switch monTargetDropdown.Value
                        case 'relaxation'
                            metric = 'relaxation';
                        case 'simulation'
                            metric = 'workload';
                        otherwise
                            metric = 'attention';
                    end
                case 'attention'
                    metric = 'attention';
            end
        end
    end

    function state = capture_layout_state()
        handles = findall(fig);
        posHandles = gobjects(0);
        positions = zeros(0, 4);
        fontHandles = gobjects(0);
        fontSizes = zeros(0, 1);
        for idx = 1:length(handles)
            h = handles(idx);
            if h == fig
                continue;
            end
            if isprop(h, 'Position')
                pos = h.Position;
                if isnumeric(pos) && numel(pos) == 4
                    posHandles(end+1, 1) = h;
                    positions(end+1, :) = double(pos);
                end
            end
            if isprop(h, 'FontSize')
                fs = h.FontSize;
                if isnumeric(fs) && isscalar(fs)
                    fontHandles(end+1, 1) = h;
                    fontSizes(end+1, 1) = double(fs);
                end
            end
        end
        state.posHandles = posHandles;
        state.positions = positions;
        state.fontHandles = fontHandles;
        state.fontSizes = fontSizes;
    end

    function relayout_ui()
        figPos = fig.Position;
        figW = figPos(3);
        figH = figPos(4);
        sf = max(0.9, min(1.35, min(max(figW, 1) / baseFigureSize(1), max(figH, 1) / baseFigureSize(2))));

        for idx = 1:length(layoutState.fontHandles)
            h = layoutState.fontHandles(idx);
            if ~isvalid(h)
                continue;
            end
            h.FontSize = max(9, layoutState.fontSizes(idx) * sf);
        end

        layoutPanels();
        refreshMetricBarPositions();
    end

    function line = localize_marker_line(line)
        events = {'session_start', 'action_window_open', 'action_window_close', ...
                  'shot_fired', 'enemy_hit', 'coin_collected', 'monitor_ready', ...
                  'session_end', 'trial_start', 'trial_end', 'threshold_adjusted', ...
                  'threshold_hold', 'state_above_threshold', 'state_dropped', ...
                  'aim_start', 'auto_fire', 'enemy_spawn', 'enemy_missed', ...
                  'enemy_hit_player', 'coin_spawn', 'menu_return', 'game_over', ...
                  'tcp_connected', 'tcp_disconnected'};
        for idx = 1:length(events)
            line = strrep(line, events{idx}, event_display_name(events{idx}));
        end
        line = strrep(line, 'scene=', 'Scene=');
        line = strrep(line, 'value=', 'Value=');
    end

    function cleanupAndClose()
        if ~isempty(tmr) && isvalid(tmr)
            stop(tmr);
            delete(tmr);
        end
        % 关窗时如果 session 还在跑, 优雅收尾
        if ~isempty(sessionCtx)
            try
                sessionCtx.phase = 'finished';
                nft_session_finalize(sessionCtx);
            catch
            end
            sessionCtx = [];
        end
        delete(fig);
    end
end


function data = nft_mock_data()
% 仅供 Step A 预览用的模拟数据（0-1 范围）
    persistent t;
    if isempty(t), t = 0; end
    t = t + 0.05;

    data.attention  = clamp01(0.5 + 0.25*sin(0.10*t) + 0.05*randn());
    data.relaxation = clamp01(0.6 + 0.20*cos(0.08*t) + 0.04*randn());
    data.stress     = clamp01(0.3 + 0.15*sin(0.12*t) + 0.03*randn());
    data.fatigue    = clamp01(0.4 + 0.18*cos(0.09*t) + 0.04*randn());
    data.emotion    = clamp01(0.55 + 0.20*sin(0.11*t) + 0.04*randn());
    data.workload   = clamp01(0.45 + 0.18*cos(0.13*t) + 0.05*randn());

    data.theta = clip(0.7*sin(2*pi*6*t)  + 0.15*randn(), 1.5);
    data.alpha = clip(0.8*sin(2*pi*10*t) + 0.2*randn(),  1.5);
    data.smr   = clip(0.6*sin(2*pi*13*t) + 0.15*randn(), 1.5);
    data.beta  = clip(0.6*sin(2*pi*20*t) + 0.3*randn(),  1.5);
end

function y = clamp01(x)
    y = max(0, min(1, x));
end

function y = clip(x, lim)
    y = max(-lim, min(lim, x));
end

function y = clamp01_local(x)
    if isempty(x) || ~isnumeric(x), y = 0.5; return; end
    y = max(0, min(1, x(1)));
end

function y = clip_local(x, lim)
    if isempty(x) || ~isnumeric(x), y = 0; return; end
    y = max(-lim, min(lim, x(1)));
end

function y = safe_log(x)
    if isempty(x) || ~isnumeric(x), y = 0; return; end
    if x(1) <= 0, y = 0; return; end
    y = log10(x(1));
end
