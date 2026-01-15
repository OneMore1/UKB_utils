#!/usr/bin/env bash
set -euo pipefail

# check python3 installed
if ! command -v python3 &>/dev/null; then
  echo "Python3 could not be found."
  exit 1
fi

pip3 install nilearn

# check zstd + base64 installed
if ! command -v zstd &>/dev/null; then
  echo "zstd could not be found."
  exit 1
fi
if ! command -v base64 &>/dev/null; then
  echo "base64 command could not be found."
  exit 1
fi

# check fsl installed
if ! command -v fslroi &>/dev/null || ! command -v applywarp &>/dev/null; then
  echo "FSL could not be found."
  exit 1
fi

# check tar installed
if ! command -v tar &>/dev/null; then
  echo "tar could not be found."
  exit 1
fi

atlas_list=(
  AA424_2mm
  AAL
  Glasser_2mm
  Schaefer2018_100Parcels_17Networks_order_FSLMNI152_2mm
  Schaefer2018_200Parcels_17Networks_order_FSLMNI152_2mm
  Schaefer2018_300Parcels_17Networks_order_FSLMNI152_2mm
  Schaefer2018_400Parcels_17Networks_order_FSLMNI152_2mm
  Schaefer2018_500Parcels_17Networks_order_FSLMNI152_2mm
  Schaefer2018_600Parcels_17Networks_order_FSLMNI152_2mm
  Schaefer2018_700Parcels_17Networks_order_FSLMNI152_2mm
  Schaefer2018_800Parcels_17Networks_order_FSLMNI152_2mm
  Schaefer2018_900Parcels_17Networks_order_FSLMNI152_2mm
  Schaefer2018_1000Parcels_17Networks_order_FSLMNI152_2mm
  Tian_Subcortex_S1_3T
  Tian_Subcortex_S2_3T
  Tian_Subcortex_S3_3T
  Tian_Subcortex_S4_3T
)

atlas_list_vox2fc=(
  Glasser_2mm
  Schaefer2018_100Parcels_17Networks_order_FSLMNI152_2mm
  Schaefer2018_400Parcels_17Networks_order_FSLMNI152_2mm
  Tian_Subcortex_S3_3T
)

process_rfMRI() {
  local sub_file_idx="$1"
  local base_path="$2"

  local FRAME_START=200
  local FRAME_LENGTH=40

  local SUBJECT_DIR="${base_path}/${sub_file_idx}"

  # check required files
  if [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/mask.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/example_func.nii.gz" ]]; then
    echo "Required file not found for subject ${sub_file_idx}."
    return 1
  fi

  echo "[${sub_file_idx}] Starting rfMRI processing..."
  export FSLOUTPUTTYPE=NIFTI

  echo "[${sub_file_idx}] Warping mask to MNI space..."
  applywarp \
    -i "${SUBJECT_DIR}/fMRI/rfMRI.ica/mask.nii.gz" \
    -r "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard.nii.gz" \
    -w "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" \
    -o "${SUBJECT_DIR}/mask_MNI.nii" \
    --interp=nn

  echo "[${sub_file_idx}] Cutting frames ${FRAME_START}-${FRAME_START}+${FRAME_LENGTH}..."
  fslroi \
    "${SUBJECT_DIR}/fMRI/rfMRI.nii.gz" \
    "${SUBJECT_DIR}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}.nii" \
    0 -1 0 -1 0 -1 "$FRAME_START" "$FRAME_LENGTH"

  echo "[${sub_file_idx}] Warping to MNI space..."
  applywarp \
    -i "${SUBJECT_DIR}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}.nii" \
    -r "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard.nii.gz" \
    -w "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" \
    -o "${SUBJECT_DIR}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.nii" \
    --interp=spline

  mkdir -p "${SUBJECT_DIR}/voxel_process/${sub_file_idx}"
  echo "[${sub_file_idx}] Converting warped volume to npy.zst..."
  python3 nifti_process.py \
    -t 4D \
    -i "${SUBJECT_DIR}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.nii" \
    -m "${SUBJECT_DIR}/mask_MNI.nii" \
    -o "${SUBJECT_DIR}/voxel_process/${sub_file_idx}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.npy.zst"

  echo "[${sub_file_idx}] Generating inverse warp for atlas processing..."
  invwarp \
    -w "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" \
    -o "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/standard2example_func_warp.nii" \
    -r "${SUBJECT_DIR}/fMRI/rfMRI.ica/example_func.nii.gz"

  mkdir -p "${SUBJECT_DIR}/atlas_data"
  mkdir -p "${SUBJECT_DIR}/voxel2atlas/${sub_file_idx}"

  for atlas in "${atlas_list[@]}"; do
    echo "[${sub_file_idx}] Processing atlas: ${atlas}..."

    applywarp \
      -i ./roi_augmentation/atlas_data/${atlas}.nii.gz \
      -r "${SUBJECT_DIR}/fMRI/rfMRI.ica/example_func.nii.gz" \
      -w "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/standard2example_func_warp.nii" \
      -o "${SUBJECT_DIR}/atlas_data/${atlas}.nii" \
      --interp=nn

    if [[ " ${atlas_list_vox2fc[*]} " == *" ${atlas} "* ]]; then
      echo "[${sub_file_idx}] Generating voxel-to-FC for atlas: ${atlas}..."
      python3 volume2fc.py \
        --fmri "${SUBJECT_DIR}/fMRI/rfMRI.nii.gz" \
        --atlas "${SUBJECT_DIR}/atlas_data/${atlas}.nii" \
        --out-npy "${SUBJECT_DIR}/voxel2atlas/${sub_file_idx}/vox2fc_${atlas}.npy"
    fi
  done

  python3 roi_augmentation/augment_rois.py \
    --fmri "${SUBJECT_DIR}/fMRI/rfMRI.nii.gz" \
    --adjacency_dir "./roi_augmentation/atlas_data/adjacency" \
    --atlas_dir "${SUBJECT_DIR}/atlas_data" \
    --output_dir "${SUBJECT_DIR}/voxel2atlas/${sub_file_idx}"

  echo "[${sub_file_idx}] rfMRI processing complete."
}

process_rfMRI sub-demo .
