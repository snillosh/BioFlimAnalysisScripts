"""Transform parsed reports into the four-sheet summary workbook."""

from __future__ import annotations

import re
from collections import OrderedDict
from dataclasses import dataclass
from datetime import date
from pathlib import Path

from openpyxl import Workbook

from .formatting import format_summary_sheet
from .models import ParsedReport, Statistics


SHEET_STATISTICS = OrderedDict(
    (
        ("Median 1", "median_1"),
        ("Median 2", "median_2"),
        ("Frequency", "frequency"),
        ("Count", "count"),
    )
)
_WHITESPACE = re.compile(r"\s+")


@dataclass(frozen=True, slots=True)
class OutputRow:
    experiment_date: date
    source_order: int
    replicate_index: int
    values: dict[str, Statistics | None]


def _specimen_key(specimen_id: str) -> str:
    return _WHITESPACE.sub(" ", specimen_id.strip()).casefold()


def _prepare_rows(
    reports: list[ParsedReport],
) -> tuple[list[str], dict[str, str], list[OutputRow]]:
    specimen_keys: list[str] = []
    specimen_names: dict[str, str] = {}
    rows: list[OutputRow] = []

    for source_order, report in enumerate(reports):
        occurrences: OrderedDict[str, list[Statistics | None]] = OrderedDict()

        for section in report.sections:
            key = _specimen_key(section.specimen_id)
            if key not in specimen_names:
                specimen_keys.append(key)
                specimen_names[key] = _WHITESPACE.sub(" ", section.specimen_id.strip())
            occurrences.setdefault(key, []).append(section.statistics)

        replicate_count = max((len(items) for items in occurrences.values()), default=0)
        for replicate_index in range(replicate_count):
            values = {
                key: items[replicate_index] if replicate_index < len(items) else None
                for key, items in occurrences.items()
            }
            rows.append(
                OutputRow(
                    experiment_date=report.experiment_date,
                    source_order=source_order,
                    replicate_index=replicate_index,
                    values=values,
                )
            )

    rows.sort(
        key=lambda row: (
            row.experiment_date,
            row.source_order,
            row.replicate_index,
        )
    )
    return specimen_keys, specimen_names, rows


def write_summary_workbook(reports: list[ParsedReport], output_path: Path) -> None:
    """Write exactly four formatted worksheets to *output_path*."""

    specimen_keys, specimen_names, rows = _prepare_rows(reports)
    workbook = Workbook()
    workbook.remove(workbook.active)

    for sheet_name, attribute in SHEET_STATISTICS.items():
        worksheet = workbook.create_sheet(sheet_name)
        worksheet.append(["Date", *(specimen_names[key] for key in specimen_keys)])

        for output_row in rows:
            values: list[object] = [output_row.experiment_date]
            for key in specimen_keys:
                statistics = output_row.values.get(key)
                values.append(
                    getattr(statistics, attribute) if statistics is not None else None
                )
            worksheet.append(values)

        format_summary_sheet(worksheet)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    workbook.save(output_path)
