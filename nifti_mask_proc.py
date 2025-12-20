# -*- coding: utf-8 -*-

import argparse
import io

import nibabel as nib
import numpy as np
import zstandard as zstd

_LEVEL = 8
_WRITE_CHECKSUM = True
_WRITE_CONTENT_SIZE = True

_cctx = zstd.ZstdCompressor(level=_LEVEL, write_checksum=_WRITE_CHECKSUM, write_content_size=_WRITE_CONTENT_SIZE)
_dctx = zstd.ZstdDecompressor()


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


def load(file, allow_pickle=False, fix_imports=True, encoding='ASCII'):
    with open(file, 'rb') as _f:
        data = _f.read()

    buf = io.BytesIO(_dctx.decompress(data))
    return np.load(buf, allow_pickle=allow_pickle, fix_imports=fix_imports, encoding=encoding)


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
    Symmetrically pad/crop a 3D array on the first three axes to match `target_xyz`.

    Parameters
    ----------
    img_data : np.ndarray
        3D array with shape (X, Y, Z).
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
    if img_data.ndim != 3:
        raise ValueError(f'Expect 3D array (X, Y, Z), got shape {img_data.shape}')

    img_X, img_Y, img_Z = img_data.shape

    # Generate plan for each axis
    pxL, pxR, mx = split_plan(img_X, target_xyz[0])
    pyL, pyR, my = split_plan(img_Y, target_xyz[1])
    pzL, pzR, mz = split_plan(img_Z, target_xyz[2])

    # Crop before padding to avoid padding that will be removed
    new_data = img_data[
        slice(pxL, img_X - pxR) if mx == 'crop' else slice(None),
        slice(pyL, img_Y - pyR) if my == 'crop' else slice(None),
        slice(pzL, img_Z - pzR) if mz == 'crop' else slice(None)
    ]

    # Apply symmetric padding
    pad_width = (
        (pxL if mx == 'pad' else 0, pxR if mx == 'pad' else 0),
        (pyL if my == 'pad' else 0, pyR if my == 'pad' else 0),
        (pzL if mz == 'pad' else 0, pzR if mz == 'pad' else 0)
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
    mask_nii = nib.load(mask_path)
    mask_data = mask_nii.get_fdata().astype(bool)
    mask_data = pad_crop(mask_data, target_xyz=fmri.shape[:3], fill_value=0).astype(bool)

    if fmri.shape[:3] != mask_data.shape:
        raise ValueError(f'Mask shape {mask_data.shape} does not match fMRI spatial shape {fmri.shape[:3]}')

    # Apply the mask
    masked_fmri = fmri * mask_data[..., np.newaxis]

    return masked_fmri


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Apply a binary mask to fMRI data.')
    parser.add_argument('fmri_path', type=str, help='Path to the input fMRI NIfTI file.')
    parser.add_argument('mask_path', type=str, help='Path to the binary mask NIfTI file.')
    parser.add_argument('output_prefix', type=str, help='Prefix for saving the masked fMRI NumPy files.')

    args = parser.parse_args()

    # Load fMRI data
    fmri_data = load(args.fmri_path)

    # Apply the mask
    masked_fmri_data = mask_fmri(fmri_data, args.mask_path)

    masked_fmri_data_pre = masked_fmri_data[..., :40]
    masked_fmri_data_post = masked_fmri_data[..., -40:]

    save(args.output_prefix + '_pre40_masked.npy.zst', masked_fmri_data_pre)
    save(args.output_prefix + '_post40_masked.npy.zst', masked_fmri_data_post)
