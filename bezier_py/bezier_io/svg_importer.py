"""
SVG importer — parses SVG <path> elements into CubicCurveManagers.
Port of BezierSvgImporter.java.

Public API:
    import_svg(svg_file_path, polygon_manager, layer_id)

Supported path commands: M/m, C/c, L/l, Q/q, Z/z.
Unsupported (H, V, S, T, A) are silently skipped.
Each <path> becomes one closed polygon added to polygon_manager.
"""
from __future__ import annotations
import re
from xml.etree import ElementTree as ET
from PySide6.QtCore import QPointF

EDGE_OFFSET = 20
GRID_SIZE   = 1000  # GRIDWIDTH


# ── Number extraction ─────────────────────────────────────────────────────────

_NUM_RE = re.compile(r'-?[0-9]*\.?[0-9]+(?:[eE][+-]?[0-9]+)?')


def _extract_numbers(s: str) -> list[float]:
    return [float(m) for m in _NUM_RE.findall(s)]


# ── Geometry helpers ──────────────────────────────────────────────────────────

def _line_to_cubic(x0, y0, x1, y1) -> list[float]:
    """Line segment → cubic Bézier (control points at 1/3, 2/3)."""
    return [
        x0, y0,
        x0 + (x1 - x0) / 3.0, y0 + (y1 - y0) / 3.0,
        x0 + 2.0 * (x1 - x0) / 3.0, y0 + 2.0 * (y1 - y0) / 3.0,
        x1, y1,
    ]


def _quad_to_cubic(x0, y0, qx, qy, x1, y1) -> list[float]:
    """Quadratic → cubic Bézier via degree elevation (exact)."""
    return [
        x0, y0,
        x0 + 2.0 / 3.0 * (qx - x0), y0 + 2.0 / 3.0 * (qy - y0),
        x1 + 2.0 / 3.0 * (qx - x1), y1 + 2.0 / 3.0 * (qy - y1),
        x1, y1,
    ]


# ── SVG path parser ───────────────────────────────────────────────────────────

_TOK_RE = re.compile(
    r'([MmCcLlQqZzHhVvSsTtAa])([^MmCcLlQqZzHhVvSsTtAa]*)'
)


def _parse_path(d: str) -> list[list[float]]:
    """
    Parse a path d attribute into a list of cubic Bézier curve descriptors.
    Each entry: [a0x, a0y, c1x, c1y, c2x, c2y, a1x, a1y]
    """
    curves: list[list[float]] = []
    cx = cy = 0.0
    start_x = start_y = 0.0

    for m in _TOK_RE.finditer(d):
        cmd = m.group(1)
        n = _extract_numbers(m.group(2))
        ni = 0

        if cmd == 'M':
            if len(n) >= 2:
                cx, cy = n[0], n[1]; ni = 2
                start_x, start_y = cx, cy
            while ni + 1 < len(n):
                ex, ey = n[ni], n[ni + 1]; ni += 2
                curves.append(_line_to_cubic(cx, cy, ex, ey))
                cx, cy = ex, ey

        elif cmd == 'm':
            if len(n) >= 2:
                cx += n[0]; cy += n[1]; ni = 2
                start_x, start_y = cx, cy
            while ni + 1 < len(n):
                ex, ey = cx + n[ni], cy + n[ni + 1]; ni += 2
                curves.append(_line_to_cubic(cx, cy, ex, ey))
                cx, cy = ex, ey

        elif cmd == 'C':
            while ni + 5 < len(n):
                c1x, c1y = n[ni], n[ni + 1]
                c2x, c2y = n[ni + 2], n[ni + 3]
                ex, ey   = n[ni + 4], n[ni + 5]; ni += 6
                curves.append([cx, cy, c1x, c1y, c2x, c2y, ex, ey])
                cx, cy = ex, ey

        elif cmd == 'c':
            while ni + 5 < len(n):
                c1x, c1y = cx + n[ni],     cy + n[ni + 1]
                c2x, c2y = cx + n[ni + 2], cy + n[ni + 3]
                ex, ey   = cx + n[ni + 4], cy + n[ni + 5]; ni += 6
                curves.append([cx, cy, c1x, c1y, c2x, c2y, ex, ey])
                cx, cy = ex, ey

        elif cmd == 'L':
            while ni + 1 < len(n):
                ex, ey = n[ni], n[ni + 1]; ni += 2
                curves.append(_line_to_cubic(cx, cy, ex, ey))
                cx, cy = ex, ey

        elif cmd == 'l':
            while ni + 1 < len(n):
                ex, ey = cx + n[ni], cy + n[ni + 1]; ni += 2
                curves.append(_line_to_cubic(cx, cy, ex, ey))
                cx, cy = ex, ey

        elif cmd == 'Q':
            while ni + 3 < len(n):
                qx, qy = n[ni], n[ni + 1]
                ex, ey = n[ni + 2], n[ni + 3]; ni += 4
                curves.append(_quad_to_cubic(cx, cy, qx, qy, ex, ey))
                cx, cy = ex, ey

        elif cmd == 'q':
            while ni + 3 < len(n):
                qx, qy = cx + n[ni],     cy + n[ni + 1]
                ex, ey = cx + n[ni + 2], cy + n[ni + 3]; ni += 4
                curves.append(_quad_to_cubic(cx, cy, qx, qy, ex, ey))
                cx, cy = ex, ey

        elif cmd in ('Z', 'z'):
            # Add closing segment only if current point differs from subpath start
            if abs(cx - start_x) > 0.001 or abs(cy - start_y) > 0.001:
                curves.append(_line_to_cubic(cx, cy, start_x, start_y))
            cx, cy = start_x, start_y

        # H, V, S, T, A: silently skipped

    # Remove redundant closing segment (set_all_points auto-wraps last→first anchor)
    if curves:
        last, first = curves[-1], curves[0]
        if abs(last[6] - first[0]) < 0.01 and abs(last[7] - first[1]) < 0.01:
            curves.pop()

    return curves


