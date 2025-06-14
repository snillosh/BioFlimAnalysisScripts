import os
import argparse
import pandas as pd
import numpy as np

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

def split_into_cells(df):
    print("  Splitting dataset into individual cells...")
    cells = []
    current_cell = []

    for _, row in df.iterrows():
        if row.isnull().all():
            if current_cell:
                cells.append(pd.DataFrame(current_cell, columns=df.columns))
                current_cell = []
        else:
            current_cell.append(row)

    if current_cell:
        cells.append(pd.DataFrame(current_cell, columns=df.columns))

    print(f"  Found {len(cells)} cells.")
    return cells

def load_all_datasets(root_path):
    print(f"Scanning for dataset CSVs under: {root_path}")
    datasets = {}
    for subdir, _, files in os.walk(root_path):
        for file in files:
            if file.lower().endswith('.csv'):
                path = os.path.join(subdir, file)
                print(f"\nProcessing dataset: {file}")
                try:
                    df = pd.read_csv(path)
                    cells = split_into_cells(df)
                    datasets[file] = cells
                except Exception as e:
                    print(f"  Failed to load {path}: {e}")
    print(f"\nTotal datasets found: {len(datasets)}")
    return datasets

def select_cells(datasets):
    print("\nSelecting 30 cells per dataset (weighted random)...")
    all_cells = []
    for dataset_name, cells in datasets.items():
        for cell in cells:
            all_cells.append((dataset_name, cell))

    if len(all_cells) < 90:
        raise ValueError(f"Only found {len(all_cells)} cells in total — need at least 90.")

    selected_cells = {name: [] for name in datasets}
    used_cells = set()

    def cell_id(name, df):
        return (name, id(df))

    for dataset_name in datasets:
        own_cells = [(n, c) for n, c in all_cells if n == dataset_name and cell_id(n, c) not in used_cells]
        if len(own_cells) >= 30:
            weights = [len(c[1]) for c in own_cells]
            probabilities = np.array(weights) / np.sum(weights)
            sampled = np.random.choice(len(own_cells), size=30, replace=False, p=probabilities)
            selected = [own_cells[i] for i in sampled]
        else:
            selected = own_cells

        selected_cells[dataset_name].extend(selected)
        for n, c in selected:
            used_cells.add(cell_id(n, c))
        print(f"  Selected {len(selected)} from {dataset_name}")

    for dataset_name in datasets:
        needed = 30 - len(selected_cells[dataset_name])
        if needed > 0:
            print(f"  Borrowing {needed} cells for {dataset_name}...")
            remaining_cells = [(n, c) for n, c in all_cells if cell_id(n, c) not in used_cells]
            weights = [len(c[1]) for c in remaining_cells]
            probabilities = np.array(weights) / np.sum(weights)
            sampled = np.random.choice(len(remaining_cells), size=needed, replace=False, p=probabilities)
            to_add = [remaining_cells[i] for i in sampled]
            selected_cells[dataset_name].extend(to_add)
            for n, c in to_add:
                used_cells.add(cell_id(n, c))

    for name in selected_cells:
        if len(selected_cells[name]) != 30:
            raise RuntimeError(f"Dataset '{name}' ended up with {len(selected_cells[name])} cells instead of 30.")

    print("Cell selection complete.")
    return selected_cells

def combine_selected_cells(selected_cells):
    print("\nCombining selected cells into final DataFrame...")
    all_rows = []
    header_written = False

    for dataset_name, cell_list in selected_cells.items():
        for cell in cell_list:
            df = cell[1]
            ordered_cols = [col for col in EXPECTED_COLUMNS if col in df.columns]
            extra_cols = [col for col in df.columns if col not in EXPECTED_COLUMNS]
            df = df[ordered_cols + extra_cols]

            if not header_written:
                all_rows.append(df.columns.tolist())
                header_written = True

            all_rows.extend(df.values.tolist())

    return pd.DataFrame(all_rows)

def main():
    parser = argparse.ArgumentParser(description="Select 30 cells from each dataset (CSV file) under a root folder.")
    parser.add_argument("root_path", help="Path to root folder containing dataset CSV files.")
    parser.add_argument("output_path", help="Path to save the combined selected cells CSV.")

    args = parser.parse_args()

    print("========== CELL SELECTOR START ==========\n")

    datasets = load_all_datasets(args.root_path)
    if len(datasets) != 3:
        raise ValueError(f"Expected exactly 3 datasets, found {len(datasets)}.")

    selected_cells = select_cells(datasets)

    print("\nSelected cell summary:")
    for name, cells in selected_cells.items():
        print(f"  {name}: {len(cells)} cells")

    final_df = combine_selected_cells(selected_cells)
    final_df.to_csv(args.output_path, index=False, header=False)

    print(f"\n✅ Final CSV saved to: {args.output_path}")
    print("\n========== CELL SELECTOR COMPLETE ==========")

if __name__ == "__main__":
    main()
