// Fiji/ImageJ: batch-export two-channel CZI stacks in the selected folder.
// Requires Bio-Formats and Volume Viewer (as included with Fiji).
// Uses the normal ImageJ opening route and its remembered import settings.
// Expects one opened stack with exactly two channels, one time point,
// and at least two Z slices. Subfolders are not processed.
// Output: exports/<name>.tif and exports/<name>_Volume_Viewer.tif.
// Existing outputs are never overwritten: if either exists, skip that file.
// Volume Viewer macro parameters: https://imagej.net/ij/plugins/volume-viewer
requires("1.48");

// Volume Viewer must be called WITHOUT options: supplying any options bypasses
// its saved preferences, including background, viewing angle and render mode.
// Configure Volume Viewer manually and close its window to save preferences
// before running this macro. Batch mode still renders without interaction.

rootDir = getDirectory("Choose the folder containing CZI stacks");
exportsDir = rootDir + "exports" + File.separator;
File.makeDirectory(exportsDir);
if (!File.isDirectory(exportsDir)) exit("Could not create: " + exportsDir);
files = getFileList(rootDir);
Array.sort(files);
processed = 0;
skipped = 0;
setBatchMode(true);

for (i = 0; i < files.length; i++) {
    if (!endsWith(toLowerCase(files[i]), ".czi")) continue;
    if (File.isDirectory(rootDir + files[i])) continue;
    base = substring(files[i], 0, lengthOf(files[i]) - 4);
    projectionPath = exportsDir + base + ".tif";
    volumePath = exportsDir + base + "_Volume_Viewer.tif";
    if (File.exists(projectionPath) || File.exists(volumePath)) {
        print("Skipped (output already exists): " + files[i]);
        skipped++;
        continue;
    }

    showStatus("Exporting " + files[i]);
    print("Processing: " + rootDir + files[i]);
    // Match the recording: do not override import options or force autoscaling.
    // Depending on remembered Bio-Formats settings, an import dialog may appear.
    open(rootDir + files[i]);
    sourceID = getImageID();
    getDimensions(w, h, channels, slices, frames);
    if (channels != 2 || frames != 1 || slices < 2) {
        print("Skipped (requires 2 channels, 1 time point and >=2 Z slices): " + files[i]);
        close();
        skipped++;
        continue;
    }

    // Unique intermediate titles avoid collisions with other open images.
    sourceTitle = "RBExport_" + sourceID;
    rename(sourceTitle);
    // These LUT commands are part of the original working recording.
    run("Blue");
    run("Red");
    run("Z Project...", "projection=[Max Intensity]");
    projectionTitle = "RBProjection_" + sourceID;
    rename(projectionTitle);
    run("Split Channels");
    // Merge without 'create' produces an RGB image/stack: C2 red, C1 blue.
    run("Merge Channels...", "c1=[C2-" + projectionTitle + "] c3=[C1-" + projectionTitle + "]");
    saveAs("Tiff", projectionPath);
    close();

    selectImage(sourceID);
    run("Split Channels");
    run("Merge Channels...", "c1=[C2-" + sourceTitle + "] c3=[C1-" + sourceTitle + "]");
    rgbID = getImageID();
    // Match the recorded workflow and load the user's saved viewer preferences.
    // Volume Viewer detects ImageJ batch mode and returns a rendered view image.
    run("Volume Viewer");
    if (getImageID() == rgbID)
        exit("Volume Viewer did not return a rendered image for " + files[i]);
    saveAs("Tiff", volumePath);
    close();
    selectImage(rgbID);
    close();
    processed++;
    print("Saved: " + projectionPath);
    print("Saved: " + volumePath);
}

setBatchMode(false);
showStatus("Red/blue exports complete");
print("Done. Exported " + processed + " file(s); skipped " + skipped + ".");
