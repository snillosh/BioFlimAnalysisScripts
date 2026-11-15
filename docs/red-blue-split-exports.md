# Red/blue split exports

Run `Scripts/RedBlueSplitExporter.ijm` in Fiji through
**Plugins > Macros > Run...**, then choose the input folder.
Requires Bio-Formats and Volume Viewer.

This is the two-channel adaptation of `SplitExporter.ijm`. It processes CZI
files in the chosen folder and its subfolders. Source channel 1 is blue and
source channel 2 is red. No channels are merged and no green output is created.

Four TIFF files are saved into `split exports` beside each input. For `D7_2.czi`:

- `BlueD7_2.tif`: channel 1 maximum-intensity projection.
- `RedD7_2.tif`: channel 2 maximum-intensity projection.
- `BlueD7_2Volume_Viewer_1.tif`: channel 1 rendered volume view.
- `RedD7_2Volume_Viewer_1.tif`: channel 2 rendered volume view.

Spaces in the input basename become underscores, matching SplitExporter.
Projection TIFFs retain the individual channel data and its colour lookup table,
matching SplitExporter; rendered volume views are RGB images.

Like the existing exporters, the macro calls Bio-Formats Importer with explicit
options to suppress the import-options dialog: Autoscale enabled, Default colour
mode, Hyperstack view, and XYCZT stack order. These match the confirmed working
import settings; they are supplied by the macro rather than read from the dialog.
Volume Viewer is called without options: configure it manually and close its
window to save preferences before running. The macro applies the requested
red or blue lookup table to each split image before exporting.

As in SplitExporter, the macro uses existing output paths, so move old outputs
elsewhere to retain them. Close any old image named `Volume_Viewer_1` first;
the exporter saves that named window. Missing output windows are logged.

Checked against the existing scripts; not runtime-tested in Fiji with CZI data.
