"""
Data models for oval set configuration.
"""
from dataclasses import dataclass, field
from typing import List, Optional
from enum import Enum
from models.polygon_config import FileSource


class OvalSourceType(Enum):
    FILE = "file"


@dataclass
class OvalSetDef:
    """Definition of a single oval set (file-based only)."""
    name: str = "Untitled"
    source_type: OvalSourceType = OvalSourceType.FILE
    file_source: Optional[FileSource] = None

    def __post_init__(self):
        if self.file_source is None:
            self.file_source = FileSource(folder="ovalSets")

    def copy(self) -> 'OvalSetDef':
        return OvalSetDef(
            name=self.name,
            source_type=self.source_type,
            file_source=self.file_source.copy() if self.file_source else None
        )


@dataclass
class OvalSetLibrary:
    """Library containing multiple oval set definitions."""
    name: str = "MainLibrary"
    oval_sets: List[OvalSetDef] = field(default_factory=list)

    def add_oval_set(self, os: OvalSetDef) -> None:
        self.oval_sets.append(os)

    def remove_oval_set(self, name: str) -> bool:
        for i, os in enumerate(self.oval_sets):
            if os.name == name:
                del self.oval_sets[i]
                return True
        return False

    def get_oval_set(self, name: str) -> Optional[OvalSetDef]:
        for os in self.oval_sets:
            if os.name == name:
                return os
        return None

    def copy(self) -> 'OvalSetLibrary':
        return OvalSetLibrary(
            name=self.name,
            oval_sets=[os.copy() for os in self.oval_sets]
        )

    @classmethod
    def default(cls) -> 'OvalSetLibrary':
        return cls(name="MainLibrary")
