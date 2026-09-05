"""Application orchestration for discovery, parsing, and workbook output."""

from __future__ import annotations

import logging
from pathlib import Path

from .dates import extract_experiment_date
from .discovery import find_matching_files
from .models import (
    BuildSummary,
    FileFailure,
    FileSpecimenSummary,
    ParsedReport,
)
from .report_reader import read_report
from .section_parser import parse_specimen_sections
from .workbook_writer import write_summary_workbook


LOGGER = logging.getLogger("phago_summary")


def build_summary(
    root: Path,
    match_string: str,
    output_path: Path,
    *,
    logger: logging.Logger = LOGGER,
) -> BuildSummary:
    """Process matching reports and write a single summary workbook."""

    files = find_matching_files(root, match_string, exclude=output_path)
    reports: list[ParsedReport] = []
    failures: list[FileFailure] = []
    per_file: list[FileSpecimenSummary] = []

    logger.info("Found %d matching file(s).", len(files))

    for path in files:
        try:
            experiment_date = extract_experiment_date(path.parent.name)
            frame = read_report(path)
            sections = parse_specimen_sections(frame)
        except Exception as error:
            failure = FileFailure(path=path, reason=str(error))
            failures.append(failure)
            logger.error("SKIPPED FILE: %s | Reason: %s", path, error)
            continue

        report = ParsedReport(
            path=path,
            experiment_date=experiment_date,
            sections=sections,
        )
        reports.append(report)
        file_summary = FileSpecimenSummary(
            path=path,
            valid=report.valid_sections,
            skipped=report.skipped_sections,
        )
        per_file.append(file_summary)

        logger.info(
            "PROCESSED: %s | Valid specimens: %d | Skipped specimens: %d",
            path,
            file_summary.valid,
            file_summary.skipped,
        )
        for section in report.sections:
            if section.is_valid:
                continue
            logger.warning(
                "  SKIPPED SPECIMEN: %s (worksheet row %d) | Reason: %s",
                section.specimen_id,
                section.worksheet_row,
                section.error,
            )

    write_summary_workbook(reports, output_path)

    summary = BuildSummary(
        matched_files=len(files),
        processed_files=len(reports),
        skipped_files=len(failures),
        valid_specimens=sum(item.valid for item in per_file),
        skipped_specimens=sum(item.skipped for item in per_file),
        per_file=tuple(per_file),
        failures=tuple(failures),
        output_path=output_path,
    )
    _log_summary(summary, logger)
    return summary


def _log_summary(summary: BuildSummary, logger: logging.Logger) -> None:
    logger.info("Run summary")
    logger.info("  Files matched: %d", summary.matched_files)
    logger.info("  Files processed: %d", summary.processed_files)
    logger.info("  Files skipped: %d", summary.skipped_files)
    logger.info("  Valid specimen sections: %d", summary.valid_specimens)
    logger.info("  Skipped specimen sections: %d", summary.skipped_specimens)
    logger.info("  Skipped specimens per processed file:")
    for item in summary.per_file:
        logger.info("    %s: %d", item.path, item.skipped)
    logger.info("  Output workbook: %s", summary.output_path.resolve())
