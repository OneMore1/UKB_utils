#!/usr/bin/env bash

set -euo pipefail

# check python3 installed
if ! command -v python3 &> /dev/null; then
    echo "Python3 could not be found."
    exit 1
fi

# check DNAnexus env
: "${DX_PROJECT_CONTEXT_ID:?DX_PROJECT_CONTEXT_ID is not set}"

TXT_FILE=subject_atlas_id_31016.txt
if [[ ! -f "$TXT_FILE" ]]; then
    echo "Getting $TXT_FILE from dx folder..."
    dx download ${DX_PROJECT_CONTEXT_ID}:/${TXT_FILE} -o ${TXT_FILE}
fi

SCRIPT_NAME="atlas_concat.py"
if [[ ! -f "$SCRIPT_NAME" ]]; then
    echo "Getting $SCRIPT_NAME from dx folder..."
    dx download ${DX_PROJECT_CONTEXT_ID}:/codes/${SCRIPT_NAME} -o ${SCRIPT_NAME}
fi

prepare_subject_data() {
    local base_path="$1"
    local subject_idx="$2"
    local sub_session="$3"

    echo "[${subject_idx}] Locating archive in DNAnexus..."

    # 31016 31018 31019
    local TARGET_TASK_LIST=("31016" "31018" "31019")

    for task in "${TARGET_TASK_LIST[@]}"; do
        local file_name="${subject_idx}_${task}_${sub_session}_0.zip"
        local rel_path=$(
          dx find data --name "${file_name}" --json \
          | jq -r '.[0] | .describe.folder + "/" + .describe.name' 2>/dev/null || true
        )

        if [[ -z "$rel_path" ]]; then
            echo "File ${subject_idx}_rfMRI_${task}_${sub_session}.zip not found in DNAnexus."
            return 1
        fi

        echo "[${subject_idx}] Downloading input archive for task ${task}..."
        mkdir -p "${base_path}/${subject_idx}"
        dx download --no-progress "$rel_path" -o "${base_path}/${subject_idx}/"

        echo "[${subject_idx}] Unzipping input archive for task ${task}..."
        python3 -m zipfile \
        -e "${base_path}/${subject_idx}/${file_name}" "${base_path}/${subject_idx}/"

        rm "${base_path}/${subject_idx}/${file_name}"
    done
}

process_atlas() {
    local base_path="$1"
    local subject_idx="$2"
    local sub_session="$3"

    prepare_subject_data "$base_path" "$subject_idx" "$sub_session" || return 1

    local SUBJECT_DIR="${base_path}/${subject_idx}"

    if [[ ! -f ${SUBJECT_DIR}/fMRI.Tian_Subcortex_S3_3T.csv.gz ]] \
    || [[ ! -f ${SUBJECT_DIR}/fMRI.Schaefer17n100p.csv.gz ]] \
    || [[ ! -f ${SUBJECT_DIR}/fMRI.Schaefer17n400p.csv.gz ]] \
    || [[ ! -f ${SUBJECT_DIR}/fMRI.Glasser.csv.gz ]]; then
        echo "Required atlas file not found for subject ${subject_idx}."
        rm -rf "${SUBJECT_DIR}"
        return 1
    fi

    python3 "$SCRIPT_NAME" \
      --source_dir "${SUBJECT_DIR}" \
      --output_dir "${SUBJECT_DIR}"
    
    rm -f ${SUBJECT_DIR}/*.csv.gz
    dx mkdir -p "/datasets/atlas/${subject_idx}/"
    local file_list=("roi50.npy" "roi100.npy" "roi360.npy" "roi400.npy")
    for file_name in "${file_list[@]}"; do
      dx upload \
        --wait \
        --no-progress \
        --path "${DX_PROJECT_CONTEXT_ID}:/datasets/atlas/${subject_idx}/${file_name}" \
        "${SUBJECT_DIR}/${file_name}"
    done    
    
    echo "[${subject_idx}] Atlas processing completed."
}


START_LINE="$1"
END_LINE="$2"

BASE_PATH="."

sed -n "${START_LINE},${END_LINE}p" "$TXT_FILE" | while IFS= read -r sub_file_idx; do
  sub_id=$(echo "$sub_file_idx" | cut -d'_' -f1)
  session=$(echo "$sub_file_idx" | cut -d'_' -f3)
  echo "process_atlas $sub_id $session"
  process_atlas "$BASE_PATH" "$sub_id" "$session"
  rm -rf ${BASE_PATH}/${sub_file_idx}
done

rm "$SCRIPT_NAME"
rm "$TXT_FILE"
