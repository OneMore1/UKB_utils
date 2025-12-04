#!/usr/bin/env bash

set -euo pipefail

# Fixed filenames
PY_SCRIPT="nifti_process.py"
BASH_SCRIPTS=("ukb_fmri_processing.sh" "ukb_surf_processing.sh")

# Check that the Python script exists
if [[ ! -f "$PY_SCRIPT" ]]; then
    echo "Python script '$PY_SCRIPT' not found."
    exit 1
fi

# Check that all Bash scripts exist
for BASH_SCRIPT in "${BASH_SCRIPTS[@]}"; do
    if [[ ! -f "$BASH_SCRIPT" ]]; then
        echo "Bash script '$BASH_SCRIPT' not found."
        exit 1
    fi
done

# Check for required commands
for cmd in zstd base64 awk; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "Command '$cmd' not found. Please install it."
        exit 1
    fi
done

# Temporary file for base64 content
TMP_B64="$(mktemp)"

# 1. Compress + base64 (wrap at 76 chars per line for easier diffing)
zstd -19 < "$PY_SCRIPT" | base64 -w 76 > "$TMP_B64"

# 2. For each Bash script, use awk to replace the base64 block
#    Replacement range: from the first line `base64 -d << 'EOF'`
#    up to the following solitary `EOF` line
for BASH_SCRIPT in "${BASH_SCRIPTS[@]}"; do
    TMP_OUT="$(mktemp)"

    awk -v b64_file="$TMP_B64" '
    BEGIN { inblock = 0 }

    # Match the line containing base64 -d << '"'"'EOF'"'"' (there may be a pipe or more after it)
    /^base64 -d << '"'"'EOF'"'"'/ {
        print
        # Insert the new base64 content
        while ((getline line < b64_file) > 0) {
            print line
        }
        close(b64_file)
        inblock = 1
        next
    }

    # Block end: a single line containing only EOF
    /^EOF$/ && inblock {
        print
        inblock = 0
        next
    }

    # Drop the old base64 content while inside the block
    inblock { next }

    # All other lines are passed through unchanged
    { print }
    ' "$BASH_SCRIPT" > "$TMP_OUT"

    # Overwrite the original script
    mv "$TMP_OUT" "$BASH_SCRIPT"

    echo "Updated BASE64 block in '$BASH_SCRIPT' from '$PY_SCRIPT'."
done

# Cleanup
rm -f "$TMP_B64"
