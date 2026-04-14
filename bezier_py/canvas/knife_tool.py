"""
KnifeTool — cuts closed polygons along a line segment.
Port of BezierKnifeTool.java.

Public API:
    perform_cut(polygon_manager, line_a, line_b, pre_knife_selection, selected_polygons)
"""
from __future__ import annotations
import math
from PySide6.QtCore import QPointF

from model.cubic_curve import CubicCurve
from model.cubic_curve_manager import CubicCurveManager


# ── Geometry helpers ──────────────────────────────────────────────────────────

def _lerp(a: tuple, b: tuple, t: float) -> tuple:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def _line_coeffs(p1: tuple, p2: tuple) -> tuple[float, float, float]:
    """Return (a, b, c) for line equation ax + by + c = 0."""
    a = -(p2[1] - p1[1])
    b = p2[0] - p1[0]
    c = -(a * p1[0] + b * p1[1])
    return a, b, c


def _signed_dist(p: tuple, a: float, b: float, c: float) -> float:
    return a * p[0] + b * p[1] + c


def _eval_bezier(cv: CubicCurve, t: float) -> tuple:
    pts = cv.points
    mt = 1.0 - t
    return (
        mt**3 * pts[0].pos.x() + 3*mt**2*t * pts[1].pos.x()
        + 3*mt*t**2 * pts[2].pos.x() + t**3 * pts[3].pos.x(),
        mt**3 * pts[0].pos.y() + 3*mt**2*t * pts[1].pos.y()
        + 3*mt*t**2 * pts[2].pos.y() + t**3 * pts[3].pos.y(),
    )


# ── Intersection data class ───────────────────────────────────────────────────

class _Intersection:
    def __init__(self, curve_index: int, t: float, pt: tuple) -> None:
        self.curve_index = curve_index
        self.t = t
        self.pt = pt
        self.global_t = curve_index + t


# ── De Casteljau subdivision for root finding ─────────────────────────────────

def _find_roots_rec(d: list[float], t_min: float, t_max: float,
                    ci: int, cv: CubicCurve, out: list) -> None:
    all_pos = all(x >= 0 for x in d)
    all_neg = all(x <= 0 for x in d)
    if all_pos or all_neg:
        return
    if t_max - t_min < 1e-6:
        tm = (t_min + t_max) / 2
        out.append(_Intersection(ci, tm, _eval_bezier(cv, tm)))
        return
    t_mid = (t_min + t_max) / 2
    d01  = (d[0] + d[1]) / 2; d12 = (d[1] + d[2]) / 2; d23 = (d[2] + d[3]) / 2
    d012 = (d01 + d12) / 2;   d123 = (d12 + d23) / 2;  d0123 = (d012 + d123) / 2
    _find_roots_rec([d[0], d01, d012, d0123], t_min, t_mid, ci, cv, out)
    _find_roots_rec([d0123, d123, d23, d[3]], t_mid, t_max, ci, cv, out)


def _deduplicate(raw: list) -> list:
    out = []
    for ix in raw:
        dup = any(abs(ix.global_t - jx.global_t) < 0.015 for jx in out)
        if not dup:
            out.append(ix)
    return out


# ── De Casteljau split ────────────────────────────────────────────────────────

def casteljau_split(p: list[tuple], t: float) -> tuple[list[tuple], list[tuple]]:
    """Split bezier control points at t. Returns (left[4], right[4])."""
    q0 = _lerp(p[0], p[1], t); q1 = _lerp(p[1], p[2], t); q2 = _lerp(p[2], p[3], t)
    r0 = _lerp(q0, q1, t);     r1 = _lerp(q1, q2, t)
    s  = _lerp(r0, r1, t)
    return [p[0], q0, r0, s], [s, r1, q2, p[3]]


def _get_curve_pts(cv: CubicCurve) -> list[tuple]:
    return [(pt.pos.x(), pt.pos.y()) for pt in cv.points]


def _extract_sub_curve(cv: CubicCurve, t0: float, t1: float) -> list[tuple]:
    right = casteljau_split(_get_curve_pts(cv), t0)[1]
    if t1 >= 1.0 - 1e-9:
        return right
    t1p = (t1 - t0) / (1.0 - t0)
    return casteljau_split(right, t1p)[0]


# ── Build piece points ────────────────────────────────────────────────────────

def _build_piece_points(mgr: CubicCurveManager,
                        i_a: _Intersection, i_b: _Intersection) -> list[tuple]:
    cvs  = mgr.curves
    n    = len(cvs)
    ia, ib = i_a.curve_index, i_b.curve_index
    ta, tb = i_a.t, i_b.t
    segs: list[list[tuple]] = []

    if ia == ib and ta < tb:
        segs.append(_extract_sub_curve(cvs[ia], ta, tb))
    elif ia <= ib:
        segs.append(casteljau_split(_get_curve_pts(cvs[ia]), ta)[1])
        for k in range(ia + 1, ib):
            segs.append(_get_curve_pts(cvs[k]))
        segs.append(casteljau_split(_get_curve_pts(cvs[ib]), tb)[0])
    else:
        segs.append(casteljau_split(_get_curve_pts(cvs[ia]), ta)[1])
        for k in range(ia + 1, n):
            segs.append(_get_curve_pts(cvs[k]))
        for k in range(0, ib):
            segs.append(_get_curve_pts(cvs[k]))
        segs.append(casteljau_split(_get_curve_pts(cvs[ib]), tb)[0])

    # Straight closing edge i_b → i_a
    pb, pa = i_b.pt, i_a.pt
    segs.append([
        pb,
        _lerp(pb, pa, 1.0 / 3.0),
        _lerp(pb, pa, 2.0 / 3.0),
        pa,
    ])

    pts: list[tuple] = []
    for seg in segs:
        pts.extend(seg)
    return pts


