"""
CurveFitter — Schneider algorithm for fitting freehand strokes to cubic Bézier segments.

Port of CurveFitter.java.

Public API:
    fit(pts: list[QPointF], error_threshold: float) -> list[QPointF] | None

Returns a flat list [a0,c1,c2,a1, a1,c1',c2',a1', ...] — N*4 points per segment.
Adjacent segments share the same end/start anchor value.
"""
from __future__ import annotations
import math
from PySide6.QtCore import QPointF


# ── Internal 2D vector helpers (simple tuples for speed) ─────────────────────

def _dist(a: tuple, b: tuple) -> float:
    dx, dy = b[0] - a[0], b[1] - a[1]
    return math.sqrt(dx * dx + dy * dy)


def _sub(a: tuple, b: tuple) -> tuple:
    return (a[0] - b[0], a[1] - b[1])


def _normalize(v: tuple) -> tuple:
    length = math.sqrt(v[0] * v[0] + v[1] * v[1])
    if length < 1e-10:
        return (1.0, 0.0)
    return (v[0] / length, v[1] / length)


# ── Bernstein basis polynomials ───────────────────────────────────────────────

def _b0(t: float) -> float:
    mt = 1.0 - t; return mt * mt * mt

def _b1(t: float) -> float:
    mt = 1.0 - t; return 3.0 * mt * mt * t

def _b2(t: float) -> float:
    mt = 1.0 - t; return 3.0 * mt * t * t

def _b3(t: float) -> float:
    return t * t * t


def _bezier_point(b: list[tuple], t: float) -> tuple:
    b0, b1, b2, b3 = _b0(t), _b1(t), _b2(t), _b3(t)
    return (
        b0 * b[0][0] + b1 * b[1][0] + b2 * b[2][0] + b3 * b[3][0],
        b0 * b[0][1] + b1 * b[1][1] + b2 * b[2][1] + b3 * b[3][1],
    )


def _bezier_tangent(b: list[tuple], t: float) -> tuple:
    mt = 1.0 - t
    k0, k1, k2 = 3.0 * mt * mt, 6.0 * mt * t, 3.0 * t * t
    return (
        k0 * (b[1][0] - b[0][0]) + k1 * (b[2][0] - b[1][0]) + k2 * (b[3][0] - b[2][0]),
        k0 * (b[1][1] - b[0][1]) + k1 * (b[2][1] - b[1][1]) + k2 * (b[3][1] - b[2][1]),
    )


def _bezier_second_deriv(b: list[tuple], t: float) -> tuple:
    mt = 1.0 - t
    k0, k1 = 6.0 * mt, 6.0 * t
    return (
        k0 * (b[2][0] - 2.0 * b[1][0] + b[0][0]) + k1 * (b[3][0] - 2.0 * b[2][0] + b[1][0]),
        k0 * (b[2][1] - 2.0 * b[1][1] + b[0][1]) + k1 * (b[3][1] - 2.0 * b[2][1] + b[1][1]),
    )


# ── Douglas-Peucker polyline simplification ───────────────────────────────────

def _point_to_line_dist(p: tuple, a: tuple, b: tuple) -> float:
    dx, dy = b[0] - a[0], b[1] - a[1]
    len2 = dx * dx + dy * dy
    if len2 < 1e-12:
        return _dist(p, a)
    t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2
    cx, cy = a[0] + t * dx, a[1] + t * dy
    ex, ey = p[0] - cx, p[1] - cy
    return math.sqrt(ex * ex + ey * ey)


def _douglas_peucker(pts: list[tuple], epsilon: float) -> list[tuple]:
    if len(pts) <= 2:
        return list(pts)
    start, end = pts[0], pts[-1]
    max_dist, max_idx = 0.0, 1
    for i in range(1, len(pts) - 1):
        d = _point_to_line_dist(pts[i], start, end)
        if d > max_dist:
            max_dist, max_idx = d, i
    if max_dist > epsilon:
        left  = _douglas_peucker(pts[:max_idx + 1], epsilon)
        right = _douglas_peucker(pts[max_idx:], epsilon)
        return left + right[1:]
    else:
        return [start, end]


