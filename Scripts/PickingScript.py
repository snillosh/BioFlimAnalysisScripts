import random
import numpy as np

def select_cells(datasets):
    all_cells = []
    for dataset_name, cells in datasets.items():
        for cell in cells:
            all_cells.append((dataset_name, cell))

    if len(all_cells) < 90:
        raise ValueError(f"Only found {len(all_cells)} cells in total — need at least 90.")

    selected_cells = {name: [] for name in datasets}
    used_cells = set()

    # Helper to get unique ID of a cell
    def cell_id(name, df):
        return (name, id(df))

    # For each dataset
    for dataset_name in datasets:
        own_cells = [(n, c) for n, c in all_cells if n == dataset_name and cell_id(n, c) not in used_cells]
        if len(own_cells) >= 30:
            # Weighted random sample
            weights = [len(c[1]) for c in own_cells]
            probabilities = np.array(weights) / np.sum(weights)
            sampled = np.random.choice(len(own_cells), size=30, replace=False, p=probabilities)
            selected = [own_cells[i] for i in sampled]
        else:
            # Take all available
            selected = own_cells

        selected_cells[dataset_name].extend(selected)
        for n, c in selected:
            used_cells.add(cell_id(n, c))

    # Fill in remaining deficits by borrowing
    for dataset_name in datasets:
        needed = 30 - len(selected_cells[dataset_name])
        if needed > 0:
            remaining_cells = [(n, c) for n, c in all_cells if cell_id(n, c) not in used_cells]
            remaining_cells.sort(key=lambda x: len(x[1]), reverse=True)
            weights = [len(c[1]) for c in remaining_cells]
            probabilities = np.array(weights) / np.sum(weights)
            sampled = np.random.choice(len(remaining_cells), size=needed, replace=False, p=probabilities)
            to_add = [remaining_cells[i] for i in sampled]
            selected_cells[dataset_name].extend(to_add)
            for n, c in to_add:
                used_cells.add(cell_id(n, c))

    # Final sanity check
    for name in selected_cells:
        if len(selected_cells[name]) != 30:
            raise RuntimeError(f"Dataset '{name}' ended up with {len(selected_cells[name])} cells instead of 30.")

    return selected_cells
