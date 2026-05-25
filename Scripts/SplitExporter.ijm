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
    exportsDir = parentDir + "split exports" + File.separator;
    File.makeDirectory(exportsDir);

    fileName = getFileName(path);
    baseName = stripExtension(fileName);
    safeName = replace(baseName, " ", "_");

    run("Bio-Formats Importer", "open=[" + path + "] autoscale color_mode=Default view=Hyperstack stack_order=XYCZT");

    original = getTitle();

    run("Blue");
    run("Green");
    run("Red");

    // ---- Max projection split-channel exports ----
    run("Z Project...", "projection=[Max Intensity]");
    maxTitle = getTitle();

    run("Split Channels");

    redMax = "C3-" + maxTitle;
    greenMax = "C2-" + maxTitle;
    blueMax = "C1-" + maxTitle;

    saveChannel(redMax, "Red", exportsDir + "Red" + safeName + ".tif");
    saveChannel(greenMax, "Green", exportsDir + "Green" + safeName + ".tif");
    saveChannel(blueMax, "Blue", exportsDir + "Blue" + safeName + ".tif");

    closeIfOpen(maxTitle);

    // ---- Volume Viewer split-channel exports ----
    selectWindow(original);
    run("Split Channels");

    red = "C3-" + original;
    green = "C2-" + original;
    blue = "C1-" + original;

    saveVolume(red, "Red", exportsDir + "Red" + safeName + "Volume_Viewer_1.tif");
    saveVolume(green, "Green", exportsDir + "Green" + safeName + "Volume_Viewer_1.tif");
    saveVolume(blue, "Blue", exportsDir + "Blue" + safeName + "Volume_Viewer_1.tif");

    closeIfOpen(original);
}

function saveChannel(title, lut, outputPath) {
    if (isOpen(title)) {
        selectWindow(title);
        run(lut);
        saveAs("Tiff", outputPath);
        close();
    } else {
        print("Warning: could not find " + title);
    }
}

function saveVolume(title, lut, outputPath) {
    if (isOpen(title)) {
        selectWindow(title);
        run(lut);
        run("Volume Viewer");

        if (isOpen("Volume_Viewer_1")) {
            selectWindow("Volume_Viewer_1");
            saveAs("Tiff", outputPath);
            close();
        } else {
            print("Warning: Volume_Viewer_1 not found for " + title);
        }

        closeIfOpen(title);
    } else {
        print("Warning: could not find " + title);
    }
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