"""
BezierIntersectTool — port of Java BezierIntersectTool.
Creates N quad polygons spanning the annular region between two concentric polygons
with matching anchor counts.
"""
from __future__ import annotations
import math
from PySide6.QtCore import QPointF
from PySide6.QtGui import QPainterPath

# Points within this distance (px) are considered coincident and get welded
WELD_EPSILON = 0.5


# ── geometry helpers ──────────────────────────────────────────────────────────

def _build_closed_path(mgr) -> QPainterPath:
    path = QPainterPath()
    if not mgr.curves:
        return path
    first = mgr.curves[0].points[0]
    if first is None:
        return path
    path.moveTo(first.pos)
    for cv in mgr.curves:
        pts = cv.points
        if all(p is not None for p in pts):
            path.cubicTo(pts[1].pos, pts[2].pos, pts[3].pos)
    path.closeSubpath()
    return path


def _all_anchors_inside(inner, outer_path: QPainterPath) -> bool:
    """Return True if every anchor of inner lies inside outer_path."""
    for cv in inner.curves:
        pt = cv.points[0]
        if pt is None or not outer_path.contains(pt.pos):
            return False
    return True


def _polygon_angle(mgr) -> float:
    """Direction of the first edge (degrees), used for rotation-compatibility check."""
    if not mgr.curves:
        return 0.0
    p0 = mgr.curves[0].points[0]
    p3 = mgr.curves[0].points[3]
    if p0 is None or p3 is None:
        return 0.0
    return math.degrees(math.atan2(p3.pos.y() - p0.pos.y(), p3.pos.x() - p0.pos.x()))


def _rotation_compatible(a, b) -> bool:
    """True if the two polygons' first-edge directions differ by < 5°."""
    diff = abs(_polygon_angle(a) - _polygon_angle(b)) % 360
    if diff > 180:
        diff = 360 - diff
    return diff < 5.0


def _lerp(a: QPointF, b: QPointF, t: float) -> QPointF:
    return QPointF(a.x() + (b.x() - a.x()) * t, a.y() + (b.y() - a.y()) * t)


def _straight_edge(a: QPointF, b: QPointF) -> list[QPointF]:
    """4 points (A, C1, C2, B) representing a straight cubic segment A→B."""
    return [QPointF(a), _lerp(a, b, 1/3), _lerp(a, b, 2/3), QPointF(b)]


# ── main entry point ──────────────────────────────────────────────────────────

def perform_intersect(polygon_manager, a, b,
                      active_layer_id: int,
                      selected_polygons: list) -> bool:
    """
    Port of Java BezierIntersectTool.performIntersect().

    Validation rules (mirrors Java):
      - Both polygons must have the same curve count, minimum 3
      - Rotation difference < 5°
      - One polygon must be fully inside the other

    On success:
      - Both originals are removed
      - N quad polygons (annular segments) are inserted and selected
      - Coincident boundary points are welded

    Returns True on success, False if validation fails (no changes made).
    """
    N = len(a.curves)
    if N != len(b.curves) or N < 3:
        return False

    if not _rotation_compatible(a, b):
        return False

    path_a = _build_closed_path(a)
    path_b = _build_closed_path(b)

    if _all_anchors_inside(b, path_a):
        outer, inner = a, b
    elif _all_anchors_inside(a, path_b):
        outer, inner = b, a
    else:
        return False

    # ── Build N quad polygons ─────────────────────────────────────────────────
    # Each quad i spans the annular region between outer curve[i] and inner curve[i]:
    #   Curve 0: outer edge i (forward bezier from outer polygon)
    #   Curve 1: right spoke (straight: outer anchor[i+1] → inner anchor[i+1])
    #   Curve 2: inner edge i (reversed bezier from inner polygon)
    #   Curve 3: left spoke  (straight: inner anchor[i] → outer anchor[i])
    quads: list[list[QPointF]] = []
    for i in range(N):
        op = outer.curves[i].points   # [oAi, oC1, oC2, oAi+1]
        ip = inner.curves[i].points   # [iAi, iC1, iC2, iAi+1]
        if any(p is None for p in op) or any(p is None for p in ip):
            return False

        oAi  = QPointF(op[0].pos); oC1  = QPointF(op[1].pos)
        oC2  = QPointF(op[2].pos); oAi1 = QPointF(op[3].pos)
        iAi  = QPointF(ip[0].pos); iC1  = QPointF(ip[1].pos)
        iC2  = QPointF(ip[2].pos); iAi1 = QPointF(ip[3].pos)

        pts: list[QPointF] = [
            # Curve 0: outer edge forward
            oAi, oC1, oC2, oAi1,
            # Curve 1: right spoke (straight oAi+1 → iAi+1)
            *_straight_edge(oAi1, iAi1),
            # Curve 2: inner edge reversed (iAi+1 → iAi)
            iAi1, iC2, iC1, iAi,
            # Curve 3: left spoke (straight iAi → oAi)
            *_straight_edge(iAi, oAi),
        ]
        quads.append(pts)

    # ── Remove originals (descending index to avoid shift) ────────────────────
    count = polygon_manager.polygon_count
    outer_idx = inner_idx = -1
    for k in range(count):
        if polygon_manager.get_manager(k) is outer:
            outer_idx = k
        if polygon_manager.get_manager(k) is inner:
            inner_idx = k
    if outer_idx < 0 or inner_idx < 0:
        return False

    hi, lo = max(outer_idx, inner_idx), min(outer_idx, inner_idx)
    polygon_manager.remove_manager_at(hi)
    polygon_manager.remove_manager_at(lo)

    # ── Add quad managers ─────────────────────────────────────────────────────
    for mgr in list(selected_polygons):
        mgr.clear_all_highlights()
    selected_polygons.clear()

    for pts in quads:
        nm = polygon_manager.add_closed_from_points(pts, active_layer_id)
        nm.selected = True
        selected_polygons.append(nm)

    # ── Weld all coincident boundary points ───────────────────────────────────
    _weld_coincident_points(polygon_manager, WELD_EPSILON)
    return True


def _weld_coincident_points(polygon_manager, epsilon: float) -> None:
    """Register weld links for all cross-manager point pairs within epsilon px."""
    wr = polygon_manager.weld_registry
    all_pts: list[tuple] = []   # (manager, CubicPoint)
    for mgr in polygon_manager.committed_managers():
        for cv in mgr.curves:
            for pt in cv.points:
                if pt is not None:
                    all_pts.append((mgr, pt))

    eps2 = epsilon * epsilon
    n = len(all_pts)
    for a_idx in range(n):
        mgr_a, pt_a = all_pts[a_idx]
        for b_idx in range(a_idx + 1, n):
            mgr_b, pt_b = all_pts[b_idx]
            if mgr_a is mgr_b or pt_a is pt_b:
                continue
            dx = pt_a.pos.x() - pt_b.pos.x()
            dy = pt_a.pos.y() - pt_b.pos.y()
            if dx * dx + dy * dy < eps2:
                wr.register_weld(pt_a, pt_b)
