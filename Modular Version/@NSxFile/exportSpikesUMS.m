function spikes = exportSpikesUMS(obj,varargin)
% Export the detected spikes into UMS2000 style structs
if ~exist('ss_default_params.m','file')
    error('Need the UltraMegaSort2000 toolbox on the path to export in their data format')
end
settings.channels = obj.loadedChannels;

settings = obj.parseInputs(varargin,settings);

% Required for preallocation. Kinda annoying. Because it's a
% struct array, of a different type than this class, it doesn't
% like other preallocation methods:
spikes = cell(1,length(settings.channels));

for c = 1:length(settings.channels)
    if length(obj.spikes) < c ...
            || ~isfield(obj.spikes(c),'loaded') ...
            || ~obj.spikes(c).loaded
        disp(['Channel ' num2str(settings.channels(c)) ' has not had spikes extracted, doing so now'])
        obj.detectSpikes('channels',settings.channels(c));
    end
    if obj.spikes(c).loaded
        ind = settings.channels(c);
        count = length(obj.spikes(ind).spiketimes);
        spikes{c} = ss_default_params(obj.Fs);
        spikes{c}.info.detect.stds = obj.spikes(ind).sd;
        spikes{c}.info.detect.dur = obj.spikes(ind).duration;
        spikes{c}.info.detect.thresh = obj.spikes(ind).threshold;
        spikes{c}.info.detect.align_sample = floor(-obj.spikes(ind).window(1)*(obj.Fs/1e3)) + 1;
        spikes{c}.info.detect.event_channel = obj.spikes(ind).channel * ones(1,count);

        spikes{c}.waveforms = obj.spikes(ind).waveforms;
        spikes{c}.spiketimes = obj.spikes(ind).spiketimes;
        spikes{c}.trials = ones(1,count);
        spikes{c}.unwrapped_times = obj.spikes(ind).spiketimes;

        [pca.u,pca.s,pca.v] = svd(detrend(spikes{c}.waveforms(:,:),'constant'), 0);
        spikes{c}.info.pca = pca;
        spikes{c}.info.detect.cov = obj.spikes(ind).covariance;
        spikes{c}.info.align.aligned = 1; % this detection method is always aligned
    end
end

spikes = [spikes{:}];
