import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import argparse

def visualize(output_dir):
    ts_path = os.path.join(output_dir, "augmented_timeseries.npy")
    log_path = os.path.join(output_dir, "augmentation_log.tsv")

    if not os.path.exists(ts_path) or not os.path.exists(log_path):
        print(f"Error: Output files not found in {output_dir}")
        return

    print(f"Loading data from {output_dir}...")
    ts_data = np.load(ts_path)
    log_df = pd.read_csv(log_path, sep='\t')

    print(f"Time series shape: {ts_data.shape}")
    print(f"Log dataframe shape: {log_df.shape}")
    print("\nFirst 5 rows of log:")
    print(log_df.head())

    # Plotting
    plt.figure(figsize=(15, 10))

    # 1. Plot first 5 time series
    plt.subplot(2, 2, 1)
    for i in range(min(5, ts_data.shape[0])):
        plt.plot(ts_data[i], label=f"Sample {i}")
    plt.title("First 5 Augmented Time Series")
    plt.xlabel("Time Point")
    plt.ylabel("Signal Intensity")
    plt.legend()

    # 2. Heatmap of first 50 time series
    plt.subplot(2, 2, 2)
    plt.imshow(ts_data[:50, :], aspect='auto', cmap='viridis')
    plt.title("Heatmap of First 50 Samples")
    plt.xlabel("Time Point")
    plt.ylabel("Sample Index")
    plt.colorbar(label="Intensity")

    # 3. Distribution of Mean Signal
    plt.subplot(2, 2, 3)
    means = np.mean(ts_data, axis=1)
    plt.hist(means, bins=50, color='skyblue', edgecolor='black')
    plt.title("Distribution of Mean Signal Intensity")
    plt.xlabel("Mean Intensity")
    plt.ylabel("Count")

    # 4. Distribution of Standard Deviation
    plt.subplot(2, 2, 4)
    stds = np.std(ts_data, axis=1)
    plt.hist(stds, bins=50, color='salmon', edgecolor='black')
    plt.title("Distribution of Signal Standard Deviation")
    plt.xlabel("Standard Deviation")
    plt.ylabel("Count")

    plt.tight_layout()
    
    save_path = os.path.join(output_dir, "visualization_report.png")
    plt.savefig(save_path)
    print(f"\nVisualization saved to {save_path}")
    # plt.show() # Commented out to avoid blocking if running in non-interactive env, but user can uncomment if needed.

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Visualize augmentation results.")
    parser.add_argument("--output_dir", type=str, default="output/augmentation_results", help="Directory containing output files.")
    args = parser.parse_args()
    
    visualize(args.output_dir)
