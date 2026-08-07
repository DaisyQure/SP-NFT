function eeg_close(handle)
if strcmp(handle.type, 'neuracle')
    try
        handle.server.Close();
        fprintf('[EEG] Disconnected.\n');
    catch err
        fprintf('[EEG] Close error: %s\n', err.message);
    end
end
end