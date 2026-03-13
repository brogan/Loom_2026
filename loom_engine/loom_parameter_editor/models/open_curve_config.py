"""
Data models for open curve set configuration.
"""
from dataclasses import dataclass, field
from typing import List, Optional
from enum import Enum
from models.polygon_config import FileSource


class OpenCurveSourceType(Enum):
    FILE = "file"


@dataclass
class OpenCurveDef:
    """Definition of a single open curve set (file-based only)."""
    name: str = "Untitled"
    source_type: OpenCurveSourceType = OpenCurveSourceType.FILE
    file_source: Optional[FileSource] = None

    def __post_init__(self):
        if self.file_source is None:
            self.file_source = FileSource(folder="curveSets")

    def copy(self) -> 'OpenCurveDef':
        return OpenCurveDef(
            name=self.name,
            source_type=self.source_type,
            file_source=self.file_source.copy() if self.file_source else None
        )


@dataclass
class OpenCurveSetLibrary:
    """Library containing multiple open curve set definitions."""
    name: str = "MainLibrary"
    curve_sets: List[OpenCurveDef] = field(default_factory=list)

    def add_curve_set(self, curve_set: OpenCurveDef) -> None:
        self.curve_sets.append(curve_set)

    def remove_curve_set(self, name: str) -> bool:
        for i, cs in enumerate(self.curve_sets):
            if cs.name == name:
                del self.curve_sets[i]
                return True
        return False

    def get_curve_set(self, name: str) -> Optional[OpenCurveDef]:
        for cs in self.curve_sets:
            if cs.name == name:
                return cs
        return None

    def copy(self) -> 'OpenCurveSetLibrary':
        return OpenCurveSetLibrary(
            name=self.name,
            curve_sets=[cs.copy() for cs in self.curve_sets]
        )

    @classmethod
    def default(cls) -> 'OpenCurveSetLibrary':
        return cls(name="MainLibrary")
