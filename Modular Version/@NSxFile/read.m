function read(obj,varargin)
% Read a channel (or all channels) for a specific time (or all 
% times)
% Loads the data into the object, as a cell array, so that the data
% structure is the same regardless of whether a file contains
% paused data. The data are stored in NSxFile.data
%
% Will default to reading all channels and the whole file if called
% with no input arguments. Available inputs (name, value pairs)
% are:
%
%   'channels':   array of channel numbers to read. If empty, will 
%                   read all (default)
%   'channel':    duplicate of 'channels', holdover from previous
%                   version.
%   'time':       [1 x 2] array for the start and stop time to read 
%                   from the file (see below for changing units).
%                   Defaults to [-Inf Inf] for full file.
%   'units':      What units for the time input, either seconds or
%                   datapoints (defaults to seconds)
%   'downsample': Read every specified data point to downsample 
%                   (e.g. 3 will read every 3rd data point)
%                   Defaults to 1, for no downsampling. N.B. this
%                   is a holdover from openNSx, do not use to
%                   downsample data without first low pass
%                   filtering!
%
% Set NSxFile.useRAM to false if you want to read a subset of the
% file and the file is larger than your available RAM (slower, but
% can avoid out-of-memory errors)
if ~obj.isOpen
    error('File has already been closed, reopen to read data')
end
if isnan(obj.headerEnd) || obj.headerEnd < obj.extHdrLngth
    error('Haven''t managed to find the end of the header data')
end

settings.channel = -1;
settings.channels = []; % 'channels' is more routinely used outside this function, so allow both
settings.time = [-Inf Inf];
settings.units = 's';
settings.downsample = 1; % read every nth data point

settings = obj.parseInputs(varargin,settings);

% If settings.channels isn't empty and settings.channel isn't the same,
% then the user supplied 'channels' instead of 'channel', so use that
% instead:
if ~isempty(settings.channels) && ~isequal(settings.channel, settings.channels)
    settings.channel = settings.channels;
end

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