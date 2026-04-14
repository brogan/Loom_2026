"""
Selection data structures shared across canvas modules.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum, auto


class SelectionSubMode(Enum):
    RELATIONAL = auto()   # default: affects weld partners
    DISCRETE   = auto()   # Cmd+click: affects only the clicked item


@dataclass
class SelectedEdge:
    manager: object     # CubicCurveManager (typed as object to avoid circular import)
    curve_index: int

    def matches(self, other: SelectedEdge) -> bool:
        return self.manager is other.manager and self.curve_index == other.curve_index


@dataclass
class SelectionSnapshot:
    """One entry in the selection history stack (max 10)."""
    points:   list = field(default_factory=list)  # list[CubicPoint]
    edges:    list = field(default_factory=list)  # list[SelectedEdge]
    polygons: list = field(default_factory=list)  # list[CubicCurveManager]
    ovals:    list = field(default_factory=list)  # list[OvalManager]

    def is_empty(self) -> bool:
        return not (self.points or self.edges or self.polygons or self.ovals)
