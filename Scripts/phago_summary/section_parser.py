"""Structure-aware parsing of SpecimenID-delimited report sections."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass

import pandas as pd

from .models import Number, SectionResult, Statistics


_WHITESPACE = re.compile(r"\s+")
_MEDIAN_LABEL = re.compile(r"^median\b", re.IGNORECASE)
_FREQUENCY_LABEL = re.compile(r"^freq", re.IGNORECASE)
_COUNT_LABEL = re.compile(r"^count\b", re.IGNORECASE)


@dataclass(frozen=True, slots=True)
class ReportLayout:
    """Column positions discovered from the report header row."""

    header_row: int
    specimen_column: int
    label_column: int
    statistic_column: int


def _text(value: object) -> str:
    if value is None:
        return ""
    try:
        if pd.isna(value):
            return ""
    except (TypeError, ValueError):
        pass
    return _WHITESPACE.sub(" ", str(value).strip())


def _header_key(value: object) -> str:
    return _WHITESPACE.sub("", _text(value)).casefold()


def find_report_layout(frame: pd.DataFrame) -> ReportLayout:
    """Find the SpecimenID, Name, and Statistic columns dynamically."""

    for row_index in range(len(frame.index)):
        keys = [_header_key(value) for value in frame.iloc[row_index].tolist()]
        if "specimenid" not in keys:
            continue

        missing = [name for name in ("name", "statistic") if name not in keys]
        if missing:
            joined = ", ".join(missing)
            raise ValueError(
                f"header row {row_index + 1} contains SpecimenID but is missing: "
                f"{joined}"
            )

        return ReportLayout(
            header_row=row_index,
            specimen_column=keys.index("specimenid"),
            label_column=keys.index("name"),
            statistic_column=keys.index("statistic"),
        )

    raise ValueError("could not find a SpecimenID header on the first sheet")


def _number(value: object) -> Number:
    if value is None or isinstance(value, bool):
        raise ValueError("is blank or non-numeric")

    try:
        if pd.isna(value):
            raise ValueError("is blank or non-numeric")
    except TypeError:
        pass

    text = str(value).strip().replace(",", "")
    if not text:
        raise ValueError("is blank or non-numeric")

    try:
        number = float(text)
    except (TypeError, ValueError) as error:
        raise ValueError(f"is not numeric: {value!r}") from error

    if not math.isfinite(number):
        raise ValueError(f"is not finite: {value!r}")
    if number.is_integer():
        return int(number)
    return number


def _parse_section(
    frame: pd.DataFrame,
    layout: ReportLayout,
    start_row: int,
    end_row: int,
) -> SectionResult:
    specimen_id = _text(frame.iat[start_row, layout.specimen_column])
    medians: list[Number] = []
    frequencies: list[Number] = []
    counts: list[Number] = []
    errors: list[str] = []

    for row_index in range(start_row, end_row):
        label = _text(frame.iat[row_index, layout.label_column])
        target: list[Number] | None = None
        statistic_name = ""

        if _MEDIAN_LABEL.match(label):
            target = medians
            statistic_name = "Median"
        elif _FREQUENCY_LABEL.match(label):
            target = frequencies
            statistic_name = "Frequency"
        elif _COUNT_LABEL.match(label):
            target = counts
            statistic_name = "Count"

        if target is None:
            continue

        try:
            target.append(_number(frame.iat[row_index, layout.statistic_column]))
        except ValueError as error:
            errors.append(
                f"{statistic_name} value at worksheet row {row_index + 1} {error}"
            )

    expected_counts = (
        ("Median", medians, 2),
        ("Frequency", frequencies, 1),
        ("Count", counts, 1),
    )
    for name, values, expected in expected_counts:
        if len(values) != expected:
            errors.append(f"expected {expected} {name} value(s), found {len(values)}")

    if errors:
        return SectionResult(
            specimen_id=specimen_id,
            worksheet_row=start_row + 1,
            error="; ".join(errors),
        )

    return SectionResult(
        specimen_id=specimen_id,
        worksheet_row=start_row + 1,
        statistics=Statistics(
            median_1=medians[0],
            median_2=medians[1],
            frequency=frequencies[0],
            count=counts[0],
        ),
    )


def parse_specimen_sections(frame: pd.DataFrame) -> tuple[SectionResult, ...]:
    """Parse all sections, retaining invalid sections as skipped placeholders."""

    layout = find_report_layout(frame)
    specimen_rows = [
        row_index
        for row_index in range(layout.header_row + 1, len(frame.index))
        if _text(frame.iat[row_index, layout.specimen_column])
    ]

    if not specimen_rows:
        raise ValueError("SpecimenID column contains no populated specimen sections")

    sections: list[SectionResult] = []
    for index, start_row in enumerate(specimen_rows):
        end_row = (
            specimen_rows[index + 1]
            if index + 1 < len(specimen_rows)
            else len(frame.index)
        )
        sections.append(_parse_section(frame, layout, start_row, end_row))

    return tuple(sections)
