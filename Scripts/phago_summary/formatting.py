"""Consistent formatting for generated summary worksheets."""

from __future__ import annotations

from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.worksheet.worksheet import Worksheet


HEADER_FILL = PatternFill(fill_type="solid", fgColor="1F4E78")
HEADER_FONT = Font(name="Arial", size=11, bold=True, color="FFFFFF")
BODY_FONT = Font(name="Arial", size=11, color="000000")


def format_summary_sheet(worksheet: Worksheet) -> None:
    """Apply the shared, compact table formatting to one output sheet."""

    worksheet.sheet_view.showGridLines = False
    worksheet.freeze_panes = "B2"
    worksheet.auto_filter.ref = worksheet.dimensions
    worksheet.row_dimensions[1].height = 22

    for cell in worksheet[1]:
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
        cell.alignment = Alignment(horizontal="center", vertical="center")

    worksheet.column_dimensions["A"].width = 13
    for cell in worksheet["A"][1:]:
        cell.number_format = "dd/mm/yyyy"
        cell.font = BODY_FONT

    for column in worksheet.iter_cols(min_col=2, max_col=worksheet.max_column):
        header = str(column[0].value or "")
        width = min(max(len(header) + 2, 12), 32)
        worksheet.column_dimensions[column[0].column_letter].width = width
        for cell in column[1:]:
            cell.font = BODY_FONT

    for row in worksheet.iter_rows(min_row=2):
        for cell in row:
            cell.alignment = Alignment(vertical="center")
