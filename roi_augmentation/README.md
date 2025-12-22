# ROI Augmentation Tool

This folder contains a set of tools for augmenting fMRI data by sampling and merging connected regions of interest (ROIs) from various brain atlases.

## Overview

The goal is to generate augmented fMRI time series by:
1.  Ensuring all atlases are in the same space (2mm isotropic).
2.  Identifying spatially connected ROIs within each atlas.
3.  Randomly sampling pairs of connected ROIs, merging them, and extracting the mean time series from a target fMRI file.

## Contents

*   `prepare_atlas_neighbors.py`: Pre-processes atlases to ensure 2mm resolution and computes adjacency graphs (neighbor lists) for ROIs.
*   `augment_rois.py`: The main script that performs the sampling and extraction.
*   `visualize_augmentation.py`: A utility to visualize the generated time series and statistics.

## Usage

### 1. Prepare Atlases
First, you need to generate the adjacency information for your atlases. This script scans the `atlas_data` directory, resamples atlases if necessary, and saves neighbor lists.

```bash
python roi_augmentation/prepare_atlas_neighbors.py
```
*Note: You may need to edit the `atlas_dir` path inside this script if your data is not in `C:\Users\47841\Desktop\ICML2026\atlas_data`.*

### 2. Run Augmentation
Use this script to generate the augmented time series from an fMRI file.

```bash
python roi_augmentation/augment_rois.py --fmri "path/to/your/fmri.nii.gz" --atlas_dir "path/to/atlas_data" --output_dir "output/augmentation_results" --n_samples 2000
```

**Arguments:**
*   `--fmri`: Path to the input 4D fMRI NIfTI file.
*   `--atlas_dir`: Directory containing the atlas files (must match the one used in step 1).
*   `--output_dir`: Directory where results will be saved.
*   `--n_samples`: Number of augmented samples to generate (default: 2000).

**Outputs:**
*   `augmented_timeseries.npy`: A numpy array of shape `(n_samples, time_points)`.
*   `augmentation_log.tsv`: A tab-separated file recording the source atlas and merged ROI IDs for each sample.

### 3. Visualize Results
Generate a report with plots of the extracted time series.

```bash
python roi_augmentation/visualize_augmentation.py --output_dir "output/augmentation_results"
```
This will save a `visualization_report.png` in the output directory.
