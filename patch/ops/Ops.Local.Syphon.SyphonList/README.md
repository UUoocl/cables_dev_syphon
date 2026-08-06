# Ops.Local.Syphon.SyphonList

Query active macOS Syphon servers and expose them as JavaScript arrays for custom UI selectors inside a Cables patch.

---

## Description
This Op allows you to build custom in-patch UI dropdowns, selectors, or list components to dynamically switch between different Syphon video feeds.

---

## Design & Architecture
*   **Decoupled Selection**: Queries the list of active servers from the Electron main process via the `syphonGetServers` IPC channel.
*   **Dual Array Output**: Outputs two parallel arrays:
    *   `Servers`: A string array of user-friendly server names (e.g. `["None", "OBS Syphon6", "Resolume Output"]`).
    *   `Server Descriptions`: An array containing the full raw server dictionary objects (including UUID and type metadata).
*   **Event Triggering**: Triggers the `Triggered` output port immediately after retrieving and updating the lists, allowing downstream UI components to refresh their state.

---

## How to Use
1.  **Place the Op**: In Cables, add `Ops.Local.Syphon.SyphonList`.
2.  **Trigger Refresh**: Connect a button or a periodic timer trigger to the `Refresh` input port to scan for servers.
3.  **Drive Custom UI**: Connect the `Servers` string array to a UI component (like an HTML Select dropdown list or list component).
4.  **Drive Syphon Input**: Connect the selected server name from your UI element directly to the `Server` input port of `Ops.Local.Syphon.SyphonInput`.
