import argparse
import os
import re
from pathlib import Path
from collections import defaultdict
from datetime import datetime

import pandas as pd


# ==========================================================
# CONFIGURATION
# ==========================================================

SUPPORTED_EXTENSIONS = {
    ".xls",
    ".xlsx",
    ".csv",
    ".txt",
}


# ==========================================================
# DATE HANDLING
# ==========================================================

def parse_date(folder_name):
    """
    Converts:
        7126    -> 7.1.26
        151225  -> 15.12.25

    The date may appear anywhere in the folder name, for example:
        070126_phago_ebc    -> 7.1.26
        experiment_151225   -> 15.12.25

    Returns:
        display_date, sortable_date
    """

    folder_name = folder_name.strip()

    # Recognise six-digit dates while retaining support for the original
    # four-digit format. Digit boundaries prevent part of a longer number
    # being treated as a date.
    candidates = re.findall(
        r"(?<!\d)(?:\d{6}|\d{4})(?!\d)",
        folder_name,
    )

    for candidate in candidates:
        if len(candidate) == 4:
            day = int(candidate[0])
            month = int(candidate[1])
            year = int(candidate[2:])
        else:
            day = int(candidate[:2])
            month = int(candidate[2:4])
            year = int(candidate[4:])

        try:
            sortable = datetime(
                year=2000 + year,
                month=month,
                day=day,
            )
        except ValueError:
            # Continue looking in case another numeric group is a valid date.
            continue

        display = f"{day}.{month}.{year:02d}"
        return display, sortable

    raise ValueError(
        f"Folder '{folder_name}' does not contain a recognised date "
        "(for example, 7126 or 151225)."
    )


# ==========================================================
# FILE DISCOVERY
# ==========================================================

def find_matching_files(root, match_string):
    files = []

    for path in Path(root).rglob("*"):

        if not path.is_file():
            continue

        if path.suffix.lower() not in SUPPORTED_EXTENSIONS:
            continue

        if match_string.lower() in path.name.lower():
            files.append(path)

    return files


# ==========================================================
# FILE READING
# ==========================================================

def load_file(path):

    suffix = path.suffix.lower()

    if suffix == ".csv":
        return pd.read_csv(path, header=None)

    elif suffix == ".txt":
        return pd.read_csv(
            path,
            sep=None,
            engine="python",
            header=None,
        )

    elif suffix in [".xls", ".xlsx"]:

        return pd.read_excel(
            path,
            header=None,
            engine=None,
        )

    raise ValueError(f"Unsupported file type: {path}")


# ==========================================================
# PARSER
# ==========================================================

def parse_sections(df):
    """
    Assumes the file looks similar to your example.

    Looks for:

        Specimen ID
        Frequency
        Count
        Median
        Median

    Returns:
        {
            specimen: {
                "median1": ...,
                "median2": ...,
                "frequency": ...,
                "count": ...
            }
        }
    """

    results = {}

    flat = []

    for row in df.fillna("").values:
        for item in row:
            flat.append(str(item).strip())

    i = 0

    while i < len(flat):

        text = flat[i]

        #
        # SPECIMEN DETECTION
        #
        # Update this regex if needed after testing
        #
        if text and "median" not in text.lower():

            medians = []
            frequency = None
            count = None

            j = i + 1

            while j < len(flat):

                current = flat[j]

                lower = current.lower()

                #
                # New specimen encountered
                #
                if (
                    current
                    and current != text
                    and "median" not in lower
                    and len(medians) >= 2
                ):
                    break

                #
                # Frequency
                #
                if "frequency" in lower:

                    match = re.search(
                        r"([-+]?\d*\.?\d+)",
                        current,
                    )

                    if match:
                        frequency = float(match.group(1))

                #
                # Count
                #
                elif "count" in lower:

                    match = re.search(r"(\d+)", current)

                    if match:
                        count = int(match.group(1))

                #
                # Median
                #
                elif "median" in lower:

                    match = re.search(
                        r"([-+]?\d*\.?\d+)",
                        current,
                    )

                    if match:
                        medians.append(float(match.group(1)))

                j += 1

            if len(medians) == 2:

                results[text] = {
                    "median1": medians[0],
                    "median2": medians[1],
                    "frequency": frequency,
                    "count": count,
                }

                i = j
                continue

        i += 1

    return results


# ==========================================================
# MAIN
# ==========================================================

def build_workbook(root, match_string, output):

    median1_rows = []
    median2_rows = []
    frequency_rows = []
    count_rows = []

    files = find_matching_files(
        root,
        match_string,
    )

    print(f"\nFound {len(files)} matching files.\n")

    for file in files:

        try:

            parent = file.parent.name

            display_date, sortable_date = parse_date(parent)

            print(f"Processing: {file}")

            df = load_file(file)

            sections = parse_sections(df)

            if not sections:
                print(
                    f"WARNING: No specimen sections found "
                    f"in {file}"
                )
                continue

            med1 = {
                "Date": display_date,
                "_sort": sortable_date,
            }

            med2 = {
                "Date": display_date,
                "_sort": sortable_date,
            }

            freq = {
                "Date": display_date,
                "_sort": sortable_date,
            }

            count = {
                "Date": display_date,
                "_sort": sortable_date,
            }

            for specimen, values in sections.items():

                med1[specimen] = values["median1"]
                med2[specimen] = values["median2"]

                freq[specimen] = values["frequency"]
                count[specimen] = values["count"]

            median1_rows.append(med1)
            median2_rows.append(med2)
            frequency_rows.append(freq)
            count_rows.append(count)

        except Exception as e:

            print(
                f"FAILED: {file}\n"
                f"Reason: {e}\n"
            )

    #
    # CREATE DATAFRAMES
    #

    dfs = {
        "Median 1": pd.DataFrame(median1_rows),
        "Median 2": pd.DataFrame(median2_rows),
        "Frequency": pd.DataFrame(frequency_rows),
        "Count": pd.DataFrame(count_rows),
    }

    #
    # SORT
    #

    for name, df in dfs.items():

        if df.empty:
            continue

        df.sort_values("_sort", inplace=True)

        df.drop(columns="_sort", inplace=True)

        dfs[name] = df

    #
    # WRITE OUTPUT
    #

    with pd.ExcelWriter(output) as writer:

        for name, df in dfs.items():

            df.to_excel(
                writer,
                sheet_name=name,
                index=False,
            )

    print(f"\nWorkbook written to:\n{output}")


# ==========================================================
# ENTRY POINT
# ==========================================================

if __name__ == "__main__":

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--root",
        required=True,
        help="Root directory to search.",
    )

    parser.add_argument(
        "--match",
        required=True,
        help="Substring to match in filenames.",
    )

    parser.add_argument(
        "--output",
        default="results.xlsx",
        help="Output workbook.",
    )

    args = parser.parse_args()

    build_workbook(
        root=args.root,
        match_string=args.match,
        output=args.output,
    )
