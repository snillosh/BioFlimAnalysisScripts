// Batch process all .czi files in a folder and subfolders
// For each .czi file:
// 1. Open it
// 2. Export original to LIVEDEAD as .ome.tif
// 3. Split channels
// 4. Add C1 + C2 into a new stack
// 5. Export result to COMBINED as .ome.tif
// 6. Close everything

requires("1.48");

dir = getDirectory("Choose a Directory");

// Create output folders under the selected root folder
liveDeadDir = dir + "LIVEDEAD" + File.separator;
combinedDir = dir + "COMBINED" + File.separator;

File.makeDirectory(liveDeadDir);
File.makeDirectory(combinedDir);

setBatchMode(true);
processFiles(dir);
setBatchMode(false);

print("Done.");

function processFiles(dir) {
    list = getFileList(dir);

    for (i = 0; i < list.length; i++) {
        path = dir + list[i];

        if (endsWith(list[i], "/")) {
            // Recurse into subfolder
            processFiles(path);
        } else if (endsWith(toLowerCase(path), ".czi")) {
            processFile(path);
        }
    }
}

function processFile(path) {
    print("Processing: " + path);

    run("Bio-Formats Importer", "open=[" + path + "] autoscale color_mode=Default view=Hyperstack stack_order=XYCZT");

    originalTitle = getTitle();              // e.g. "F9 3.czi"
    baseName = replace(originalTitle, ".czi", "");
    safeName = replace(baseName, " ", "_");  // e.g. "F9_3"

    liveDeadPath = liveDeadDir + safeName + ".ome.tif";
    combinedPath = combinedDir + safeName + ".ome.tif";

    // Export original opened file
    run("Bio-Formats Exporter", "save=[" + liveDeadPath + "] compression=Uncompressed");

    // Split channels
    run("Split Channels");

    c1 = "C1-" + originalTitle;
    c2 = "C2-" + originalTitle;

    // Combine C1 and C2
    imageCalculator("Add create stack", c1, c2);

    resultTitle = getTitle(); // usually "Result of C1-..."

    // Export combined image
    selectWindow(resultTitle);
    run("Bio-Formats Exporter", "save=[" + combinedPath + "] compression=Uncompressed");
    close();

    // Close channel windows if they exist
    if (isOpen(c2)) {
        selectWindow(c2);
        close();
    }

    if (isOpen(c1)) {
        selectWindow(c1);
        close();
    }

    // Close original if still open
    if (isOpen(originalTitle)) {
        selectWindow(originalTitle);
        close();
    }
}
