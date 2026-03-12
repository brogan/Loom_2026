"""
Data models for subdivision configuration.
Matches the Scala SubdivisionParams, SubdivisionParamsSet, and SubdivisionParamsSetCollection classes.
"""
from dataclasses import dataclass, field
from typing import List, Optional
from enum import Enum
from models.transform_config import TransformSetConfig


class SubdivisionType(Enum):
    """Types of subdivision algorithms."""
    QUAD = 0
    QUAD_BORD = 1
    QUAD_BORD_ECHO = 2
    QUAD_BORD_DOUBLE = 3
    QUAD_BORD_DOUBLE_ECHO = 4
    TRI = 5
    TRI_BORD_A = 6
    TRI_BORD_A_ECHO = 7
    TRI_BORD_B = 8
    TRI_STAR = 9
    TRI_BORD_C = 10
    TRI_BORD_C_ECHO = 11
    SPLIT_VERT = 12
    SPLIT_HORIZ = 13
    SPLIT_DIAG = 14
    ECHO = 16
    ECHO_ABS_CENTER = 17
    TRI_BORD_B_ECHO = 18
    TRI_STAR_FILL = 19


class VisibilityRule(Enum):
    """Visibility rules for subdivided polygons."""
    ALL = 0
    QUADS = 1
    TRIS = 2
    ALL_BUT_LAST = 3
    ALTERNATE_ODD = 4
    ALTERNATE_EVEN = 5
    FIRST_HALF = 6
    SECOND_HALF = 7
    EVERY_THIRD = 8
    EVERY_FOURTH = 9
    EVERY_FIFTH = 10
    RANDOM_1_2 = 11
    RANDOM_1_3 = 12
    RANDOM_1_5 = 13
    RANDOM_1_7 = 14
    RANDOM_1_10 = 15


@dataclass
class Vector2D:
    """Simple 2D vector for ratios and transforms."""
    x: float = 0.0
    y: float = 0.0

    def copy(self) -> 'Vector2D':
        return Vector2D(self.x, self.y)


@dataclass
class Range:
    """A range with min and max values."""
    min_val: float = 0.0
    max_val: float = 0.0

    def copy(self) -> 'Range':
        return Range(self.min_val, self.max_val)


@dataclass
class RangeXY:
    """X and Y ranges."""
    x: Range = field(default_factory=Range)
    y: Range = field(default_factory=Range)

    def copy(self) -> 'RangeXY':
        return RangeXY(self.x.copy(), self.y.copy())


@dataclass
class Transform2D:
    """2D transformation with translation, scale, and rotation."""
    translation: Vector2D = field(default_factory=Vector2D)
    scale: Vector2D = field(default_factory=lambda: Vector2D(1.0, 1.0))
    rotation: Vector2D = field(default_factory=Vector2D)

    def copy(self) -> 'Transform2D':
        return Transform2D(
            self.translation.copy(),
            self.scale.copy(),
            self.rotation.copy()
        )


