# NSxFile

NSxFile is an object-oriented approach to working with [Blackrock Microsystems](https://www.blackrockmicro.com) neural data files (e.g. ns3, ns5 etc.) in Matlab.

This was developed for a couple of reasons:
* Object-oriented classes allow for smoother interaction with files:
  - Fast reading of header without closing file access;
  - Ability to dip in and out of file data as needed
* Modular extensibility:
  - Switch between options within the object itself during read-time;
  - Load extra functionality as needed _(e.g. spike extraction and export to [UMS2000](https://github.com/danamics/UMS2K) format is built-in, and writing new modules is as simple as adding a new method)_
  
The basic reading of the data structure builds on Blackrock's original [openNSx.m](https://github.com/BlackrockMicrosystems/NPMK/blob/master/NPMK/openNSx.m) in the [NPMK](https://github.com/BlackrockMicrosystems/NPMK) toolbox, and updates the methods to run in an object-oriented manner.

### Quick start

Two versions are included: an "inline" one with all code in a single file ([NSxFile.m](NSxFile.m)); and a "modular" version, with extra methods in their own files in a Matlab class directory ([@NSxFile](Modular%20Version/%40NSxFile)).

Only one is needed: 
For basic usage, go for the [inline code](NSxFile.m);
For an easily modifiable version, in order to add your own methods, go for the [modular one](Modular%20Version/%40NSxFile).

Using either, basic usage to load a file called "example.ns5" is:
```Matlab
% short-hand to immediately read the header of a file and store a handle to it:
nsx = NSxFile('filename','example.ns5');
% the nsx variable now contains various information about the file, such as the sampling frequency, electrode labels, duration, and date of recording, both in UTC and local time.

% Alternatively:
nsx = NSxFile();
nsx.read('example.ns5');
% In either method, a handle to the file to read extra data will be stored in the object, and the file is only ever opened in read-only mode for data peace-of-mind.

% Now read the data from channels 1, 4 and 20, between 200 and 320 seconds:
nsx.read('channels',[1 4 20],'time',[200 320]);
% The requested data are now in nsx.data.
% To read the data from all channels and all times, simply call:
nsx.read();

% Let's extract spikes automatically from channels 4 and 20, using the default settings:
nsx.detectSpikes('channels',[4 20]);
% and now export them to a UMS2k style structure:
spikes = nsx.exportSpikesUMS('channels',[4 20]);

% Now let's read just channels 64 and 73, but take advantage of the ability to not load the whole file into RAM in order to do so (this is slower, but enables loading very large files on machines with less available memory), and tell the function to print more feedback while it's processing:
nsx.useRAM = false;
nsx.verbose = true;
nsx.read('channels',[64 73]);
% and now quickly export all channels that have been read into a UMS2k structure:
spikes = nsx.exportSpikesUMS();
% without arguments, this will run on all loaded channels, and if a channel hasn't had spike detection run on it already, it will do so seamlessly now.

% We can now move onto spike sorting the spikes data however we wish (the original detections are in nsx.spikes, so needn't be a UMS2k export), so let's close the file:
nsx.close();
```

### Properties

Accessible properties within an NSxFile object are:

| Name | Description |
| ------ | ------ |
| filename | Name of the open file |
| data | Raw neural data, once read |
| spikes | Extracted single unit data, once detected |
| MetaTags | Meta information for the file |
| Fs | Sampling frequency of the data |
| date | Start time of the recording in UTC |
| date_local | Start time of the recording converted to NSxFile.timezone |
| timezone | The timezone the file was recorded in (defaults to NYC) |
| duration | vector of the durations of each segment in the file in seconds |
| datapoints | vector of the raw number of data points (duration * Fs) |
| channels | array of channel numbers in the file |
| electrodelabels | cell array of each electrode's name |
| electrodeinfo | struct array of recording data for each electrode |
| useRAM | flag to signify whether or not to use RAM during read |
| verbose | flag to signify whether or not to print extra info to screen |

### Methods:

To see all available methods you can run on the file, run:

``` Matlab
methods('NSxFile')
```

### Help:

To see a basic overview for usage, run:
``` Matlab
help('NSxFile')
```
or to see specific help for methods, run:
``` Matlab
help('NSxFile.read')
```
or
``` Matlab
NSxFile.help('read','open','detectSpikes')
```
to see the documentation for multiple methods at once.
