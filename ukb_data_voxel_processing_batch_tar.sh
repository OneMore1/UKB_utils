#!/usr/bin/env bash
set -euo pipefail

INPUT_1=$1
INPUT_2=$2

TXT_FILE="${3:-final_list_wo_disease_mapped.csv}"
TXT_NAME=$(basename "$TXT_FILE")

START_LINE=$(($1 + 1))
END_LINE=$(($2 + 1))
BASE_PATH="."

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

# check DNAnexus env
: "${DX_PROJECT_CONTEXT_ID:?DX_PROJECT_CONTEXT_ID is not set}"

# --------------------------
# Batching / staging settings
# --------------------------
BATCH_SIZE=100

# 本地暂存目录（可改）
STAGE_ROOT="./_stage_batches"
STAGE_FMRI="${STAGE_ROOT}/fMRI_rb"              # 每个被试一个子目录
STAGE_ATLAS="${STAGE_ROOT}/voxel_atlas_rb"      # 每个被试一个子目录

# 远端 tar 上传目录（每类一个；tar+txt 上传到同一目录；可改）
REMOTE_FMRI_TAR_DIR="/datasets/fMRI_rb_tar2_${TXT_NAME}"
REMOTE_ATLAS_TAR_DIR="/datasets/voxel_atlas_rb_tar2_${TXT_NAME}"

BATCH_NUM=1
BATCH_COUNT=0

init_stage_dirs() {
  mkdir -p "${STAGE_FMRI}" "${STAGE_ATLAS}"
}

prepare_subject_data() {
  local sub_file_idx="$1"
  local base_path="$2"

  echo "[${sub_file_idx}] Locating archive in DNAnexus..."

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
  python3 -m zipfile -e \
    "${base_path}/${sub_file_idx}/${sub_file_idx}.zip" \
    "${base_path}/${sub_file_idx}/"

  rm -f "${base_path}/${sub_file_idx}/${sub_file_idx}.zip"
  echo "[${sub_file_idx}] Input data ready."
}

stage_subject_outputs() {
  local sub_file_idx="$1"
  local subject_dir="$2"

  # 将产物移动到本地暂存目录
  if [[ -d "${subject_dir}/voxel_process/${sub_file_idx}" ]]; then
    mv "${subject_dir}/voxel_process/${sub_file_idx}" "${STAGE_FMRI}/"
  else
    echo "[${sub_file_idx}] Staging error: missing ${subject_dir}/voxel_process/${sub_file_idx}"
    return 1
  fi

  if [[ -d "${subject_dir}/voxel2atlas/${sub_file_idx}" ]]; then
    mv "${subject_dir}/voxel2atlas/${sub_file_idx}" "${STAGE_ATLAS}/"
  else
    echo "[${sub_file_idx}] Staging error: missing ${subject_dir}/voxel2atlas/${sub_file_idx}"
    return 1
  fi
}