@dataclass
class SubdivisionParams:
    """Parameters for a single subdivision operation."""
    name: str = "default"
    enabled: bool = True

    # Core subdivision settings
    subdivision_type: SubdivisionType = SubdivisionType.QUAD
    visibility_rule: VisibilityRule = VisibilityRule.ALL

    # Randomization
    ran_middle: bool = False
    ran_div: float = 100.0

    # Line ratios for intermediate points
    line_ratios: Vector2D = field(default_factory=lambda: Vector2D(0.5, 0.5))
    control_point_ratios: Vector2D = field(default_factory=lambda: Vector2D(0.25, 0.75))

    # Inset transform (for echo subdivision)
    inset_transform: Transform2D = field(default_factory=lambda: Transform2D(
        Vector2D(0, 0), Vector2D(0.5, 0.5), Vector2D(0, 0)
    ))

    # Continuous mode
    continuous: bool = True

    # Polygon transforms
    polys_transform: bool = True
    polys_transform_whole: bool = False

    # Random transform flags
    ptw_random_translation: bool = False
    ptw_random_scale: bool = False
    ptw_random_rotation: bool = False
    ptw_common_centre: bool = False

    # Transform probability and values
    ptw_probability: float = 100.0
    ptw_transform: Transform2D = field(default_factory=Transform2D)
    ptw_random_centre_divisor: float = 100.0
    ptw_random_translation_range: RangeXY = field(default_factory=RangeXY)
    ptw_random_scale_range: RangeXY = field(default_factory=lambda: RangeXY(
        Range(1.0, 1.0), Range(1.0, 1.0)
    ))
    ptw_random_rotation_range: Range = field(default_factory=Range)

    # Point transforms
    polys_transform_points: bool = False
    ptp_probability: float = 100.0

    # Transform set for point transforms
    transform_set: TransformSetConfig = field(default_factory=TransformSetConfig)

    def copy(self) -> 'SubdivisionParams':
        return SubdivisionParams(
            name=self.name,
            enabled=self.enabled,
            subdivision_type=self.subdivision_type,
            visibility_rule=self.visibility_rule,
            ran_middle=self.ran_middle,
            ran_div=self.ran_div,
            line_ratios=self.line_ratios.copy(),
            control_point_ratios=self.control_point_ratios.copy(),
            inset_transform=self.inset_transform.copy(),
            continuous=self.continuous,
            polys_transform=self.polys_transform,
            polys_transform_whole=self.polys_transform_whole,
            ptw_random_translation=self.ptw_random_translation,
            ptw_random_scale=self.ptw_random_scale,
            ptw_random_rotation=self.ptw_random_rotation,
            ptw_common_centre=self.ptw_common_centre,
            ptw_probability=self.ptw_probability,
            ptw_transform=self.ptw_transform.copy(),
            ptw_random_centre_divisor=self.ptw_random_centre_divisor,
            ptw_random_translation_range=self.ptw_random_translation_range.copy(),
            ptw_random_scale_range=self.ptw_random_scale_range.copy(),
            ptw_random_rotation_range=self.ptw_random_rotation_range.copy(),
            polys_transform_points=self.polys_transform_points,
            ptp_probability=self.ptp_probability,
            transform_set=self.transform_set.copy()
        )


@dataclass
class SubdivisionParamsSet:
    """A named set of subdivision parameters."""
    name: str = "default"
    params_list: List[SubdivisionParams] = field(default_factory=list)

    def add_params(self, params: SubdivisionParams) -> None:
        self.params_list.append(params)

    def remove_params(self, name: str) -> bool:
        for i, p in enumerate(self.params_list):
            if p.name == name:
                del self.params_list[i]
                return True
        return False

    def get_params(self, name: str) -> Optional[SubdivisionParams]:
        for p in self.params_list:
            if p.name == name:
                return p
        return None

    def move_params(self, from_index: int, to_index: int) -> None:
        if 0 <= from_index < len(self.params_list) and 0 <= to_index < len(self.params_list):
            params = self.params_list.pop(from_index)
            self.params_list.insert(to_index, params)

    def copy(self) -> 'SubdivisionParamsSet':
        return SubdivisionParamsSet(
            name=self.name,
            params_list=[p.copy() for p in self.params_list]
        )


@dataclass
class SubdivisionParamsSetCollection:
    """Collection of subdivision parameter sets."""
    params_sets: List[SubdivisionParamsSet] = field(default_factory=list)

    def add_params_set(self, params_set: SubdivisionParamsSet) -> None:
        self.params_sets.append(params_set)

    def remove_params_set(self, name: str) -> bool:
        for i, ps in enumerate(self.params_sets):
            if ps.name == name:
                del self.params_sets[i]
                return True
        return False

    def get_params_set(self, name: str) -> Optional[SubdivisionParamsSet]:
        for ps in self.params_sets:
            if ps.name == name:
                return ps
        return None

    def move_params_set(self, from_index: int, to_index: int) -> None:
        if 0 <= from_index < len(self.params_sets) and 0 <= to_index < len(self.params_sets):
            ps = self.params_sets.pop(from_index)
            self.params_sets.insert(to_index, ps)

    def copy(self) -> 'SubdivisionParamsSetCollection':
        return SubdivisionParamsSetCollection(
            params_sets=[ps.copy() for ps in self.params_sets]
        )

    @classmethod
    def default(cls) -> 'SubdivisionParamsSetCollection':
        """Create a default collection with sample subdivision parameters."""
        collection = cls()

        # Create a default params set
        params_set = SubdivisionParamsSet(name="default")

        # Add a simple quad subdivision
        simple_params = SubdivisionParams(
            name="simpler",
            subdivision_type=SubdivisionType.QUAD,
            visibility_rule=VisibilityRule.ALL,
            line_ratios=Vector2D(0.5, 0.5),
            inset_transform=Transform2D(
                Vector2D(0, 0), Vector2D(0.5, 0.5), Vector2D(0, 0)
            )
        )
        params_set.add_params(simple_params)

        collection.add_params_set(params_set)
        return collection
