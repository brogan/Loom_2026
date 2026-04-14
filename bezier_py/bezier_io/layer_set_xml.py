"""
Layer-set XML — saves/loads the .layers.xml manifest.
Mirrors Java LayerSetXml.java and CubicCurvePanel.loadLayerSet().

Manifest format:
  <layerSet>
    <overallName>My Shape</overallName>
    <layer>
      <name>Layer 1</name>
      <file>my_shape_layer_1.xml</file>
      <visible>true</visible>
    </layer>
    ...
    <!-- optional — present only when a trace layer exists -->
    <traceLayer>
      <visible>true</visible>
      <imagePath>../tracing_images/photo.png</imagePath>
      <x>520.0</x>
      <y>520.0</y>
      <scale>1.0</scale>
      <alpha>0.5</alpha>
    </traceLayer>
  </layerSet>
"""
from __future__ import annotations
import os
import re
from xml.etree import ElementTree as ET

from model.layer_manager import LayerManager
from bezier_io.polygon_set_xml import write_polygon_set, read_polygon_set


def _to_filename(s: str) -> str:
    """Java LayerSetXml.toFilename: lowercase, spaces→_, strip non-alnum/dash/underscore."""
    s = s.strip()
    s = re.sub(r'\s+', '_', s)
    s = re.sub(r'[^a-zA-Z0-9_\-]', '', s)
    return s.lower()


def write_layer_set(save_dir: str, overall_name: str,
                    layer_manager: LayerManager,
                    polygon_manager) -> None:
    """
    Save one .xml per geometry layer (polygonSet format) + a .layers.xml manifest.
    If a trace layer exists its metadata is written as a <traceLayer> element
    (no per-layer polygon file is written for trace layers).

    Files written:
      {save_dir}/{overall_fn}_{layer_fn}.xml   — one per geometry layer
      {save_dir}/{overall_fn}.layers.xml        — manifest
    """
    overall_fn = _to_filename(overall_name)

    # Build manifest root
    root = ET.Element('layerSet')
    name_el = ET.SubElement(root, 'overallName')
    name_el.text = overall_name

    for layer in layer_manager.layers:
        if layer.is_trace:
            # Trace layer: write <traceLayer> metadata only — no polygon file
            tl_el = ET.SubElement(root, 'traceLayer')
            ET.SubElement(tl_el, 'visible').text = str(layer.visible).lower()
            # Store the image path relative to save_dir so the manifest is portable
            img_path = layer.trace_image_path or ''
            if img_path and os.path.isabs(img_path):
                try:
                    img_path = os.path.relpath(img_path, save_dir)
                except ValueError:
                    pass   # different drive on Windows — keep absolute
            ET.SubElement(tl_el, 'imagePath').text = img_path
            ET.SubElement(tl_el, 'x').text     = f"{layer.trace_x:.4f}"
            ET.SubElement(tl_el, 'y').text     = f"{layer.trace_y:.4f}"
            ET.SubElement(tl_el, 'scale').text  = f"{layer.trace_scale:.4f}"
            ET.SubElement(tl_el, 'alpha').text  = f"{layer.trace_alpha:.4f}"
            continue

        layer_fn   = overall_fn + '_' + _to_filename(layer.name)
        layer_file = layer_fn + '.xml'
        layer_path = os.path.join(save_dir, layer_file)

        # Write the per-layer polygon XML (only managers on this layer)
        mgrs_for_layer = polygon_manager.get_managers_for_layer(layer.id)
        _write_layer_polygon_file(layer_path, layer.name, mgrs_for_layer,
                                  polygon_manager)

        # Add <layer> element to manifest
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
    print(f"LayerSetXml: saved {manifest_path}")


def _write_layer_polygon_file(path: str, layer_name: str,
                               managers, polygon_manager) -> None:
    """
    Write a subset of managers (those belonging to one layer) as a polygonSet XML.
    Reuses write_polygon_set but passes a filtered manager list.
    """
    # We need a fake polygon_manager that only returns the layer's managers.
    # Easiest: write manually using the same normalise pipeline.
    from bezier_io.polygon_set_xml import _write_polygon_set_xml
    _write_polygon_set_xml(path, layer_name, managers)


def read_layer_set(manifest_path: str) -> list[dict]:
    """
    Parse a .layers.xml manifest.

    Returns a list of dicts:
      [{'name': str, 'file': str, 'visible': bool}, ...]
    with 'file' as a bare filename (no directory).
    """
    tree = ET.parse(manifest_path)
    root = tree.getroot()
    layers = []
    for layer_el in root.findall('layer'):
        name    = (layer_el.findtext('name') or '').strip()
        file_   = (layer_el.findtext('file') or '').strip()
        vis_txt = (layer_el.findtext('visible') or 'true').strip().lower()
        layers.append({
            'name':    name,
            'file':    file_,
            'visible': (vis_txt != 'false'),
        })
    return layers


def peek_overall_name(manifest_path: str) -> str:
    """Return the <overallName> element from a .layers.xml manifest."""
    try:
        tree = ET.parse(manifest_path)
        root = tree.getroot()
        return (root.findtext('overallName') or '').strip()
    except Exception:
        return ''


def read_trace_layer_info(manifest_path: str) -> dict | None:
    """
    Return the trace layer metadata dict from a .layers.xml manifest, or None.

    Dict keys: 'visible' (bool), 'image_path' (str), 'x' (float), 'y' (float),
               'scale' (float), 'alpha' (float).
    image_path is returned as stored (may be relative to manifest directory).
    """
    try:
        tree = ET.parse(manifest_path)
        root = tree.getroot()
        tl = root.find('traceLayer')
        if tl is None:
            return None
        vis_txt = (tl.findtext('visible') or 'true').strip().lower()
        def _f(tag: str, default: float) -> float:
            txt = (tl.findtext(tag) or '').strip()
            try:
                return float(txt)
            except ValueError:
                return default
        return {
            'visible':    vis_txt != 'false',
            'image_path': (tl.findtext('imagePath') or '').strip(),
            'x':          _f('x',     520.0),
            'y':          _f('y',     520.0),
            'scale':      _f('scale', 1.0),
            'alpha':      _f('alpha', 1.0),
        }
    except Exception:
        return None
