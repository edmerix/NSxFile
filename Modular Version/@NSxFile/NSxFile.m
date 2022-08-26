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
%       dateLocal:      Date converted to local time (set nsx.timezone
%                        first, according to where the file was recorded)
%       electrodeLabels: Labels for each channel
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
%   E. M. Merricks, Ph.D. 2020-03-07 <MODULAR_VERSION>

classdef (CaseInsensitiveProperties=true, TruncatedProperties=true) NSxFile < handle
    properties
        filename                char
        data            (1,:)   cell
        spikes          (1,:)   struct
        metaTags                struct
        Fs              (1,1)   double
        date                    datetime
        dateLocal               datetime
        timezone                char        = 'America/New_York';
        duration        (1,:)   double
        datapoints      (1,:)   double
        channels        (1,1)   double
        loadedChannels  (1,:)   double
        electrodeLabels         cell
        electrodeInfo           struct
        useRAM          (1,1)   logical     = true
        verbose         (1,1)   logical     = false
    end

    properties (SetAccess = private, Hidden = true)
        cleanup
        fid = -1
        isOpen = false
        isPaused = false
        extHdrLngth = 66;

        headerEnd = NaN
        fileEnd = NaN
        dataStart = NaN
        dataEnd = NaN

        readSettings = struct()
    end

    methods

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%%%%%%%%%% Constructor/Destructor %%%%%%%%%%%%
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        function obj = NSxFile(varargin)
        % Constructor method.
        % Run NSXFile.help for more info.
            obj.cleanup = onCleanup(@()delete(obj));
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

        function delete(obj)
        % Destructor method
            if obj.isOpen
                fclose(obj.fid);
            end
        end

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%%%% Define new modules you write here: %%%%%%
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        open(obj,filename);
        read(obj,varargin);
        close(obj);
        %filter(obj,varargin);
        commonReref(obj,varargin);
        detectSpikes(obj,varargin);
        spikes = exportSpikesUMS(obj,varargin);
        hfig = plot(obj,varargin);

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % TEMPORARY FUNCTIONS TO SEMI-DUPLICATE OLD NAMING VERSIONS: %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function res = electrodelabels(obj)
            warning('NSxFile:oldNaming','Naming has been updated to "camelCase", "electrodelabels" will be deprecated in a future release, please use "electrodeLabels" instead')
            res = obj.electrodeLabels;
        end

        function res = electrodeinfo(obj)
            warning('NSxFile:oldNaming','Naming has been updated to "camelCase", "electrodeinfo" will be deprecated in a future release, please use "electrodeInfo" instead')
            res = obj.electrodeInfo;
        end

        function res = date_local(obj)
            warning('NSxFile:oldNaming','Naming has been updated to "camelCase", "date_local" will be deprecated in a future release, please use "dateLocal" instead')
            res = obj.dateLocal;
        end

        function res = MetaTags(obj)
            warning('NSxFile:oldNaming','Naming has been updated to "camelCase", "MetaTags" will be deprecated in a future release, please use "metaTags" instead')
            res = obj.metaTags;
        end
        % End of temporary deprecated naming functions. These will be removed in a future update.
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%% Internal, private methods: %%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods (Access = protected, Hidden = true)
        readHeader(obj);
        parseExtendedHeader(obj,extHdr);
        findData(obj);
        calculateSegments(obj);
        readData(obj);
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%% Static, hidden methods: %%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%%% Wrapper for help info: %%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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
