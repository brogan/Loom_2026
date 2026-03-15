"""
Data models for polygon configuration.
Supports both regular polygons (defined by parameters) and file-based polygons (spline curves).
"""
from dataclasses import dataclass, field
from typing import List, Optional
from enum import Enum


class PolygonSourceType(Enum):
    """Source type for polygon data."""
    FILE = "file"           # Load from external XML file
    REGULAR = "regular"     # Generate regular polygon from parameters


class PolygonType(Enum):
    """Type of polygon geometry."""
    LINE_POLYGON = "LINE_POLYGON"       # Straight line edges
    SPLINE_POLYGON = "SPLINE_POLYGON"   # Cubic bezier curves


@dataclass
class RegularPolygonParams:
    """Parameters for generating a regular polygon."""
    total_points: int = 4
    internal_radius: float = 0.5
    offset: float = 0.0
    scale_x: float = 1.0
    scale_y: float = 1.0
    rotation_angle: float = 0.0
    trans_x: float = 0.5
    trans_y: float = 0.5
    positive_synch: bool = True
    synch_multiplier: float = 1.0

    def copy(self) -> 'RegularPolygonParams':
        return RegularPolygonParams(
            total_points=self.total_points,
            internal_radius=self.internal_radius,
            offset=self.offset,
            scale_x=self.scale_x,
            scale_y=self.scale_y,
            rotation_angle=self.rotation_angle,
            trans_x=self.trans_x,
            trans_y=self.trans_y,
            positive_synch=self.positive_synch,
            synch_multiplier=self.synch_multiplier
        )


@dataclass
class FileSource:
    """Reference to an external polygon file."""
    folder: str = "polygonSet"
    filename: str = ""
    polygon_type: PolygonType = PolygonType.SPLINE_POLYGON
    filter_type: str = "all"   # "all" | "closed_only"

    def copy(self) -> 'FileSource':
        return FileSource(
            folder=self.folder,
            filename=self.filename,
            polygon_type=self.polygon_type,
            filter_type=self.filter_type
        )


@dataclass
class PolygonSetDef:
    """Definition of a polygon set - either file-based or regular polygon."""
    name: str = "Untitled"
    source_type: PolygonSourceType = PolygonSourceType.FILE
    file_source: Optional[FileSource] = None
    regular_params: Optional[RegularPolygonParams] = None

    def __post_init__(self):
        if self.file_source is None and self.source_type == PolygonSourceType.FILE:
            self.file_source = FileSource()
        if self.regular_params is None and self.source_type == PolygonSourceType.REGULAR:
            self.regular_params = RegularPolygonParams()

    def copy(self) -> 'PolygonSetDef':
        return PolygonSetDef(
            name=self.name,
            source_type=self.source_type,
            file_source=self.file_source.copy() if self.file_source else None,
            regular_params=self.regular_params.copy() if self.regular_params else None
        )


@dataclass
class PolygonSetLibrary:
    """Library containing multiple polygon set definitions."""
    name: str = "MainLibrary"
    polygon_sets: List[PolygonSetDef] = field(default_factory=list)

    def add_polygon_set(self, polygon_set: PolygonSetDef) -> None:
        self.polygon_sets.append(polygon_set)

    def remove_polygon_set(self, name: str) -> bool:
        for i, ps in enumerate(self.polygon_sets):
            if ps.name == name:
                del self.polygon_sets[i]
                return True
        return False

    def get_polygon_set(self, name: str) -> Optional[PolygonSetDef]:
        for ps in self.polygon_sets:
            if ps.name == name:
                return ps
        return None

    def copy(self) -> 'PolygonSetLibrary':
        return PolygonSetLibrary(
            name=self.name,
            polygon_sets=[ps.copy() for ps in self.polygon_sets]
        )

    @classmethod
    def default(cls) -> 'PolygonSetLibrary':
        """Create an empty default library."""
        return cls(name="MainLibrary")
