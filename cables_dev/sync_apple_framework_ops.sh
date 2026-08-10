#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SRC_DIR="$SCRIPT_DIR/../patch/ops"
DST_DIR="$SCRIPT_DIR/cables/src/ops/extensions/Ops.Extension.AppleFramework"

echo "Syncing local patch ops to Apple Frameworks extension..."
echo "Source: $SRC_DIR"
echo "Destination: $DST_DIR"

if [ ! -d "$SRC_DIR" ]; then
    echo "Source directory $SRC_DIR does not exist. Skipping."
    exit 0
fi

# Make sure destination directory exists
mkdir -p "$DST_DIR"

# Clean existing subdirectories starting with Ops.Extension.AppleFramework.
# (to prevent stale ops that were deleted or renamed in local patch)
find "$DST_DIR" -maxdepth 1 -mindepth 1 -type d -name "Ops.Extension.AppleFramework.*" -exec rm -rf {} +

# Loop over all Ops.Local.* directories in patch/ops
for op_path in "$SRC_DIR"/Ops.Local.*; do
    if [ -d "$op_path" ]; then
        src_name=$(basename "$op_path")
        dst_name="Ops.Extension.AppleFramework${src_name#Ops.Local}"
        
        echo "Copying $src_name -> $dst_name..."
        
        # 1. Copy directory structure and files
        cp -R "$op_path" "$DST_DIR/$dst_name"
        
        # 2. Rename files inside directory
        for f in "$DST_DIR/$dst_name"/*; do
            if [ -f "$f" ]; then
                base=$(basename "$f")
                if [[ "$base" == "$src_name"* ]]; then
                    suffix="${base#$src_name}"
                    mv "$f" "$DST_DIR/$dst_name/$dst_name$suffix"
                fi
            fi
        done
        
        # 3. Replace all occurrences of "Ops.Local" with "Ops.Extension.AppleFramework" inside files
        for f in "$DST_DIR/$dst_name"/*; do
            if [ -f "$f" ]; then
                # Use sed with empty extension for macOS compatibility
                sed -i '' 's/Ops.Local/Ops.Extension.AppleFramework/g' "$f"
            fi
        done
    fi
done

echo "Sync completed successfully!"
