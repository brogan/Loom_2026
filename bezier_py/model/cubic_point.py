"""CubicPoint — a single point in a cubic Bézier curve."""
from __future__ import annotations
from enum import IntEnum
from PySide6.QtCore import QPointF


class PointType(IntEnum):
    ANCHOR = 0
    CONTROL = 1


class CubicPoint:
    """Mirrors Java CubicPoint. Holds pos + orig_pos (pre-transform)."""

    def __init__(self, pos: QPointF, point_type: PointType) -> None:
        self.pos = QPointF(pos)
        self.orig_pos = QPointF(pos)
        # Saved at start of drag so we can compute delta
        self.current_pos = QPointF(0.0, 0.0)
        self.type = point_type
        self.selected = False

    # ── position helpers ────────────────────────────────────────────────────

    def save_current_pos(self) -> None:
        """Freeze current pos at drag start."""
        self.current_pos = QPointF(self.pos)

    def set_orig_to_pos(self) -> None:
        """Commit current pos as the new original (after slider release)."""
        self.orig_pos = QPointF(self.pos)

    def drag(self, new_pos: QPointF) -> None:
        self.pos = QPointF(new_pos)

    def __repr__(self) -> str:
        return f"CubicPoint({self.type.name}, ({self.pos.x():.2f},{self.pos.y():.2f}))"
