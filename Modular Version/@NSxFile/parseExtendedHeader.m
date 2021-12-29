function parseExtendedHeader(obj,extHdr)
% Sort out the extended header data if the file has any
obj.electrodeInfo = struct();
obj.electrodeLabels = cell(1,obj.channels);
filtTypes = {'None','Butterworth'};
for i = 1:obj.channels
    offset = double((i-1)*obj.extHdrLngth);
    obj.electrodeInfo(i).Type = char(extHdr((1:2)+offset))';

    if ~strcmpi(obj.electrodeInfo(i).Type, 'CC')
        warning(['Attempted to read extended header on channel' num2str(i) ', but electrode type was not CC'])
    else
        obj.electrodeInfo(i).ElectrodeID        = typecast(extHdr((3:4)+offset), 'uint16');
        obj.electrodeLabels{i}                  = deblank(char(extHdr((5:20)+offset))');
        obj.electrodeInfo(i).ConnectorBank      = deblank(char(extHdr(21+offset) + ('A' - 1)));
        obj.electrodeInfo(i).ConnectorPin       = extHdr(22+offset);
        obj.electrodeInfo(i).DigitalRange(1)    = typecast(extHdr((23:24)+offset), 'int16');
        obj.electrodeInfo(i).DigitalRange(2)    = typecast(extHdr((25:26)+offset), 'int16');
        obj.electrodeInfo(i).AnalogRange(1)     = typecast(extHdr((27:28)+offset), 'int16');
        obj.electrodeInfo(i).AnalogRange(2)     = typecast(extHdr((29:30)+offset), 'int16');
        obj.electrodeInfo(i).AnalogUnits        = deblank(char(extHdr((31:46)+offset))');
        obj.electrodeInfo(i).HighFreqCorner     = typecast(extHdr((47:50)+offset), 'uint32');
        obj.electrodeInfo(i).HighFreqOrder      = typecast(extHdr((51:54)+offset), 'uint32');
        obj.electrodeInfo(i).HighFilterType     = filtTypes{typecast(extHdr((55:56)+offset), 'uint16')+1};
        obj.electrodeInfo(i).LowFreqCorner      = typecast(extHdr((57:60)+offset), 'uint32');
        obj.electrodeInfo(i).LowFreqOrder       = typecast(extHdr((61:64)+offset), 'uint32');
        obj.electrodeInfo(i).LowFilterType      = filtTypes{typecast(extHdr((65:66)+offset), 'uint16')+1};
    end
end