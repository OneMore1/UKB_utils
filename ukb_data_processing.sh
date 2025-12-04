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
o3E=
EOF
fi

process_rfMRI() {
    local sub_file_idx="$1"
    local BASE_PATH="."

    local FRAME_START=200
    local FRAME_LENGTH=40

    # find file path in DNAnexus
    local dx_rel_path=$(
      dx find data --name "${sub_file_idx}.zip" --json \
      | jq -r '.[0] | .describe.folder + "/" + .describe.name' 2>/dev/null || true
    )

    if [[ -z "$dx_rel_path" ]]; then
        echo "File ${sub_file_idx}.zip not found in DNAnexus."
        return 1
    fi

    local f_path="/mnt/project/${dx_rel_path}"

    if [[ ! -f "$f_path" ]]; then
        echo "File path $f_path does not exist."
        return 1
    fi

    # unzip and prepare output directory
    mkdir -p "${BASE_PATH}/${sub_file_idx}"
    python3 -m zipfile -e "$f_path" "${BASE_PATH}/${sub_file_idx}"

    export FSLOUTPUTTYPE=NIFTI

    # cut frames
    fslroi \
      "${BASE_PATH}/${sub_file_idx}/fMRI/rfMRI.nii.gz" \
      "${BASE_PATH}/${sub_file_idx}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}.nii" \
      0 -1 0 -1 0 -1 "$FRAME_START" "$FRAME_LENGTH"

    # warp to MNI space
    applywarp \
      -i "${BASE_PATH}/${sub_file_idx}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}.nii" \
      -r "${BASE_PATH}/${sub_file_idx}/fMRI/rfMRI.ica/reg/example_func2standard.nii.gz" \
      -w "${BASE_PATH}/${sub_file_idx}/fMRI/rfMRI.ica/reg/example_func2standard_warp.nii.gz" \
      -o "${BASE_PATH}/${sub_file_idx}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.nii" \
      --interp=spline

    # convert to npy.zst using the generated nifti_process.py
    python3 "$SCRIPT_NAME" \
      -t 4D \
      -i "${BASE_PATH}/${sub_file_idx}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.nii" \
      -o "${BASE_PATH}/${sub_file_idx}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.npy.zst"

    # upload to DNAnexus
    dx mkdir -p "${DX_PROJECT_CONTEXT_ID}:/datasets/fMRI/${sub_file_idx}"
    dx upload \
      --wait \
      --no-progress \
      --path "${DX_PROJECT_CONTEXT_ID}:/datasets/fMRI/${sub_file_idx}/" \
      "${BASE_PATH}/${sub_file_idx}/rfMRI_s${FRAME_START}l${FRAME_LENGTH}_MNI_nonlin.npy.zst"
}

process_surf() {
    local sub_file_idx="$1"
    local BASE_PATH="."

    local FRAME_START=200
    local FRAME_LENGTH=40

    # find file path in DNAnexus
    local dx_rel_path=$(
      dx find data --name "${sub_file_idx}.zip" --json \
      | jq -r '.[0] | .describe.folder + "/" + .describe.name' 2>/dev/null || true
    )

    if [[ -z "$dx_rel_path" ]]; then
        echo "File ${sub_file_idx}.zip not found in DNAnexus."
        return 1
    fi

    local f_path="/mnt/project/${dx_rel_path}"

    if [[ ! -f "$f_path" ]]; then
        echo "File path $f_path does not exist."
        return 1
    fi

    # unzip and prepare output directory
    mkdir -p "${BASE_PATH}/${sub_file_idx}"
    python3 -m zipfile -e "$f_path" "${BASE_PATH}/${sub_file_idx}"

    export FSLOUTPUTTYPE=NIFTI

    # convert to npy.zst using the generated nifti_process.py
    python3 "$SCRIPT_NAME" \
      -t 2D \
      -i "${BASE_PATH}/${sub_file_idx}/surf_fMRI/CIFTIs/bb.rfMRI.MNI.MSMAll.dtseries.nii" \
      -o "${BASE_PATH}/${sub_file_idx}/bb.rfMRI.MNI.MSMAll.dtseries.npy.zst"

    # upload to DNAnexus
    dx mkdir -p "${DX_PROJECT_CONTEXT_ID}:/datasets/surf_fMRI/${sub_file_idx}"
    dx upload \
      --wait \
      --no-progress \
      --path "${DX_PROJECT_CONTEXT_ID}:/datasets/surf_fMRI/${sub_file_idx}/" \
      "${BASE_PATH}/${sub_file_idx}/bb.rfMRI.MNI.MSMAll.dtseries.npy.zst"
}

sub_file_idx="1044210_20227_2_0"

if [[ "${sub_file_idx##*_}" == "20227" ]]; then
    process_rfMRI "$sub_file_idx"
elif [[ "${sub_file_idx##*_}" == "32136" ]]; then
    process_surf "$sub_file_idx"
else
    echo "Unknown sub_file_idx type: $sub_file_idx"
    exit 1
fi
