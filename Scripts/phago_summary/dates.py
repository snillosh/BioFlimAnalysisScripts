"""Experiment-date extraction from report parent-folder names."""

from __future__ import annotations

import re
from datetime import date


_DATE_CANDIDATE = re.compile(r"(?<!\d)(?:\d{6}|\d{4})(?!\d)")


def extract_experiment_date(folder_name: str) -> date:
    """Return the first valid compact date found in *folder_name*.

    Six digits are interpreted as ``DDMMYY``. The legacy four-digit form is
    interpreted as ``DMYY``. Numeric groups embedded in longer numbers are
    ignored, and invalid candidates do not prevent a later valid date from
    being used.
    """

    for match in _DATE_CANDIDATE.finditer(folder_name.strip()):
        candidate = match.group(0)

        if len(candidate) == 6:
            day = int(candidate[:2])
            month = int(candidate[2:4])
            year = int(candidate[4:])
        else:
            day = int(candidate[0])
            month = int(candidate[1])
            year = int(candidate[2:])

        try:
            return date(2000 + year, month, day)
        except ValueError:
            continue

    raise ValueError(
        f"parent folder '{folder_name}' does not contain a valid compact date "
        "such as 070126 or 7126"
    )
