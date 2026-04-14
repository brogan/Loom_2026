"""
CubicCurveManager — manages one polygon or open curve (a list of CubicCurves).
Mirrors Java CubicCurveManager.
"""
from __future__ import annotations
import math
from PySide6.QtCore import QPointF
from PySide6.QtGui import QPainterPath
from model.cubic_point import CubicPoint, PointType
from model.cubic_curve import CubicCurve, ANCHOR_FIRST, ANCHOR_LAST


class CubicCurveManager:

    def __init__(self) -> None:
        self.curves: list[CubicCurve] = []
        self._current_curve: CubicCurve = CubicCurve()
        self._curve_count: int = 0    # committed curves so far
        self._point_count: int = 0    # 0 or 1 within first curve only

        self.add_points: bool = True
        self.is_closed: bool = False
        self.layer_id: int = 0

        # Per-anchor pressure (0.0–1.0); None = uniform 1.0
        self.anchor_pressures: list[float] | None = None

        # Selection / highlight state
        self.selected: bool = False
        self.selected_relational: bool = False
        self.scoped: bool = False
        self.discrete_edge_indices: set[int] = set()
        self.relational_edge_indices: set[int] = set()
        self.weldable_edge_indices: set[int] = set()   # purple drag-weld preview
        self.discrete_points: set[CubicPoint] = set()
        self.relational_points: set[CubicPoint] = set()

    # ── interactive drawing ─────────────────────────────────────────────────

    def set_point(self, pos: QPointF) -> None:
        """
        Add an anchor click during interactive drawing.
        Mirrors Java BezierDrawPanel.setPoint(Point2D.Double).
        """
        if not self.add_points:
            return

        if self._curve_count == 0:  # first curve
            if self._point_count == 0:
                self._current_curve.set_anchor_first(pos)
                self._point_count = 1
            else:  # second click → complete first curve
                self._current_curve.set_anchor_last(pos)
                self._current_curve.auto_control_points()
                self.curves.append(self._current_curve)
                self._point_count = 0
                self._curve_count += 1
                self._current_curve = CubicCurve()
        else:  # subsequent curves: each click adds one anchor and completes a curve
            if self._point_count == 0:
                last_anchor = self.curves[-1].points[3]
                self._current_curve.set_anchor_first(last_anchor.pos, master=last_anchor)
                self._current_curve.set_anchor_last(pos)
                self._current_curve.auto_control_points()
                self.curves.append(self._current_curve)
                self._point_count = 0
                self._curve_count += 1
                self._current_curve = CubicCurve()

    def close_curve(self) -> None:
        """
        Close by adding a synthetic last curve from the last anchor back to the first.
        Mirrors Java CubicCurveManager.closeCurve().
        """
        if self._curve_count == 0:
            return
        closing = CubicCurve()
        last_anchor = self.curves[self._curve_count - 1].points[3]
        origin_anchor = self.curves[0].points[0]
        closing.set_anchor_first(last_anchor.pos, master=last_anchor)
        closing.set_anchor_last(origin_anchor.pos, master=origin_anchor)
        closing.auto_control_points()
        self.curves.append(closing)
        self.add_points = False
        self.is_closed = True

    def finish_open(self) -> None:
        """Finalise as an open curve (no closing edge)."""
        self.add_points = False
        self.is_closed = False

    # ── loading from XML ────────────────────────────────────────────────────

    def set_all_points(self, pts: list[QPointF]) -> None:
        """
        Rebuild from a flat list of N*4 QPointF (order: A1,C1,C2,A2 per curve).
        Last anchor links back to first (closed polygon).
        Mirrors Java setAllPoints().
        """
        self.curves.clear()
        self._curve_count = 0
        n = len(pts) // 4
        for i in range(n):
            base = i * 4
            curve = CubicCurve()
            if i == 0:
                curve.set_anchor_first(pts[base])
            else:
                curve.set_anchor_first(pts[base], master=self.curves[i - 1].points[3])
            curve.set_control_points_from(pts[base + 1], pts[base + 2])
            if i == n - 1:
                curve.set_anchor_last(pts[base + 3], master=self.curves[0].points[0])
            else:
                curve.set_anchor_last(pts[base + 3])
            self.curves.append(curve)
            self._curve_count += 1
        self.add_points = False

    def set_open_points(self, pts: list[QPointF]) -> None:
        """
        Like set_all_points but does NOT link last anchor back to first.
        Mirrors Java setOpenPoints().
        """
        self.curves.clear()
        self._curve_count = 0
        n = len(pts) // 4
        for i in range(n):
            base = i * 4
            curve = CubicCurve()
            if i == 0:
                curve.set_anchor_first(pts[base])
            else:
                curve.set_anchor_first(pts[base], master=self.curves[i - 1].points[3])
            curve.set_control_points_from(pts[base + 1], pts[base + 2])
            curve.set_anchor_last(pts[base + 3])
            self.curves.append(curve)
            self._curve_count += 1
        self.add_points = False
        self.is_closed = False

    # ── geometry queries ────────────────────────────────────────────────────

    def get_average_xy(self) -> QPointF:
        """Centroid of all anchor points (current pos)."""
        if not self.curves:
            return QPointF(520.0, 520.0)
        sx = sy = 0.0
        n = 0
        for cv in self.curves:
            for idx in (0, 3):
                p = cv.points[idx]
                if p:
                    sx += p.pos.x()
                    sy += p.pos.y()
                    n += 1
        if n == 0:
            return QPointF(520.0, 520.0)
        return QPointF(sx / n, sy / n)

    def get_average_xy_from_orig(self) -> QPointF:
        """Centroid of all anchor points (orig_pos — stable during slider gestures)."""
        if not self.curves:
            return QPointF(520.0, 520.0)
        sx = sy = 0.0
        n = 0
        for cv in self.curves:
            for idx in (0, 3):
                p = cv.points[idx]
                if p:
                    sx += p.orig_pos.x()
                    sy += p.orig_pos.y()
                    n += 1
        if n == 0:
            return QPointF(520.0, 520.0)
        return QPointF(sx / n, sy / n)

    def contains_point(self, pt: QPointF) -> bool:
        """True if pt is inside the closed Bézier polygon."""
        if not self.curves:
            return False
        path = self._build_painter_path()
        return path.contains(pt)

    def _build_painter_path(self) -> QPainterPath:
        """Build a QPainterPath from all curves."""
        path = QPainterPath()
        if not self.curves:
            return path
        first = self.curves[0].points[0]
        if first is None:
            return path
        path.moveTo(first.pos)
        for cv in self.curves:
            p = cv.points
            if all(x is not None for x in p):
                path.cubicTo(p[1].pos, p[2].pos, p[3].pos)
        if self.is_closed:
            path.closeSubpath()
        return path

    def near_open_curve(self, pos: QPointF, hit_dist: float = 8.0) -> bool:
        """True if pos is within hit_dist of the (open) curve path — stroked containment."""
        path = self._build_painter_path()
        if path.isEmpty():
            return False
        from PySide6.QtGui import QPainterPathStroker
        stroker = QPainterPathStroker()
        stroker.setWidth(hit_dist * 2)
        return stroker.createStroke(path).contains(pos)

    @staticmethod
    def distance_to_edge(pos: QPointF, cv) -> float:
        """Approximate min distance from pos to a cubic curve (30-sample parametric)."""
        pts = cv.points
        if not all(p is not None for p in pts):
            return float('inf')
        p0, p1, p2, p3 = [p.pos for p in pts]
        min_d = float('inf')
        for i in range(31):
            t = i / 30.0
            u = 1.0 - t
            bx = (u**3 * p0.x() + 3*u**2*t * p1.x()
                  + 3*u*t**2 * p2.x() + t**3 * p3.x())
            by = (u**3 * p0.y() + 3*u**2*t * p1.y()
                  + 3*u*t**2 * p2.y() + t**3 * p3.y())
            d = math.hypot(bx - pos.x(), by - pos.y())
            if d < min_d:
                min_d = d
        return min_d

    def check_for_intersect(self, mouse_pos: QPointF, hit_radius: float = 8.0) -> tuple[int, int]:
        """
        Find (curve_idx, point_idx) of closest point within hit_radius.
        Returns (-1, -1) if none found.
        """
        for ci, cv in enumerate(self.curves):
            for pi, pt in enumerate(cv.points):
                if pt is None:
                    continue
                dx = mouse_pos.x() - pt.pos.x()
                dy = mouse_pos.y() - pt.pos.y()
                if math.hypot(dx, dy) < hit_radius:
                    return ci, pi
        return -1, -1

    def save_all_current_pos(self) -> None:
        """Save all point positions at drag start."""
        seen: set[int] = set()
        for cv in self.curves:
            for pt in cv.points:
                if pt is not None and id(pt) not in seen:
                    seen.add(id(pt))
                    pt.save_current_pos()

    def clear_all_highlights(self) -> None:
        self.selected = False
        self.selected_relational = False
        self.scoped = False
        self.discrete_edge_indices.clear()
        self.relational_edge_indices.clear()
        self.weldable_edge_indices.clear()
        self.discrete_points.clear()
        self.relational_points.clear()

    def get_anchor_pressure(self, k: int) -> float:
        if self.anchor_pressures is None or k < 0 or k >= len(self.anchor_pressures):
            return 1.0
        return self.anchor_pressures[k]

    @property
    def curve_count(self) -> int:
        return self._curve_count

    @property
    def point_count(self) -> int:
        return self._point_count

    @property
    def current_curve(self) -> CubicCurve:
        return self._current_curve
