"""
Persistent application-level settings (not per-project).
Stored as JSON in ~/.loom_projects/.loom_editor_settings.json
"""
import json
import os


SETTINGS_FILE = os.path.expanduser("~/.loom_projects/.loom_editor_settings.json")


class AppSettings:
    MAX_RECENT = 10

    def __init__(self):
        self.default_projects_dir: str = os.path.expanduser("~/.loom_projects")
        self.recent_projects: list = []
        self._load()

    def _load(self) -> None:
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, "r") as f:
                    data = json.load(f)
                self.default_projects_dir = data.get(
                    "default_projects_dir", self.default_projects_dir
                )
                self.recent_projects = data.get("recent_projects", [])
            except Exception:
                pass  # use defaults on any error

    def save(self) -> None:
        try:
            os.makedirs(os.path.dirname(SETTINGS_FILE), exist_ok=True)
            with open(SETTINGS_FILE, "w") as f:
                json.dump({
                    "default_projects_dir": self.default_projects_dir,
                    "recent_projects": self.recent_projects,
                }, f, indent=2)
        except Exception as e:
            print(f"Warning: could not save editor settings: {e}")

    def add_recent_project(self, project_dir: str) -> None:
        if project_dir in self.recent_projects:
            self.recent_projects.remove(project_dir)
        self.recent_projects.insert(0, project_dir)
        self.recent_projects = self.recent_projects[:self.MAX_RECENT]
        self.save()
