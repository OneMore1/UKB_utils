#!/usr/bin/env bash

set -euo pipefail

DATASETS="datasets"
TARGET="$1"

echo "Downloading atlas data from DNAnexus..."
dx download \
  --no-progress \
  --recursive \
  --overwrite \
  "${DX_PROJECT_CONTEXT_ID}:/${DATASETS}/${TARGET}"

echo "Repacking atlas data..."
tar --zstd -cf "${TARGET}.tar.zst" "${TARGET}"

echo "Uploading repacked atlas data to DNAnexus..."
dx upload \
  --wait \
  --no-progress \
  --path "${DX_PROJECT_CONTEXT_ID}:/${DATASETS}/${TARGET}.tar.zst" \
  "${TARGET}.tar.zst"

echo "Cleaning up local files..."
rm -rf "${TARGET}" "${TARGET}.tar.zst"
