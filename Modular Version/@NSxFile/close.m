function close(obj)
% close handle to file (use when done loading specific data etc.)
fclose(obj.fid);
obj.isOpen = false;
% What a short file... Kept it modular to be same as rest, and maybe other
% actions will be useful when closing the file at a later date...?