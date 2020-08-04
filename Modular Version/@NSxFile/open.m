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
