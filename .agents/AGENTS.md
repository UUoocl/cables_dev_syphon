# Workspace Rules for Cables Standalone for Mac Dev

## Operation Development Workflow
- All new operations must initially be created and developed inside the local patch folder `@patch/ops` using the `Ops.Local` namespace:
  - Operations beginning with `Ops.Local.Standalone.*` (e.g. `Ops.Local.Standalone.Server.*`, `Ops.Local.Standalone.HtmlInCanvas`) are synced exclusively to `@cables_dev/cables/src/ops/extensions/Ops.Extension.Standalone` (renamed to `Ops.Extension.Standalone.*`).
  - Operations NOT beginning with `Ops.Local.Standalone.*` (e.g. `Ops.Local.Vision.*`, `Ops.Local.Syphon.*`, `Ops.Local.Input.*`, `Ops.Local.Audio.*`, `Ops.Local.Camera.*`, `Ops.Local.Speech.*`, `Ops.Local.ActiveApp.*`, `Ops.Local.WindowsList`) are synced exclusively to `@cables_dev/cables/src/ops/extensions/Ops.Extension.AppleFramework` (renamed to `Ops.Extension.AppleFramework.*`).
- Op synchronization is handled automatically by `@cables_dev/sync_apple_framework_ops.sh` during Gulp build and watch tasks, as well as during the distribution packaging process.