# ── Coordinate transform ──────────────────────────────────────────────────────

def _to_screen(svg_x: float, svg_y: float,
               vb_x: float, vb_y: float,
               vb_w: float, vb_h: float) -> QPointF:
    bx = (svg_x - vb_x) / vb_w * GRID_SIZE + EDGE_OFFSET
    by = (svg_y - vb_y) / vb_h * GRID_SIZE + EDGE_OFFSET
    return QPointF(bx, by)


# ── Public entry point ────────────────────────────────────────────────────────

def import_svg(svg_file_path: str, polygon_manager, layer_id: int = 0) -> int:
    """
    Parse an SVG file and add each recognised <path> as a closed polygon to
    polygon_manager. Existing geometry is preserved (import adds to it).

    Returns the number of polygons imported.
    """
    try:
        tree = ET.parse(svg_file_path)
    except Exception as e:
        print(f'svg_importer: failed to parse {svg_file_path} — {e}')
        return 0

    root = tree.getroot()

    # Strip namespace prefix for attribute lookup
    vb_str = root.get('viewBox') or root.get('viewbox') or ''
    vb_nums = _extract_numbers(vb_str)
    if len(vb_nums) >= 4:
        vb_x, vb_y, vb_w, vb_h = vb_nums[:4]
    else:
        vb_x, vb_y = 0.0, 0.0
        vb_w = float(root.get('width') or GRID_SIZE)
        vb_h = float(root.get('height') or GRID_SIZE)
    if vb_w == 0: vb_w = GRID_SIZE
    if vb_h == 0: vb_h = GRID_SIZE

    imported = 0

    def walk(el: ET.Element) -> None:
        nonlocal imported
        # Strip namespace braces from tag for comparison
        tag = el.tag.split('}')[-1] if '}' in el.tag else el.tag
        if tag == 'path':
            d = el.get('d') or ''
            if d.strip():
                curves = _parse_path(d)
                if curves:
                    pts_flat: list[QPointF] = []
                    for seg in curves:
                        for k in range(0, 8, 2):
                            pts_flat.append(
                                _to_screen(seg[k], seg[k + 1],
                                           vb_x, vb_y, vb_w, vb_h)
                            )
                    polygon_manager.add_closed_from_points(pts_flat, layer_id)
                    imported += 1
        for child in el:
            walk(child)

    walk(root)
    return imported
