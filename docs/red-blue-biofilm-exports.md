# Red/blue biofilm exports

In Fiji, choose **Plugins > Macros > Run...**, open
`Scripts/RedBlueBiofilmExports.ijm`, and select the folder containing your CZI
files. Bio-Formats and Volume Viewer must be installed.

The macro processes CZI files directly inside that folder (not subfolders),
using the first series in each file. Each stack must have exactly two channels,
one time point, and at least two Z slices. Unsupported stacks are skipped with
a message in the Log window.

Channel 2 becomes red and channel 1 becomes blue in both outputs:

- `exports/D7_2.tif`: RGB maximum-intensity Z projection.
- `exports/D7_2_Volume_Viewer.tif`: RGB image of the rendered volume.

The volume export is a rendered view, not a copy of the original 3D stack.
All files use the same rendering parameters in `volumeOptions` near the top of
the macro. Bio-Formats autoscales the imported display ranges per image.
Rendering parameters follow the
[Volume Viewer macro interface](https://imagej.net/ij/plugins/volume-viewer).

If either output already exists, the file is skipped. To rerun it, move or
delete its existing outputs first. If an importer or plugin error stops the
macro, inspect the error and any open intermediate images before rerunning.

The macro has been reviewed statically; it still needs a trial run in Fiji
with representative CZI data to verify the installed plugins and rendering.
