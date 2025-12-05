#!/usr/bin/env bash

set -euo pipefail

# check python3 installed
if ! command -v python3 &> /dev/null; then
    echo "Python3 could not be found."
    exit 1
fi

# check zstd + base64 installed
if ! command -v zstd &> /dev/null; then
    echo "zstd could not be found."
    exit 1
fi

if ! command -v base64 &> /dev/null; then
    echo "base64 command could not be found."
    exit 1
fi

# check fsl installed
if ! command -v fslroi &> /dev/null || ! command -v applywarp &> /dev/null; then
    echo "FSL could not be found."
    exit 1
fi

# check DNAnexus env
: "${DX_PROJECT_CONTEXT_ID:?DX_PROJECT_CONTEXT_ID is not set}"

# make sure to keep this block in sync with update_script_b64.sh
SCRIPT_NAME="nifti_process.py"
if [[ ! -f "$SCRIPT_NAME" ]]; then
    echo "Creating $SCRIPT_NAME from embedded compressed data..."
    base64 -d << 'EOF' | zstd -d -o "$SCRIPT_NAME"
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
EOF
fi

prepare_subject_data() {
    local sub_file_idx="$1"
    local base_path="$2"

    echo "[${sub_file_idx}] Locating archive in DNAnexus..."

    # Locate, validate, and unpack the DNAnexus zip for the subject.
    local dx_rel_path=$(
      dx find data --name "${sub_file_idx}.zip" --json \
      | jq -r '.[0] | .describe.folder + "/" + .describe.name' 2>/dev/null || true
    )

    if [[ -z "$dx_rel_path" ]]; then
        echo "File ${sub_file_idx}.zip not found in DNAnexus."
        return 1
    fi

    echo "[${sub_file_idx}] Downloading input archive..."
    mkdir -p "${base_path}/${sub_file_idx}"
    dx download --no-progress "$dx_rel_path" -o "${base_path}/${sub_file_idx}/"

    echo "[${sub_file_idx}] Unzipping input archive..."
    python3 -m zipfile \
    -e "${base_path}/${sub_file_idx}/${sub_file_idx}.zip" "${base_path}/${sub_file_idx}/"

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
    if [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.nii.gz" ]] \
    || [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard.nii.gz" ]] \
    || [[ ! -f "${SUBJECT_DIR}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" ]]; then
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

    echo "[${sub_file_idx}] rfMRI processing complete."
}

process_surf() {
    local sub_file_idx="$1"
    local base_path="$2"

    prepare_subject_data "$sub_file_idx" "$base_path" || return 1

    local SUBJECT_DIR="${base_path}/${sub_file_idx}"

    # check required files
    if [[ ! -f "${SUBJECT_DIR}/surf_fMRI/CIFTIs/bb.rfMRI.MNI.MSMAll.dtseries.nii" ]]; then
        echo "Required surface file not found for subject ${sub_file_idx}."
        rm -rf "${SUBJECT_DIR}"
        return 1
    fi

    echo "[${sub_file_idx}] Starting surface processing..."

    # convert to npy.zst using the generated nifti_process.py
    echo "[${sub_file_idx}] Converting surface dtseries to npy.zst..."
    python3 "$SCRIPT_NAME" \
      -t 2D \
      -i "${SUBJECT_DIR}/surf_fMRI/CIFTIs/bb.rfMRI.MNI.MSMAll.dtseries.nii" \
      -o "${SUBJECT_DIR}/bb.rfMRI.MNI.MSMAll.dtseries.npy.zst"

    # upload to DNAnexus
    echo "[${sub_file_idx}] Uploading surface artifact to DNAnexus..."
    dx mkdir -p "${DX_PROJECT_CONTEXT_ID}:/datasets/surf_fMRI/${sub_file_idx}"
    dx upload \
      --wait \
      --no-progress \
      --path "${DX_PROJECT_CONTEXT_ID}:/datasets/surf_fMRI/${sub_file_idx}/" \
      "${SUBJECT_DIR}/bb.rfMRI.MNI.MSMAll.dtseries.npy.zst"

    echo "[${sub_file_idx}] Surface processing complete."
}

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <sub_file_idx>"
  exit 1
fi

sub_file_idx="$1"
BASE_PATH="."
sub_type_id=$(cut -d'_' -f2 <<< "$sub_file_idx")

if [[ "${sub_type_id}" == "20227" ]]; then
    process_rfMRI "$sub_file_idx" "${BASE_PATH}"
elif [[ "${sub_type_id}" == "32136" ]]; then
    process_surf "$sub_file_idx" "${BASE_PATH}"
else
    echo "Unknown sub_file_idx type: $sub_file_idx"
    exit 1
fi

rm -rf ${BASE_PATH}/${sub_file_idx}
