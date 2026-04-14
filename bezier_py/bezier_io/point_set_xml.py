"""
PointSet XML IO — read/write pointSet XML files.
No DOCTYPE. Same 2dp coordinate pipeline as polygonSet.

Coordinate pipeline (matches Java PointSetXml):
  Save: nX = canvas_x / GRID - 0.5  then  aX = nX - EDGE/GRID  then  round(aX*100)/100
  Load: valX = xml_x + EDGE/GRID     then  canvas_x = valX * GRID + GRID/2
"""
from __future__ import annotations
import os
from xml.etree import ElementTree as ET
from PySide6.QtCore import QPointF

GRID  = 1000.0
EDGE  = 20.0
XML_DECL = '<?xml version="1.0" encoding="ISO-8859-1"?>'


def _to_xml(canvas_val: float) -> float:
    norm = canvas_val / GRID - 0.5
    adj  = norm - EDGE / GRID
    return round(round(adj * 100)) / 100.0

def _from_xml(xml_val: float) -> float:
    val = xml_val + EDGE / GRID
    return val * GRID + GRID / 2


def write_point_set(file_path: str, name: str,
                    points: list[QPointF],
                    pressures: list[float] | None = None) -> None:
    """Write a pointSet XML file."""
    lines: list[str] = [
        '<pointSet>',
        f'    <name>{_esc(name)}</name>',
    ]
    for i, pt in enumerate(points):
        xv = _to_xml(pt.x())
        yv = _to_xml(pt.y())
        pr = pressures[i] if (pressures and i < len(pressures)) else 1.0
        pr_attr = f' pressure="{pr:.3f}"' if pr != 1.0 else ''
        lines.append(f'    <point x="{xv}" y="{yv}"{pr_attr}/>')
    lines += [
        '    <scaleX>1.0</scaleX>',
        '    <scaleY>1.0</scaleY>',
        '    <rotationAngle>0.0</rotationAngle>',
        '    <transX>0.5</transX>',
        '    <transY>0.5</transY>',
        '</pointSet>',
    ]
    os.makedirs(os.path.dirname(os.path.abspath(file_path)), exist_ok=True)
    with open(file_path, 'w', encoding='ISO-8859-1') as f:
        f.write('\n'.join(lines) + '\n')


def read_point_set(file_path: str) -> tuple[list[QPointF], list[float]]:
    """
    Parse a pointSet XML.
    Returns (list_of_canvas_QPointF, list_of_pressures).
    """
    with open(file_path, 'r', encoding='ISO-8859-1', errors='replace') as f:
        content = f.read()
    import re
    content = re.sub(r'<!DOCTYPE[^>]*>', '', content)
    # Handle missing XML declaration
    if not content.lstrip().startswith('<?xml') and not content.lstrip().startswith('<pointSet'):
        content = content.strip()
    root = ET.fromstring(content)
    pts: list[QPointF] = []
    pressures: list[float] = []
    for el in root.findall('point'):
        xv = float(el.get('x', '0'))
        yv = float(el.get('y', '0'))
        cx = _from_xml(xv)
        cy = _from_xml(yv)
        pts.append(QPointF(cx, cy))
        pr_str = el.get('pressure')
        pressures.append(float(pr_str) if pr_str else 1.0)
    return pts, pressures


def _esc(s: str) -> str:
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
