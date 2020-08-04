function readData(obj)
% Actually read the data based on the readSettings calculated
chan = obj.readSettings.channel;
switch obj.readSettings.units
    case  {'s','seconds','sec','secs'}
        readFrom = floor(obj.readSettings.time(1) * obj.Fs);
        readTo = ceil(obj.readSettings.time(2) * obj.Fs);
    case {'datapoints','raw','dp'}
        readFrom = obj.readSettings.time(1);
    otherwise
        error(['Unknown units for data read timings: ' obj.readSettings.units])
end
readFrom = max(readFrom,1);
readTo = min(readTo,sum(obj.datapoints));
if obj.verbose
    disp([9 'Reading channel ' num2str(chan) ' from ' num2str(readFrom) ' to ' num2str(readTo) ' (datapoints)'])
end
segs = obj.readSettings.firstSegment:obj.readSettings.lastSegment;

% Need to know where to read from and to within each data seg:
innerReads = [
    zeros(1,length(segs));
    obj.datapoints(segs)
]';

% The first segment needs to be read from the user's input time
innerReads(1,1) = readFrom - 1;
% the last segment needs only be read until the user's input time
innerReads(end,end) = readTo - sum(obj.datapoints(segs(1:end-1)));
% (everything in between is read completely)

if obj.useRAM
    chanlist = 1:obj.channels;
    skipsize = 0;
    startPoint = 0;
else
    chanlist = chan;
    skipsize = double((obj.channels-length(chan))*2);
    startPoint = min(chan)-1;
end

obj.data = cell(1,length(segs));
for s = 1:length(segs)
    fseek(obj.fid,obj.dataStart(segs(s)),'bof');
    if innerReads(s,1) > 0
        fseek(obj.fid, innerReads(s,1) * 2 * obj.channels, 'cof');
    end
    % Skip the file to the first channel to read
    fseek(obj.fid, startPoint * 2, 'cof');
    obj.data{s} = fread(...
        obj.fid,...
        [length(chanlist) diff(innerReads(s,:))],...
        [num2str(length(chanlist)) '*short=>short'],... % for some reason, *short=>short is twice as fast as *short
        skipsize);
    if obj.useRAM
        % Need to remove the channels that weren't asked for
        obj.data{s}(setdiff(chanlist,chan),:) = [];
    end
end
obj.loadedChannels = chan;