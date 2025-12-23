#!/usr/bin/env bash
set -uEo pipefail

usage() {
  cat <<'EOF'
Usage:
  batch_rb_by_batchsize.sh <start_line> <end_line> <batch_size>

Example:
  batch_rb_by_batchsize.sh 1 1000 100
  batch_rb_by_batchsize.sh 1 1050 100

Remote list:
  /mri_process_utils/fMRI_rb_list.txt

Remote data root:
  /datasets/fMRI_rb/{sub_id}

Upload destination:
  /datasets/fMRI_rb_tar/

Env (optional):
  TAR_DIR=./tars
  WORK_ROOT=./work_batches
  CLEANUP=1              # 上传成功后删除本地 tar（默认不删）；下载内容会在打包后必然清理
EOF
}

if [[ $# -ne 3 ]]; then usage; exit 2; fi
START_LINE="$1"; END_LINE="$2"; BATCH_SIZE="$3"

[[ "$START_LINE" =~ ^[0-9]+$ && "$END_LINE" =~ ^[0-9]+$ && "$BATCH_SIZE" =~ ^[0-9]+$ ]] || {
  echo "ERROR: start_line/end_line/batch_size must be positive integers." >&2; exit 2; }
(( START_LINE >= 1 && START_LINE <= END_LINE )) || { echo "ERROR: 1 <= start_line <= end_line" >&2; exit 2; }
(( BATCH_SIZE >= 1 )) || { echo "ERROR: batch_size must be >= 1" >&2; exit 2; }

command -v dx >/dev/null 2>&1 || { echo "ERROR: dx not found in PATH." >&2; exit 2; }
command -v tar >/dev/null 2>&1 || { echo "ERROR: tar not found in PATH." >&2; exit 2; }

REMOTE_LIST="/mri_process_utils/fMRI_rb_list.txt"
DATA_ROOT="/datasets/fMRI_rb"
REMOTE_UPLOAD_DIR="/datasets/fMRI_rb_tar"

TAR_DIR="${TAR_DIR:-./tars}"
WORK_ROOT="${WORK_ROOT:-./work_batches}"
mkdir -p "$TAR_DIR" "$WORK_ROOT"

TS="$(date +%Y%m%d_%H%M%S)"
LIST_LOCAL="${WORK_ROOT}/fMRI_rb_list_${TS}.txt"

echo "Downloading list: ${REMOTE_LIST} -> ${LIST_LOCAL}"
dx download "${REMOTE_LIST}" -o "${LIST_LOCAL}" --overwrite

TOTAL=$(( END_LINE - START_LINE + 1 ))
NUM_PACKS=$(( (TOTAL + BATCH_SIZE - 1) / BATCH_SIZE ))

ABS_TAR_DIR="$(cd "$TAR_DIR" && pwd -P)"

echo "Range     : ${START_LINE}-${END_LINE} (total=${TOTAL})"
echo "Batch size: ${BATCH_SIZE} (packs=${NUM_PACKS})"
echo "TAR_DIR   : ${ABS_TAR_DIR}"
echo "WORK_ROOT : ${WORK_ROOT}"

pack_idx=0
batch_start="$START_LINE"

while (( batch_start <= END_LINE )); do
  batch_end=$(( batch_start + BATCH_SIZE - 1 ))
  if (( batch_end > END_LINE )); then batch_end="$END_LINE"; fi

  pack_idx=$(( pack_idx + 1 ))
  pack_tag="$(printf "p%02dof%02d" "$pack_idx" "$NUM_PACKS")"

  echo "=============================="
  echo "Batch ${pack_tag}: lines ${batch_start}-${batch_end}"

  OUT_DIR="${WORK_ROOT}/work_${TS}_${pack_tag}_${batch_start}-${batch_end}"
  mkdir -p "$OUT_DIR"

  # FAILED_LIST 放在 OUT_DIR 外面，便于打包后删除 OUT_DIR
  FAILED_LIST="${WORK_ROOT}/failed_${TS}_${pack_tag}_${batch_start}-${batch_end}.txt"
  : > "$FAILED_LIST"

  mapfile -t IDS < <(
    sed -n "${batch_start},${batch_end}p" "$LIST_LOCAL" \
    | sed 's/\r$//' \
    | awk '{$1=$1} NF>0 {print}'
  )

  if (( ${#IDS[@]} == 0 )); then
    echo "WARNING: no IDs found in lines ${batch_start}-${batch_end}, skipping." >&2
    rm -rf "$OUT_DIR"
    batch_start=$(( batch_end + 1 ))
    continue
  fi

  SUCCEEDED_IDS=()

  for sub_id in "${IDS[@]}"; do
    remote_path="${DATA_ROOT}/${sub_id}"
    echo "==> Download: ${remote_path} -> ${OUT_DIR}"
    if dx download -r "${remote_path}" -o "${OUT_DIR}" --overwrite; then
      expected_dir="${OUT_DIR}/${sub_id}"
      if [[ -d "$expected_dir" ]] && find "$expected_dir" -mindepth 1 -print -quit | grep -q .; then
        SUCCEEDED_IDS+=("$sub_id")
      else
        echo "    FAIL(empty or missing dir): ${sub_id}" >&2
        echo "${sub_id}" >> "$FAILED_LIST"
      fi
    else
      echo "    FAIL: ${sub_id}" >&2
      echo "${sub_id}" >> "$FAILED_LIST"
    fi
  done

  if (( ${#SUCCEEDED_IDS[@]} == 0 )); then
    echo "ERROR: batch ${pack_tag} has no successful downloads; skip packing/upload." >&2
    rm -rf "$OUT_DIR"
    batch_start=$(( batch_end + 1 ))
    continue
  fi

  TARBALL_BASENAME="fMRI_rb_${START_LINE}-${END_LINE}_${pack_tag}_${batch_start}-${batch_end}_${TS}.tar"
  TARBALL_PATH="${ABS_TAR_DIR}/${TARBALL_BASENAME}"

  echo "Packing ${#SUCCEEDED_IDS[@]} subject directories into: ${TARBALL_PATH}"
  tar -cf "$TARBALL_PATH" -C "$OUT_DIR" "${SUCCEEDED_IDS[@]}"

  # 打包后立刻清理下载内容（必做）
  echo "Cleaning downloaded content for batch ${pack_tag}: rm -rf ${OUT_DIR}"
  rm -rf "$OUT_DIR"

  REMOTE_DEST="${REMOTE_UPLOAD_DIR}/${TARBALL_BASENAME}"
  echo "Uploading to: ${REMOTE_DEST}"
  UPLOADED_ID="$(dx upload "$TARBALL_PATH" --path "$REMOTE_DEST" --parents --brief || true)"

  if [[ -z "${UPLOADED_ID}" ]]; then
    echo "ERROR: dx upload returned empty id for ${TARBALL_BASENAME}. Tar kept at: ${TARBALL_PATH}" >&2
  else
    echo "Upload done. File ID: ${UPLOADED_ID}"

    # 可选：上传成功后删本地 tar
    if [[ "${CLEANUP:-0}" == "1" ]]; then
      echo "Cleanup enabled: removing tar ${TARBALL_PATH}"
      rm -f "$TARBALL_PATH"
    fi
  fi

  if [[ -s "$FAILED_LIST" ]]; then
    echo "WARNING: some downloads failed in batch ${pack_tag}. See: ${FAILED_LIST}" >&2
  else
    rm -f "$FAILED_LIST" || true
  fi

  batch_start=$(( batch_end + 1 ))
done

echo "All batches done."
