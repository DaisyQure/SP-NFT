function marker_close(mk)
if isfield(mk, 'fid') && mk.fid ~= -1
    try
        fclose(mk.fid);
        fprintf('[Marker] Closed after recording %d markers: %s\n', ...
            mk.count, mk.path);
    catch err
        fprintf('[Marker] Close error: %s\n', err.message);
    end
end
end