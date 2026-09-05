"""Command-line interface for the phagocytosis summary application."""

from __future__ import annotations

import argparse
import logging
from collections.abc import Sequence
from pathlib import Path

from .application import build_summary


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="Phago.py",
        description="Summarise flow-cytometry phagocytosis reports into Excel.",
    )
    parser.add_argument("root", nargs="?", help="Root directory to search")
    parser.add_argument("match", nargs="?", help="Case-insensitive filename substring")
    parser.add_argument("output", nargs="?", help="Output .xlsx workbook")
    parser.add_argument("--root", dest="root_option", help="Root directory to search")
    parser.add_argument(
        "--match",
        dest="match_option",
        help="Case-insensitive filename substring",
    )
    parser.add_argument(
        "--output",
        dest="output_option",
        help="Output .xlsx workbook (default: results.xlsx)",
    )
    return parser


def _resolve_argument(
    parser: argparse.ArgumentParser,
    name: str,
    positional: str | None,
    option: str | None,
    *,
    required: bool,
    default: str | None = None,
) -> str:
    if positional is not None and option is not None and positional != option:
        parser.error(f"{name} was supplied twice with different values")
    value = option if option is not None else positional
    if value is None:
        value = default
    if required and (value is None or not value.strip()):
        parser.error(f"{name} is required")
    assert value is not None
    return value


def main(arguments: Sequence[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(arguments)

    root = _resolve_argument(
        parser,
        "root",
        args.root,
        args.root_option,
        required=True,
    )
    match_string = _resolve_argument(
        parser,
        "match",
        args.match,
        args.match_option,
        required=True,
    )
    output = _resolve_argument(
        parser,
        "output",
        args.output,
        args.output_option,
        required=False,
        default="results.xlsx",
    )

    if Path(output).suffix.casefold() != ".xlsx":
        parser.error("output must use the .xlsx extension")

    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    try:
        build_summary(
            root=Path(root),
            match_string=match_string,
            output_path=Path(output),
        )
    except Exception as error:
        logging.getLogger("phago_summary").error("FAILED: %s", error)
        return 1

    return 0
