import os
import argparse
import pandas as pd
import numpy as np

EXPECTED_COLUMNS = [
    "Filename", "Position Index", "X Position", "Y Position",
    "Baseline Offset [N]", "Contact Point Offset [m]", "Young's Modulus [Pa]",
    "Contact Point [m]", "Baseline [N]", "ResidualRMS [N]", "Height [m]",
    "Ref. Value For Feedback Chan. [N]", "Baseline Offset [N]", "Adhesion [N]",
    "Minimum Value [N]", "Minimum Position [m]"
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
    selected_cells = {name: [] for name in datasets}
    used_cells = set()
    original_counts = {name: len(cells) for name, cells in datasets.items()}

    def cell_id(name, df):
        return (name, id(df))

    # Step 1: Try to select up to 30 from each dataset
    for name, cells in datasets.items():
        available = [(name, c) for c in cells if cell_id(name, c) not in used_cells]
        if len(available) >= 30:
            weights = [len(c[1]) for c in available]
            probs = np.array(weights) / np.sum(weights)
            sampled = np.random.choice(len(available), size=30, replace=False, p=probs)
            selected = [available[i] for i in sampled]
        else:
            selected = available

        selected_cells[name].extend(selected)
        for s in selected:
            used_cells.add(cell_id(*s))
        print(f"  Selected {len(selected)} from {name}")

    # Step 2: Borrow for any deficient datasets
    for name in datasets:
        needed = 30 - len(selected_cells[name])
        if needed > 0:
            print(f"  Borrowing {needed} cells for {name}...")

            donor_pool = []

            for donor_name, donor_cells in datasets.items():
                if donor_name == name:
                    continue  # Don't borrow from self
                total_donor_cells = original_counts[donor_name]
                donor_selected = selected_cells[donor_name]
                donor_remaining = [
                    (donor_name, c) for c in donor_cells
                    if cell_id(donor_name, c) not in used_cells
                ]
                max_lendable = total_donor_cells - 30
                if max_lendable > 0:
                    donor_pool.extend(donor_remaining[:max_lendable])

            if len(donor_pool) < needed:
                raise RuntimeError(
                    f"Not enough available cells to borrow for {name}. "
                    f"Needed {needed}, only found {len(donor_pool)} eligible for borrowing."
                )

            weights = [len(c[1]) for c in donor_pool]
            probs = np.array(weights) / np.sum(weights)
            sampled = np.random.choice(len(donor_pool), size=needed, replace=False, p=probs)
            to_add = [donor_pool[i] for i in sampled]

            selected_cells[name].extend(to_add)
            for s in to_add:
                used_cells.add(cell_id(*s))

    # Final check
    for name in selected_cells:
        if len(selected_cells[name]) != 30:
            raise RuntimeError(f"Dataset '{name}' ended up with {len(selected_cells[name])} cells instead of 30.")

    print("Cell selection complete.")
    return selected_cells

def combine_selected_cells(selected_cells):
    print("\nCombining selected cells into final DataFrame...")
    all_rows = []
    header_written = False

    for cell_list in selected_cells.values():
        for dataset_name, df in cell_list:
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
