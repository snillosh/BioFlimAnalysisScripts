"""Recursive report-file discovery."""

from __future__ import annotations

from pathlib import Path


SUPPORTED_EXTENSIONS = frozenset(
    {".xls", ".xlsx", ".xlsm", ".csv", ".tsv", ".txt"}
)


def find_matching_files(
    root: Path,
    match_string: str,
    *,
    exclude: Path | None = None,
) -> list[Path]:
    """Return matching supported files beneath *root* in stable path order."""

    root = root.expanduser()
    if not root.is_dir():
        raise ValueError(f"root directory does not exist or is not a directory: {root}")

    match_key = match_string.casefold()
    excluded_path = exclude.expanduser().resolve() if exclude is not None else None
    matches: list[Path] = []

    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.casefold() not in SUPPORTED_EXTENSIONS:
            continue
        if match_key not in path.name.casefold():
            continue
        if excluded_path is not None and path.resolve() == excluded_path:
            continue
        matches.append(path)

    return sorted(matches, key=lambda path: str(path).casefold())
