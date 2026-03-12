"""
Data models for project manifest.
"""
from dataclasses import dataclass, field
from typing import List, Optional
from datetime import datetime


@dataclass
class ProjectFile:
    """Reference to a domain configuration file within a project."""
    domain: str  # e.g., "rendering", "geometry", "subdivision"
    path: str    # Relative path to the XML file

    def copy(self) -> 'ProjectFile':
        return ProjectFile(domain=self.domain, path=self.path)


@dataclass
class Project:
    """Project manifest containing metadata and file references."""
    name: str = "New Project"
    description: str = ""
    created: datetime = field(default_factory=datetime.now)
    modified: datetime = field(default_factory=datetime.now)
    files: List[ProjectFile] = field(default_factory=list)
    version: str = "1.0"

    def add_file(self, domain: str, path: str) -> None:
        """Add a domain file reference."""
        # Remove existing file for this domain if present
        self.files = [f for f in self.files if f.domain != domain]
        self.files.append(ProjectFile(domain=domain, path=path))

    def get_file(self, domain: str) -> Optional[ProjectFile]:
        """Get file reference for a domain."""
        for f in self.files:
            if f.domain == domain:
                return f
        return None

    def remove_file(self, domain: str) -> bool:
        """Remove file reference for a domain."""
        original_len = len(self.files)
        self.files = [f for f in self.files if f.domain != domain]
        return len(self.files) < original_len

    def touch(self) -> None:
        """Update modified timestamp."""
        self.modified = datetime.now()

    def copy(self) -> 'Project':
        return Project(
            name=self.name,
            description=self.description,
            created=self.created,
            modified=self.modified,
            files=[f.copy() for f in self.files],
            version=self.version
        )
