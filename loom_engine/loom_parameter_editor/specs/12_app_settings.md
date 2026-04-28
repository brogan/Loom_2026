# Application Settings

**Source:** `app_settings.py`  
**Storage:** `~/.loom_projects/.loom_editor_settings.json`

## Purpose

`AppSettings` persists editor-level preferences that apply across all projects and survive application restarts. These settings are intentionally separate from `project.xml` — they reflect the local machine's configuration, not the project's artistic parameters.

## Settings

| Field | Type | Default | Description |
|---|---|---|---|
| `default_projects_dir` | str | `~/.loom_projects` | Base directory shown in Open/New Project dialogs |
| `recent_projects` | List[str] | [] | Absolute paths of up to 10 recently opened projects (most recent first) |
| `selected_engine` | str | "scala" | Last selected engine; "scala" or "swift" |
| `loom_app_path` | str | "" | Path to loom_swift source directory (shown in RunTab Swift path field) |

## JSON Format

```json
{
  "default_projects_dir": "/Users/broganbunt/.loom_projects",
  "recent_projects": [
    "/Users/broganbunt/.loom_projects/Project_A",
    "/Users/broganbunt/.loom_projects/Project_B"
  ],
  "selected_engine": "scala",
  "loom_app_path": "/Users/broganbunt/Loom_2026/loom_swift"
}
```

## API

```python
class AppSettings:
    MAX_RECENT = 10

    def __init__()                     # loads from file, uses defaults if missing
    def save()                         # writes JSON to SETTINGS_FILE
    def add_recent_project(path: str)  # prepend, dedupe, truncate to MAX_RECENT, auto-save
```

Load errors (missing file, parse errors) are silently ignored — defaults are used. Save errors print a warning to stdout but do not raise.

## Lifecycle in `MainWindow`

- **On startup:** `AppSettings()` loaded; values pushed into `GlobalTab` (engine selection, projects dir) and `RunTab` (engine, LoomApp path).
- **On engine change:** `_on_engine_changed()` updates `selected_engine` and saves.
- **On LoomApp path change:** `_on_loom_app_path_changed()` updates `loom_app_path` and saves.
- **On projects dir change:** `_on_projects_dir_changed()` updates `default_projects_dir` and saves.
- **On project open/save:** `add_recent_project()` called; `_rebuild_recent_menu()` refreshes the File menu.

## Recent Projects Menu

`MainWindow._rebuild_recent_menu()` rebuilds `File → Open Recent Project` from `recent_projects`. Each action's tooltip shows the full path. Clicking opens the project directly (same path as `_load_project_dir()`). If the directory no longer exists, a warning is shown and the entry is pruned.
