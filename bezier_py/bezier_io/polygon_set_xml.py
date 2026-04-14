"""
PolygonSet XML IO — read/write polygonSet XML files.
Byte-for-byte compatible with Java PolygonSetXml output.

Coordinate pipeline:
  Save: canvas_px → normalise → adjustForOffset → simplify(2dp) → XML
  Load: XML → add_offset → store → denormalise → canvas_px
"""
from __future__ import annotations
import os
from xml.etree import ElementTree as ET
from PySide6.QtCore import QPointF

from model.polygon_manager import PolygonManager

GRIDWIDTH  = 1000
GRIDHEIGHT = 1000
EDGE_OFFSET = 20

DOCTYPE = '<!DOCTYPE polygonSet SYSTEM "polygonSet.dtd">'
XML_DECL = '<?xml version="1.0" encoding="ISO-8859-1"?>'


# ── coordinate helpers ────────────────────────────────────────────────────────

def _normalise(canvas_val: float, grid: int) -> float:
    return canvas_val / grid - 0.5

def _adjust_offset(norm: float) -> float:
    return norm - EDGE_OFFSET / GRIDWIDTH   # 0.02

def _simplify(val: float) -> float:
    return round(round(val * 100)) / 100.0

def _to_xml_coord(canvas_val: float, grid: int) -> float:
    return _simplify(_adjust_offset(_normalise(canvas_val, grid)))

def _from_xml_coord(xml_val: float) -> float:
    """Return a normalised+offset value ready for denormalise."""
    return xml_val + EDGE_OFFSET / GRIDWIDTH   # add offset back

def _denormalise(val: float, grid: int) -> float:
    return val * grid + grid / 2


# ── write ─────────────────────────────────────────────────────────────────────

def write_polygon_set(file_path: str, name: str, polygon_manager: PolygonManager) -> None:
    """
    Write a polygonSet XML file with DOCTYPE header.
    name: the shape name (written inside <name> element).
    """
    _write_polygon_set_xml(file_path, name, polygon_manager.committed_managers())


def _write_polygon_set_xml(file_path: str, name: str, managers) -> None:
    """
    Internal: write a polygonSet XML from an explicit list of managers.
    Used by write_polygon_set and by layer_set_xml for per-layer files.
    """
    lines: list[str] = [
        XML_DECL,
        DOCTYPE,
        '<polygonSet>',
        f'    <name>{_escape(name)}</name>',
        '    <shapeType>CUBIC_CURVE</shapeType>',
    ]

    for mgr in managers:
        is_closed_attr = '' if mgr.is_closed else ' isClosed="false"'
        lines.append(f'    <polygon{is_closed_attr}>')

        # Determine which curves to serialise.
        # For closed polygons the last curve is synthetic (closes back to anchor[0]);
        # we still write it so the Java reader gets the same closing curve.
        curves_to_write = mgr.curves

        for cv in curves_to_write:
            pts = cv.points
            if not all(p is not None for p in pts):
                continue
            lines.append('        <curve>')
            for i, pt in enumerate(pts):
                xv = _to_xml_coord(pt.pos.x(), GRIDWIDTH)
                yv = _to_xml_coord(pt.pos.y(), GRIDHEIGHT)

                # Pressure attribute on anchor points if present
                pressure_attr = ''
                if mgr.anchor_pressures is not None and (i == 0 or i == 3):
                    # anchor index in the open-curve sense
                    curve_idx = mgr.curves.index(cv) if cv in mgr.curves else -1
                    anchor_k = curve_idx if i == 0 else curve_idx + 1
                    p_val = mgr.get_anchor_pressure(anchor_k)
                    if p_val != 1.0:
                        pressure_attr = f' pressure="{p_val:.3f}"'

                lines.append(f'            <point x="{xv}" y="{yv}"{pressure_attr}/>')
            lines.append('        </curve>')

        lines.append('    </polygon>')

    # Transform metadata (default values; transforms not tracked in Phase 1)
    lines += [
        '    <scaleX>1.0</scaleX>',
        '    <scaleY>1.0</scaleY>',
        '    <rotationAngle>0.0</rotationAngle>',
        '    <transX>0.0</transX>',
        '    <transY>0.0</transY>',
        '</polygonSet>',
    ]

    os.makedirs(os.path.dirname(os.path.abspath(file_path)), exist_ok=True)
    with open(file_path, 'w', encoding='ISO-8859-1') as f:
        f.write('\n'.join(lines) + '\n')


# ── read ──────────────────────────────────────────────────────────────────────

def read_polygon_set(file_path: str) -> list[dict]:
    """
    Parse a polygonSet XML file.
    Returns a list of dicts: {'points': [QPointF, ...], 'is_closed': bool}
    where each list of QPointF is in flat order A1,C1,C2,A2 per curve (still
    normalised+offset; denormalise after to get canvas coords).
    The caller (BezierWidget.load_polygon_set) calls set_all_points / set_open_points
    which expect canvas-space coords, so we denormalise here.
    """
    # Strip DOCTYPE before parsing (xml.etree doesn't handle it)
    with open(file_path, 'r', encoding='ISO-8859-1', errors='replace') as f:
        content = f.read()

    content = _strip_doctype(content)

    try:
        root = ET.fromstring(content)
    except ET.ParseError as e:
        raise ValueError(f"Could not parse {file_path}: {e}") from e

    if root.tag not in ('polygonSet', 'openCurveSet'):
        raise ValueError(f"Unexpected root element <{root.tag}> in {file_path}")

    result: list[dict] = []
    poly_tag = 'polygon' if root.tag == 'polygonSet' else 'openCurve'

    for poly_el in root.findall(poly_tag):
        is_closed = poly_el.get('isClosed', 'true').lower() != 'false'
        if root.tag == 'openCurveSet':
            is_closed = False

        pts: list[QPointF] = []
        pressures: list[float] = []

        curve_els = list(poly_el.findall('curve'))
        for ci, curve_el in enumerate(curve_els):
            point_els = list(curve_el.findall('point'))
            if len(point_els) != 4:
                continue
            for pi, pt_el in enumerate(point_els):
                xv = float(pt_el.get('x', '0'))
                yv = float(pt_el.get('y', '0'))
                # Add offset back (mirrors Java appendPolygonSet: A1x = xml_x + offset)
                xv += EDGE_OFFSET / GRIDWIDTH
                yv += EDGE_OFFSET / GRIDHEIGHT
                # Denormalise to canvas space
                cx = _denormalise(xv, GRIDWIDTH)
                cy = _denormalise(yv, GRIDHEIGHT)
                pts.append(QPointF(cx, cy))

                # Collect pressure for anchor points (index 0 and 3)
                if pi in (0, 3):
                    p_str = pt_el.get('pressure')
                    if p_str is not None:
                        pressures.append(float(p_str))
                    else:
                        pressures.append(1.0)

        result.append({
            'points': pts,
            'is_closed': is_closed,
            'pressures': pressures if any(p != 1.0 for p in pressures) else None,
        })

    return result


# ── helpers ───────────────────────────────────────────────────────────────────

def _strip_doctype(content: str) -> str:
    """Remove <!DOCTYPE ...> declarations so ET can parse the file."""
    import re
    content = re.sub(r'<!DOCTYPE[^>]*>', '', content)
    return content


def _escape(s: str) -> str:
    return (s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
             .replace('"', '&quot;'))
