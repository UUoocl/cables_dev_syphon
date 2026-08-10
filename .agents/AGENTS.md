# Workspace Rules for Cables Standalone for Mac Dev

## Operation Development Workflow
- All new operations must initially be created and developed inside the local patch folder `@patch/ops` (using the `Ops.Local` namespace, e.g. `Ops.Local.Vision.HumanFace`).
- Once an operation has been thoroughly tested, it will be moved/copied to `@cables_dev/cables/src/ops/extensions/Ops.Extension.AppleFramework` (and renamed to the `Ops.Extension.AppleFramework` namespace) during the distribution packaging/build process.
