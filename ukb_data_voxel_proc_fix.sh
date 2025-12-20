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

SUB_LIST="voxel_fix_list_dedup.txt"
dx download --no-progress "voxel_fix_list_dedup.txt"

SCRIPT_NAME="nifti_mask_proc.py"
wget https://raw.githubusercontent.com/OneMore1/UKB_utils/master/$SCRIPT_NAME

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

process_fixing() {
  local sub_file_idx="$1"
  local base_path="$2"

  prepare_subject_data "$sub_file_idx" "$base_path" || return 1

  local SUBJECT_DIR="${base_path}/${sub_file_idx}"

  # check required files
  if [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/mask.nii.gz" ]]; then
    echo "Required file not found for subject ${sub_file_idx}."
    rm -rf "${SUBJECT_DIR}"
    return 1
  fi

  export FSLOUTPUTTYPE=NIFTI

  # warp to MNI space
  echo "[${sub_file_idx}] Warping to MNI space..."
  applywarp \
    -i "${SUBJECT_DIR}/fMRI/rfMRI.ica/mask.nii.gz" \
    -r "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard.nii.gz" \
    -w "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" \
    -o "${SUBJECT_DIR}/fMRI/rfMRI.ica/mask_MNI.nii" \
    --interp=spline

  echo "[${sub_file_idx}] Getting fMRI data in MNI space..."
  name="rfMRI_s200l100_MNI_nonlin.npy.zst"
  folder="/datasets/fMRI/${sub_file_idx}"

  latest_id="$(dx find data --class file --name "$name" --path "$folder" --json | jq -r 'sort_by(.describe.modified // 0) | last | .id')"

  dx download --no-progress "$latest_id" -o "${SUBJECT_DIR}/${name}"

  mkdir -p fMRI_masked

  echo "[${sub_file_idx}] Applying mask to fMRI data..."
  python3 $SCRIPT_NAME \
    "${SUBJECT_DIR}/rfMRI_s200l100_MNI_nonlin.npy.zst" \
    "${SUBJECT_DIR}/fMRI/rfMRI.ica/mask_MNI.nii" \
    "fMRI_masked/${sub_file_idx}_rfMRI_s200l100_MNI_nonlin_masked"

  rm -rf "${SUBJECT_DIR}"

  echo "[${sub_file_idx}] rfMRI fix processing complete."
}

START_LINE="$1"
END_LINE="$2"

BASE_PATH="."

sed -n "${START_LINE},${END_LINE}p" "$SUB_LIST" | while IFS= read -r sub_file_idx; do
  echo "process_fixing $sub_file_idx $BASE_PATH"
  process_fixing "$sub_file_idx" "$BASE_PATH" || {
    echo "skip $sub_file_idx"
    continue
  }
done

rm "$SCRIPT_NAME"
rm "$SUB_LIST"

tar -cvf fMRI_masked_s${START_LINE}_e${END_LINE}.tar fMRI_masked/
rm -rf fMRI_masked

echo "[INFO] Uploading to /datasets/fMRI_masked/ ..."
dx mkdir -p /datasets/fMRI_masked/
dx upload \
  --wait \
  --path "/datasets/fMRI_masked/" \
  fMRI_masked_s${START_LINE}_e${END_LINE}.tar

rm -rf fMRI_masked_s${START_LINE}_e${END_LINE}.tar
