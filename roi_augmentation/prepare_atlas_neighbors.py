import os
import glob
import numpy as np
import nibabel as nib
from nibabel.processing import resample_to_output
from tqdm import tqdm

def get_adjacency_graph(atlas_data):
    """
    Finds all pairs of adjacent ROIs in the 3D atlas.
    Returns a list of tuples (roi1, roi2).
    """
    pairs = set()
    
    # Check neighbors in x, y, z directions
    for axis in range(3):
        # Compare slice i with slice i+1
        # We want to find voxels where the label changes
        
        # Create views shifted by 1 voxel
        sl_d1 = [slice(None)] * 3
        sl_d1[axis] = slice(0, -1)
        
        sl_d2 = [slice(None)] * 3
        sl_d2[axis] = slice(1, None)
        
        d1 = atlas_data[tuple(sl_d1)]
        d2 = atlas_data[tuple(sl_d2)]
        
        # Find boundaries between different non-zero regions
        mask = (d1 != d2) & (d1 != 0) & (d2 != 0)
        
        if not np.any(mask):
            continue
            
        # Extract the pairs of labels at the boundaries
        p1 = d1[mask]
        p2 = d2[mask]
        
        # Stack and sort to ensure (a,b) is treated same as (b,a)
        p_stacked = np.stack([p1, p2], axis=1)
        p_stacked.sort(axis=1)
        
        # Find unique pairs in this axis
        unique_pairs = np.unique(p_stacked, axis=0)
        
        for row in unique_pairs:
            pairs.add(tuple(row))
            
    return list(pairs)

def main():
    atlas_dir = r"C:\Users\47841\Desktop\ICML2026\atlas_data"
    adj_dir = os.path.join(atlas_dir, "adjacency")
    os.makedirs(adj_dir, exist_ok=True)
    
    print(f"Scanning atlases in {atlas_dir}...")
    files = glob.glob(os.path.join(atlas_dir, "*.nii.gz")) + glob.glob(os.path.join(atlas_dir, "*.nii"))
    
    for fpath in tqdm(files, desc="Preparing Atlases"):
        fname = os.path.basename(fpath)
        
        # Skip if it's a file we just generated (avoid loops if running multiple times)
        if "_2mm.nii" in fname and os.path.exists(fpath.replace("_2mm.nii", ".nii")):
             # This logic is tricky, let's just process everything but be careful about overwriting
             pass

        try:
            img = nib.load(fpath)
            
            # 1. Check and Enforce 2mm Resolution
            zooms = img.header.get_zooms()[:3]
            is_2mm = np.allclose(zooms, [2.0, 2.0, 2.0], atol=0.05)
            
            if not is_2mm:
                print(f"Resampling {fname} to 2mm isotropic...")
                img = resample_to_output(img, voxel_sizes=(2.0, 2.0, 2.0), order=0)
                
                # Save the resampled version
                # If original was 'atlas.nii.gz', new is 'atlas_2mm.nii.gz'
                # If it already has _2mm, we might be re-resampling, which is fine but maybe redundant.
                if "_2mm" not in fname:
                    new_fname = fname.replace(".nii", "_2mm.nii")
                    new_fpath = os.path.join(atlas_dir, new_fname)
                    nib.save(img, new_fpath)
                    fpath = new_fpath # Update fpath to point to the 2mm version
                    fname = new_fname
                else:
                    # It says 2mm but header wasn't close enough? Overwrite.
                    nib.save(img, fpath)
            
            # 2. Compute Adjacency
            # Check if adjacency file already exists
            adj_fname = fname.replace(".nii.gz", "").replace(".nii", "") + "_adj.npy"
            adj_fpath = os.path.join(adj_dir, adj_fname)
            
            if os.path.exists(adj_fpath):
                # print(f"Adjacency file exists for {fname}, skipping computation.")
                continue

            data = img.get_fdata().astype(int)
            adj = get_adjacency_graph(data)
            
            if not adj:
                print(f"Warning: No adjacent ROIs found in {fname}")
            
            # 3. Save Adjacency
            np.save(adj_fpath, np.array(adj))
            
        except Exception as e:
            print(f"Error processing {fname}: {e}")

    print("Preparation complete.")

if __name__ == "__main__":
    main()
