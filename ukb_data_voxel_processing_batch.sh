#!/usr/bin/env bash

set -euo pipefail

# check python3 installed
if ! command -v python3 &>/dev/null; then
  echo "Python3 could not be found."
  exit 1
fi

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

# check DNAnexus env
: "${DX_PROJECT_CONTEXT_ID:?DX_PROJECT_CONTEXT_ID is not set}"

# download nifti_process.py
wget -q https://raw.githubusercontent.com/OneMore1/UKB_utils/master/nifti_process.py
wget -q https://raw.githubusercontent.com/OneMore1/UKB_utils/master/volume2fc.py
wget -q https://raw.githubusercontent.com/OneMore1/UKB_utils/master/roi_augmentation/augment_rois.py

# extract subject id txt
TXT_FILE=final_list_with_disease_mapped.csv
dx download --no-progress /mri_process_utils/final_list_with_disease_mapped.csv
dx download --no-progress --recursive /mri_process_utils/roi_augmentation/atlas_data

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

prepare_subject_data() {
  local sub_file_idx="$1"
  local base_path="$2"

  echo "[${sub_file_idx}] Locating archive in DNAnexus..."

  # Locate, validate, and unpack the DNAnexus zip for the subject.
  local dx_rel_path=$(
    dx find data --name "${sub_file_idx}.zip" --json |
      jq -r '.[0] | .describe.folder + "/" + .describe.name' 2>/dev/null || true
  )

  if [[ -z "$dx_rel_path" ]] || [[ "$dx_rel_path" == "/" ]]; then
    echo "File ${sub_file_idx}.zip not found in DNAnexus."
    return 1
  fi

  echo "[${sub_file_idx}] Downloading input archive..."
  mkdir -p "${base_path}/${sub_file_idx}"
  dx download --no-progress "$dx_rel_path" -o "${base_path}/${sub_file_idx}/"

  if [[ ! -f "${base_path}/${sub_file_idx}/${sub_file_idx}.zip" ]]; then
    echo "Failed to download ${sub_file_idx}.zip from DNAnexus."
    rm -rf "${base_path}/${sub_file_idx}"
    return 1
  fi

  echo "[${sub_file_idx}] Unzipping input archive..."
  python3 -m zipfile \
    -e "${base_path}/${sub_file_idx}/${sub_file_idx}.zip" "${base_path}/${sub_file_idx}/"

  rm -f "${base_path}/${sub_file_idx}/${sub_file_idx}.zip"

  echo "[${sub_file_idx}] Input data ready."
}

