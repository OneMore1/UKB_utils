#!/usr/bin/env bash

set -euo pipefail

# check python3 installed
if ! command -v python3 &> /dev/null; then
    echo "Python3 could not be found."
    exit 1
fi

# check DNAnexus env
: "${DX_PROJECT_CONTEXT_ID:?DX_PROJECT_CONTEXT_ID is not set}"

TXT_FILE=atlas_sample_id_list.csv
if [[ ! -f "$TXT_FILE" ]]; then
    echo "Getting $TXT_FILE from dx folder..."
    dx download ${DX_PROJECT_CONTEXT_ID}:/mri_process_utils/${TXT_FILE} -o ${TXT_FILE}
fi

# 31014 31015 31016 31018 31019
TARGET_TASK_LIST=("31014" "31015" "31016" "31018" "31019")

prepare_subject_data() {
    local base_path="$1"
    local subject_idx="$2"
    local sub_session="$3"

    echo "[${subject_idx}] Locating archive in DNAnexus..."

    for task in "${TARGET_TASK_LIST[@]}"; do
        local file_name="${subject_idx}_${task}_${sub_session}_0.zip"
        local rel_path=$(
          dx find data --name "${file_name}" --json | jq -r '.[0] | .describe.folder + "/" + .describe.name' 2>/dev/null || true
        )

        # $rel_path may be "/" if not found
        if [[ -z "$rel_path" ]] || [[ "$rel_path" == "/" ]]; then
            echo "File ${subject_idx}_rfMRI_${task}_${sub_session}.zip not found in DNAnexus."
            continue
        fi

        echo "[${subject_idx}] Downloading input archive for task ${task}..."
        mkdir -p "${base_path}/${subject_idx}"
        dx download --no-progress "$rel_path" -o "${base_path}/${subject_idx}/"

        if [[ ! -f "${base_path}/${subject_idx}/${file_name}" ]]; then
            echo "Downloaded file ${file_name} not found."
            continue
        fi

        echo "[${subject_idx}] Unzipping input archive for task ${task}..."
        python3 -m zipfile -e "${base_path}/${subject_idx}/${file_name}" "${base_path}/${subject_idx}/"

        rm -f "${base_path}/${subject_idx}/${file_name}"
    done
}


START_LINE="$1"
END_LINE="$2"

# merge TARGET_TASK_LIST to base_path name
BASE_PATH="ukb_atlas_${TARGET_TASK_LIST[*]}"
BASE_PATH="${BASE_PATH// /-}"

mkdir -p "$BASE_PATH"

sed -n "${START_LINE},${END_LINE}p" "$TXT_FILE" | while IFS= read -r sub_file_idx; do
  sub_id=$sub_file_idx
  session="2"
  echo "process_atlas $sub_id $session"
  prepare_subject_data "$BASE_PATH" "$sub_id" "$session" || { echo "skip $sub_id $session"; continue; }
done

tar -cf "${BASE_PATH}.tar" "$BASE_PATH"

ls -R "${BASE_PATH}" > "${BASE_PATH}_${START_LINE}-${END_LINE}_file_list.txt"

dx mkdir -p "${DX_PROJECT_CONTEXT_ID}:/datasets/${BASE_PATH}"

dx upload \
  --wait \
  --no-progress \
  --path "${DX_PROJECT_CONTEXT_ID}:/datasets/${BASE_PATH}/${BASE_PATH}_${START_LINE}-${END_LINE}.tar" \
  "${BASE_PATH}.tar"

dx upload \
  --wait \
  --no-progress \
  --path "${DX_PROJECT_CONTEXT_ID}:/datasets/${BASE_PATH}/${BASE_PATH}_${START_LINE}-${END_LINE}_file_list.txt" \
  "${BASE_PATH}_${START_LINE}-${END_LINE}_file_list.txt"

rm -f "$TXT_FILE"
