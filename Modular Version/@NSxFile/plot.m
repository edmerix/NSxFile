function ax = plot(obj,varargin)
%
if isempty(obj.data)
    error('Haven''t read any data to plot yet')
end

if length(varargin{1}) == 1 && isgraphics(varargin{1})
    ax = varargin{1};
    args = varargin(2:end);
else
    ax = gca;
    args = varargin;
end

settings.channels = obj.loadedChannels;
settings.maxtime = 300;
settings.figpos = [0.05 0.05 0.9 0.9];
settings.figunits = 'normalized';
settings.targetFs = 100;
settings.sdCutoff = 1000;
settings.scale = 5;
settings.from = -Inf;
settings.to = Inf;
settings.tickScale = 30; % number of seconds to leave between ticks on the plot

allowable = fieldnames(settings);

if mod(nargin,2) ~= 0
    disp([9 'Inputs should be given in name/value pairs, i.e. an even number'])
end
for v = 1:2:length(args)
    if max(strcmp(allowable,args{v})) < 1
        disp([9 'Not assigning ' args{v} ' value - not a setting in the NSxFile.plot() method '])
    else
        settings.(args{v}) = args{v+1};
    end
end

