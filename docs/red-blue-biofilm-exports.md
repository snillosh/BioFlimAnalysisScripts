# Red/blue biofilm exports

In Fiji, choose **Plugins > Macros > Run...**, open
`Scripts/RedBlueBiofilmExports.ijm`, and select the folder containing your CZI
files. Bio-Formats and Volume Viewer must be installed.

The macro processes CZI files directly inside that folder (not subfolders).
It uses `open(path)`, as in the original recording, rather than supplying
Bio-Formats import options. Your normal opening settings apply; an import dialog
may appear. Configure the importer to open one series as one two-channel stack.
Each stack must have exactly two channels,
one time point, and at least two Z slices. Unsupported stacks are skipped with
a message in the Log window.

The image-processing commands follow the original recording: `Blue`, `Red`,
maximum-intensity Z projection, channel splitting, and merging with channel 2
in the red slot and channel 1 in the blue slot. No new contrast, autoscale,
threshold, LUT inversion, or projection-range settings are applied.

Outputs:

- `exports/D7_2.tif`: RGB maximum-intensity Z projection.
- `exports/D7_2_Volume_Viewer.tif`: RGB image of the rendered volume.

The volume export is a rendered view, not a copy of the original 3D stack.
Before running the macro, open Volume Viewer manually, configure the view as
desired, then close the Volume Viewer window so the plugin saves its preferences.
The macro calls `run("Volume Viewer")` without options, matching the recorded
workflow and loading those saved preferences. ImageJ batch mode makes the plugin
return a rendered image automatically, without pausing for each file.

Do not add an options string to that call: Volume Viewer bypasses its saved
preferences whenever macro options are supplied. Unspecified settings then use
plugin defaults, including a blue background. See the source included in the
[official Volume Viewer plugin](https://imagej.net/ij/plugins/volume-viewer).
The macro does not force Bio-Formats autoscaling or a colour mode. These are
controlled by your normal import settings. Display adjustments on an already
open image are not automatically transferred by ImageJ to newly opened files.

If either output already exists, the file is skipped. To rerun it, move or
delete its existing outputs first. If an importer or plugin error stops the
macro, inspect the error and any open intermediate images before rerunning.

The macro has been reviewed statically; it still needs a trial run in Fiji
with representative CZI data to verify the installed plugins and rendering.
