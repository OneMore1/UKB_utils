#!/usr/bin/env bash
set -euo pipefail

INPUT_1=$1
INPUT_2=$2

START_LINE=$(($1 + 1))
END_LINE=$(($2 + 1))
BASE_PATH="."

# 1. Check dependencies
if ! command -v python3 &>/dev/null; then
  echo "Python3 could not be found."
  exit 1
fi

if ! command -v tar &>/dev/null; then
  echo "tar could not be found."
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "jq could not be found."
  exit 1
fi

# 安装 Python 依赖
pip3 install --quiet nibabel numpy

# 检查 DNAnexus 环境
: "${DX_PROJECT_CONTEXT_ID:?DX_PROJECT_CONTEXT_ID is not set}"

# --------------------------
# Batching / staging settings
# --------------------------
BATCH_SIZE=1000

# 本地暂存目录
STAGE_ROOT="./_stage_batches"
STAGE_NPY="${STAGE_ROOT}/t1_npy"

# 远端 tar 上传目录（可根据你的需求修改）
REMOTE_TAR_DIR="/datasets/t1_npy_tar"

BATCH_NUM=1
BATCH_COUNT=0

init_stage_dirs() {
  mkdir -p "${STAGE_NPY}"
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

  if [[ -d "${subject_dir}/processed_output/${sub_file_idx}" ]]; then
    mv "${subject_dir}/processed_output/${sub_file_idx}" "${STAGE_NPY}/"
  else
    echo "[${sub_file_idx}] Staging error: missing output directory."
    return 1
  fi
}

flush_batch() {
  local batch_num="$1"
  local batch_tag ts
  printf -v batch_tag "%04d" "${batch_num}"
  ts="$(date +'%Y%m%d_%H%M%S')"

  local tar_file="${STAGE_ROOT}/t1_npyzst_batch_s${INPUT_1}-e${INPUT_2}_${batch_tag}_${ts}.tar"
  local list_file="${STAGE_ROOT}/t1_npyzst_batch_s${INPUT_1}-e${INPUT_2}_${batch_tag}_${ts}.txt"

  mapfile -t npy_dirs < <(find "${STAGE_NPY}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

  if [[ "${#npy_dirs[@]}" -eq 0 ]]; then
    echo "[batch ${batch_tag}] Nothing to flush (staging dir empty)."
    return 0
  fi

  echo "[batch ${batch_tag}] Creating manifest text files..."
  printf "%s\n" "${npy_dirs[@]}" >"${list_file}"

  echo "[batch ${batch_tag}] Creating tar archives..."
  tar -cf "${tar_file}" -C "${STAGE_NPY}" "${npy_dirs[@]}"

  echo "[batch ${batch_tag}] Uploading tar + manifest to DNAnexus..."
  dx mkdir -p "${REMOTE_TAR_DIR}"
  dx upload --wait --no-progress --path "${REMOTE_TAR_DIR}/" "${tar_file}" "${list_file}"

  echo "[batch ${batch_tag}] Cleaning local staged data..."
  rm -f "${tar_file}" "${list_file}"
  rm -rf "${STAGE_NPY}"
  mkdir -p "${STAGE_NPY}"
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

process_subject() {
  local sub_file_idx="$1"
  local base_path="$2"

  prepare_subject_data "$sub_file_idx" "$base_path" || return 1
  local SUBJECT_DIR="${base_path}/${sub_file_idx}"

  # -------------------------------------------------------------
  # 注意：你需要确保这里的输入 NIfTI 路径与你解压后的文件结构匹配。
  # 以 UKB T1 数据通常的结构为例，这里暂定为 T1/T1_brain_to_MNI.nii.gz
  # -------------------------------------------------------------
  local TARGET_NII="${SUBJECT_DIR}/T1/T1_brain_to_MNI.nii.gz"

  if [[ ! -f "${TARGET_NII}" ]]; then
    echo "Required NIfTI file not found for subject ${sub_file_idx}: ${TARGET_NII}"
    rm -rf "${SUBJECT_DIR}"
    return 1
  fi

  echo "[${sub_file_idx}] Processing NIfTI to NPY..."
  local OUT_DIR="${SUBJECT_DIR}/processed_output/${sub_file_idx}"
  mkdir -p "${OUT_DIR}"

  python3 mri_t1_mni2npyzst.py \
    -i "${TARGET_NII}" \
    -o "${OUT_DIR}/${sub_file_idx}_T1_brain_to_MNI.npy.zst"

  # 如果 Python 脚本执行失败则清理退出
  if [[ $? -ne 0 ]]; then
    echo "Python script failed for ${sub_file_idx}"
    rm -rf "${SUBJECT_DIR}"
    return 1
  fi

  echo "[${sub_file_idx}] Staging outputs locally for batch upload..."
  stage_subject_outputs "${sub_file_idx}" "${SUBJECT_DIR}"

  rm -rf "${SUBJECT_DIR}"
  echo "[${sub_file_idx}] Processing complete."
}

# ==============================
# MAIN PIPELINE
# ==============================

wget -q https://raw.githubusercontent.com/OneMore1/UKB_utils/master/mri_t1_mni2npyzst.py

TXT_FILE="fMRI_20227_id.txt"
# 下载被试列表
dx download --no-progress /mri_process_utils/${TXT_FILE}

init_stage_dirs

while IFS= read -r sub_file_idx; do
  [[ -z "${sub_file_idx}" ]] && continue

  echo "Processing ${sub_file_idx}"
  if process_subject "${sub_file_idx}" "${BASE_PATH}"; then
    BATCH_COUNT=$((BATCH_COUNT + 1))
    maybe_flush
  else
    echo "Skipping ${sub_file_idx} due to error"
    continue
  fi
  # 注意下面的数据流处理部分
done < <(
  sed -n "${START_LINE},${END_LINE}p" "$TXT_FILE" | sed "s|_20227_|_20252_|g"
)

final_flush

# 清理环境
rm -f mri_t1_mni2npyzst.py "$TXT_FILE"
rm -rf "${STAGE_ROOT}"

echo "All batch tasks finished!"
