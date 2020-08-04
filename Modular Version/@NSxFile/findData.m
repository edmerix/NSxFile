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