# -*- coding: utf-8 -*-

import argparse
import io
import os

import nibabel as nib
import numpy as np
import zstandard as zstd

_LEVEL = 8
_WRITE_CHECKSUM = True
_WRITE_CONTENT_SIZE = True

_cctx = zstd.ZstdCompressor(level=_LEVEL, write_checksum=_WRITE_CHECKSUM, write_content_size=_WRITE_CONTENT_SIZE)


def save(file, arr, allow_pickle=False) -> None:
    buf = io.BytesIO()
    np.save(buf, arr, allow_pickle=allow_pickle)

    with open(file, 'wb') as _f:
        _f.write(_cctx.compress(buf.getvalue()))


def convert_nifti_to_npy(input_path, output_path, quiet=False):
    try:
        # Load the NIfTI file
        if not quiet:
            print(f'Loading: {input_path}')
        img = nib.load(input_path)

        # Get the data as a numpy array
        # .get_fdata() handles scaling and floating point conversion automatically
        data = img.get_fdata()

        data[data < 0] = 0  # Set negative values to zero
        # do z-score normalization for > 0 values
        positive_mask = data > 0
        if np.any(positive_mask):
            if not quiet:
                print(f'Performing z-score normalization on {np.sum(positive_mask)} positive voxels.')
            data_mean = np.mean(data[positive_mask])
            data_std = np.std(data[positive_mask])
            data_var = np.var(data[positive_mask])
            data[positive_mask] = (data[positive_mask] - data_mean) / data_std

        # Ensure the output directory exists
        output_dir = os.path.dirname(output_path)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir)

        # Save as .npy
        save(output_path, data)
        if not quiet:
            print(f'Successfully saved to: {output_path}')
            print(f'Array shape: {data.shape}')

        # save mean / std / var to csv file
        stats_path = os.path.splitext(output_path)[0] + '_stats.csv'
        with open(stats_path, 'w') as f:
            f.write(f'eid,Mean,Std,Var\n')
            f.write(f'{os.path.basename(output_path)},{data_mean},{data_std},{data_var}\n')

    except Exception as e:
        print(f'Error: {e}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Convert .nii.gz MRI files to .npy format.')

    # Define arguments
    parser.add_argument('-i', '--input', required=True, help='Path to the input .nii.gz file')
    parser.add_argument('-o', '--output', required=True, help='Path to save the output .npy.zst file')
    parser.add_argument('--quiet', '-q', action='store_true', help='Suppress non-error output')

    args = parser.parse_args()

    if not args.quiet:
        print(f'Processing input: {args.input}')
        print(f'Output path: {args.output}')

    convert_nifti_to_npy(args.input, args.output, quiet=args.quiet)
