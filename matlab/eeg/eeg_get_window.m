function data = eeg_get_window(handle, window_sec)
% 取最近 window_sec 秒的 EEG 数据
% 返回 [n_channels x n_samples]

n = round(window_sec * handle.fs);

switch handle.type
    case 'sim'
        t_abs = toc(handle.t_start);
        t = t_abs + (0:n-1) / handle.fs;
        data = zeros(handle.n_channels, n);

        state = 0.5 ...
              + 0.30 * sin(2*pi * t_abs / 18.0) ...
              + 0.12 * sin(2*pi * t_abs / 5.5 + 0.7) ...
              + 0.05 * randn();
        state = max(0.05, min(0.95, state));

        theta_amp = 1.15 - 0.55 * state;
        alpha_amp = 0.75 + 0.65 * state;
        smr_amp   = 0.70 + 0.75 * state;
        beta1_amp = 0.65 + 0.55 * state;
        beta2_amp = 0.75 - 0.35 * state;
        mu_amp    = 1.15 - 0.65 * state;
        beta_amp  = 1.00 - 0.45 * state;

        for ch = 1:handle.n_channels
            cname = handle.montage{ch};
            ch_gain = 0.9 + 0.2 * sin(ch * 1.7);

            theta_local = theta_amp;
            alpha_local = alpha_amp;
            smr_local = smr_amp;
            beta1_local = beta1_amp;
            beta2_local = beta2_amp;
            mu_local = mu_amp;
            beta_local = beta_amp;

            if any(strcmpi(cname, {'C3','Cz','C4'}))
                smr_local = smr_local * 1.35;
                beta1_local = beta1_local * 1.15;
                mu_local = mu_local * 0.85;
                beta_local = beta_local * 0.9;
            end
            if any(strcmpi(cname, {'Pz','POz','O1','O2'}))
                alpha_local = alpha_local * 1.35;
                beta1_local = beta1_local * 0.9;
                beta2_local = beta2_local * 0.85;
            end
            if any(strcmpi(cname, {'Fz','FC1','FC2'}))
                theta_local = theta_local * 1.15;
            end

            data(ch,:) = ch_gain * ( ...
                theta_local * sin(2*pi*6*t + ch*0.11) + ...
                alpha_local * sin(2*pi*10*t + ch*0.17) + ...
                smr_local   * sin(2*pi*13.5*t + ch*0.23) + ...
                beta1_local * sin(2*pi*18*t + ch*0.31) + ...
                beta2_local * sin(2*pi*25*t + ch*0.37) + ...
                mu_local    * sin(2*pi*11*t + ch*0.41) + ...
                beta_local  * sin(2*pi*22*t + ch*0.47)) + ...
                0.35 * randn(1, n);
        end
        
    case 'neuracle'
        % 从环形缓冲取整个缓冲，再截取最后 n 个点
        full = handle.server.GetBufferData();   % [nChan x nPoint_buffer]
        if size(full, 2) < n
            error('[EEG] Buffer is too short: %d samples required, %d available.', n, size(full,2));
        end
        data = full(:, end-n+1:end);
end

end