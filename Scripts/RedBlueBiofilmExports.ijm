// Based on NeutExport.ijm for two-channel CZI stacks: C2 red, C1 blue.
// Normal import settings; no Volume Viewer rendering options are supplied.
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

    parentDir = getParentDir(path);
    exportsDir = parentDir + "Exports" + File.separator;
    File.makeDirectory(exportsDir);

    fileName = getFileName(path);              // e.g. B4 1.czi
    baseName = stripExtension(fileName);       // e.g. B4 1
    safeName = replace(baseName, " ", "_");    // e.g. B4_1

    projectionPath = exportsDir + safeName + ".tif";
    volumePath = exportsDir + safeName + "_Volume_Viewer_1.tif";

    // Use the normal opening route and remembered import settings.
    open(path);

    original = getTitle();

    // LUT commands affect the active channel; select each source explicitly.
    Stack.setChannel(1);
    run("Blue");
    Stack.setChannel(2);
    run("Red");

    // ---- Max projection export ----
    run("Z Project...", "projection=[Max Intensity]");
    maxTitle = getTitle();

    run("Split Channels");

    c1Max = "C1-" + maxTitle;
    c2Max = "C2-" + maxTitle;

    run("Merge Channels...", "c1=[" + c2Max + "] c3=[" + c1Max + "]");
    rgbMax = getTitle();

    saveAs("Tiff", projectionPath);
    close();

    closeIfOpen(c2Max);
    closeIfOpen(c1Max);
    closeIfOpen(maxTitle);

    // ---- Volume Viewer export ----
    selectWindow(original);
    run("Split Channels");

    c1 = "C1-" + original;
    c2 = "C2-" + original;

    run("Merge Channels...", "c1=[" + c2 + "] c3=[" + c1 + "]");
    rgb = getTitle();

    run("Volume Viewer");

    if (isOpen("Volume_Viewer_1")) {
        selectWindow("Volume_Viewer_1");
        saveAs("Tiff", volumePath);
        close();
    } else {
        print("Warning: Volume_Viewer_1 not found for " + path);
    }

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
    if (i < 0)
        return name;
    return substring(name, 0, i);
}
