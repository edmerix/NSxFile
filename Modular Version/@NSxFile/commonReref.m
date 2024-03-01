function commonReref(obj,varargin)
% Common re-reference. Help to be written soon.
%

if isempty(obj.data)
    error('Need to read data from the file first')
end

settings = [];
settings.groupSize = Inf;
settings.convertUnits = true;
settings.ignoreElectrodes = {'ainp1','ainp2','pulses','digin'};

settings = obj.parseInputs(varargin,settings);

disp('Centering each channel')
for d = 1:length(obj.data)
    obj.data{d} = double(obj.data{d});
    obj.data{d} = obj.data{d} - nanmean(obj.data{d},2);
end

ignoring = contains(obj.electrodeLabels,settings.ignoreElectrodes);
loadedElecs = obj.electrodeLabels(obj.loadedChannels);
ignoringLoaded = ignoring(obj.loadedChannels);

if settings.groupSize < length(obj.loadedChannels)
    banks = loadedElecs;
    for b = 1:length(banks)
        banks{b}(regexp(banks{b},'[\d]')) = [];
    end
    bank_opts = unique(banks);
    grps = zeros(1,length(loadedElecs));

    disp(['Found ' num2str(length(bank_opts)) ' banks:'])
    for b = 1:length(bank_opts)
        disp([9 'Bank "' bank_opts{b} '":'])
        grps(strcmp(banks,bank_opts{b})) = b;
        disp([9 9 strjoin(loadedElecs(grps == b),'\n\t\t')]);
        if length(find(grps == b)) == settings.groupSize
            disp([9 9 'Subtracting mean now...'])
            if ~isempty(loadedElecs(grps == b & ignoringLoaded))
                disp([9 9 '(Ignoring ' strjoin(loadedElecs(grps == b & ignoringLoaded),', ') ')'])
            end
            for d = 1:length(obj.data)
                mnVal = nanmean(obj.data{d}(grps == b & ~ignoringLoaded,:));
                obj.data{d}(grps == b & ~ignoringLoaded,:) = obj.data{d}(grps == b & ~ignoringLoaded,:) - mnVal;
                disp([9 9 '...done data segment ' num2str(d) ' of ' num2str(length(obj.data))]);
            end
        else
            disp([9 9 'Not a group of ' num2str(settings.groupSize) ', not subtracting means'])
        end
    end
else
    disp('Subtracting mean of all channels, ignoring channels in ''ignoreElectrodes'' field')
    bueno = ones(1,length(loadedElecs));
    for i = 1:length(settings.ignoreElectrodes)
        bueno(strcmpi(loadedElecs,settings.ignoreElectrodes{i})) = 0;
    end
    for d = 1:length(obj.data)
        mnVal = nanmean(obj.data{d}(bueno,:));
        obj.data{d}(bueno,:) = obj.data{d}(bueno,:) - mnVal;
    end
end

if settings.convertUnits
    disp('Converting units to microvolts')
    % note that this will run afoul if no electrode labels, just channel 
    % numbers, which I think happens on old CKI files, but then they don't 
    % need dividing anyway.
    for e = 1:length(obj.loadedChannels)
        if ~isempty(obj.electrodeInfo)
            overRes = double(obj.electrodeInfo(obj.loadedChannels(e)).DigitalRange(2)) ...
                / double(obj.electrodeInfo(obj.loadedChannels(e)).AnalogRange(2));
            if overRes ~= round(overRes)
                disp(['Electrode ' obj.electrodeLabels{obj.loadedChannels(e)} ...
                    ' has a weird digital:analog ratio (' ...
                    num2str(overRes) '), not converting to uV']);
            else
                for d = 1:length(obj.data)
                    obj.data{d}(e,:) = obj.data{d}(e,:) / overRes;
                end
            end
        end
    end
end