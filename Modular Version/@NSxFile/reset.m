function reset(obj)
% "Un-read" the data, i.e. reset it to not have any channels read
% or spike data extracted, but keep all the header information and
% the handle to the file open if it hasn't been closed.
obj.data = cell(1,0);
obj.spikes = struct();
obj.loadedChannels = [];
obj.readSettings = struct();