process_rfMRI() {
  local sub_file_idx="$1"
  local base_path="$2"

  local FRAME_START=200
  local FRAME_LENGTH=40

  prepare_subject_data "$sub_file_idx" "$base_path" || return 1

  local SUBJECT_DIR="${base_path}/${sub_file_idx}"

  # check required files
  if [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/mask.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/example_func.nii.gz" ]]; then
    echo "Required file not found for subject ${sub_file_idx}."
    rm -rf "${SUBJECT_DIR}"
    return 1
  fi

  echo "[${sub_file_idx}] Starting rfMRI processing..."

  export FSLOUTPUTTYPE=NIFTI

  # ========== Voxel Processing Steps ==========
  # warp mask to MNI space
  echo "[${sub_file_idx}] Warping mask to MNI space..."
  applywarp \
    -i "${SUBJECT_DIR}/fMRI/rfMRI.ica/mask.nii.gz" \
    -r "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard.nii.gz" \
    -w "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" \
    -o "${SUBJECT_DIR}/mask_MNI.nii" \
    --interp=nn

  # cut frames
  echo "[${sub_file_idx}] Cutting frames ${FRAME_START}-${FRAME_START}+${FRAME_LENGTH}..."
  fslroi \
    "${SUBJECT_DIR}/fMRI/rfMRI.nii.gz" \
    "${SUBJECT_DIR}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}.nii" \
    0 -1 0 -1 0 -1 "$FRAME_START" "$FRAME_LENGTH"

  # warp to MNI space
  echo "[${sub_file_idx}] Warping to MNI space..."
  applywarp \
    -i "${SUBJECT_DIR}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}.nii" \
    -r "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard.nii.gz" \
    -w "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" \
    -o "${SUBJECT_DIR}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.nii" \
    --interp=spline

  # convert to npy.zst using the generated nifti_process.py
  mkdir -p "${SUBJECT_DIR}/voxel_process/${sub_file_idx}"
  echo "[${sub_file_idx}] Converting warped volume to npy.zst..."
  python3 nifti_process.py \
    -t 4D \
    -i "${SUBJECT_DIR}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.nii" \
    -m "${SUBJECT_DIR}/mask_MNI.nii" \
    -o "${SUBJECT_DIR}/voxel_process/${sub_file_idx}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.npy.zst"

  # upload to DNAnexus
  echo "[${sub_file_idx}] Uploading rfMRI artifact to DNAnexus..."
  dx mkdir -p "/datasets/fMRI_rb/${sub_file_idx}"
  dx upload \
    --wait \
    --no-progress \
    --recursive \
    --path "/datasets/fMRI_rb/" \
    "${SUBJECT_DIR}/voxel_process/${sub_file_idx}"

  # ========== ROI Atlas Processing Steps ==========
  echo "[${sub_file_idx}] Generating inverse warp for atlas processing..."
  invwarp \
    -w "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" \
    -o "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/standard2example_func_warp.nii" \
    -r "${SUBJECT_DIR}/fMRI/rfMRI.ica/example_func.nii.gz"

  dx mkdir -p "/datasets/voxel_atlas_rb/${sub_file_idx}"

  mkdir -p "${SUBJECT_DIR}/atlas_data"
  mkdir -p "${SUBJECT_DIR}/voxel2atlas/${sub_file_idx}"

  for atlas in "${atlas_list[@]}"; do
    echo "[${sub_file_idx}] Processing atlas: ${atlas}..."

    applywarp \
      -i ./atlas_data/${atlas}.nii.gz \
      -r "${SUBJECT_DIR}/fMRI/rfMRI.ica/example_func.nii.gz" \
      -w "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/standard2example_func_warp.nii" \
      -o ${SUBJECT_DIR}/atlas_data/${atlas}.nii

    python3 augment_rois.py \
      --fmri "${SUBJECT_DIR}/fMRI/rfMRI.nii.gz" \
      --atlas "${SUBJECT_DIR}/atlas_data/${atlas}.nii" \
      --output_dir "${SUBJECT_DIR}/voxel2atlas/${sub_file_idx}" \

    if [[ " ${atlas_list_vox2fc[*]} " == *" ${atlas} "* ]]; then
      echo "[${sub_file_idx}] Generating voxel-to-FC for atlas: ${atlas}..."
      python3 volume2fc.py \
        --fmri "${SUBJECT_DIR}/fMRI/rfMRI.nii.gz" \
        --atlas "${SUBJECT_DIR}/atlas_data/${atlas}.nii" \
        --out-npy "${SUBJECT_DIR}/voxel2atlas/${sub_file_idx}/vox2fc_${atlas}.npy"
    fi

    # upload folder "${SUBJECT_DIR}/voxel2atlas"
    dx upload \
      --wait \
      --no-progress \
      --recursive \
      --path "/datasets/voxel_atlas_rb/" \
      "${SUBJECT_DIR}/voxel2atlas/${sub_file_idx}"
  done

  # ========== Clean up ==========
  rm -rf "${SUBJECT_DIR}"

  echo "[${sub_file_idx}] rfMRI processing complete."
}

START_LINE=$(($1 + 1))
END_LINE=$(($2 + 1))

BASE_PATH="."

sed -n "${START_LINE},${END_LINE}p" "$TXT_FILE" |
  awk -F',' 'NF {gsub(/^\s+|\s+$/, "", $1); print $1}' |
  while IFS= read -r sub_file_idx; do
    echo "process_rfMRI $sub_file_idx $BASE_PATH"
    process_rfMRI "$sub_file_idx" "$BASE_PATH" || {
      echo "skip $sub_file_idx"
      continue
    }
  done

rm nifti_process.py volume2fc.py augment_rois.py
rm "$TXT_FILE"
