"""
PolygonManager — owns the list of CubicCurveManagers.
Mirrors Java CubicCurvePolygonManager.

The last manager is always the "active drawing" manager (add_points=True until
the user finishes a curve). Committed managers are indices 0..polygon_count-1.
"""
from __future__ import annotations
import copy
from PySide6.QtCore import QPointF
from model.cubic_curve_manager import CubicCurveManager
from model.cubic_curve import CubicCurve
from model.cubic_point import CubicPoint, PointType
from model.weld_registry import WeldRegistry

# Coord constants (same as BezierWidget)
GRIDWIDTH  = 1000
GRIDHEIGHT = 1000
EDGE_OFFSET = 20


class PolygonManager:

    def __init__(self, layer_manager=None) -> None:
        self._layer_manager = layer_manager  # LayerManager | None
        first = CubicCurveManager()
        if layer_manager is not None:
            first.layer_id = layer_manager.active_layer_id
        self._managers: list[CubicCurveManager] = [first]
        self.weld_registry: WeldRegistry = WeldRegistry()

    # ── manager access ───────────────────────────────────────────────────────

    @property
    def polygon_count(self) -> int:
        """Number of committed managers (all but the last active one)."""
        return len(self._managers) - 1

    def current_manager(self) -> CubicCurveManager:
        return self._managers[-1]

    def get_manager(self, index: int) -> CubicCurveManager:
        return self._managers[index]

    def committed_managers(self) -> list[CubicCurveManager]:
        return self._managers[:-1]

    def all_managers(self) -> list[CubicCurveManager]:
        return list(self._managers)

    def add_manager(self) -> None:
        """Append a fresh drawing manager after committing the current one."""
        mgr = CubicCurveManager()
        if self._layer_manager is not None:
            mgr.layer_id = self._layer_manager.active_layer_id
        self._managers.append(mgr)

    def sync_active_drawing_manager_layer(self) -> None:
        """Keep the drawing manager's layer_id in sync with the active layer."""
        if self._layer_manager is None:
            return
        self._managers[-1].layer_id = self._layer_manager.active_layer_id

    def remove_manager_at(self, index: int) -> None:
        """Remove a committed manager by index."""
        if 0 <= index < self.polygon_count:
            self._managers.pop(index)

    def get_managers_for_layer(self, layer_id: int) -> list[CubicCurveManager]:
        """Return all committed managers belonging to a specific layer."""
        return [m for m in self.committed_managers() if m.layer_id == layer_id]

    def add_duplicate_of(self, source: CubicCurveManager,
                         offset_x: float = 0.0, offset_y: float = 0.0) -> CubicCurveManager:
        """
        Deep-copy source (with optional positional offset) and insert it
        immediately before the drawing manager. Returns the new manager.
        """
        new_mgr = CubicCurveManager()
        new_mgr.is_closed = source.is_closed
        new_mgr.layer_id = (self._layer_manager.active_layer_id
                            if self._layer_manager else 0)
        for cv in source.curves:
            new_cv = CubicCurve()
            for i, pt in enumerate(cv.points):
                if pt is not None:
                    new_pt = CubicPoint(
                        QPointF(pt.pos.x() + offset_x, pt.pos.y() + offset_y),
                        pt.type,
                    )
                    new_cv.points[i] = new_pt
            new_mgr.curves.append(new_cv)
        new_mgr.add_points = False
        # Insert before the drawing manager (last slot)
        self._managers.insert(len(self._managers) - 1, new_mgr)
        return new_mgr

    # ── interactive: called from BezierWidget ────────────────────────────────

    def set_point(self, pos: QPointF) -> None:
        """Forward a click to the active drawing manager."""
        self.current_manager().set_point(pos)

    def finish_closed(self) -> None:
        """Close the active manager as a polygon, push a new active manager."""
        mgr = self.current_manager()
        if mgr.curve_count < 2:
            return
        mgr.close_curve()
        self.add_manager()
        self.sync_active_drawing_manager_layer()

    def finish_open(self) -> None:
        """Finish the active manager as an open curve, push a new active manager."""
        mgr = self.current_manager()
        if mgr.curve_count < 1:
            return
        mgr.finish_open()
        self.add_manager()
        self.sync_active_drawing_manager_layer()

    # ── coordinate helpers ───────────────────────────────────────────────────

    @staticmethod
    def normalise_point(canvas_x: float, canvas_y: float) -> tuple[float, float]:
        """
        canvas pixel → XML normalised value.
        Formula: norm = canvas / GRIDWIDTH - 0.5 - EDGE_OFFSET/GRIDWIDTH
        """
        offset = EDGE_OFFSET / GRIDWIDTH  # 0.02
        nx = canvas_x / GRIDWIDTH - 0.5 - offset
        ny = canvas_y / GRIDHEIGHT - 0.5 - offset
        return nx, ny

    @staticmethod
    def denormalise_point(nx: float, ny: float) -> tuple[float, float]:
        """
        XML value + pre-added offset → canvas pixel.
        Formula: canvas = val * GRIDWIDTH + GRIDWIDTH/2
        (offset is added back before calling this, matching Java load path)
        """
        cx = nx * GRIDWIDTH + GRIDWIDTH / 2
        cy = ny * GRIDHEIGHT + GRIDHEIGHT / 2
        return cx, cy

    @staticmethod
    def simplify(val: float) -> float:
        """Round to 2 decimal places using Math.round semantics."""
        return round(round(val * 100)) / 100.0

    # ── center / transform ───────────────────────────────────────────────────

    def center_all(self, screen_centre: QPointF) -> None:
        """Translate all committed shapes so their collective centroid = screen_centre."""
        managers = self.committed_managers()
        if not managers:
            return
        centroids = [m.get_average_xy() for m in managers]
        mean_x = sum(c.x() for c in centroids) / len(centroids)
        mean_y = sum(c.y() for c in centroids) / len(centroids)
        dx = screen_centre.x() - mean_x
        dy = screen_centre.y() - mean_y

        moved: set[int] = set()
        for mgr in managers:
            for cv in mgr.curves:
                for pt in cv.points:
                    if pt is not None and id(pt) not in moved:
                        moved.add(id(pt))
                        pt.pos = QPointF(pt.pos.x() + dx, pt.pos.y() + dy)
                        pt.set_orig_to_pos()

    # ── paste / clipboard helpers ─────────────────────────────────────────────

    def add_closed_from_points(self, pts: list[QPointF],
                               layer_id: int) -> CubicCurveManager:
        """Create a closed manager from a flat list of QPointF (A1,C1,C2,A2 …)."""
        mgr = CubicCurveManager()
        mgr.layer_id = layer_id
        mgr.set_all_points(pts)
        mgr.is_closed = True
        self._managers.insert(len(self._managers) - 1, mgr)
        return mgr

    def add_open_from_points(self, pts: list[QPointF],
                             layer_id: int) -> CubicCurveManager:
        """Create an open manager from a flat list of QPointF (A1,C1,C2,A2 …)."""
        mgr = CubicCurveManager()
        mgr.layer_id = layer_id
        mgr.set_open_points(pts)
        mgr.is_closed = False
        self._managers.insert(len(self._managers) - 1, mgr)
        return mgr

    def replace_point(self, old_pt: CubicPoint, new_pt: CubicPoint) -> None:
        """Replace every occurrence of old_pt with new_pt across all managers.
        Mirrors Java CubicCurvePolygonManager.replacePoints(): shared object
        reference means dragging one curve automatically drags the welded partner.
        """
        for mgr in self._managers:
            for cv in mgr.curves:
                for i, pt in enumerate(cv.points):
                    if pt is old_pt:
                        cv.points[i] = new_pt

    # ── snapshot for undo ────────────────────────────────────────────────────

    def snapshot(self) -> list[CubicCurveManager]:
        """Deep-copy all committed managers for undo."""
        return copy.deepcopy(self.committed_managers())

    def restore_snapshot(self, snap: list[CubicCurveManager]) -> None:
        """Replace committed managers with snapshot; keep last active manager."""
        active = self._managers[-1]
        self._managers = list(snap) + [CubicCurveManager()]
        # Keep the active drawing manager state if it has no committed curves
        if active.curve_count == 0:
            self._managers[-1] = active
