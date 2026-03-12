"""
Transform configuration models for subdivision point transforms.

These transforms modify polygon control points during subdivision:
- ExteriorAnchors: Spike/push exterior anchor points
- CentralAnchors: Tear/move central anchor points
- AnchorsLinkedToCentre: Move side anchors relative to centre
- OuterControlPoints: Curve outer control points
- InnerControlPoints: Curve inner control points
"""
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional


@dataclass
class Range:
    """Min/max range for random values."""
    min: float = 0.0
    max: float = 0.0

    def copy(self) -> 'Range':
        return Range(self.min, self.max)


@dataclass
class ExteriorAnchorsConfig:
    """Configuration for ExteriorAnchors transform."""
    enabled: bool = False
    probability: float = 100.0
    spike_factor: float = -0.3
    # Which spike: ALL, CORNERS, MIDDLES
    which_spike: str = "ALL"
    # Spike type: SYMMETRICAL, RIGHT, LEFT, RANDOM
    spike_type: str = "SYMMETRICAL"
    # Spike axis: XY, X, Y
    spike_axis: str = "XY"
    # Random spike
    random_spike: bool = False
    random_spike_factor: Range = field(default_factory=lambda: Range(-0.2, 0.2))
    # Control points follow
    cps_follow: bool = False
    cps_follow_multiplier: float = 2.0
    random_cps_follow: bool = False
    random_cps_follow_range: Range = field(default_factory=lambda: Range(-1.5, 1.5))
    # Control points squeeze
    cps_squeeze: bool = False
    cps_squeeze_factor: float = -0.2
    random_cps_squeeze: bool = False
    random_cps_squeeze_range: Range = field(default_factory=lambda: Range(-0.5, 0.5))

    def copy(self) -> 'ExteriorAnchorsConfig':
        import dataclasses
        return dataclasses.replace(self,
            random_spike_factor=self.random_spike_factor.copy(),
            random_cps_follow_range=self.random_cps_follow_range.copy(),
            random_cps_squeeze_range=self.random_cps_squeeze_range.copy())


@dataclass
class CentralAnchorsConfig:
    """Configuration for CentralAnchors transform."""
    enabled: bool = False
    probability: float = 100.0
    tear_factor: float = 0.2
    # Tear axis: XY, X, Y, RANDOM
    tear_axis: str = "XY"
    # Tear direction: DIAGONAL, LEFT, RIGHT, RANDOM
    tear_direction: str = "DIAGONAL"
    # Random tear
    random_tear: bool = False
    random_tear_factor: Range = field(default_factory=lambda: Range(-0.2, 0.2))
    # Control points follow
    cps_follow: bool = False
    cps_follow_multiplier: float = -7.0
    random_cps_follow: bool = False
    random_cps_follow_range: Range = field(default_factory=lambda: Range(-1.5, 1.5))
    # All points follow centre
    all_points_follow: bool = False
    inverted_follow: bool = False

    def copy(self) -> 'CentralAnchorsConfig':
        import dataclasses
        return dataclasses.replace(self,
            random_tear_factor=self.random_tear_factor.copy(),
            random_cps_follow_range=self.random_cps_follow_range.copy())


@dataclass
class AnchorsLinkedToCentreConfig:
    """Configuration for AnchorsLinkedToCentre transform."""
    enabled: bool = False
    probability: float = 100.0
    tear_factor: float = 0.45
    # Tear type: TOWARDS_OUTSIDE_CORNER, TOWARDS_OPPOSITE_CORNER, TOWARDS_CENTRE, RANDOM
    tear_type: str = "TOWARDS_OUTSIDE_CORNER"
    # Random tear
    random_tear: bool = False
    random_tear_factor: Range = field(default_factory=lambda: Range(-0.2, 0.2))
    # Control points follow
    cps_follow: bool = True
    cps_follow_multiplier: float = 1.0
    random_cps_follow: bool = False
    random_cps_follow_range: Range = field(default_factory=lambda: Range(-1.5, 1.5))

    def copy(self) -> 'AnchorsLinkedToCentreConfig':
        import dataclasses
        return dataclasses.replace(self,
            random_tear_factor=self.random_tear_factor.copy(),
            random_cps_follow_range=self.random_cps_follow_range.copy())


