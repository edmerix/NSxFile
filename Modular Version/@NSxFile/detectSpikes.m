function detectSpikes(obj,varargin)
% Extract spikes from the data. Defaults to running on all channels
% that have already been read, using the .read() method. Stores the
% detected spikes and meta-info in NSxFile.spikes(channelNumber).
% Inputs are name, value pairs:
%
%   'threshold':   what multiple of the MAD-estimate of SD to use
%                   (median(abs(MUA)/0.6745; see Quian Quiroga et
%                   al., 2004 for explanation).
%                   If negative, will detect troughs ("negative
%                   peaks"), if positive will detect peaks.
%                   Defaults to -4
%   'bandpass':    frequency band to filter between before spike
%                   detection, in Hz. Defaults to [300 5000]
%   'filterType':  type of filter to use, FIR of Butter. Defaults
%                   to FIR.
%   'filterOrder': order of filter to use. Defaults to 1024. Note
%                   that Butterworth filter orders are poles, while
%                   FIR are zeros, and Butterworth should have a
%                   much lower order, e.g. 2 or 4.
%   'blank':       [n x 2] array of times (in seconds) to ignore
%                   during both the threshold calculation and spike
%                   extraction. Useful for blanking seizures.
%                   Defaults to [], i.e. not blanking anything.
%   'channels':    which channel numbers to run detection on,
%                   defaults to all currently loaded channels, will
%                   warn you if a user-specified channel hasn't
%                   been read yet, but not do anything about it.
%   'maxThresh':   hard-coded value in �V beyond which to discard
%                   as noise (defaults to 1000 �V)
%   'window':      window in milliseconds around each detection to
%                   store as a waveform. [1 x 2] so window(1) is
%                   milliseconds to start storage from and 
%                   window(2) is milliseconds to store until.
%                   Defaults to [-0.6 1];
if isempty(obj.data)
    error('Need to read data from the file first')
end

if obj.Fs < 2e4
    error('Need a high sampling frequency file to run spike detection and sorting');
end

settings = [];
settings.threshold = -4;
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
        b = fir1(settings.filterOrder,settings.bandpass/(obj.Fs/2));
        a = 1;
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
        
        if ~isempty(obj.electrodeInfo)
            overRes = double(obj.electrodeInfo(ind).DigitalRange(2)) ...
                / double(obj.electrodeInfo(ind).AnalogRange(2));
            if overRes ~= round(overRes)
                warning(['Channel ' num2str(settings.channels(c)) ...
                    ' has a weird digital:analog ratio (' ...
                    num2str(overRes) '), proceeding nonetheless']);
            end
            mua = mua/overRes;
        end

        mask = ones(1,length(mua));
        if ~isempty(settings.blank)
            for b = 1:size(settings.blank,1)
                mask(round(settings.blank(b,1)*obj.Fs):round(settings.blank(b,2)*obj.Fs)) = 0;
            end
        end
        rqq = median(abs(mua(mask == 1))/0.6745);
        obj.spikes(settings.channels(c)).threshold = rqq * settings.threshold;

        obj.spikes(settings.channels(c)).sd = single(std(mua(mask == 1)));
        obj.spikes(settings.channels(c)).duration = single(length(mua)/obj.Fs);
        
        direction = settings.threshold/abs(settings.threshold); % find out if threshold is -ve or +ve
        [~,locs] = findpeaks(direction * mua,'minpeakheight',direction * obj.spikes(settings.channels(c)).threshold);

        pre = floor(settings.window(1)*(obj.Fs/1e3));
        post = ceil(settings.window(2)*(obj.Fs/1e3));

        locs(locs+pre < 1 | locs+post > length(mua)) = [];
        % don't include the spikes that were within the blanking period:
        if ~isempty(settings.blank)
            locs(locs >= settings.blank(1)*obj.Fs & locs < settings.blank(2)*obj.Fs) = [];
        end

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