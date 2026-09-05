# Phagocytosis report summariser

`Phago.py` recursively finds flow-cytometry report exports and combines their
phagocytosis statistics into one Excel workbook. It is designed around the
formatted report structure produced by the laboratory software, using
`JUL.xls` as the canonical input example.

## Requirements

- Python 3.10 or newer
- pandas 2.0 or newer
- openpyxl 3.1 or newer
- xlrd 2.0 or newer

Install the dependencies from the repository root:

```powershell
python -m pip install -r Scripts\requirements-phago.txt
```

Keep `Phago.py` and the `phago_summary` directory together inside `Scripts`.
The entry-point file is intentionally small and imports the application
components from that directory.

## Running the application

The recommended form uses three positional arguments:

```powershell
python Scripts\Phago.py "D:\Results" "JUL" "D:\Results\summary.xlsx"
```

The existing named arguments remain supported:

```powershell
python Scripts\Phago.py `
  --root "D:\Results" `
  --match "JUL" `
  --output "D:\Results\summary.xlsx"
```

The arguments are:

1. `root`: directory searched recursively.
2. `match`: case-insensitive substring required in each input filename.
3. `output`: destination workbook. It must end in `.xlsx`. If omitted when
   using named arguments, it defaults to `results.xlsx`.

The output file is excluded from discovery if it is beneath the search root.

## Supported input files

The application recognises:

- `.xls`
- `.xlsx`
- `.xlsm`
- `.csv`
- `.tsv`
- `.txt`

Only the first worksheet of an Excel file is used. CSV files use commas, TSV
files use tabs, and TXT files use automatic delimiter detection. UTF-8 and
Windows-1252 text are supported.

## Date extraction

The experiment date comes from the input file's immediate parent-folder name.
The application searches the complete folder name for the first valid compact
date:

- `DDMMYY`, for example `070126` becomes 7 January 2026.
- Legacy `DMYY`, for example `7126` also becomes 7 January 2026.

Text may appear before or after the date. For example,
`phago_070126_pretreatment` is valid. A candidate must be a separate four- or
six-digit group; part of a longer number is not treated as a date. Invalid
candidates are ignored if a later candidate is a valid date.

Dates are stored as real Excel dates and displayed as `dd/mm/yyyy`.

## How reports are parsed

The parser does not use fixed worksheet coordinates or fixed distances between
statistics.

1. It searches the first sheet for a header row containing `SpecimenID`.
2. It finds the `Name` and `Statistic` columns on that same header row.
3. Every populated cell below `SpecimenID` starts a specimen section.
4. The section ends immediately before the next populated `SpecimenID` cell.
5. Within each section, the parser searches the `Name` column for labels that
   begin with `Median`, `Freq`, or `Count`, ignoring case and trailing text.
6. Values come from the `Statistic` column on the corresponding rows. Numbers
   embedded in detector names such as `B615-H` are never used as results.

A valid section must contain exactly two numeric Median values, one numeric
Frequency value, and one numeric Count value. The values are assigned in this
order:

- first Median: `Median 1`
- second Median: `Median 2`
- Frequency: `Frequency`
- Count: `Count`

## Replicates

Repeated SpecimenIDs are retained as replicates. Within one report, the first
occurrence of each SpecimenID is placed on the first output row for that report,
the second occurrence on the second row, and so on.

If specimen `A` and specimen `B` both occur twice, one report produces:

| Date | A | B |
| --- | ---: | ---: |
| 07/01/2026 | first A value | first B value |
| 07/01/2026 | second A value | second B value |

If a specimen has fewer replicates, its later cells are blank. Specimen names
are compared case-insensitively with repeated whitespace collapsed; the first
spelling encountered becomes the output column heading.

## Malformed data

An invalid specimen section is skipped without discarding other sections in
the same report. Its replicate position remains blank, preventing later
replicates from shifting into the wrong row. The log includes the SpecimenID,
worksheet row, and reason.

A complete file is skipped only when it cannot be processed at file level, for
example when:

- its parent folder contains no valid date;
- the file cannot be read;
- the first sheet lacks the required headers; or
- the `SpecimenID` column contains no specimen sections.

The application continues after both section-level and file-level errors.

## Console output

Each processed file reports its valid and skipped specimen-section counts:

```text
INFO: PROCESSED: D:\Results\070126 experiment\JUL.xls | Valid specimens: 17 | Skipped specimens: 1
WARNING:   SKIPPED SPECIMEN: 3h vehicle (worksheet row 12) | Reason: expected 2 Median value(s), found 1
```

The final summary reports:

- matching files;
- files processed;
- files skipped;
- valid specimen sections;
- skipped specimen sections;
- skipped specimen counts for each processed file; and
- the absolute output-workbook location.

## Output workbook

The workbook always contains exactly four worksheets in this order:

1. `Median 1`
2. `Median 2`
3. `Frequency`
4. `Count`

Each worksheet uses the same structure:

```text
Date | Specimen 1 | Specimen 2 | Specimen 3 | ...
```

Unique SpecimenIDs become columns in first-seen order. Report replicate rows
are sorted chronologically. When dates match, the deterministic input-file
order and replicate order are preserved. Missing or skipped measurements are
blank.

Formatting includes:

- frozen header row and Date column;
- autofilter across the populated range;
- dark-blue, bold headers;
- real Excel date values with date formatting;
- practical column widths; and
- hidden gridlines.

## Exit behaviour

Skipped reports and skipped specimen sections do not make the command fail if
the output workbook can still be written. Configuration, discovery, or output
writing failures return a non-zero exit status and are printed as `FAILED`.

## Project structure

```text
Scripts/
  Phago.py                         command-line entry point
  requirements-phago.txt          runtime dependencies
  phago_summary/
    application.py                processing orchestration and run summary
    cli.py                        argument handling
    dates.py                      parent-folder date extraction
    discovery.py                  recursive file discovery
    formatting.py                 worksheet formatting
    models.py                     shared data models
    report_reader.py              first-sheet and text-file readers
    section_parser.py             structural specimen parsing
    workbook_writer.py            replicate assembly and workbook writing
tests/
  test_phago_summary.py           unit and integration tests
```

## Testing

Run the test suite from the repository root:

```powershell
python -m unittest discover -s tests -v
```

The tests cover date extraction, structural parsing, use of the `Statistic`
column, section-level skipping, replicate alignment, first-sheet selection,
worksheet names, and output formatting.

## Troubleshooting

### No matching files

Check that the match text occurs in the filename itself, not only in a folder
name. Matching ignores letter case.

### Parent folder does not contain a date

Add a valid compact date such as `070126` somewhere in the immediate
parent-folder name.

### Required headers are missing

Confirm that the first worksheet contains `Name`, `Statistic`, and `SpecimenID`
on the same header row. Header matching ignores case and whitespace.

### An individual specimen is skipped

Read the warning for the worksheet row and exact reason. Confirm that the
section contains exactly two Median rows, one Frequency row, and one Count row,
and that each corresponding `Statistic` cell is numeric.

### Legacy `.xls` files cannot be read

Install `xlrd` using the supplied requirements file. `openpyxl` reads modern
`.xlsx` and `.xlsm` inputs but does not read `.xls` files.
