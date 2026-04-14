"""CubicCurve — 4-point Bézier segment (anchor, ctrl, ctrl, anchor)."""
from __future__ import annotations
from PySide6.QtCore import QPointF
from model.cubic_point import CubicPoint, PointType

ANCHOR_FIRST = 0
ANCHOR_LAST = 1


class CubicCurve:
    """
    Mirrors Java CubicCurve.
    points[0] = anchor start
    points[1] = control 1
    points[2] = control 2
    points[3] = anchor end
    """

    def __init__(self) -> None:
        self.points: list[CubicPoint | None] = [None, None, None, None]

    # ── anchor setters ───────────────────────────────────────────────────────

    def set_anchor_first(self, pos: QPointF, master: CubicPoint | None = None) -> None:
        """Set anchor[0]. If master is given, share the CubicPoint object."""
        if master is not None:
            self.points[0] = master
        else:
            self.points[0] = CubicPoint(pos, PointType.ANCHOR)

    def set_anchor_last(self, pos: QPointF, master: CubicPoint | None = None) -> None:
        """Set anchor[3]. If master is given, share the CubicPoint object."""
        if master is not None:
            self.points[3] = master
        else:
            self.points[3] = CubicPoint(pos, PointType.ANCHOR)

    def set_control_point(self, index: int, pos: QPointF) -> None:
        """Set control point at index 1 or 2."""
        self.points[index] = CubicPoint(pos, PointType.CONTROL)

    def auto_control_points(self) -> None:
        """Generate evenly-spaced control points from anchor[0] to anchor[3]."""
        p0 = self.points[0].pos
        p3 = self.points[3].pos
        dx = (p3.x() - p0.x()) / 3.0
        dy = (p3.y() - p0.y()) / 3.0
        self.points[1] = CubicPoint(QPointF(p0.x() + dx, p0.y() + dy), PointType.CONTROL)
        self.points[2] = CubicPoint(QPointF(p0.x() + 2 * dx, p0.y() + 2 * dy), PointType.CONTROL)

    def set_control_points_from(self, c1: QPointF, c2: QPointF) -> None:
        """Set control points to explicit positions (used when loading from XML)."""
        self.points[1] = CubicPoint(c1, PointType.CONTROL)
        self.points[2] = CubicPoint(c2, PointType.CONTROL)

    def is_complete(self) -> bool:
        return all(p is not None for p in self.points)

    def save_all_current_pos(self) -> None:
        """Freeze all point positions at drag start."""
        for p in self.points:
            if p is not None:
                p.save_current_pos()
