"""
OpenCurveSet XML IO — read/write openCurveSet XML files (no DOCTYPE).
"""
from __future__ import annotations
import os
import re
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

def _to_filename(s: str) -> str:
    """Matches layer_set_xml._to_filename: lowercase, spaces→_, strip non-alnum/dash/underscore."""
    s = s.strip()
    s = re.sub(r'\s+', '_', s)
    s = re.sub(r'[^a-zA-Z0-9_\-]', '', s)
    return s.lower()


def _write_open_curve_set_xml(file_path: str, name: str, managers) -> None:
    """Write an openCurveSet XML for an explicit iterable of managers."""
    lines: list[str] = [
        XML_DECL,
        '<openCurveSet>',
        f'    <name>{name}</name>',
        '    <shapeType>CUBIC_CURVE</shapeType>',
    ]

    for mgr in managers:
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


def write_open_curve_set(file_path: str, name: str, polygon_manager: PolygonManager) -> None:
    """Write an openCurveSet XML (no DOCTYPE) — all committed open curves."""
    _write_open_curve_set_xml(file_path, name,
                               polygon_manager.committed_managers())


def write_open_curve_layer_set(save_dir: str, overall_name: str,
                                layer_manager, polygon_manager) -> None:
    """
    Save one openCurveSet XML per geometry layer + a .layers.xml manifest.

    Mirrors layer_set_xml.write_layer_set() but writes <openCurveSet> format
    per-layer files instead of <polygonSet>.

    Files written:
      {save_dir}/{overall_fn}_{layer_fn}.xml   — one per geometry layer
      {save_dir}/{overall_fn}.layers.xml        — manifest
    """
    overall_fn = _to_filename(overall_name)

    root = ET.Element('layerSet')
    ET.SubElement(root, 'overallName').text = overall_name

    for layer in layer_manager.layers:
        if layer.is_trace:
            tl_el = ET.SubElement(root, 'traceLayer')
            ET.SubElement(tl_el, 'visible').text = str(layer.visible).lower()
            img_path = layer.trace_image_path or ''
            if img_path and os.path.isabs(img_path):
                try:
                    img_path = os.path.relpath(img_path, save_dir)
                except ValueError:
                    pass
            ET.SubElement(tl_el, 'imagePath').text = img_path
            ET.SubElement(tl_el, 'x').text      = f"{layer.trace_x:.4f}"
            ET.SubElement(tl_el, 'y').text      = f"{layer.trace_y:.4f}"
            ET.SubElement(tl_el, 'scale').text   = f"{layer.trace_scale:.4f}"
            ET.SubElement(tl_el, 'alpha').text   = f"{layer.trace_alpha:.4f}"
            continue

        layer_fn   = overall_fn + '_' + _to_filename(layer.name)
        layer_file = layer_fn + '.xml'
        layer_path = os.path.join(save_dir, layer_file)

        mgrs = polygon_manager.get_managers_for_layer(layer.id)
        _write_open_curve_set_xml(layer_path, layer.name, mgrs)
        print(f"OpenCurveLayerSet: saved {layer_path}")

        layer_el = ET.SubElement(root, 'layer')
        ET.SubElement(layer_el, 'name').text    = layer.name
        ET.SubElement(layer_el, 'file').text    = layer_file
        ET.SubElement(layer_el, 'visible').text = str(layer.visible).lower()

    manifest_path = os.path.join(save_dir, overall_fn + '.layers.xml')
    tree = ET.ElementTree(root)
    ET.indent(tree, space='  ')
    with open(manifest_path, 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        tree.write(f, encoding='unicode', xml_declaration=False)
    print(f"OpenCurveLayerSet: saved {manifest_path}")


def read_open_curve_set(file_path: str) -> list[dict]:
    """Parse an openCurveSet XML.  Returns same format as read_polygon_set."""
    from bezier_io.polygon_set_xml import read_polygon_set
    return read_polygon_set(file_path)  # same parser handles both root elements
