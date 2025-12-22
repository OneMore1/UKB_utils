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

# make sure to keep this block in sync with update_script_b64.sh
SCRIPT_NAME="nifti_process.py"
# TODO

# extract subject id txt
TXT_FILE=fMRI_20227_id.txt
# TODO

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
  local FRAME_LENGTH=100

  prepare_subject_data "$sub_file_idx" "$base_path" || return 1

  local SUBJECT_DIR="${base_path}/${sub_file_idx}"

  # check required files
  if [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard.nii.gz" ]] ||
    [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" ]]; then
    echo "Required file not found for subject ${sub_file_idx}."
    rm -rf "${SUBJECT_DIR}"
    return 1
  fi

  echo "[${sub_file_idx}] Starting rfMRI processing..."

  export FSLOUTPUTTYPE=NIFTI

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
  echo "[${sub_file_idx}] Converting warped volume to npy.zst..."
  python3 "$SCRIPT_NAME" \
    -t 4D \
    -i "${SUBJECT_DIR}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.nii" \
    -o "${SUBJECT_DIR}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.npy.zst"

  # upload to DNAnexus
  echo "[${sub_file_idx}] Uploading rfMRI artifact to DNAnexus..."
  dx mkdir -p "${DX_PROJECT_CONTEXT_ID}:/datasets/fMRI/${sub_file_idx}"
  dx upload \
    --wait \
    --no-progress \
    --path "${DX_PROJECT_CONTEXT_ID}:/datasets/fMRI/${sub_file_idx}/" \
    "${SUBJECT_DIR}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.npy.zst"

  rm -rf "${SUBJECT_DIR}"

  echo "[${sub_file_idx}] rfMRI processing complete."
}

START_LINE="$1"
END_LINE="$2"

BASE_PATH="."

sed -n "${START_LINE},${END_LINE}p" "$TXT_FILE" | while IFS= read -r sub_file_idx; do
  echo "process_rfMRI $sub_file_idx $BASE_PATH"
  process_rfMRI "$sub_file_idx" "$BASE_PATH" || {
    echo "skip $sub_file_idx"
    continue
  }
done

rm "$SCRIPT_NAME"
rm "$TXT_FILE"
