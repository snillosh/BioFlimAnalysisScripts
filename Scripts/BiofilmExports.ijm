requires("1.48");

rootDir = getDirectory("Choose a Directory");
setBatchMode(true);
processFiles(rootDir);
setBatchMode(false);

print("Done.");

function processFiles(dir) {
    list = getFileList(dir);

    for (i = 0; i < list.length; i++) {
        path = dir + list[i];

        if (endsWith(list[i], "/")) {
            processFiles(path);
        } else if (endsWith(toLowerCase(path), ".czi")) {
            processFile(path);
        }
    }
}

function processFile(path) {
    print("Processing: " + path);

    // Setup paths
    parentDir = getParentDir(path);
    exportsDir = parentDir + "Exports" + File.separator;
    File.makeDirectory(exportsDir);

    fileName = getFileName(path);              // D5 2.czi
    baseName = stripExtension(fileName);       // D5 2
    safeName = replace(baseName, " ", "_");    // D5_2

    maxPath = exportsDir + safeName + ".tif";
    volumePath = exportsDir + safeName + "_Volume.tif";

    // Open (no popup)
    run("Bio-Formats Importer", "open=[" + path + "] autoscale color_mode=Default view=Hyperstack stack_order=XYCZT");

    original = getTitle();

    // ---- Max projection pipeline ----
    run("Green");
    run("Red");

    run("Z Project...", "projection=[Max Intensity]");
    maxTitle = getTitle();

    run("Split Channels");

    c1Max = "C1-" + maxTitle;
    c2Max = "C2-" + maxTitle;

    run("Merge Channels...", "c1=[" + c2Max + "] c2=[" + c1Max + "]");
    rgbMax = getTitle();

    saveAs("Tiff", maxPath);
    close(); // close RGB

    // cleanup max stuff
    closeIfOpen(c2Max);
    closeIfOpen(c1Max);
    closeIfOpen(maxTitle);

    // ---- Volume viewer pipeline ----
    selectWindow(original);
    run("Split Channels");

    c1 = "C1-" + original;
    c2 = "C2-" + original;

    run("Merge Channels...", "c1=[" + c2 + "] c2=[" + c1 + "]");
    rgb = getTitle();

    run("Volume Viewer");

    // usually "Volume_Viewer_1"
    if (isOpen("Volume_Viewer_1")) {
        selectWindow("Volume_Viewer_1");
        saveAs("Tiff", volumePath);
        close();
    }

    // cleanup
    closeIfOpen(rgb);
    closeIfOpen(c2);
    closeIfOpen(c1);
    closeIfOpen(original);
}

function closeIfOpen(title) {
    if (isOpen(title)) {
        selectWindow(title);
        close();
    }
}

function getParentDir(path) {
    sep = File.separator;
    i = lastIndexOf(path, sep);
    return substring(path, 0, i + 1);
}

function getFileName(path) {
    sep = File.separator;
    i = lastIndexOf(path, sep);
    return substring(path, i + 1);
}

function stripExtension(name) {
    i = lastIndexOf(name, ".");
    if (i < 0) return name;
    return substring(name, 0, i);
}