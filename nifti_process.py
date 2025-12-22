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


def savez(file, *args, allow_pickle=False, **kwargs) -> None:
    buf = io.BytesIO()
    np.savez(buf, *args, allow_pickle=allow_pickle, **kwargs)

    with open(file, 'wb') as _f:
        _f.write(_cctx.compress(buf.getvalue()))


def split_plan(old, new):
    """Return (left, right, mode); mode ∈ {'pad','crop','same'}"""
    if old == new:
        return 0, 0, 'same'
    if old < new:
        tot = new - old
        left = tot // 2
        right = tot - left
        return left, right, 'pad'
    else:
        tot = old - new
        left = tot // 2
        right = tot - left
        return left, right, 'crop'


def pad_crop(img_data: np.ndarray,
             target_xyz=(96, 96, 96),
             fill_value: float = 0) -> np.ndarray:
    """
    Symmetrically pad/crop a 4D array on the first three axes to match `target_xyz`.

    Parameters
    ----------
    img_data : np.ndarray
        4D array with shape (X, Y, Z, T).
    target_xyz : tuple of int
        Target spatial shape (X, Y, Z).
    fill_value : float
        Constant value for padding.

    Returns
    -------
    new_data : np.ndarray
        4D array with shape (target_x, target_y, target_z, T).
    """

    # Parse the shape and extract T
    if img_data.ndim != 4:
        raise ValueError(f'Expect 4D array (X, Y, Z, T), got shape {img_data.shape}')

    img_X, img_Y, img_Z, _ = img_data.shape

    # Generate plan for each axis
    pxL, pxR, mx = split_plan(img_X, target_xyz[0])
    pyL, pyR, my = split_plan(img_Y, target_xyz[1])
    pzL, pzR, mz = split_plan(img_Z, target_xyz[2])

    # Crop before padding to avoid padding that will be removed
    new_data = img_data[
        slice(pxL, img_X - pxR) if mx == 'crop' else slice(None),
        slice(pyL, img_Y - pyR) if my == 'crop' else slice(None),
        slice(pzL, img_Z - pzR) if mz == 'crop' else slice(None),
        :
    ]

    # Apply symmetric padding
    pad_width = (
        (pxL if mx == 'pad' else 0, pxR if mx == 'pad' else 0),
        (pyL if my == 'pad' else 0, pyR if my == 'pad' else 0),
        (pzL if mz == 'pad' else 0, pzR if mz == 'pad' else 0),
        (0, 0)
    )
    if any(pw != (0, 0) for pw in pad_width):
        new_data = np.pad(new_data, pad_width=pad_width, mode='constant', constant_values=fill_value)

    return new_data


def mask_fmri(fmri: np.ndarray, mask_path: str) -> np.ndarray:
    """
    Apply a binary mask to fMRI data.

    Parameters
    ----------
    fmri : np.ndarray
        4D fMRI data array with shape (X, Y, Z, T).
    mask_path : str
        File path to the NIfTI mask.

    Returns
    -------
    masked_fmri : np.ndarray
        Masked fMRI data array.
    """
    # Load the mask
    mask_data = pad_crop(nib.load(mask_path).get_fdata().astype(bool), target_xyz=fmri.shape[:3], fill_value=0).astype(bool)

    masked_fmri = fmri * mask_data[..., np.newaxis]

    return masked_fmri


def global_zscore_nonzero(arr: np.ndarray, mean=None, std=None, eps=1e-8):
    """
    Global z-score on non-zero entries of arr. Zeros remain zeros.

    If mean/std are provided, use them (so you can apply the same global stats
    to multiple arrays, e.g., pre and post).
    """
    arr = np.asarray(arr)
    nz = (arr != 0)

    if mean is None or std is None:
        n = int(np.count_nonzero(nz))
        if n == 0:
            return arr, 0.0, 1.0

        # Because zeros are excluded by count, sums over the whole array are OK
        s = arr.sum(dtype=np.float64)
        ss = np.multiply(arr, arr, dtype=np.float64).sum(dtype=np.float64)

        mean = s / n
        var = ss / n - mean * mean
        if var < eps:
            var = eps
        std = float(np.sqrt(var))

    out = arr.astype(np.float16)
    out[nz] = (out[nz] - mean) / std
    return out, float(mean), float(std)


if __name__ == '__main__':
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description='Pad/Crop NIfTI image data to target size and save as NumPy (.npy or .npy.zst).')
    parser.add_argument('--type', '-t', type=str, required=True, help='Type of NIfTI file to process (2D or 4D).')
    parser.add_argument('--input', '-i', type=str, required=True, help='Input NIfTI file path.')
    parser.add_argument('--output', '-o', type=str, required=True, help='Output file path (.npy or .npy.zst).')
    parser.add_argument('--target_xyz', '-xyz', type=int, nargs=3, default=(96, 96, 96),
                        help='Target shape for the first three dimensions. Default is (96, 96, 96).')
    parser.add_argument('--fill_value', '-fv', type=float, default=0, help='Fill value for padding. Default is 0.')
    parser.add_argument('--force', '-f', action='store_true', help='Overwrite existing output files.')
    parser.add_argument('--mask', '-m', type=str, default=None, help='Mask NIfTI file path (only for 4D).')
    args = parser.parse_args()

    img_type = args.type
    if img_type not in ['2D', '4D']:
        raise ValueError(f'Type {img_type} is not supported.')

    input_path = args.input
    output_path = args.output  # output file path
    xyz = args.target_xyz
    fv = args.fill_value

    # Handle a single file only
    if not os.path.isfile(input_path):
        raise ValueError(f'Input path {input_path} is not a valid file.')

    if os.path.exists(output_path) and not args.force:
        raise ValueError(f'Output file {output_path} already exists.')

    if not (output_path.endswith('.npy') or output_path.endswith('.npy.zst')):
        raise ValueError(f'Output file {output_path} must have .npy or .npy.zst extension.')

    if img_type == '2D':
        data = nib.load(input_path).get_fdata()
    else:
        data = pad_crop(nib.load(input_path).get_fdata(), target_xyz=xyz, fill_value=fv)
        if args.mask is not None:
            data = mask_fmri(data, args.mask)
            data, data_mean, data_std = global_zscore_nonzero(data)
            if output_path.endswith('.npy.zst'):
                savez(output_path.replace('.npy.zst', '_meanstd.npz.zst'), mean=data_mean, std=data_std)
            else:
                np.savez(output_path.replace('.npy', '_meanstd.npz'), mean=data_mean, std=data_std)
        else:
            raise ValueError('Mask file must be provided for 4D data processing.')

    data = data.astype(np.float16)

    print(f'Data shape after processing: {data.shape}, size: {data.nbytes / (1024 ** 2):.2f} MiB')

    if output_path.endswith('.npy'):
        np.save(output_path, data, allow_pickle=False)
    else:
        save(output_path, data, allow_pickle=False)
