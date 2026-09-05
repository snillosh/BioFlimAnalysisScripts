"""Data models shared by the phagocytosis summary components."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from pathlib import Path

Number = int | float


@dataclass(frozen=True, slots=True)
class Statistics:
    """The four values extracted from one valid specimen section."""

    median_1: Number
    median_2: Number
    frequency: Number
    count: Number


@dataclass(frozen=True, slots=True)
class SectionResult:
    """The result of parsing one SpecimenID-delimited section."""

    specimen_id: str
    worksheet_row: int
    statistics: Statistics | None = None
    error: str | None = None

    @property
    def is_valid(self) -> bool:
        return self.statistics is not None


@dataclass(frozen=True, slots=True)
class ParsedReport:
    """A report that was read successfully and split into specimen sections."""

    path: Path
    experiment_date: date
    sections: tuple[SectionResult, ...]

    @property
    def valid_sections(self) -> int:
        return sum(section.is_valid for section in self.sections)

    @property
    def skipped_sections(self) -> int:
        return len(self.sections) - self.valid_sections


@dataclass(frozen=True, slots=True)
class FileFailure:
    """A report that could not be processed at file level."""

    path: Path
    reason: str


@dataclass(frozen=True, slots=True)
class FileSpecimenSummary:
    """Per-file specimen counts for a successfully parsed report."""

    path: Path
    valid: int
    skipped: int


@dataclass(frozen=True, slots=True)
class BuildSummary:
    """Counts and paths reported after a complete application run."""

    matched_files: int
    processed_files: int
    skipped_files: int
    valid_specimens: int
    skipped_specimens: int
    per_file: tuple[FileSpecimenSummary, ...]
    failures: tuple[FileFailure, ...]
    output_path: Path
