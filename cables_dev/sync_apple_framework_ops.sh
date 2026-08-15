#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SRC_DIR="$SCRIPT_DIR/../patch/ops"
DST_APPLE_DIR="$SCRIPT_DIR/cables/src/ops/extensions/Ops.Extension.AppleFramework"
DST_STANDALONE_DIR="$SCRIPT_DIR/cables/src/ops/extensions/Ops.Extension.Standalone"

echo "Syncing local patch ops to extension directories..."
echo "Source: $SRC_DIR"

if [ ! -d "$SRC_DIR" ]; then
    echo "Source directory $SRC_DIR does not exist. Skipping."
    exit 0
fi

# Make sure destination directories exist
mkdir -p "$DST_APPLE_DIR"
mkdir -p "$DST_STANDALONE_DIR"

# Clean existing subdirectories starting with Ops.Extension.AppleFramework. in AppleFramework dir
find "$DST_APPLE_DIR" -maxdepth 1 -mindepth 1 -type d -name "Ops.Extension.AppleFramework.*" -exec rm -rf {} +

# Loop over all Ops.Local.* directories in patch/ops
for op_path in "$SRC_DIR"/Ops.Local.*; do
    if [ -d "$op_path" ]; then
        src_name=$(basename "$op_path")
        
        # 1. Sync to Ops.Extension.AppleFramework
        dst_name="Ops.Extension.AppleFramework${src_name#Ops.Local}"
        echo "Copying $src_name -> $dst_name..."
        cp -R "$op_path" "$DST_APPLE_DIR/$dst_name"
        for f in "$DST_APPLE_DIR/$dst_name"/*; do
            if [ -f "$f" ]; then
                base=$(basename "$f")
                if [[ "$base" == "$src_name"* ]]; then
                    suffix="${base#$src_name}"
                    mv "$f" "$DST_APPLE_DIR/$dst_name/$dst_name$suffix"
                fi
            fi
        done
        for f in "$DST_APPLE_DIR/$dst_name"/*; do
            if [ -f "$f" ]; then
                sed -i '' 's/Ops.Local/Ops.Extension.AppleFramework/g' "$f"
            fi
        done

        # 2. If it is a Standalone op (e.g. Ops.Local.Standalone.*), also sync to Ops.Extension.Standalone
        if [[ "$src_name" == "Ops.Local.Standalone."* ]]; then
            std_name="Ops.Extension.Standalone${src_name#Ops.Local.Standalone}"
            echo "Copying $src_name -> $std_name (in Ops.Extension.Standalone)..."
            rm -rf "$DST_STANDALONE_DIR/$std_name"
            cp -R "$op_path" "$DST_STANDALONE_DIR/$std_name"
            for f in "$DST_STANDALONE_DIR/$std_name"/*; do
                if [ -f "$f" ]; then
                    base=$(basename "$f")
                    if [[ "$base" == "$src_name"* ]]; then
                        suffix="${base#$src_name}"
                        mv "$f" "$DST_STANDALONE_DIR/$std_name/$std_name$suffix"
                    fi
                fi
            done
            for f in "$DST_STANDALONE_DIR/$std_name"/*; do
                if [ -f "$f" ]; then
                    sed -i '' 's/Ops.Local.Standalone/Ops.Extension.Standalone/g' "$f"
                    sed -i '' 's/Ops.Local/Ops.Extension.Standalone/g' "$f"
                fi
            done
        fi
    fi
done

echo "Sync completed successfully!"
