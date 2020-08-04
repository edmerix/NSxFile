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