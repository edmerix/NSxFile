% NSxFile: read NSx files in an object-oriented manner.
%  A class for handling Blackrock NSx files, in an object-oriented approach
%
%   Basic usage:
%       <a href="matlab:nsx = NSxFile();">nsx = NSxFile();</a>
%
%   Open a file: (quickly reads header info, stores handle to data)
%       <a href="matlab:nsx.open('filename.ns5');">nsx.open('filename.ns5');</a>
%   
%   As a shorthand, the above can be compressed into:
%       <a href="matlab:nsx = NSxFile('filename','filename.ns5');">nsx = NSxFile('filename','filename.ns5');</a>
%
%   At this point, "nsx" contains multiple properties, including:
%       Fs:              Sampling frequency
%       date:            Date as stored in the file
%       date_local:      Date converted to local time (set nsx.timezone
%                        first, according to where the file was recorded)
%       electrodelabels: Labels for each channel
%
%   (See <a href="matlab:properties('NSxFile')">properties('NSxFile')</a> for full list)
%
%   Read in channel 5 from 300 to 700 seconds:
%       <a href="matlab:nsx.read('channel',5,'time',[300 700]);">nsx.read('channel',5,'time',[300 700]);</a>
%   Or read in all the data:
%       <a href="matlab:nsx.read();">nsx.read();</a>
%   The nsx variable has now populated the nsx.data subfield with the 
%   requested data. The data are always held in a cell, so that there is no
%   difference between handling files with and without pauses.
%
%   Depending on your speed desires/RAM options, you can decide to use RAM
%   to load the full file, or if the file is too large for your RAM and you
%   only wish to read a subset, you can turn this off by typing:
%       <a href="matlab:nsx.useRam = false;">nsx.useRam = false;</a>
%   before calling nsx.read(...);
%
%   Once a channel is loaded, spikes can be automatically extracted with:
%       <a href="matlab:nsx.detectSpikes()">nsx.detectSpikes();</a>
%   or, a subset of channels can be read with the 'channels' input.
%
%   UltraMegaSort2000 spikes structs can be automatically exported if the
%   UMS2k toolbox is on the path, with:
%       <a href="matlab:spikes = nsx.exportSpikesUMS();">spikes = nsx.exportSpikesUMS();</a>
%   which exports all loaded channels, unless the 'channels' input is set.
%
%   See the help sections for each method for further details.
%   Set <a href="matlab:nsx.verbose = true;">nsx.verbose = true;</a> to see more feedback printed to screen during
%   usage.
%
%   E. M. Merricks, Ph.D. 2020-03-07 <INLINE_VERSION>
classdef NSxFile < handle
    properties
        filename            char
        data        (1,:)   cell
        spikes      (1,:)   struct
        MetaTags            struct
        Fs          (1,1)   double
        date                datetime
        date_local          datetime
        timezone            char        = 'America/New_York';
        duration    (1,:)   double
        datapoints  (1,:)   double
        channels    (1,1)   double
        electrodelabels     cell
        electrodeinfo       struct
        useRAM      (1,1)   logical     = true
        verbose     (1,1)   logical     = false
    end
    
    properties (SetAccess = private, Hidden = true)
        fid = -1
        isOpen = false
        isPaused = false
        extHdrLngth = 66;
        
        headerEnd = NaN
        fileEnd = NaN
        dataStart = NaN
        dataEnd = NaN
        
        loadedChannels = []
        
        readSettings = struct()
    end
    
    methods
        function obj = NSxFile(varargin)
        % This is the constructor. Run NSXFile.help for more info.
            allowable = fieldnames(obj);
            if mod(length(varargin),2) ~= 0
                error('Inputs must be in name, value pairs');
            end
            for v = 1:2:length(varargin)
                if find(ismember(allowable,varargin{v}))
                    obj.(varargin{v}) = varargin{v+1};
                else
                    disp([9 'Not assigning ''' varargin{v} ''': not a property of NSxFile object']);
                end
            end
            
            if ~isempty(obj.filename)
                obj.open(obj.filename);
            end
        end
        
        function open(obj,filename)
        % Opens the designated filename within the NSxFile object.
        % Takes one argument: the filename (including file path if not
        % currently on the Matlab path)
        %
        % Note that this leaves the file open for reading various
        % components, NSxFile.close() should be called if you wish to close
        % the file. Alternatively, it is automatically closed upon deletion
        % of the NSxFile variable.
        %
        % The file is opened in read-only mode.
            obj.fid = fopen(filename,'r','ieee-le');
            if obj.fid < 0
                error(['Could not open ' filename ': does it exist?'])
            end
            obj.filename = filename;
            obj.isOpen = true;
            obj.readHeader();
        end
        
        function read(obj,varargin)
        % read a channel (or all channels) for a specific time (or all 
        % times)
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
        end
        
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
        end
        
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
            %spikes(dropping == 1) = [];
            spikes = [spikes{:}];
        end
        
        function close(obj)
        % close handle to file (use when done loading specific data etc.)
            fclose(obj.fid);
            obj.isOpen = false;
        end
        
        function delete(obj)
        % Destructor method
            if obj.isOpen
                fclose(obj.fid);
            end
        end
    end
    
    methods (Access = protected, Hidden = true)
        function readHeader(obj)
        % Read the header from the file
            if obj.fid < 0 || ~obj.isOpen
                error('No file is open, cannot read header');
            end
            obj.MetaTags = struct();
            obj.MetaTags.FileTypeID = fread(obj.fid, [1,8], '*char');
            switch obj.MetaTags.FileTypeID
                case 'NEURALSG'
                    obj.MetaTags.FileSpec       = '2.1';
                    obj.MetaTags.SamplingLabel  = deblank(fread(obj.fid, [1,16], '*char'));
                    obj.MetaTags.TimeRes        = 30000;
                    obj.Fs                      = obj.MetaTags.TimeRes/fread(obj.fid, 1, 'uint32=>double');
                    obj.channels                = double(fread(obj.fid, 1, 'uint32=>double'));
                    obj.MetaTags.ChannelID      = fread(obj.fid, [obj.channels 1], '*uint32');
                case 'NEURALCD'
                    mainHeader = fread(obj.fid, 306, '*uint8');
                    
                    obj.MetaTags.FileSpec       = [num2str(double(mainHeader(1))) '.' num2str(double(mainHeader(2)))];
                    obj.MetaTags.SamplingLabel  = deblank(char(mainHeader(7:22))');
                    obj.MetaTags.Comment        = deblank(char(mainHeader(23:278))');
                    obj.MetaTags.TimeRes        = double(typecast(mainHeader(283:286), 'uint32'));
                    obj.Fs                      = obj.MetaTags.TimeRes / double(typecast(mainHeader(279:282), 'uint32'));
                    t                           = double(typecast(mainHeader(287:302), 'uint16'));
                    obj.channels                = double(typecast(mainHeader(303:306), 'uint32'));
                    
                    obj.MetaTags.Comment(find(obj.MetaTags.Comment==0,1):end) = 0;
                    
                    tFormat = t([1 2 4:7])';
                    tFormat(end) = tFormat(end) + t(8)/1e3;
                    
                    tempdate = datetime(tFormat,'TimeZone','UTC');
                    tempdate.Format = 'yyyy/MM/dd HH:mm:ss.SSS Z';
                    obj.date = tempdate;
                    localtime = tempdate;
                    localtime.TimeZone = obj.timezone;
                    obj.date_local = localtime;
                    
                    readSize = double(obj.channels * obj.extHdrLngth);
                    extendedHeader = fread(obj.fid, readSize, '*uint8');
                    obj.parseExtendedHeader(extendedHeader);
                otherwise
                    error(['Unkonwn file type: ' obj.MetaTags.FileTypeID])
            end
            obj.headerEnd = double(ftell(obj.fid));
            fseek(obj.fid, 0, 'eof');
            obj.fileEnd = double(ftell(obj.fid));
            
            obj.findData();
        end
        
        function parseExtendedHeader(obj,extHdr)
        % Sort out the extended header data if the file has any
            obj.electrodeinfo = struct();
            obj.electrodelabels = cell(1,obj.channels);
            filtTypes = {'None','Butterworth'};
            for i = 1:obj.channels
                offset = double((i-1)*obj.extHdrLngth);
                obj.electrodeinfo(i).Type = char(extHdr((1:2)+offset))';
                
                if ~strcmpi(obj.electrodeinfo(i).Type, 'CC')
                    warning(['Attempted to read extended header on channel' num2str(i) ', but electrode type was not CC'])
                else
                    obj.electrodeinfo(i).ElectrodeID        = typecast(extHdr((3:4)+offset), 'uint16');
                    obj.electrodelabels{i}                  = deblank(char(extHdr((5:20)+offset))');
                    obj.electrodeinfo(i).ConnectorBank      = deblank(char(extHdr(21+offset) + ('A' - 1)));
                    obj.electrodeinfo(i).ConnectorPin       = extHdr(22+offset);
                    obj.electrodeinfo(i).DigitalRange(1)    = typecast(extHdr((23:24)+offset), 'int16');
                    obj.electrodeinfo(i).DigitalRange(2)    = typecast(extHdr((25:26)+offset), 'int16');
                    obj.electrodeinfo(i).AnalogRange(1)     = typecast(extHdr((27:28)+offset), 'int16');
                    obj.electrodeinfo(i).AnalogRange(2)     = typecast(extHdr((29:30)+offset), 'int16');
                    obj.electrodeinfo(i).AnalogUnits        = deblank(char(extHdr((31:46)+offset))');
                    obj.electrodeinfo(i).HighFreqCorner     = typecast(extHdr((47:50)+offset), 'uint32');
                    obj.electrodeinfo(i).HighFreqOrder      = typecast(extHdr((51:54)+offset), 'uint32');
                    obj.electrodeinfo(i).HighFilterType     = filtTypes{typecast(extHdr((55:56)+offset), 'uint16')+1};
                    obj.electrodeinfo(i).LowFreqCorner      = typecast(extHdr((57:60)+offset), 'uint32');
                    obj.electrodeinfo(i).LowFreqOrder       = typecast(extHdr((61:64)+offset), 'uint32');
                    obj.electrodeinfo(i).LowFilterType      = filtTypes{typecast(extHdr((65:66)+offset), 'uint16')+1};
                end
            end
        end
        
        function findData(obj)
        % Actually find the data within the binary file
            fseek(obj.fid, obj.headerEnd, 'bof');
            switch obj.MetaTags.FileTypeID
                case 'NEURALSG'
                    obj.dataStart = obj.headerEnd;
                    obj.dataEnd = obj.fileEnd;
                    obj.datapoints = (obj.dataEnd - obj.dataStart)/(obj.channels * 2);
                case {'NEURALCD','BRSMPGRP'}
                    segmentCount = 0;
                    while double(ftell(obj.fid)) < obj.fileEnd
                        if fread(obj.fid, 1, 'uint8') ~= 1
                            % Blackrock need to fix this in the original
                            % NPMK/data structure...
                            disp([9 'Duration read issue after segment ' num2str(segmentCount) ', calculating full data points'])
                            
                            disp([9 9 'Position was ' num2str(double(ftell(obj.fid)))])
                            disp([9 9 'End of file was ' num2str(obj.fileEnd)])
                            
                            obj.datapoints = double(obj.fileEnd - obj.dataStart)/(obj.channels * 2);
                            break;
                        end
                        
                        segmentCount = segmentCount + 1;
                        if strcmp(obj.MetaTags.FileTypeID, 'BRSMPGRP')
                            startTimeStamp = fread(obj.fid, 1, 'uint64');
                        else
                            startTimeStamp = fread(obj.fid, 1, 'uint32');
                        end
                        
                        obj.MetaTags.Timestamp(segmentCount) = startTimeStamp;
                        obj.datapoints(segmentCount) = fread(obj.fid, 1, 'uint32');
                        obj.dataStart(segmentCount) = double(ftell(obj.fid));
                        fseek(obj.fid, obj.datapoints(segmentCount) * obj.channels * 2, 'cof');
                        obj.dataEnd(segmentCount) = double(ftell(obj.fid));
                    end
                otherwise
                    error(['Don''t even know how you got here, but not sure what this file type is: ' obj.MetaTags.FileTypeID])
            end
            obj.duration = obj.datapoints/obj.Fs;
            if length(obj.datapoints) > 1
                obj.isPaused = true;
            end
        end
        
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
        end
        
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
        end
        
    end
    
    methods (Static, Access = protected, Hidden = true)
        
        function c = covEst(mua, spklen)
        % Estimate the covariance in the original signal (adapted and
        % improved from UMS2000 toolbox ? now uses randperm so will not
        % resample the same segment more than once, which is a possibility
        % when using random numbers. Also quicker.)
            num_samples = length(mua);
            max_samples = min(10000, round(num_samples/2));
            waves = NaN(max_samples, spklen);
            inds = randperm(num_samples - spklen, max_samples);
            for j = 1:max_samples
                waves(j,:) = mua(inds(j)+(0:spklen-1));
            end
            c = cov(waves(:,:));
        end
        
        function settings = parseInputs(inputs,settings,methodName)
        % Input parser (matlab has its own now, which is much more powerful
        % than this, but I got into the habit of using my own...)
            if nargin < 3 || isempty(methodName)
                stack = dbstack;
                methodName = stack(2).name;
            end
            allowable = fieldnames(settings);
            if mod(length(inputs),2) ~= 0
                error('Inputs must be in name, value pairs');
            end
            for v = 1:2:length(inputs)
                if find(ismember(allowable,inputs{v}))
                    settings.(inputs{v}) = inputs{v+1};
                else
                    disp([9 'Not assigning ''' inputs{v} ''': not a setting in the ' methodName '() method']);
                end
            end
        end
    end
    
    methods (Static)
        function help(varargin)
        % display help for chosen methods (as many as requested), or for
        % the root class if no inputs
            if nargin < 1
                help NSxFile
            else
                for v = 1:length(varargin)
                   if ismethod(NSxFile,varargin{v})
                       disp(['--- NSxFile method "' varargin{v} '" ---'])
                       help(['NSxFile.' varargin{v}])
                   end
                end
            end
        end
    end
end