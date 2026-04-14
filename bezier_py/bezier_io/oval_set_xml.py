"""
OvalSet XML IO — read/write ovalSet XML files.
No DOCTYPE. UTF-8 encoding.

Coordinate pipeline (matches Java OvalSetXml):
  Save centre: norm = (canvas_px - EDGE) / GRID - 0.5
  Save radius:  norm = radius / GRID
  Load centre:  canvas_px = (norm + 0.5) * GRID + EDGE
  Load radius:  radius = norm * GRID
"""
from __future__ import annotations
import os
from xml.etree import ElementTree as ET
from model.oval_manager import OvalManager

GRID = 1000.0
EDGE = 20.0
XML_DECL = '<?xml version="1.0" encoding="UTF-8"?>'


def _to_norm(canvas_px: float) -> str:
    v = (canvas_px - EDGE) / GRID - 0.5
    return f"{v:.4f}"

def _to_norm_radius(r: float) -> str:
    return f"{r / GRID:.4f}"

def _from_norm(norm: float) -> float:
    return (norm + 0.5) * GRID + EDGE

def _from_norm_radius(norm: float) -> float:
    return norm * GRID


def write_oval_set(file_path: str, name: str, ovals: list[OvalManager]) -> None:
    """Write an ovalSet XML file (no DOCTYPE, UTF-8)."""
    lines: list[str] = [
        XML_DECL,
        '<ovalSet>',
        f'    <name>{_esc(name)}</name>',
    ]
    for oval in ovals:
        cx = _to_norm(oval.cx)
        cy = _to_norm(oval.cy)
        rx = _to_norm_radius(oval.rx)
        ry = _to_norm_radius(oval.ry)
        lines.append(f'    <oval cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}"/>')
    lines.append('</ovalSet>')

    os.makedirs(os.path.dirname(os.path.abspath(file_path)), exist_ok=True)
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def read_oval_set(file_path: str) -> list[OvalManager]:
    """Parse an ovalSet XML and return a list of OvalManagers in canvas pixel space."""
    with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    import re
    content = re.sub(r'<!DOCTYPE[^>]*>', '', content)
    root = ET.fromstring(content)
    ovals: list[OvalManager] = []
    for el in root.findall('oval'):
        cx = _from_norm(float(el.get('cx', '0')))
        cy = _from_norm(float(el.get('cy', '0')))
        rx = _from_norm_radius(float(el.get('rx', '0')))
        ry = _from_norm_radius(float(el.get('ry', '0')))
        ovals.append(OvalManager(cx, cy, rx, ry))
    return ovals


def _esc(s: str) -> str:
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
