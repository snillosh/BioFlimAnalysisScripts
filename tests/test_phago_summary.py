from __future__ import annotations

import logging
import sys
import tempfile
import unittest
from datetime import date
from io import StringIO
from pathlib import Path

import pandas as pd
from openpyxl import Workbook, load_workbook


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIRECTORY = REPOSITORY_ROOT / "Scripts"
sys.path.insert(0, str(SCRIPTS_DIRECTORY))

from phago_summary.application import build_summary  # noqa: E402
from phago_summary.dates import extract_experiment_date  # noqa: E402
from phago_summary.models import ParsedReport, SectionResult, Statistics  # noqa: E402
from phago_summary.report_reader import read_report  # noqa: E402
from phago_summary.section_parser import parse_specimen_sections  # noqa: E402
from phago_summary.workbook_writer import _prepare_rows, write_summary_workbook  # noqa: E402


def _section_rows(
    specimen_id: str,
    *,
    median_1: object = 1053,
    median_2: object = 2456,
    frequency: object = 13.0,
    count: object = 1002,
) -> list[list[object]]:
    rows = [
        ["", "sample.fcs", "", 10000, "", specimen_id],
        [">", "sample.fcs/Neuts", 80.9, 8087, "", ""],
        ["> > >", "Median : B615-H = 999999", median_1, "", "", ""],
        ["> > > >", "Count with descriptive text = 999999", count, "", "", ""],
        ["> > > >", "Freq. of Parent = 0.999999", frequency, "", "", ""],
    ]
    if median_2 is not None:
        rows.append(
            ["> > > >", "Median : YG586-H = 999999", median_2, "", "", ""]
        )
    return rows


def _report_frame(*sections: list[list[object]]) -> pd.DataFrame:
    rows: list[list[object]] = [
        ["Export metadata", "", "", "", "", ""],
        ["", "", "", "", "", ""],
        ["Depth", "Name", "Statistic", "#Cells", "unused", "SpecimenID"],
    ]
    for section in sections:
        rows.extend(section)
        rows.append(["", "", "", "", "", ""])
    return pd.DataFrame(rows, dtype=object)


class DateExtractionTests(unittest.TestCase):
    def test_finds_six_digit_date_anywhere(self) -> None:
        self.assertEqual(
            extract_experiment_date("experiment_070126_phago"),
            date(2026, 1, 7),
        )

    def test_retains_legacy_four_digit_date(self) -> None:
        self.assertEqual(extract_experiment_date("phago 7126 data"), date(2026, 1, 7))

    def test_skips_invalid_candidate_before_valid_date(self) -> None:
        self.assertEqual(
            extract_experiment_date("batch_321326_then_151225"),
            date(2025, 12, 15),
        )

    def test_rejects_dates_embedded_in_longer_numbers(self) -> None:
        with self.assertRaisesRegex(ValueError, "does not contain"):
            extract_experiment_date("batch_10701260")


class SectionParserTests(unittest.TestCase):
    def test_uses_statistic_column_and_retains_invalid_section(self) -> None:
        frame = _report_frame(
            _section_rows("3h ut"),
            _section_rows("3h vehicle", median_2=None),
            _section_rows("3h ut", median_1=975, median_2=2477, frequency=9.16, count=745),
        )

        sections = parse_specimen_sections(frame)

        self.assertEqual(len(sections), 3)
        self.assertEqual(
            sections[0].statistics,
            Statistics(median_1=1053, median_2=2456, frequency=13, count=1002),
        )
        self.assertFalse(sections[1].is_valid)
        self.assertIn("expected 2 Median", sections[1].error or "")
        self.assertEqual(sections[2].statistics.median_1, 975)  # type: ignore[union-attr]


class ReportReaderTests(unittest.TestCase):
    def test_reads_only_first_workbook_sheet(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "report.xlsx"
            workbook = Workbook()
            workbook.active["A1"] = "first"
            workbook.create_sheet("Ignored")["A1"] = "second"
            workbook.save(path)

            frame = read_report(path)

        self.assertEqual(frame.iat[0, 0], "first")


class WorkbookWriterTests(unittest.TestCase):
    def test_preserves_skipped_replicate_position_and_formats_output(self) -> None:
        valid_a = Statistics(10, 20, 1.5, 30)
        valid_b = Statistics(11, 21, 2.5, 31)
        report = ParsedReport(
            path=Path("report.xls"),
            experiment_date=date(2026, 1, 7),
            sections=(
                SectionResult("A", 2, error="missing Median"),
                SectionResult("A", 12, statistics=valid_a),
                SectionResult("B", 22, statistics=valid_b),
            ),
        )

        keys, names, rows = _prepare_rows([report])
        self.assertEqual([names[key] for key in keys], ["A", "B"])
        self.assertIsNone(rows[0].values["a"])
        self.assertEqual(rows[0].values["b"], valid_b)
        self.assertEqual(rows[1].values["a"], valid_a)
        self.assertIsNone(rows[1].values["b"])

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "summary.xlsx"
            write_summary_workbook([report], output)
            workbook = load_workbook(output)

        self.assertEqual(
            workbook.sheetnames,
            ["Median 1", "Median 2", "Frequency", "Count"],
        )
        worksheet = workbook["Median 1"]
        self.assertEqual(worksheet.freeze_panes, "B2")
        self.assertEqual(worksheet.auto_filter.ref, "A1:C3")
        self.assertEqual(worksheet["A2"].value.date(), date(2026, 1, 7))
        self.assertIsNone(worksheet["B2"].value)
        self.assertEqual(worksheet["C2"].value, 11)
        self.assertEqual(worksheet["B3"].value, 10)


class ApplicationTests(unittest.TestCase):
    def test_reports_skipped_specimen_count_per_file(self) -> None:
        frame = _report_frame(
            _section_rows("A"),
            _section_rows("B", median_2=None),
        )

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report_directory = root / "batch_070126"
            report_directory.mkdir()
            report_path = report_directory / "JUL.csv"
            output_path = root / "summary.xlsx"
            frame.to_csv(report_path, index=False, header=False)

            log_output = StringIO()
            handler = logging.StreamHandler(log_output)
            logger = logging.getLogger("phago_summary_test")
            logger.handlers = [handler]
            logger.setLevel(logging.INFO)
            logger.propagate = False

            summary = build_summary(root, "JUL", output_path, logger=logger)

        self.assertEqual(summary.processed_files, 1)
        self.assertEqual(summary.skipped_files, 0)
        self.assertEqual(summary.valid_specimens, 1)
        self.assertEqual(summary.skipped_specimens, 1)
        self.assertEqual(summary.per_file[0].skipped, 1)
        self.assertIn("Skipped specimens: 1", log_output.getvalue())
        self.assertIn(f"{report_path}: 1", log_output.getvalue())


if __name__ == "__main__":
    unittest.main()
