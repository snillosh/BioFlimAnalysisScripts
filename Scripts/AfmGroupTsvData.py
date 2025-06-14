import os
import pandas as pd
import argparse

EXPECTED_COLUMNS = [
    "Filename",
    "Position Index",
    "X Position",
    "Y Position",
    "Baseline Offset [N]",
    "Contact Point Offset [m]",
    "Young's Modulus [Pa]",
    "Contact Point [m]",
    "Baseline [N]",
    "ResidualRMS [N]",
    "Height [m]",
    "Ref. Value For Feedback Chan. [N]",
    "Baseline Offset [N]",
    "Adhesion [N]",
    "Minimum Value [N]",
    "Minimum Position [m]"
]

def combine_tsvs_as_cell_tables(root_folder, output_csv_path):
    output_rows = []
    header_written = False

    for subdir, _, files in os.walk(root_folder):
        for file in files:
            if file.lower().endswith('.tsv'):
                file_path = os.path.join(subdir, file)
                try:
                    df = pd.read_csv(file_path, sep='\t', engine='python')

                    # Reorder columns
                    ordered_cols = [col for col in EXPECTED_COLUMNS if col in df.columns]
                    extra_cols = [col for col in df.columns if col not in EXPECTED_COLUMNS]
                    df = df[ordered_cols + extra_cols]

                    # Add header once
                    if not header_written:
                        output_rows.append(df.columns.tolist())
                        header_written = True

                    # Append data rows
                    output_rows.extend(df.values.tolist())

                    # Add blank row
                    output_rows.append([""] * len(df.columns))
                    print(f"Processed: {file_path}")
                except Exception as e:
                    print(f"Failed to load {file_path}: {e}")

    if not output_rows:
        print("No data was collected from TSV files.")
        return

    # Save to CSV
    final_df = pd.DataFrame(output_rows)
    final_df.to_csv(output_csv_path, index=False, header=False)
    print(f"Combined CSV saved to: {output_csv_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Combine TSV files as separate cell tables into one CSV.")
    parser.add_argument("root_folder", help="Root directory to search for TSV files")
    parser.add_argument("output_csv_path", help="Path to save the combined CSV output")

    args = parser.parse_args()
    combine_tsvs_as_cell_tables(args.root_folder, args.output_csv_path)
