"""
Persistent application-level settings (not per-project).
Stored as JSON in ~/.loom_projects/.loom_editor_settings.json
"""
import json
import os


SETTINGS_FILE = os.path.expanduser("~/.loom_projects/.loom_editor_settings.json")


class AppSettings:
    def __init__(self):
        self.default_projects_dir: str = os.path.expanduser("~/.loom_projects")
        self._load()

    def _load(self) -> None:
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, "r") as f:
                    data = json.load(f)
                self.default_projects_dir = data.get(
                    "default_projects_dir", self.default_projects_dir
                )
            except Exception:
                pass  # use defaults on any error

    def save(self) -> None:
        try:
            os.makedirs(os.path.dirname(SETTINGS_FILE), exist_ok=True)
            with open(SETTINGS_FILE, "w") as f:
                json.dump({"default_projects_dir": self.default_projects_dir}, f, indent=2)
        except Exception as e:
            print(f"Warning: could not save editor settings: {e}")
