"""
Shape configuration models.

Shapes in Loom are composed of:
- A list of polygons (from a PolygonSet or defined inline)
- A SubdivisionParamsSet for subdivision operations

Shapes can be:
- 2D shapes (from loaded polygons or regular polygon generators)
- 3D shapes (crystals, grids, extrusions - more complex, may need special handling)
"""
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional


class ShapeSourceType(Enum):
    """How the shape's polygons are sourced."""
    POLYGON_SET = 0      # Reference a PolygonSet by name
    REGULAR_POLYGON = 1  # Generate a regular polygon with N sides
    INLINE_POINTS = 2    # Define points directly in the shape config
    OPEN_CURVE_SET = 3   # Reference an OpenCurveSet by name
    POINT_SET = 4        # Reference a PointSet by name
    OVAL_SET = 5         # Reference an OvalSet by name


class Shape3DType(Enum):
    """Types of 3D shape generators."""
    NONE = 0             # 2D shape only
    CRYSTAL = 1          # Crystal shape (top/bottom points with middle ring)
    RECT_PRISM = 2       # Rectangular prism / cube-like
    EXTRUSION = 3        # Extruded 2D polygon
    GRID_PLANE = 4       # Grid plane
    GRID_BLOCK = 5       # 3D grid block


@dataclass
class Vector2D:
    """2D vector for inline point definitions."""
    x: float = 0.0
    y: float = 0.0


@dataclass
class ShapeDef:
    """
    Definition of a single shape.

    A shape combines polygons with subdivision parameters.
    """
    name: str = "default"

    # Polygon source
    source_type: ShapeSourceType = ShapeSourceType.POLYGON_SET
    polygon_set_name: str = ""           # For POLYGON_SET type
    regular_polygon_sides: int = 4       # For REGULAR_POLYGON type
    inline_points: List[Vector2D] = field(default_factory=list)  # For INLINE_POINTS type
    open_curve_set_name: str = ""        # For OPEN_CURVE_SET type
    point_set_name: str = ""             # For POINT_SET type
    oval_set_name: str = ""              # For OVAL_SET type

    # Subdivision parameters reference
    subdivision_params_set_name: str = ""  # Name of SubdivisionParamsSet to use

    # 3D generation (optional)
    shape_3d_type: Shape3DType = Shape3DType.NONE
    shape_3d_param1: int = 4    # e.g., numHoriz for crystal, rows for grid
    shape_3d_param2: int = 4    # e.g., cols for grid
    shape_3d_param3: int = 4    # e.g., layers for grid block

    # Transform applied to the shape
    translate_x: float = 0.0
    translate_y: float = 0.0
    scale_x: float = 1.0
    scale_y: float = 1.0
    rotation: float = 0.0


@dataclass
class ShapeSet:
    """
    A named set of shapes.

    Allows grouping related shapes together.
    """
    name: str = "default"
    shapes: List[ShapeDef] = field(default_factory=list)

    def add(self, shape: ShapeDef) -> None:
        """Add a shape to this set."""
        self.shapes.append(shape)

    def remove(self, index: int) -> None:
        """Remove a shape by index."""
        if 0 <= index < len(self.shapes):
            self.shapes.pop(index)

    def get(self, name: str) -> Optional[ShapeDef]:
        """Get a shape by name."""
        for shape in self.shapes:
            if shape.name == name:
                return shape
        return None


@dataclass
class ShapeLibrary:
    """
    A library of shape sets.

    Top-level container for shape configuration.
    """
    name: str = "MainLibrary"
    shape_sets: List[ShapeSet] = field(default_factory=list)

    def add(self, shape_set: ShapeSet) -> None:
        """Add a shape set to the library."""
        self.shape_sets.append(shape_set)

    def remove(self, index: int) -> None:
        """Remove a shape set by index."""
        if 0 <= index < len(self.shape_sets):
            self.shape_sets.pop(index)

    def get(self, name: str) -> Optional[ShapeSet]:
        """Get a shape set by name."""
        for shape_set in self.shape_sets:
            if shape_set.name == name:
                return shape_set
        return None

    def get_all_shape_names(self) -> List[str]:
        """Get all shape names across all sets."""
        names = []
        for shape_set in self.shape_sets:
            for shape in shape_set.shapes:
                names.append(f"{shape_set.name}/{shape.name}")
        return names
