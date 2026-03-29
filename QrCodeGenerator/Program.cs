using System;
using System.Drawing;
using System.IO;
using System.Text.RegularExpressions;
using QRCoder;

internal static class Program
{
    static void Main()
    {
        PrintStep("QR Code Generator");
        PrintInfo("This tool creates a QR code PNG for a website.");

        string website = PromptWebsite();
        string mainColor = PromptColor(
            "Main QR Code Color",
            "Enter the main QR code color.",
            "You can use a color name like black, navy, red, or white.",
            "You can also use a hex code like #000000, #1E90FF, or #ffffff."
        );

        string backgroundColor = PromptColor(
            "Background Color",
            "Enter the background color.",
            "You can use a color name like white, beige, black, or lightgray.",
            "You can also use a hex code like #ffffff or #f5f5f5."
        );

        WarnIfContrastMayBePoor(mainColor, backgroundColor);

        string savePath = PromptSavePath();

        PrintStep("Generating QR Code");

        try
        {
            using var generator = new QRCodeGenerator();
            using QRCodeData data = generator.CreateQrCode(website, QRCodeGenerator.ECCLevel.Q);

            var pngQr = new PngByteQRCode(data);
            byte[] pngBytes = pngQr.GetGraphic(
                pixelsPerModule: 20,
                darkColor: ParseColor(mainColor),
                lightColor: ParseColor(backgroundColor),
                drawQuietZones: true
            );

            File.WriteAllBytes(savePath, pngBytes);

            PrintSuccess("QR code generated successfully.");
            PrintInfo($"Saved to: {savePath}");
            PrintInfo($"QR code points to: {website}");
        }
        catch (Exception ex)
        {
            PrintError("Something went wrong while generating the QR code.");
            PrintError(ex.Message);
            Environment.Exit(1);
        }

        PrintSeparator();
    }

    static string PromptWebsite()
    {
        while (true)
        {
            PrintStep("Website");
            PrintInfo("Enter the website address the QR code should open.");
            PrintInfo("Make sure to include https:// or http:// at the beginning.");
            PrintInfo("Example: https://example.com");
            Console.Write("Website: ");

            string? input = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(input))
            {
                PrintError("Please enter a website.");
                continue;
            }

            if (!Uri.TryCreate(input, UriKind.Absolute, out Uri? uri))
            {
                PrintError("That is not a valid URL. Please try again.");
                continue;
            }

            if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps)
            {
                PrintError("Please use a URL starting with http:// or https://");
                continue;
            }

            PrintSuccess("Website accepted.");
            return input;
        }
    }

    static string PromptColor(string sectionTitle, string line1, string line2, string line3)
    {
        while (true)
        {
            PrintStep(sectionTitle);
            PrintInfo(line1);
            PrintInfo(line2);
            PrintInfo(line3);
            Console.Write("Color: ");

            string? input = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(input))
            {
                PrintError("Please enter a color.");
                continue;
            }

            if (TryParseColor(input, out _))
            {
                PrintSuccess("Color accepted.");
                return input;
            }

            PrintError($"'{input}' is not a recognized color.");
            PrintError("Please enter a valid color name or hex code.");
        }
    }

    static string PromptSavePath()
    {
        while (true)
        {
            PrintStep("Save Location");
            PrintInfo("Enter the file path where the QR code PNG should be saved.");
            PrintInfo(@"Example: C:\Users\YourName\Desktop\qrcode.png");
            PrintInfo("If you leave off .png, it will be added automatically.");
            PrintInfo("Press Enter to save as 'qrcode.png' in the current folder.");
            Console.Write("Save path: ");

            string? path = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(path))
            {
                string defaultPath = Path.Combine(Directory.GetCurrentDirectory(), "qrcode.png");
                PrintSuccess($"Using default save path: {defaultPath}");
                return defaultPath;
            }

            if (!path.EndsWith(".png", StringComparison.OrdinalIgnoreCase))
            {
                path += ".png";
            }

            try
            {
                string? directory = Path.GetDirectoryName(path);

                if (!string.IsNullOrWhiteSpace(directory) && !Directory.Exists(directory))
                {
                    PrintError("That folder does not exist. Please choose an existing folder.");
                    continue;
                }

                PrintSuccess("Save path accepted.");
                return path;
            }
            catch
            {
                PrintError("That path is not valid. Please try again.");
            }
        }
    }

    static bool TryParseColor(string input, out Color color)
    {
        color = default;

        try
        {
            if (Regex.IsMatch(input, @"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$"))
            {
                color = ColorTranslator.FromHtml(input);
                return true;
            }

            color = Color.FromName(input);

            if (!color.IsKnownColor && !color.IsNamedColor)
                return false;

            if (color.ToArgb() == 0 &&
                !string.Equals(input, "Black", StringComparison.OrdinalIgnoreCase) &&
                !string.Equals(input, "Transparent", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            return true;
        }
        catch
        {
            return false;
        }
    }

    static Color ParseColor(string input)
    {
        if (!TryParseColor(input, out Color color))
            throw new ArgumentException($"Invalid color: {input}");

        return color;
    }

    static void WarnIfContrastMayBePoor(string darkColorInput, string lightColorInput)
    {
        if (!TryParseColor(darkColorInput, out Color dark) || !TryParseColor(lightColorInput, out Color light))
            return;

        double darkLum = RelativeLuminance(dark);
        double lightLum = RelativeLuminance(light);

        double brighter = Math.Max(darkLum, lightLum);
        double darker = Math.Min(darkLum, lightLum);
        double contrast = (brighter + 0.05) / (darker + 0.05);

        if (contrast < 3.0)
        {
            PrintStep("Contrast Warning");
            PrintWarning("Those colors have low contrast.");
            PrintWarning("Some phones may struggle to scan the QR code.");
            PrintWarning("Dark-on-light combinations usually work best.");
        }
    }

    static double RelativeLuminance(Color c)
    {
        static double Channel(double v)
        {
            v /= 255.0;
            return v <= 0.03928 ? v / 12.92 : Math.Pow((v + 0.055) / 1.055, 2.4);
        }

        double r = Channel(c.R);
        double g = Channel(c.G);
        double b = Channel(c.B);

        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    static void PrintSeparator()
    {
        Console.ResetColor();
        Console.WriteLine(new string('-', 60));
    }

    static void PrintStep(string title)
    {
        var oldColor = Console.ForegroundColor;

        Console.WriteLine();
        PrintSeparator();
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine(title);
        Console.ForegroundColor = oldColor;
        PrintSeparator();
    }

    static void PrintInfo(string message)
    {
        Console.ResetColor();
        Console.WriteLine(message);
    }

    static void PrintSuccess(string message)
    {
        var oldColor = Console.ForegroundColor;
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine(message);
        Console.ForegroundColor = oldColor;
    }

    static void PrintError(string message)
    {
        var oldColor = Console.ForegroundColor;
        Console.ForegroundColor = ConsoleColor.Red;
        Console.WriteLine(message);
        Console.ForegroundColor = oldColor;
    }

    static void PrintWarning(string message)
    {
        var oldColor = Console.ForegroundColor;
        Console.ForegroundColor = ConsoleColor.Yellow;
        Console.WriteLine(message);
        Console.ForegroundColor = oldColor;
    }
}