@dataclass
class OuterControlPointsConfig:
    """Configuration for OuterControlPoints transform."""
    enabled: bool = False
    probability: float = 100.0
    # Line ratio
    line_ratio_x: float = 0.33
    line_ratio_y: float = 0.66
    random_line_ratio: bool = False
    random_line_ratio_inner: Range = field(default_factory=lambda: Range(0.1, 0.5))
    random_line_ratio_outer: Range = field(default_factory=lambda: Range(0.5, 0.9))
    # Curve mode: PERPENDICULAR, FROM_CENTRE
    curve_mode: str = "PERPENDICULAR"
    # Curve type (for perpendicular): PUFF, PINCH
    curve_type: str = "PUFF"
    # Curve multiplier
    curve_multiplier_min: float = 0.2
    curve_multiplier_max: float = 0.2
    random_multiplier: bool = False
    random_curve_multiplier: Range = field(default_factory=lambda: Range(0.5, 3.0))
    # Curve from centre ratio
    curve_from_centre_ratio_x: float = 0.2
    curve_from_centre_ratio_y: float = -0.5
    random_from_centre: bool = False
    random_from_centre_a: Range = field(default_factory=lambda: Range(-1.0, 1.0))
    random_from_centre_b: Range = field(default_factory=lambda: Range(-1.0, 1.0))

    def copy(self) -> 'OuterControlPointsConfig':
        import dataclasses
        return dataclasses.replace(self,
            random_line_ratio_inner=self.random_line_ratio_inner.copy(),
            random_line_ratio_outer=self.random_line_ratio_outer.copy(),
            random_curve_multiplier=self.random_curve_multiplier.copy(),
            random_from_centre_a=self.random_from_centre_a.copy(),
            random_from_centre_b=self.random_from_centre_b.copy())


@dataclass
class InnerControlPointsConfig:
    """Configuration for InnerControlPoints transform."""
    enabled: bool = False
    probability: float = 100.0
    # Refer to outer: NONE, FOLLOW, EXAGGERATE, COUNTER
    refer_to_outer: str = "NONE"
    # Multipliers
    inner_multiplier_x: float = 1.0
    inner_multiplier_y: float = 1.0
    outer_multiplier_x: float = 1.0
    outer_multiplier_y: float = 1.0
    # Tri ratios
    inner_ratio: float = -0.15
    outer_ratio: float = 1.1
    random_ratio: bool = False
    random_inner_ratio: Range = field(default_factory=lambda: Range(-0.5, 0.5))
    random_outer_ratio: Range = field(default_factory=lambda: Range(-0.5, 0.5))
    # Common line: EVEN, ODD, RANDOM, NONE
    common_line: str = "EVEN"

    def copy(self) -> 'InnerControlPointsConfig':
        import dataclasses
        return dataclasses.replace(self,
            random_inner_ratio=self.random_inner_ratio.copy(),
            random_outer_ratio=self.random_outer_ratio.copy())


@dataclass
class TransformSetConfig:
    """Collection of transforms for a SubdivisionParams."""
    exterior_anchors: ExteriorAnchorsConfig = field(default_factory=ExteriorAnchorsConfig)
    central_anchors: CentralAnchorsConfig = field(default_factory=CentralAnchorsConfig)
    anchors_linked: AnchorsLinkedToCentreConfig = field(default_factory=AnchorsLinkedToCentreConfig)
    outer_control_points: OuterControlPointsConfig = field(default_factory=OuterControlPointsConfig)
    inner_control_points: InnerControlPointsConfig = field(default_factory=InnerControlPointsConfig)

    def has_any_enabled(self) -> bool:
        """Check if any transform is enabled."""
        return (self.exterior_anchors.enabled or
                self.central_anchors.enabled or
                self.anchors_linked.enabled or
                self.outer_control_points.enabled or
                self.inner_control_points.enabled)

    def copy(self) -> 'TransformSetConfig':
        return TransformSetConfig(
            exterior_anchors=self.exterior_anchors.copy(),
            central_anchors=self.central_anchors.copy(),
            anchors_linked=self.anchors_linked.copy(),
            outer_control_points=self.outer_control_points.copy(),
            inner_control_points=self.inner_control_points.copy())