def _remove_duplicates(pts: list[tuple]) -> list[tuple]:
    result: list[tuple] = []
    for p in pts:
        if not result or _dist(result[-1], p) > 0.01:
            result.append(p)
    return result


# ── Chord-length parameterisation ─────────────────────────────────────────────

def _chord_length_param(d: list[tuple], first: int, last: int) -> list[float]:
    count = last - first + 1
    u = [0.0] * count
    for i in range(1, count):
        u[i] = u[i - 1] + _dist(d[first + i - 1], d[first + i])
    total = u[-1]
    if total > 0:
        u = [x / total for x in u]
    u[-1] = 1.0
    return u


# ── Least-squares Bézier generation ──────────────────────────────────────────

def _generate_bezier(d: list[tuple], first: int, last: int,
                     u: list[float], t_hat1: tuple, t_hat2: tuple) -> list[tuple]:
    p0, p3 = d[first], d[last]
    count = last - first + 1

    a1x = [0.0] * count
    a1y = [0.0] * count
    a2x = [0.0] * count
    a2y = [0.0] * count

    for i in range(count):
        t = u[i]
        b1, b2 = _b1(t), _b2(t)
        a1x[i] = b1 * t_hat1[0]; a1y[i] = b1 * t_hat1[1]
        a2x[i] = b2 * t_hat2[0]; a2y[i] = b2 * t_hat2[1]

    c00 = c01 = c11 = 0.0
    x0 = x1 = 0.0

    for i in range(count):
        t = u[i]
        b0, b3 = _b0(t), _b3(t)
        c00 += a1x[i] * a1x[i] + a1y[i] * a1y[i]
        c01 += a1x[i] * a2x[i] + a1y[i] * a2y[i]
        c11 += a2x[i] * a2x[i] + a2y[i] * a2y[i]
        pt = d[first + i]
        tx = pt[0] - (b0 * p0[0] + b3 * p3[0])
        ty = pt[1] - (b0 * p0[1] + b3 * p3[1])
        x0 += a1x[i] * tx + a1y[i] * ty
        x1 += a2x[i] * tx + a2y[i] * ty

    c10 = c01
    det = c00 * c11 - c01 * c10

    if abs(det) > 1e-12:
        alpha1 = (x0 * c11 - c01 * x1) / det
        alpha2 = (c00 * x1 - x0 * c10) / det
    else:
        dist = _dist(p0, p3) / 3.0
        alpha1 = alpha2 = dist

    if alpha1 < 1e-6 or alpha2 < 1e-6:
        dist = _dist(p0, p3) / 3.0
        alpha1 = alpha2 = dist

    c1 = (p0[0] + alpha1 * t_hat1[0], p0[1] + alpha1 * t_hat1[1])
    c2 = (p3[0] + alpha2 * t_hat2[0], p3[1] + alpha2 * t_hat2[1])
    return [p0, c1, c2, p3]


# ── Max error ─────────────────────────────────────────────────────────────────

def _max_error(d: list[tuple], first: int, last: int,
               bezier: list[tuple], u: list[float]) -> tuple[float, int]:
    max_dist = 0.0
    split_idx = (first + last) // 2
    for i in range(first + 1, last):
        pt = _bezier_point(bezier, u[i - first])
        dx, dy = pt[0] - d[i][0], pt[1] - d[i][1]
        dist = dx * dx + dy * dy
        if dist > max_dist:
            max_dist = dist
            split_idx = i
    return max_dist, split_idx


# ── Newton-Raphson reparameterisation ─────────────────────────────────────────

def _newton_raphson_step(bezier: list[tuple], p: tuple, u: float) -> float:
    q  = _bezier_point(bezier, u)
    q1 = _bezier_tangent(bezier, u)
    q2 = _bezier_second_deriv(bezier, u)
    numer = (q[0] - p[0]) * q1[0] + (q[1] - p[1]) * q1[1]
    denom = (q1[0] * q1[0] + q1[1] * q1[1]
             + (q[0] - p[0]) * q2[0] + (q[1] - p[1]) * q2[1])
    if abs(denom) < 1e-12:
        return u
    u_new = u - numer / denom
    return max(0.0, min(1.0, u_new))


def _reparameterize(d: list[tuple], first: int, last: int,
                    u: list[float], bezier: list[tuple]) -> list[float]:
    count = last - first + 1
    return [_newton_raphson_step(bezier, d[first + i], u[i]) for i in range(count)]


