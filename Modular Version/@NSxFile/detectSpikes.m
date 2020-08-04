function detectSpikes(obj,varargin)
% Extract spikes from the data for spike sorting
if isempty(obj.data)
    error('Need to read data from the file first')
end

if obj.Fs < 2e4
    error('Need a high sampling frequency file to run spike detection and sorting');
end

settings = [];
settings.threshold = 4.5;
settings.bandpass = [300 5000];
settings.filterType = 'FIR';
settings.filterOrder = 1024;
settings.blank = [];
settings.channels = obj.loadedChannels;
settings.maxThresh = 1e3;
settings.window = [-0.6 1]; % in milliseconds

settings = obj.parseInputs(varargin,settings);

switch settings.filterType
    case {'fir','FIR'}
        [b,a] = fir1(settings.filterOrder,settings.bandpass/(obj.Fs/2));
    case {'butter','Butterworth','Butter','butterworth'}
        [b,a] = butter(settings.filterOrder,settings.bandpass/(obj.Fs/2));
    otherwise
        error(['Unknown filter type: ' settings.filterType])
end

for c = 1:length(settings.channels)
    obj.spikes(settings.channels(c)).loaded = false;
    obj.spikes(settings.channels(c)).channel = settings.channels(c);
    obj.spikes(settings.channels(c)).settings = settings;
    ind = find(obj.loadedChannels == settings.channels(c));
    if isempty(ind)
        disp(['Channel ' num2str(settings.channels(c)) ' has not been loaded, skipping'])
    else
        disp(['Filtering channel ' num2str(settings.channels(c))...
            ' (' num2str(settings.bandpass(1)) ' to '...
            num2str(settings.bandpass(2)) ' Hz, ' ...
            num2str(settings.filterOrder) '-order ' settings.filterType ')'])
        raw = cell2mat(obj.data);
        mua = filtfilt(b,a,double(raw(ind,:)));
        clear raw
        overRes = double(obj.electrodeinfo(ind).DigitalRange(2)) ...
            / double(obj.electrodeinfo(ind).AnalogRange(2));
        if overRes ~= round(overRes)
            warning(['Channel ' num2str(settings.channels(c)) ...
                ' has a weird digital:analog ratio (' ...
                num2str(overRes) '), proceeding nonetheless']);
        end
        mua = mua/overRes;

        mask = ones(1,length(mua));
        if ~isempty(settings.blank)
            mask(round(settings.blank(1)*obj.Fs):round(settings.blank(2)*obj.Fs)) = 0;
        end
        rqq = median(abs(mua(mask == 1))/0.6745);
        obj.spikes(settings.channels(c)).threshold = -rqq * settings.threshold;

        obj.spikes(settings.channels(c)).sd = single(std(mua(mask == 1)));
        obj.spikes(settings.channels(c)).duration = single(length(mua)/obj.Fs);

        [~,locs] = findpeaks(-mua,'minpeakheight',-obj.spikes(settings.channels(c)).threshold);

        pre = floor(settings.window(1)*(obj.Fs/1e3));
        post = ceil(settings.window(2)*(obj.Fs/1e3));

        locs(locs-pre < 1 | locs+post > length(mua)) = [];

        spkwin = pre:post;
        spks = zeros(length(spkwin),length(locs));

        for t = 1:length(locs)
            spks(:,t) = mua(locs(t)+spkwin);
        end
        spkt = locs;

        % remove the overly large ones:
        [~,j] = ind2sub(size(spks),find(abs(spks) > settings.maxThresh));
        j = unique(j);
        spks(:,j) = [];
        spkt(j) = [];

        spkt = spkt/obj.Fs;

        obj.spikes(settings.channels(c)).waveforms = spks';
        obj.spikes(settings.channels(c)).spiketimes = single(spkt);
        obj.spikes(settings.channels(c)).window = settings.window;
        obj.spikes(settings.channels(c)).covariance = obj.covEst(mua, length(spkwin));
        obj.spikes(settings.channels(c)).loaded = true;
        disp([9 'Found ' num2str(length(spkt)) ' spikes (' num2str(length(j)) ' were auto-removed due to large amplitude)'])
    end
end