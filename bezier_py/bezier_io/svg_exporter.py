"""
SVG exporter for Bezier polygon geometry.
Port of BezierSvgExporter.java.

Public API:
    save(polygon_manager, svg_dir_path, name)
    save_managers(managers, svg_dir_path, name)

Coordinate system:
    SVG user units = canvas pixel − EDGE_OFFSET
    SVG canvas: 1000×1000 user units (matches GRIDWIDTH)
"""
from __future__ import annotations
import os

EDGE_OFFSET = 20
VIEW_SIZE   = 1000  # matches GRIDWIDTH


def _to_svg(canvas_coord: float) -> float:
    """Canvas pixel → SVG user unit."""
    return canvas_coord - EDGE_OFFSET


def _escape_xml(s: str) -> str:
    return (s.replace('&', '&amp;')
             .replace('<', '&lt;')
             .replace('>', '&gt;')
             .replace('"', '&quot;'))


def _build_svg(managers, name: str) -> str:
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg"'
        f' width="{VIEW_SIZE}" height="{VIEW_SIZE}"'
        f' viewBox="0 0 {VIEW_SIZE} {VIEW_SIZE}">',
        f'  <title>{_escape_xml(name)}</title>',
    ]

    for m in managers:
        cvs = m.curves
        if not cvs:
            continue
        first_pt = cvs[0].points[0]
        if first_pt is None:
            continue

        d_parts = [
            f'M {_to_svg(first_pt.pos.x()):.4f},{_to_svg(first_pt.pos.y()):.4f}'
        ]
        for cv in cvs:
            pts = cv.points
            if any(p is None for p in (pts[1], pts[2], pts[3])):
                continue
            d_parts.append(
                f'C {_to_svg(pts[1].pos.x()):.4f},{_to_svg(pts[1].pos.y()):.4f}'
                f' {_to_svg(pts[2].pos.x()):.4f},{_to_svg(pts[2].pos.y()):.4f}'
                f' {_to_svg(pts[3].pos.x()):.4f},{_to_svg(pts[3].pos.y()):.4f}'
            )

        if m.is_closed:
            d_parts.append('Z')

        d_attr = ' '.join(d_parts)
        lines.append(
            f'  <path d="{d_attr}"'
            f' fill="none" stroke="#000000" stroke-width="1"/>'
        )

    lines.append('</svg>')
    return '\n'.join(lines) + '\n'


def save(polygon_manager, svg_dir_path: str, name: str) -> None:
    """Save an SVG for all committed managers in polygon_manager."""
    managers = polygon_manager.committed_managers()
    _write_svg(managers, svg_dir_path, name)


def save_managers(managers: list, svg_dir_path: str, name: str) -> None:
    """Save an SVG for a specific list of CubicCurveManagers (per-layer export)."""
    _write_svg(managers, svg_dir_path, name)


def _write_svg(managers, svg_dir_path: str, name: str) -> None:
    os.makedirs(svg_dir_path, exist_ok=True)
    svg_path = os.path.join(svg_dir_path, f'{name}.svg')
    content = _build_svg(managers, name)
    with open(svg_path, 'w', encoding='utf-8') as f:
        f.write(content)
