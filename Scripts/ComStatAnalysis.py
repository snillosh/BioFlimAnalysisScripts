import os
import csv
import argparse
from collections import defaultdict

# Fields to keep from the main (null ch1) records
DESIRED_COLUMNS = [
    "Biomass (µm^3/µm^2)",
    "Roughness Coefficient (Ra*)",
    "Surface Area (µm^2)",
    "Surface to biovolume ratio (µm^2/µm^3)",
    "Average thickness (Entire area) (µm)",
    "Average thickness (Biomass) (µm)"
]

# Additional columns for Live/Dead and ratio
EXTRA_COLUMNS = ["Live", "Dead", "DEAD/LIVE ratio"]

def parse_file(file_path):
    """Parses a text file into a dictionary keyed by Image Name"""
    image_data = {}
    current_image = None

    with open(file_path, 'r') as f:
        for line in f:
            parts = line.strip().split(':', 1)
            if len(parts) != 2:
                continue
            key, value = parts[0].strip(), parts[1].strip()

            if key.lower() == 'image name':
                current_image = value
                if current_image not in image_data:
                    image_data[current_image] = {}
            elif current_image:
                if key in DESIRED_COLUMNS:
                    image_data[current_image][key] = value

    return image_data

def collect_data_from_directory(root_dir):
    """Walk through directories and collect all data"""
    merged_data = defaultdict(dict)

    for subdir, _, files in os.walk(root_dir):
        for file in files:
            if file.endswith('.txt'):
                full_path = os.path.join(subdir, file)
                file_data = parse_file(full_path)
                for image_name, props in file_data.items():
                    merged_data[image_name].update(props)

    return merged_data

def extract_basename(image_name):
    """Extracts the prefix part used for linking e.g. B10_1.ome.tif"""
    return image_name.split(":")[0].strip()

def find_channel_values(image_data, base_name):
    """Finds the biomass values for #1 ch1 (Live) and #1 ch2 (Dead)"""
    live = dead = None
    for name, props in image_data.items():
        if name.startswith(base_name):
            if "#1 ch1" in name:
                live = props.get("Biomass (µm^3/µm^2)")
            elif "#1 ch2" in name:
                dead = props.get("Biomass (µm^3/µm^2)")
    return live, dead

def safe_divide(numerator, denominator):
    try:
        return float(numerator) / float(denominator)
    except (ValueError, ZeroDivisionError, TypeError):
        return ''

def write_csv(image_data, output_file):
    """Write combined data to CSV, including Live/Dead logic"""
    fieldnames = ['Image Name'] + DESIRED_COLUMNS + EXTRA_COLUMNS

    with open(output_file, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

        for image_name, props in image_data.items():
            if image_name.endswith("null ch1"):
                base_name = extract_basename(image_name)
                live, dead = find_channel_values(image_data, base_name)
                ratio = safe_divide(dead, live)

                row = {'Image Name': image_name}
                for col in DESIRED_COLUMNS:
                    row[col] = props.get(col, '')
                row['Live'] = live or ''
                row['Dead'] = dead or ''
                row['DEAD/LIVE ratio'] = ratio
                writer.writerow(row)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Generate CSV with filtered columns and Live/Dead processing.")
    parser.add_argument('root_directory', help="Path to the root directory with text files")
    parser.add_argument('--output', default='output.csv', help="Name of the output CSV file (default: output.csv)")
    args = parser.parse_args()

    all_data = collect_data_from_directory(args.root_directory)
    write_csv(all_data, args.output)
    print(f"CSV file created at {args.output}")