# ── Auto-weld after cut ───────────────────────────────────────────────────────

_WELD_EPSILON = 0.1  # pixels

def _weld_coincident_points(polygon_manager) -> None:
    """Weld coincident boundary points across different polygon managers."""
    wr = polygon_manager.weld_registry
    count = polygon_manager.polygon_count

    mgr_of = []
    all_pts = []

    for i in range(count):
        mgr = polygon_manager.get_manager(i)
        for cv in mgr.curves:
            for pt in cv.points:
                if pt is not None:
                    mgr_of.append(mgr)
                    all_pts.append(pt)

    eps2 = _WELD_EPSILON * _WELD_EPSILON
    n = len(all_pts)
    for a in range(n):
        for b in range(a + 1, n):
            if mgr_of[a] is mgr_of[b]:
                continue
            if all_pts[a] is all_pts[b]:
                continue
            pa, pb = all_pts[a].pos, all_pts[b].pos
            dx, dy = pa.x() - pb.x(), pa.y() - pb.y()
            if dx * dx + dy * dy < eps2:
                wr.register_weld(all_pts[a], all_pts[b])


# ── Public API ────────────────────────────────────────────────────────────────

def perform_cut(polygon_manager,
                line_a: QPointF, line_b: QPointF,
                pre_knife_selection: set,
                selected_polygons: list) -> None:
    """
    Cut all closed polygons intersected by the line segment line_a→line_b.

    Parameters
    ----------
    polygon_manager    : PolygonManager instance
    line_a, line_b     : endpoints of the cut line (canvas pixel coords)
    pre_knife_selection: set of CubicCurveManagers selected before knife mode
    selected_polygons  : list cleared and repopulated with newly cut pieces
                         that came from previously-selected polygons
    """
    la = (line_a.x(), line_a.y())
    lb = (line_b.x(), line_b.y())
    a, b, c = _line_coeffs(la, lb)
    count = polygon_manager.polygon_count

    to_remove: list[int] = []
    all_pieces: list[list[list[tuple]]] = []
    was_selected: list[bool] = []

    for i in range(count):
        mgr = polygon_manager.get_manager(i)
        if not mgr.is_closed:
            continue
        cvs = mgr.curves
        raw: list[_Intersection] = []

        for ci, cv in enumerate(cvs):
            pts = cv.points
            d = [
                _signed_dist((pts[0].pos.x(), pts[0].pos.y()), a, b, c),
                _signed_dist((pts[1].pos.x(), pts[1].pos.y()), a, b, c),
                _signed_dist((pts[2].pos.x(), pts[2].pos.y()), a, b, c),
                _signed_dist((pts[3].pos.x(), pts[3].pos.y()), a, b, c),
            ]
            _find_roots_rec(d, 0.0, 1.0, ci, cv, raw)

        raw.sort(key=lambda x: x.global_t)
        hits = _deduplicate(raw)

        # Filter to intersections within the drawn segment
        seg_dx, seg_dy = lb[0] - la[0], lb[1] - la[1]
        seg_len2 = seg_dx * seg_dx + seg_dy * seg_dy
        if seg_len2 > 1e-10:
            in_seg = []
            for ix in hits:
                s = ((ix.pt[0] - la[0]) * seg_dx + (ix.pt[1] - la[1]) * seg_dy) / seg_len2
                if -0.02 <= s <= 1.02:
                    in_seg.append(ix)
            hits = in_seg

        if len(hits) < 2 or len(hits) % 2 != 0:
            continue

        sel = mgr in pre_knife_selection
        pieces = []
        ni = len(hits)
        for k in range(ni):
            pieces.append(_build_piece_points(mgr, hits[k], hits[(k + 1) % ni]))
        to_remove.append(i)
        all_pieces.append(pieces)
        was_selected.append(sel)

    if not to_remove:
        return

    # Remove in descending order to preserve lower indices
    for idx in sorted(to_remove, reverse=True):
        polygon_manager.remove_manager_at(idx)

    # Add new piece managers
    selected_polygons.clear()
    active_id = (polygon_manager._layer_manager.active_layer_id
                 if polygon_manager._layer_manager else 0)

    for g, pieces in enumerate(all_pieces):
        sel = was_selected[g]
        for pts_tuples in pieces:
            pts_qf = [QPointF(pt[0], pt[1]) for pt in pts_tuples]
            nm = polygon_manager.add_closed_from_points(pts_qf, active_id)
            if sel:
                selected_polygons.append(nm)

    _weld_coincident_points(polygon_manager)
