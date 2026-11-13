# Red/blue biofilm exports

In Fiji, choose **Plugins > Macros > Run...**, open
`Scripts/RedBlueBiofilmExports.ijm`, and select the input folder.
Bio-Formats and Volume Viewer must be installed.

This macro follows `NeutExport.ijm`, adapted for two-channel CZI stacks.
Source channel 2 goes into the red merge slot, source channel 1 into the blue
slot, and no green input is supplied. It runs `Blue` then `Red`, exports the
maximum-intensity projection, then exports the merged stack's Volume Viewer view.

It uses `open(path)` from the original recording rather than forcing
Bio-Formats autoscaling or import colour settings. Your normal import settings
apply; a dialog may appear. Configure opening to produce one two-channel Z-stack
per file. Adjustments made only to another open image are not copied.

Volume Viewer is called without rendering options. Configure it manually and
close its window to save preferences before running the macro.

Like `NeutExport.ijm`, it processes subfolders, creates `Exports` beside each
input file, and replaces spaces in output names with underscores. Outputs:

- `Exports/D7_2.tif`
- `Exports/D7_2_Volume_Viewer_1.tif`

Existing output paths are reused, following the original exporter; move old
results elsewhere to keep them. The Volume Viewer output is a rendered view,
not the original 3D stack. The macro saves the `Volume_Viewer_1` image, matching
the existing exporter. Close any old image with that name before running.
A missing viewer output is reported in the Log.

The adaptation has been checked against the existing macro, but has not been
run in Fiji with representative CZI data.
