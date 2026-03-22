from pathlib import Path
import pandas as pd
import sys


def combine_tsvs(root_dir: str, output_csv: str) -> None:
    root = Path(root_dir)
    all_frames = []

    for tsv_file in root.rglob("*.tsv"):
        parent_dir_name = tsv_file.parent.name
        treatment = parent_dir_name[:3]

        try:
            df = pd.read_csv(tsv_file, sep="\t")
            df["Treatment"] = treatment
            all_frames.append(df)
            print(f"Loaded: {tsv_file} -> Treatment={treatment}")
        except Exception as e:
            print(f"Failed to read {tsv_file}: {e}")

    if not all_frames:
        print("No TSV files found.")
        return

    combined_df = pd.concat(all_frames, ignore_index=True)
    combined_df.to_csv(output_csv, index=False)
    print(f"Combined CSV written to: {output_csv}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python script.py <root_directory> <output_csv>")
    else:
        combine_tsvs(sys.argv[1], sys.argv[2])