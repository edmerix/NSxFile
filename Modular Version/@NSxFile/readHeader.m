function readHeader(obj)
% Read the header from the file
if obj.fid < 0 || ~obj.isOpen
    error('No file is open, cannot read header');
end
obj.metaTags = struct();
obj.metaTags.FileTypeID = fread(obj.fid, [1,8], '*char');
switch obj.metaTags.FileTypeID
    case 'NEURALSG'
        obj.metaTags.FileSpec       = '2.1';
        obj.metaTags.SamplingLabel  = deblank(fread(obj.fid, [1,16], '*char'));
        obj.metaTags.TimeRes        = 30000;
        obj.Fs                      = obj.metaTags.TimeRes/fread(obj.fid, 1, 'uint32=>double');
        obj.channels                = double(fread(obj.fid, 1, 'uint32=>double'));
        obj.metaTags.ChannelID      = fread(obj.fid, [obj.channels 1], '*uint32');
    case 'NEURALCD'
        mainHeader = fread(obj.fid, 306, '*uint8');

        obj.metaTags.FileSpec       = [num2str(double(mainHeader(1))) '.' num2str(double(mainHeader(2)))];
        obj.metaTags.SamplingLabel  = deblank(char(mainHeader(7:22))');
        obj.metaTags.Comment        = deblank(char(mainHeader(23:278))');
        obj.metaTags.TimeRes        = double(typecast(mainHeader(283:286), 'uint32'));
        obj.Fs                      = obj.metaTags.TimeRes / double(typecast(mainHeader(279:282), 'uint32'));
        t                           = double(typecast(mainHeader(287:302), 'uint16'));
        obj.channels                = double(typecast(mainHeader(303:306), 'uint32'));

        obj.metaTags.Comment(find(obj.metaTags.Comment==0,1):end) = 0;

        tFormat = t([1 2 4:7])';
        tFormat(end) = tFormat(end) + t(8)/1e3;

        tempdate = datetime(tFormat,'TimeZone','UTC');
        tempdate.Format = 'yyyy/MM/dd HH:mm:ss.SSS Z';
        obj.date = tempdate;
        localtime = tempdate;
        localtime.TimeZone = obj.timezone;
        obj.dateLocal = localtime;

        readSize = double(obj.channels * obj.extHdrLngth);
        extendedHeader = fread(obj.fid, readSize, '*uint8');
        obj.parseExtendedHeader(extendedHeader);
    otherwise
        error(['Unkonwn file type: ' obj.metaTags.FileTypeID])
end
obj.headerEnd = double(ftell(obj.fid));
fseek(obj.fid, 0, 'eof');
obj.fileEnd = double(ftell(obj.fid));

obj.findData();