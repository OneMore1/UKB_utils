#!/usr/bin/env bash

set -euo pipefail

# Fixed filenames
PY_SCRIPT="nifti_process.py"
BASH_SCRIPT="ukb_data_processing.sh"

# Check that required files exist
if [[ ! -f "$PY_SCRIPT" ]]; then
    echo "Python script '$PY_SCRIPT' not found."
    exit 1
fi

if [[ ! -f "$BASH_SCRIPT" ]]; then
    echo "Bash script '$BASH_SCRIPT' not found."
    exit 1
fi

# Check for required commands
for cmd in zstd base64 awk; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "Command '$cmd' not found. Please install it."
        exit 1
    fi
done

# Temporary files
TMP_B64="$(mktemp)"
TMP_OUT="$(mktemp)"

# 1. Compress + base64 (wrap at 76 chars per line for easier diffing)
zstd -19 < "$PY_SCRIPT" | base64 -w 76 > "$TMP_B64"

# 2. Use awk to replace the base64 block in BASH_SCRIPT
#    Replacement range: from the first line `base64 -d << 'EOF'`
#    up to the following solitary `EOF` line
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

# 3. Overwrite the original script
mv "$TMP_OUT" "$BASH_SCRIPT"

# Cleanup
rm -f "$TMP_B64"

echo "Updated BASE64 block in '$BASH_SCRIPT' from '$PY_SCRIPT'."
