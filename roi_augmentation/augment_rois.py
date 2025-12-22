import os
import glob
import argparse
import numpy as np
import pandas as pd
import nibabel as nib
from nibabel.processing import resample_to_output
from nilearn.image import resample_img
from tqdm import tqdm

def main():
    parser = argparse.ArgumentParser(description="Augment ROIs by merging adjacent regions.")
    parser.add_argument("--fmri", type=str, required=True, help="Path to the input 4D fMRI NIfTI file.")
    parser.add_argument("--atlas_dir", type=str, required=True, help="Directory containing atlas NIfTI files.")
    parser.add_argument("--output_dir", type=str, required=True, help="Directory to save outputs.")
    parser.add_argument("--n_samples", type=int, default=2000, help="Number of augmented samples to generate.")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    print(f"Loading fMRI data from {args.fmri}...")
    try:
        fmri_img = nib.load(args.fmri)
        fmri_data = fmri_img.get_fdata() # (X, Y, Z, T)
        fmri_affine = fmri_img.affine
        print(f"fMRI shape: {fmri_data.shape}")
    except Exception as e:
        print(f"Error loading fMRI file: {e}")
        return

    # 1. Prepare Atlases
    print("Scanning atlases and adjacency files...")
    
    # Look for adjacency files first
    adj_dir = os.path.join(args.atlas_dir, "adjacency")
    if not os.path.exists(adj_dir):
        print(f"Error: Adjacency directory {adj_dir} not found. Please run roi_augmentation/prepare_atlas_neighbors.py first.")
        return

    processed_atlases = [] # List of (filename, data_array, adjacency_list)
    
    adj_files = glob.glob(os.path.join(adj_dir, "*_adj.npy"))
    
    for adj_fpath in tqdm(adj_files, desc="Loading Atlases"):
        # Infer atlas filename from adjacency filename
        # adj file: name_adj.npy
        # atlas file: name.nii.gz or name.nii
        base_name = os.path.basename(adj_fpath).replace("_adj.npy", "")
        
        # Try to find the corresponding atlas file
        # We prefer the one that matches the base name exactly (which should be the 2mm one if prep script ran)
        candidates = [
            os.path.join(args.atlas_dir, base_name + ".nii.gz"),
            os.path.join(args.atlas_dir, base_name + ".nii")
        ]
        
        atlas_path = None
        for c in candidates:
            if os.path.exists(c):
                atlas_path = c
                break
        
        if not atlas_path:
            print(f"Warning: Atlas file for {base_name} not found.")
            continue
            
        try:
            # Load Adjacency
            adj = np.load(adj_fpath)
            if len(adj) == 0:
                continue
                
            # Load Atlas Data
            img = nib.load(atlas_path)
            
            # Check if we need to resample to match fMRI geometry exactly
            # We assume the prep script made them 2mm isotropic.
            # If the fMRI is also 2mm isotropic but has a different affine (e.g. shifted origin),
            # we still need to resample to be safe.
            if img.shape[:3] != fmri_data.shape[:3] or not np.allclose(img.affine, fmri_affine):
                # Resample to match fMRI geometry (nearest neighbor for labels)
                img = resample_img(img, target_affine=fmri_affine, target_shape=fmri_data.shape[:3], interpolation='nearest')
            
            data = img.get_fdata().astype(int)
            
            processed_atlases.append({
                'name': base_name,
                'data': data,
                'adjacency': adj
            })
            
        except Exception as e:
            print(f"Error loading {base_name}: {e}")

    if not processed_atlases:
        print("No valid atlases available after processing.")
        return

    # 2. Sampling Loop
    print(f"Starting sampling of {args.n_samples} regions...")
    
    augmented_timeseries = []
    augmentation_log = []

    for i in tqdm(range(args.n_samples), desc="Sampling"):
        # Randomly select an atlas
        atlas_info = processed_atlases[np.random.randint(len(processed_atlases))]
        
        # Randomly select a pair of connected ROIs
        pair_idx = np.random.randint(len(atlas_info['adjacency']))
        roi1, roi2 = atlas_info['adjacency'][pair_idx]
        
        # Create merged mask
        mask = (atlas_info['data'] == roi1) | (atlas_info['data'] == roi2)
        
        # Extract time series
        # fmri_data is (X, Y, Z, T), mask is (X, Y, Z)
        # We want mean over the mask
        
        if np.sum(mask) == 0:
            # Should not happen if adjacency is correct, but safety check
            ts = np.zeros(fmri_data.shape[3])
        else:
            # Masking: fmri_data[mask] returns (N_voxels, T)
            # Mean over voxels -> (T,)
            ts = fmri_data[mask].mean(axis=0)
        
        augmented_timeseries.append(ts)
        
        augmentation_log.append({
            'sample_id': i,
            'atlas_name': atlas_info['name'],
            'roi1': roi1,
            'roi2': roi2
        })

    # 3. Save Results
    output_ts_path = os.path.join(args.output_dir, "augmented_timeseries.npy")
    output_log_path = os.path.join(args.output_dir, "augmentation_log.tsv")
    
    print(f"Saving time series to {output_ts_path}...")
    np.save(output_ts_path, np.array(augmented_timeseries))
    
    print(f"Saving log to {output_log_path}...")
    pd.DataFrame(augmentation_log).to_csv(output_log_path, sep='\t', index=False)
    
    print("Done!")

if __name__ == "__main__":
    main()
