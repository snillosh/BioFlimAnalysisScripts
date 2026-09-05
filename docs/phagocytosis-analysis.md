# Neutrophil phagocytosis/pHrodo analysis

`Scripts/PhagocytosisAnalysis.R` analyses the Excel workbook produced by
`Scripts/Phago.py`. It reads the `Median 2` and `Frequency` sheets, keeps
experimental dates paired, selects statistical tests after normality checks,
and creates tables and publication-quality plots.

The script is separate from the Python summariser. You do not need to put the
R and Python files beside your Excel workbook, but you do need to keep the
repository's `Scripts` folder or copy `PhagocytosisAnalysis.R` to a known
location.

## What you need

- R 4.1 or later
- RStudio is optional
- The output `.xlsx` workbook from `Phago.py`
- These R packages: `readxl`, `dplyr`, `tidyr`, `stringr`, `readr`, `tibble`,
  `ggplot2`, `rstatix`, and `ggpubr`

Install R from the [R Project for Windows](https://cran.r-project.org/bin/windows/base/).
If you prefer a graphical editor, install
[RStudio Desktop](https://posit.co/download/rstudio-desktop/) after installing R.

Install the required packages once. Open R or the RStudio Console and run:

```r
install.packages(c(
  "readxl", "dplyr", "tidyr", "stringr", "readr", "tibble",
  "ggplot2", "rstatix", "ggpubr"
))
```

The script checks for missing packages each time it starts. If anything is
missing, it stops and prints an installation command.

## Quick start on Windows

Open PowerShell and run the following, changing all three paths to locations
on your computer:

```powershell
cd "C:\path\to\BioFlimAnalysisScripts"

Rscript .\Scripts\PhagocytosisAnalysis.R `
  --input "E:\path\to\phagocytosis.xlsx" `
  --output "E:\path\to\Phagocytosis Results"
```

The backtick at the end of the first two command lines tells PowerShell that
the command continues on the next line. The same command can be entered on one
line instead:

```powershell
Rscript .\Scripts\PhagocytosisAnalysis.R --input "E:\path\to\phagocytosis.xlsx" --output "E:\path\to\Phagocytosis Results"
```

Paths containing spaces must remain inside quotation marks. The output folder
is created automatically if it does not exist.

If PowerShell says that `Rscript` is not recognised, restart PowerShell after
installing R. If that does not help, use the full path to `Rscript.exe`, for
example:

```powershell
& "C:\Program Files\R\R-x.y.z\bin\Rscript.exe" .\Scripts\PhagocytosisAnalysis.R --input "E:\path\to\phagocytosis.xlsx" --output "E:\path\to\Phagocytosis Results"
```

Replace `R-x.y.z` with the R version folder installed on your computer.

## Running it from RStudio

Open `Scripts/PhagocytosisAnalysis.R`. At the very top, set `INPUT_FILE` and
`OUTPUT_DIRECTORY`. Forward slashes are easiest in Windows R paths:

```r
INPUT_FILE <- "E:/path/to/phagocytosis.xlsx"
OUTPUT_DIRECTORY <- "E:/path/to/Phagocytosis Results"
```

Then click **Source**. Command-line values take priority over these variables
when both are supplied.

## Required workbook structure

The workbook must contain exactly one sheet named `Median 2` and one sheet
named `Frequency`. Capitalisation and extra spaces in the sheet name do not
matter. Only these two sheets are analysed; any other sheets are ignored.

Each relevant sheet must have:

- one `Date` column;
- one column for each sample condition; and
- numeric measurement values in the body of the table.

`Median 2` supplies **Median pHrodo intensity** and `Frequency` supplies
**% pHrodo-positive neutrophils**. The script matches them using Date and the
sample-column heading.

Dates are biological replicates. If the same Date has multiple rows, those
rows are treated as technical replicates and averaged before statistics. The
number of non-blank technical values contributing to every mean is retained in
`cleaned_tidy_data.csv`.

## Recognised sample names

Names are matched without regard to capitalisation. Spaces, underscores, and
hyphens are normalised. The recognised condition labels are:

| Workbook heading | Analysis label |
| --- | --- |
| `30min ut`, `3h ut` | Untreated |
| `30min vehicle`, `3h vehicle` | Vehicle |
| `30min ebc`, `3h ebc` | EBC (256 µg/mL) |
| `30min ebc 4`, `3h ebc 4` | EBC (4 µg/mL) |
| `30min ebc 8`, `3h ebc 8` | EBC (8 µg/mL) |
| `30min pma`, `3h pma` | PMA |
| `cold` | Cold, included at both 30 min and 3 h |
| `neut alone` | Deliberately excluded |

`untreated` is also accepted in place of `ut`, and `neutrophils alone` is
accepted in place of `neut alone`.

If a name is not recognised, it is not analysed. It is reported in
`unmatched_samples.csv` and a warning is displayed. `Neut alone` is listed
separately in `excluded_samples.csv` so the intentional exclusion is auditable.

If two different column headings map to the same Date, time point, and
treatment, the script saves `classification_ambiguities.csv` and stops. This
prevents an uncertain mapping from being analysed silently.

## Statistical analysis

The following four combinations are always handled separately:

1. 30 min — Median pHrodo intensity
2. 3 h — Median pHrodo intensity
3. 30 min — % pHrodo-positive neutrophils
4. 3 h — % pHrodo-positive neutrophils

For each combination, the script:

1. retains pairing by experimental Date;
2. when there are more than two treatment groups, assesses Shapiro-Wilk
   normality of repeated-measures model residuals;
3. uses repeated-measures ANOVA when those residuals are compatible with
   normality, with automatic sphericity correction where required, or the
   Friedman test otherwise;
4. compares each recognised treatment with Untreated only;
5. assesses the paired differences for each comparison;
6. uses a two-sided paired t-test for compatible paired differences, or a
   two-sided Wilcoxon signed-rank test otherwise; and
7. applies the Holm correction across the Untreated comparisons within that
   measurement and time point.

An overall repeated-measures test uses only Dates containing every treatment
in that particular analysis. Each Untreated comparison uses all Dates for
which that specific pair is available. Any Date omitted because a required
value is missing is recorded in `analysis_exclusions.csv`.

Shapiro-Wilk requires at least three non-identical values. When normality
cannot be assessed, the script conservatively selects the non-parametric test
and records the reason. The Q-Q plots should still be reviewed, especially
with small biological sample sizes.

Significance labels use Holm-adjusted p-values for pairwise comparisons:

| Adjusted p-value | Label |
| --- | --- |
| p ≥ 0.05 | ns |
| p < 0.05 | * |
| p < 0.01 | ** |
| p < 0.001 | *** |
| p < 0.0001 | **** |

## Output files

Use a different output directory for each source workbook. Existing files with
the same names are replaced when the script is run again.

| Output | Contents |
| --- | --- |
| `cleaned_tidy_data.csv` | Exact analysis-ready values, dates, labels, and technical-replicate counts |
| `statistical_results.csv` | Overall and Untreated comparison tests, statistics, raw and adjusted p-values, significance, and sample sizes |
| `normality_results.csv` | Shapiro-Wilk results, decisions, and selected tests |
| `anova_assumption_results.csv` | Available sphericity checks and corrections from repeated-measures ANOVA |
| `analysis_exclusions.csv` | Dates omitted from an overall test or a paired comparison because values were missing |
| `unmatched_samples.csv` | Unrecognised sample headings |
| `excluded_samples.csv` | Intentionally excluded `Neut alone` values |
| `measurement_mismatches.csv` | Samples present in only one of the two measurement sheets |
| `classification_ambiguities.csv` | More than one heading mapped to the same condition |
| `invalid_measurements.csv` | Non-numeric/non-finite values or measurements without a Date |
| `session_info.txt` | R and package versions used for reproducibility |

The `plots` folder contains four main plots as 600 dpi PNG files and as vector
PDF files. Each point is one biological Date after technical replicates have
been averaged. Grey lines connect values from the same Date. The black summary
is mean ± SD for a parametric overall analysis or median with IQR for a
non-parametric analysis. With exactly two treatments, the summary follows the
paired comparison selected by its normality check. Significant Holm-corrected
comparisons with Untreated are added automatically; p-values are never
hard-coded.

The `normality_qq` folder contains corresponding Q-Q plots for the overall
model residuals and paired differences.

## Troubleshooting

### A sample was not analysed

Check `unmatched_samples.csv`, `excluded_samples.csv`, and
`invalid_measurements.csv`. Correct the source workbook heading or value, then
rerun the script. Do not edit `cleaned_tidy_data.csv` and treat it as a new
source file; the R script expects the original two-sheet workbook.

### The analysis stopped because of an ambiguity

Open `classification_ambiguities.csv`. Rename or remove the duplicate source
column so that only one column represents each time point and treatment, then
rerun the script.

### A test was not performed

Read the `Notes` column in `statistical_results.csv` and check
`analysis_exclusions.csv`. Common reasons are too few matched Dates or missing
treatment values.

### An output file will not save

Close the CSV, PNG, or PDF if it is open in another program, check that you can
write to the output folder, and rerun the analysis.

## Getting help from the script

```powershell
Rscript .\Scripts\PhagocytosisAnalysis.R --help
```
