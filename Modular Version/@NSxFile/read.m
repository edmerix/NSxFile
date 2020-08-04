function read(obj,varargin)
% read a channel (or all channels) for a specific time (or all times)
if ~obj.isOpen
    error('File has already been closed, reopen to read data')
end
if isnan(obj.headerEnd) || obj.headerEnd < obj.extHdrLngth
    error('Haven''t managed to find the end of the header data')
end

settings.channel = -1;
settings.time = [-Inf Inf];
settings.units = 's';
settings.downsample = 1; % read every nth data point

settings = obj.parseInputs(varargin,settings);

switch settings.units
    case  {'s','seconds','sec','secs'}
        minTime = 0;
        maxTime = sum(obj.duration);
    case {'datapoints','raw','dp'}
        minTime = 1;
        maxTime = sum(obj.datapoints);
    otherwise
        error(['Unknown units for data read timings: ' settings.units])
end

settings.time(1) = max(settings.time(1),minTime);
settings.time(2) = min(settings.time(2),maxTime);

if settings.channel < 1
    settings.channel = 1:obj.channels;
end

obj.readSettings = settings;
obj.calculateSegments();
if obj.verbose
    disp(['calculateSegments decided from seg ' ...
        num2str(obj.readSettings.firstSegment) ' to seg ' ...
        num2str(obj.readSettings.lastSegment)])
end
obj.readData();