# -*- coding: utf-8 -*-

import argparse
import matplotlib.pyplot as plt
import nibabel as nib
import numpy as np
from nilearn.maskers import NiftiLabelsMasker


def extract_roi_time_series(fmri_path: str, atlas_path: str) -> np.ndarray:
    """使用 3D atlas 从 4D fMRI 中提取 ROI 时间序列。

    Args:
        fmri_path: 4D fMRI NIfTI 路径
        atlas_path: 3D atlas NIfTI 路径（例如合并后的 150 ROI 图谱）

    Returns:
        roi_time_series: np.ndarray, shape (n_rois, n_timepoints)
    """
    print(f"\n加载功能数据: {fmri_path}")
    print(f"加载图谱: {atlas_path}")

    fmri_img = nib.load(fmri_path)
    atlas_img = nib.load(atlas_path)

    # 这里假设 atlas 已经是和 fMRI 对齐/重采样好的（例如通过 combine_atlas.py 之后得到的 merged_atlas150）
    print("初始化 NiftiLabelsMasker...")
    masker = NiftiLabelsMasker(
        labels_img=atlas_img,
        standardize=True,
        strategy='mean',
        verbose=1,
    )

    print("正在提取 ROI 时间序列 (降维)...")
    roi_time_series_t = masker.fit_transform(fmri_img)  # (n_timepoints, n_rois)

    # 转置成 (n_rois, n_timepoints)
    roi_time_series = roi_time_series_t.T.astype(np.float32)
    print(f"提取完成，ROI 时间序列形状: {roi_time_series.shape} (ROI, timepoints)")
    return roi_time_series


def main():
    parser = argparse.ArgumentParser(
        description="从 4D fMRI 和 3D atlas 计算 ROI×time 序列，并保存为 .npy 和可视化图像。")
    parser.add_argument('--fmri', default='/mnt/dataset4/wangmo/fMRI_ukb/rfMRI.nii.gz',
                        help='4D fMRI NIfTI 路径，例如 /path/to/rfMRI.nii.gz')
    parser.add_argument('--atlas', default='merged_atlas150.nii.gz',
                        help='3D atlas NIfTI 路径（默认: merged_atlas150.nii.gz）')
    parser.add_argument('--out-npy', default='roi_time_series150.npy',
                        help='输出 ROI×time numpy 文件名（默认: roi_time_series150.npy）')
    parser.add_argument('--out-fig', default='roi_matrix_heatmap.png',
                        help='输出 ROI 时间序列热力图文件名（默认: roi_matrix_heatmap.png）')
    args = parser.parse_args()

    roi_ts = extract_roi_time_series(args.fmri, args.atlas)
    np.save(args.out_npy, roi_ts)
    print(f"ROI 时间序列已保存到 {args.out_npy}")


if __name__ == '__main__':
    main()
