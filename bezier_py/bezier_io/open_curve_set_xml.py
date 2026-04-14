"""
OpenCurveSet XML IO — read/write openCurveSet XML files (no DOCTYPE).
"""
from __future__ import annotations
import os
from xml.etree import ElementTree as ET
from PySide6.QtCore import QPointF

from model.polygon_manager import PolygonManager

GRIDWIDTH  = 1000
GRIDHEIGHT = 1000
EDGE_OFFSET = 20
XML_DECL = '<?xml version="1.0" encoding="ISO-8859-1"?>'


def _to_xml_coord(canvas_val: float, grid: int) -> float:
    norm = canvas_val / grid - 0.5
    adj  = norm - EDGE_OFFSET / grid
    return round(round(adj * 100)) / 100.0

def _denormalise(val: float, grid: int) -> float:
    return val * grid + grid / 2


def write_open_curve_set(file_path: str, name: str, polygon_manager: PolygonManager) -> None:
    """Write an openCurveSet XML (no DOCTYPE)."""
    lines: list[str] = [
        XML_DECL,
        '<openCurveSet>',
        f'    <name>{name}</name>',
        '    <shapeType>CUBIC_CURVE</shapeType>',
    ]

    for mgr in polygon_manager.committed_managers():
        if mgr.is_closed:
            continue  # skip closed polygons

        lines.append('    <openCurve>')
        for cv in mgr.curves:
            pts = cv.points
            if not all(p is not None for p in pts):
                continue
            lines.append('        <curve>')
            for i, pt in enumerate(pts):
                xv = _to_xml_coord(pt.pos.x(), GRIDWIDTH)
                yv = _to_xml_coord(pt.pos.y(), GRIDHEIGHT)
                pressure_attr = ''
                if mgr.anchor_pressures is not None and (i == 0 or i == 3):
                    ci = mgr.curves.index(cv)
                    k = ci if i == 0 else ci + 1
                    p_val = mgr.get_anchor_pressure(k)
                    pressure_attr = f' pressure="{p_val:.3f}"'
                lines.append(f'            <point x="{xv}" y="{yv}"{pressure_attr}/>')
            lines.append('        </curve>')
        lines.append('    </openCurve>')

    lines.append('</openCurveSet>')
    os.makedirs(os.path.dirname(os.path.abspath(file_path)), exist_ok=True)
    with open(file_path, 'w', encoding='ISO-8859-1') as f:
        f.write('\n'.join(lines) + '\n')


def read_open_curve_set(file_path: str) -> list[dict]:
    """Parse an openCurveSet XML.  Returns same format as read_polygon_set."""
    from bezier_io.polygon_set_xml import read_polygon_set
    return read_polygon_set(file_path)  # same parser handles both root elements
