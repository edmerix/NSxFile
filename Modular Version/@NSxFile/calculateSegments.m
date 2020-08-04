function calculateSegments(obj)
% work out which segments the user-requested time points lie in
switch obj.readSettings.units
    case  {'s','seconds','sec','secs'}
        segmentDurations = obj.duration;
    case {'datapoints','raw','dp'}
        segmentDurations = obj.datapoints;
    otherwise
        error(['Unknown units for data read timings: ' obj.readSettings.units])
end
pre = find(cumsum(segmentDurations) > obj.readSettings.time(1),1,'first');
if isempty(pre)
    error('Read request was after end of data')
end
obj.readSettings.firstSegment = pre;
post = find(cumsum(segmentDurations) < obj.readSettings.time(2),1,'last');
if isempty(post)
    post = 0;
end
obj.readSettings.lastSegment = post + 1;