#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SRC_DIR="$SCRIPT_DIR/../patch/ops"
DST_APPLE_DIR="$SCRIPT_DIR/cables/src/ops/extensions/Ops.Extension.AppleFramework"
DST_STANDALONE_DIR="$SCRIPT_DIR/cables/src/ops/extensions/Ops.Extension.Standalone"
DIST_APPLE_DIR="$SCRIPT_DIR/cables_electron/dist/ops/extensions/Ops.Extension.AppleFramework"
DIST_STANDALONE_DIR="$SCRIPT_DIR/cables_electron/dist/ops/extensions/Ops.Extension.Standalone"

echo "Syncing local patch ops to extension directories..."
echo "Source: $SRC_DIR"

if [ ! -d "$SRC_DIR" ]; then
    echo "Source directory $SRC_DIR does not exist. Skipping."
    exit 0
fi

# Make sure destination directories exist
mkdir -p "$DST_APPLE_DIR"
mkdir -p "$DST_STANDALONE_DIR"

# Clean existing synced subdirectories in AppleFramework dir
find "$DST_APPLE_DIR" -maxdepth 1 -mindepth 1 -type d -name "Ops.Extension.AppleFramework.*" -exec rm -rf {} +

# Clean old synced Standalone Server and HtmlInCanvas ops in Standalone dir
rm -rf "$DST_STANDALONE_DIR"/Ops.Extension.Standalone.Server.*
rm -rf "$DST_STANDALONE_DIR"/Ops.Extension.Standalone.HtmlInCanvas
rm -rf "$DST_STANDALONE_DIR"/Ops.Extension.Standalone.HTMLInCanvas
rm -rf "$DST_STANDALONE_DIR"/Ops.Extension.Standalone.HttpFileServer
rm -rf "$DST_STANDALONE_DIR"/Ops.Extension.Standalone.WebSocketClient
rm -rf "$DST_STANDALONE_DIR"/Ops.Extension.Standalone.WebSocketClientPub
rm -rf "$DST_STANDALONE_DIR"/Ops.Extension.Standalone.WebSocketClientSub
rm -rf "$DST_STANDALONE_DIR"/Ops.Extension.Standalone.WebSocketServerClientsList
rm -rf "$DST_STANDALONE_DIR"/Ops.Extension.Standalone.WebSocketServerPub
rm -rf "$DST_STANDALONE_DIR"/Ops.Extension.Standalone.WebSocketServerSub

# Loop over all Ops.Local.* directories in patch/ops
for op_path in "$SRC_DIR"/Ops.Local.*; do
    if [ -d "$op_path" ]; then
        src_name=$(basename "$op_path")
        
        # Rule 1: If op starts with Ops.Local.Standalone.* -> copy to Ops.Extension.Standalone
        if [[ "$src_name" == "Ops.Local.Standalone."* ]]; then
            dst_name="Ops.Extension.Standalone${src_name#Ops.Local.Standalone}"
            echo "Copying $src_name -> $dst_name (in Ops.Extension.Standalone)..."
            rm -rf "$DST_STANDALONE_DIR/$dst_name"
            cp -R "$op_path" "$DST_STANDALONE_DIR/$dst_name"
            for f in "$DST_STANDALONE_DIR/$dst_name"/*; do
                if [ -f "$f" ]; then
                    base=$(basename "$f")
                    if [[ "$base" == "$src_name"* ]]; then
                        suffix="${base#$src_name}"
                        mv "$f" "$DST_STANDALONE_DIR/$dst_name/$dst_name$suffix"
                    fi
                fi
            done
            for f in "$DST_STANDALONE_DIR/$dst_name"/*; do
                if [ -f "$f" ]; then
                    sed -i '' 's/Ops\.Local\.Standalone/Ops.Extension.Standalone/g' "$f"
                    sed -i '' 's/Ops\.Local/Ops.Extension.Standalone/g' "$f"
                fi
            done

        # Rule 2: If op does not start with Ops.Local.Standalone.* -> copy to Ops.Extension.AppleFramework
        else
            dst_name="Ops.Extension.AppleFramework${src_name#Ops.Local}"
            echo "Copying $src_name -> $dst_name (in Ops.Extension.AppleFramework)..."
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
                    sed -i '' 's/Ops\.Local/Ops.Extension.AppleFramework/g' "$f"
                fi
            done
        fi
    fi
done

# 3. If cables_electron dist directory exists, sync extension ops there as well
if [ -d "$SCRIPT_DIR/cables_electron/dist/ops/extensions" ]; then
    echo "Updating cables_electron/dist extensions..."
    mkdir -p "$DIST_APPLE_DIR"
    mkdir -p "$DIST_STANDALONE_DIR"
    rm -rf "$DIST_APPLE_DIR"/Ops.Extension.AppleFramework.*
    rm -rf "$DIST_STANDALONE_DIR"/Ops.Extension.Standalone.Server.*
    rm -rf "$DIST_STANDALONE_DIR"/Ops.Extension.Standalone.HtmlInCanvas
    rm -rf "$DIST_STANDALONE_DIR"/Ops.Extension.Standalone.HttpFileServer
    rm -rf "$DIST_STANDALONE_DIR"/Ops.Extension.Standalone.WebSocket*
    cp -R "$DST_APPLE_DIR"/* "$DIST_APPLE_DIR"/ 2>/dev/null || true
    cp -R "$DST_STANDALONE_DIR"/* "$DIST_STANDALONE_DIR"/ 2>/dev/null || true
fi

# 4. Invalidate stale opdoc caches so fresh docs are built
echo "Invalidating stale opdocs cache..."
rm -f "$SCRIPT_DIR/gen/electron/gen/opdocs_collections/Ops.Extension.AppleFramework.json"
rm -f "$SCRIPT_DIR/gen/electron/gen/opdocs_collections/Ops.Extension.Standalone.json"
rm -f "$SCRIPT_DIR/gen/electron/gen/opdocs.json"
rm -f "$SCRIPT_DIR/gen/electron/gen/oplookup.json"

# Invalidate Electron user data caches if present
USER_DATA_DIRS=(
    "$HOME/Library/Application Support/cables_electron"
    "$HOME/Library/Application Support/cables"
)
for udir in "${USER_DATA_DIRS[@]}"; do
    if [ -d "$udir/gen" ]; then
        rm -f "$udir/gen/opdocs_collections/Ops.Extension.AppleFramework.json"
        rm -f "$udir/gen/opdocs_collections/Ops.Extension.Standalone.json"
        rm -f "$udir/gen/opdocs.json"
        rm -f "$udir/gen/oplookup.json"
    fi
done

echo "Sync completed successfully!"