flush_batch() {
  local batch_num="$1"
  local batch_tag ts
  printf -v batch_tag "%04d" "${batch_num}"
  ts="$(date +'%Y%m%d_%H%M%S')"

  local tar_fmri="${STAGE_ROOT}/fMRI_rb_batch_s${INPUT_1}-e${INPUT_2}_${batch_tag}_${ts}.tar"
  local list_fmri="${STAGE_ROOT}/fMRI_rb_batch_s${INPUT_1}-e${INPUT_2}_${batch_tag}_${ts}.txt"

  local tar_atlas="${STAGE_ROOT}/voxel_atlas_rb_batch_s${INPUT_1}-e${INPUT_2}_${batch_tag}_${ts}.tar"
  local list_atlas="${STAGE_ROOT}/voxel_atlas_rb_batch_s${INPUT_1}-e${INPUT_2}_${batch_tag}_${ts}.txt"
  # 收集被试目录名（只取一级子目录名）
  mapfile -t fmri_dirs < <(find "${STAGE_FMRI}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
  mapfile -t atlas_dirs < <(find "${STAGE_ATLAS}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

  if [[ "${#fmri_dirs[@]}" -eq 0 ]] || [[ "${#atlas_dirs[@]}" -eq 0 ]]; then
    echo "[batch ${batch_tag}] Nothing to flush (staging dirs empty)."
    return 0
  fi

  echo "[batch ${batch_tag}] Creating manifest text files..."
  printf "%s\n" "${fmri_dirs[@]}" > "${list_fmri}"
  printf "%s\n" "${atlas_dirs[@]}" > "${list_atlas}"

  echo "[batch ${batch_tag}] Creating tar archives (no compression, no top-level dir)..."
  # 不打包顶层目录：在各自目录里 tar 被试子目录
  tar -cf "${tar_fmri}" -C "${STAGE_FMRI}" "${fmri_dirs[@]}"
  tar -cf "${tar_atlas}" -C "${STAGE_ATLAS}" "${atlas_dirs[@]}"

  echo "[batch ${batch_tag}] Uploading tar + manifest to DNAnexus..."
  dx mkdir -p "${REMOTE_FMRI_TAR_DIR}"
  dx mkdir -p "${REMOTE_ATLAS_TAR_DIR}"

  # tar 和 txt 一起上传到相同目录
  dx upload --wait --no-progress --path "${REMOTE_FMRI_TAR_DIR}/" "${tar_fmri}" "${list_fmri}"
  dx upload --wait --no-progress --path "${REMOTE_ATLAS_TAR_DIR}/" "${tar_atlas}" "${list_atlas}"

  echo "[batch ${batch_tag}] Cleaning local staged data..."
  rm -f "${tar_fmri}" "${list_fmri}" "${tar_atlas}" "${list_atlas}"
  rm -rf "${STAGE_FMRI}" "${STAGE_ATLAS}"
  mkdir -p "${STAGE_FMRI}" "${STAGE_ATLAS}"
}

maybe_flush() {
  if [[ "${BATCH_COUNT}" -ge "${BATCH_SIZE}" ]]; then
    flush_batch "${BATCH_NUM}"
    BATCH_NUM=$((BATCH_NUM + 1))
    BATCH_COUNT=0
  fi
}

final_flush() {
  if [[ "${BATCH_COUNT}" -gt 0 ]]; then
    flush_batch "${BATCH_NUM}"
    BATCH_NUM=$((BATCH_NUM + 1))
    BATCH_COUNT=0
  fi
}

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
      -i ./atlas_data/${atlas}.nii.gz \
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

  python3 augment_rois.py \
    --fmri "${SUBJECT_DIR}/fMRI/rfMRI.nii.gz" \
    --adjacency_dir "./atlas_data/adjacency" \
    --atlas_dir "${SUBJECT_DIR}/atlas_data" \
    --output_dir "${SUBJECT_DIR}/voxel2atlas/${sub_file_idx}"

  echo "[${sub_file_idx}] Staging outputs locally for batch upload..."
  stage_subject_outputs "${sub_file_idx}" "${SUBJECT_DIR}"

  rm -rf "${SUBJECT_DIR}"
  echo "[${sub_file_idx}] rfMRI processing complete."
}

# download nifti_process.py
wget -q https://raw.githubusercontent.com/OneMore1/UKB_utils/master/nifti_process.py
wget -q https://raw.githubusercontent.com/OneMore1/UKB_utils/master/volume2fc.py
wget -q https://raw.githubusercontent.com/OneMore1/UKB_utils/master/roi_augmentation/augment_rois.py

# extract subject id txt
dx download --no-progress /mri_process_utils/${TXT_FILE}
dx download --no-progress --recursive /mri_process_utils/roi_augmentation/atlas_data

init_stage_dirs

while IFS= read -r sub_file_idx; do
  [[ -z "${sub_file_idx}" ]] && continue

  echo "process_rfMRI ${sub_file_idx} ${BASE_PATH}"
  if process_rfMRI "${sub_file_idx}" "${BASE_PATH}"; then
    BATCH_COUNT=$((BATCH_COUNT + 1))
    maybe_flush
  else
    echo "skip ${sub_file_idx}"
    continue
  fi
done < <(
  sed -n "${START_LINE},${END_LINE}p" "$TXT_FILE" |
    awk -F',' 'NF {gsub(/^\s+|\s+$/, "", $1); print $1}'
)

final_flush

rm -f nifti_process.py volume2fc.py augment_rois.py "$TXT_FILE"
rm -rf atlas_data
rm -rf "${STAGE_ROOT}"