# ── Loop detection ─────────────────────────────────────────────────────────────

def _would_loop(bezier: list[tuple]) -> bool:
    arm1  = _dist(bezier[0], bezier[1])
    arm2  = _dist(bezier[3], bezier[2])
    chord = _dist(bezier[0], bezier[3])
    return chord > 1.0 and (arm1 + arm2) > chord


# ── Tangent helpers ───────────────────────────────────────────────────────────

def _left_tangent(d: list[tuple], end: int) -> tuple:
    return _normalize(_sub(d[end + 1], d[end]))


def _right_tangent(d: list[tuple], end: int) -> tuple:
    return _normalize(_sub(d[end - 1], d[end]))


def _center_tangent(d: list[tuple], center: int) -> tuple:
    return _normalize(_sub(d[center - 1], d[center + 1]))


# ── Core recursive fitter ─────────────────────────────────────────────────────

def _fit_cubic(d: list[tuple], first: int, last: int,
               t_hat1: tuple, t_hat2: tuple,
               err2: float, result: list) -> None:
    if last - first == 1:
        p0, p1 = d[first], d[last]
        dist = _dist(p0, p1) / 3.0
        c1 = (p0[0] + t_hat1[0] * dist, p0[1] + t_hat1[1] * dist)
        c2 = (p1[0] + t_hat2[0] * dist, p1[1] + t_hat2[1] * dist)
        result.append([p0, c1, c2, p1])
        return

    u = _chord_length_param(d, first, last)
    bezier = _generate_bezier(d, first, last, u, t_hat1, t_hat2)

    max_dist, split_idx = _max_error(d, first, last, bezier, u)

    if max_dist < err2 and not _would_loop(bezier):
        result.append(bezier)
        return

    if not _would_loop(bezier) and max_dist < err2 * 4.0:
        u_prime = _reparameterize(d, first, last, u, bezier)
        bezier2 = _generate_bezier(d, first, last, u_prime, t_hat1, t_hat2)
        max_dist2, split_idx2 = _max_error(d, first, last, bezier2, u_prime)
        if max_dist2 < err2 and not _would_loop(bezier2):
            result.append(bezier2)
            return
        split_idx = split_idx2

    t_center = _center_tangent(d, split_idx)
    t_center_neg = (-t_center[0], -t_center[1])
    _fit_cubic(d, first, split_idx, t_hat1,       t_center,     err2, result)
    _fit_cubic(d, split_idx, last,  t_center_neg, t_hat2,       err2, result)


# ── Public API ────────────────────────────────────────────────────────────────

def fit(pts: list[QPointF], error_threshold: float) -> list[QPointF] | None:
    """
    Fit a freehand stroke to cubic Bézier segments.

    Parameters
    ----------
    pts             : raw sample points from mouse drag
    error_threshold : max pixel error per sample (1–50 typical; higher = fewer segments)

    Returns
    -------
    Flat list of QPointF in groups of 4 (a0, c1, c2, a1) per segment, or None if
    the input is too short.
    """
    d = _remove_duplicates([(p.x(), p.y()) for p in pts])
    if len(d) < 2:
        return None

    d = _douglas_peucker(d, max(error_threshold, 2.0))
    if len(d) < 2:
        return None

    err2 = error_threshold * error_threshold
    segments: list = []

    if len(d) == 2:
        p0, p1 = d[0], d[1]
        c1 = (p0[0] + (p1[0] - p0[0]) / 3.0, p0[1] + (p1[1] - p0[1]) / 3.0)
        c2 = (p0[0] + 2.0 * (p1[0] - p0[0]) / 3.0, p0[1] + 2.0 * (p1[1] - p0[1]) / 3.0)
        segments.append([p0, c1, c2, p1])
    else:
        t_hat1 = _left_tangent(d, 0)
        t_hat2 = _right_tangent(d, len(d) - 1)
        _fit_cubic(d, 0, len(d) - 1, t_hat1, t_hat2, err2, segments)

    result: list[QPointF] = []
    for seg in segments:
        for pt in seg:
            result.append(QPointF(pt[0], pt[1]))
    return result
