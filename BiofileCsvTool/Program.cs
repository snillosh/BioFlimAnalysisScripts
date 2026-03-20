using System.Globalization;
using System.Text;

var desiredColumns = new[]
{
    "Biomass (µm^3/µm^2)",
    "Roughness Coefficient (Ra*)",
    "Surface Area (µm^2)",
    "Surface to biovolume ratio (µm^2/µm^3)",
    "Average thickness (Entire area) (µm)",
    "Average thickness (Biomass) (µm)"
};

var extraColumns = new[]
{
    "Live",
    "Dead",
    "DEAD/LIVE ratio"
};

if (args.Length == 0)
{
    Console.WriteLine("Usage:");
    Console.WriteLine("  MyApp <root_directory> [--output <output.csv>]");
    return;
}

var rootDirectory = args[0];
var outputFile = "output.csv";

for (int i = 1; i < args.Length; i++)
{
    if (args[i] == "--output" && i + 1 < args.Length)
    {
        outputFile = args[i + 1];
        i++;
    }
}

if (!Directory.Exists(rootDirectory))
{
    Console.WriteLine($"Directory does not exist: {rootDirectory}");
    return;
}

var allData = CollectDataFromDirectory(rootDirectory, desiredColumns);
WriteCsv(allData, outputFile, desiredColumns, extraColumns);

Console.WriteLine($"CSV file created at {outputFile}");

static Dictionary<string, Dictionary<string, string>> ParseFile(
    string filePath,
    HashSet<string> desiredColumns)
{
    var imageData = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
    string? currentImage = null;

    foreach (var line in File.ReadLines(filePath))
    {
        var parts = line.Split(':', 2);
        if (parts.Length != 2)
            continue;

        var key = parts[0].Trim();
        var value = parts[1].Trim();

        if (key.Equals("image name", StringComparison.OrdinalIgnoreCase))
        {
            currentImage = value;

            if (!imageData.ContainsKey(currentImage))
            {
                imageData[currentImage] = new Dictionary<string, string>(StringComparer.Ordinal);
            }
        }
        else if (currentImage is not null && desiredColumns.Contains(key))
        {
            imageData[currentImage][key] = value;
        }
    }

    return imageData;
}

static Dictionary<string, Dictionary<string, string>> CollectDataFromDirectory(
    string rootDirectory,
    IEnumerable<string> desiredColumns)
{
    var mergedData = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
    var desiredSet = new HashSet<string>(desiredColumns, StringComparer.Ordinal);

    foreach (var file in Directory.EnumerateFiles(rootDirectory, "*.txt", SearchOption.AllDirectories))
    {
        var fileData = ParseFile(file, desiredSet);

        foreach (var (imageName, props) in fileData)
        {
            if (!mergedData.TryGetValue(imageName, out var existingProps))
            {
                existingProps = new Dictionary<string, string>(StringComparer.Ordinal);
                mergedData[imageName] = existingProps;
            }

            foreach (var (key, value) in props)
            {
                existingProps[key] = value;
            }
        }
    }

    return mergedData;
}

static string ExtractBaseName(string imageName)
{
    var parts = imageName.Split(':', 2);
    return parts[0].Trim();
}

static (string? Live, string? Dead) FindChannelValues(
    Dictionary<string, Dictionary<string, string>> imageData,
    string baseName)
{
    string? live = null;
    string? dead = null;

    foreach (var (name, props) in imageData)
    {
        if (!name.StartsWith(baseName, StringComparison.Ordinal))
            continue;

        if (name.Contains("#1 ch1", StringComparison.Ordinal))
        {
            props.TryGetValue("Biomass (µm^3/µm^2)", out live);
        }
        else if (name.Contains("#1 ch2", StringComparison.Ordinal))
        {
            props.TryGetValue("Biomass (µm^3/µm^2)", out dead);
        }
    }

    return (live, dead);
}

static string SafeDivide(string? numerator, string? denominator)
{
    if (!double.TryParse(numerator, NumberStyles.Float, CultureInfo.InvariantCulture, out var num))
        return string.Empty;

    if (!double.TryParse(denominator, NumberStyles.Float, CultureInfo.InvariantCulture, out var den))
        return string.Empty;

    if (den == 0)
        return string.Empty;

    return (num / den).ToString(CultureInfo.InvariantCulture);
}

static void WriteCsv(
    Dictionary<string, Dictionary<string, string>> imageData,
    string outputFile,
    string[] desiredColumns,
    string[] extraColumns)
{
    var fieldNames = new List<string> { "Image Name" };
    fieldNames.AddRange(desiredColumns);
    fieldNames.AddRange(extraColumns);

    using var writer = new StreamWriter(outputFile, false, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));

    writer.WriteLine(string.Join(",", fieldNames.Select(EscapeCsv)));

    foreach (var (imageName, props) in imageData)
    {
        if (!imageName.EndsWith("null ch1", StringComparison.Ordinal))
            continue;

        var baseName = ExtractBaseName(imageName);
        var (live, dead) = FindChannelValues(imageData, baseName);
        var ratio = SafeDivide(dead, live);

        var row = new List<string>
        {
            imageName
        };

        foreach (var col in desiredColumns)
        {
            row.Add(props.TryGetValue(col, out var value) ? value : string.Empty);
        }

        row.Add(live ?? string.Empty);
        row.Add(dead ?? string.Empty);
        row.Add(ratio);

        writer.WriteLine(string.Join(",", row.Select(EscapeCsv)));
    }
}

static string EscapeCsv(string? value)
{
    value ??= string.Empty;

    if (value.Contains('"'))
    {
        value = value.Replace("\"", "\"\"");
    }

    if (value.Contains(',') || value.Contains('"') || value.Contains('\n') || value.Contains('\r'))
    {
        value = $"\"{value}\"";
    }

    return value;
}