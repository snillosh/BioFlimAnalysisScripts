"""Read the first worksheet or text table from a report file."""

from __future__ import annotations

from pathlib import Path

import pandas as pd


def _read_delimited(path: Path, separator: str | None) -> pd.DataFrame:
    options: dict[str, object] = {
        "header": None,
        "dtype": object,
        "keep_default_na": False,
    }
    if separator is None:
        options.update({"sep": None, "engine": "python"})
    else:
        options["sep"] = separator

    try:
        return pd.read_csv(path, encoding="utf-8-sig", **options)
    except UnicodeDecodeError:
        return pd.read_csv(path, encoding="cp1252", **options)


def read_report(path: Path) -> pd.DataFrame:
    """Read a report into a headerless DataFrame.

    Only the first worksheet is read from Excel workbooks. Text reports use a
    fixed delimiter for CSV/TSV and delimiter detection for TXT.
    """

    suffix = path.suffix.casefold()

    if suffix == ".csv":
        frame = _read_delimited(path, ",")
    elif suffix == ".tsv":
        frame = _read_delimited(path, "\t")
    elif suffix == ".txt":
        frame = _read_delimited(path, None)
    elif suffix == ".xls":
        frame = pd.read_excel(
            path,
            sheet_name=0,
            header=None,
            dtype=object,
            engine="xlrd",
        )
    elif suffix in {".xlsx", ".xlsm"}:
        frame = pd.read_excel(
            path,
            sheet_name=0,
            header=None,
            dtype=object,
            engine="openpyxl",
        )
    else:
        raise ValueError(f"unsupported report extension: {path.suffix}")

    if frame.empty:
        raise ValueError("report contains no tabular data on its first sheet")

    return frame
