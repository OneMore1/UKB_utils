#!/usr/bin/env bash

set -euo pipefail

TARGET="datasets/atlas"
OUTPUT="atlas"

echo "Downloading atlas data from DNAnexus..."
dx download \
  --no-progress \
  --recursive \
  --overwrite \
  "${DX_PROJECT_CONTEXT_ID}:/${TARGET}/" \
  --output "${OUTPUT}/"

echo "Repacking atlas data..."
tar --zstd -cf "${OUTPUT}.tar.zst" "${OUTPUT}/"

echo "Uploading repacked atlas data to DNAnexus..."
dx upload \
  --wait \
  --no-progress \
  --path "${DX_PROJECT_CONTEXT_ID}:/datasets/${OUTPUT}.tar.zst" \
  "${OUTPUT}.tar.zst"

echo "Cleaning up local files..."
rm -rf "${OUTPUT}/" "${OUTPUT}.tar.zst"
