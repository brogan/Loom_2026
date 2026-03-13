"""
Data models for discrete point set configuration.
"""
from dataclasses import dataclass, field
from typing import List, Optional
from enum import Enum
from models.polygon_config import FileSource


class PointSourceType(Enum):
    FILE = "file"


@dataclass
class PointSetDef:
    """Definition of a single point set (file-based only)."""
    name: str = "Untitled"
    source_type: PointSourceType = PointSourceType.FILE
    file_source: Optional[FileSource] = None

    def __post_init__(self):
        if self.file_source is None:
            self.file_source = FileSource(folder="pointSets")

    def copy(self) -> 'PointSetDef':
        return PointSetDef(
            name=self.name,
            source_type=self.source_type,
            file_source=self.file_source.copy() if self.file_source else None
        )


@dataclass
class PointSetLibrary:
    """Library containing multiple point set definitions."""
    name: str = "MainLibrary"
    point_sets: List[PointSetDef] = field(default_factory=list)

    def add_point_set(self, ps: PointSetDef) -> None:
        self.point_sets.append(ps)

    def remove_point_set(self, name: str) -> bool:
        for i, ps in enumerate(self.point_sets):
            if ps.name == name:
                del self.point_sets[i]
                return True
        return False

    def get_point_set(self, name: str) -> Optional[PointSetDef]:
        for ps in self.point_sets:
            if ps.name == name:
                return ps
        return None

    def copy(self) -> 'PointSetLibrary':
        return PointSetLibrary(
            name=self.name,
            point_sets=[ps.copy() for ps in self.point_sets]
        )

    @classmethod
    def default(cls) -> 'PointSetLibrary':
        return cls(name="MainLibrary")
