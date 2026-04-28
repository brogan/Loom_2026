"""Sprite preview tab widget for the sprite editor.

Renders all sprites in the current SpriteSet at their configured positions,
with interactive drag-based editing of transform parameters.
"""
from __future__ import annotations

import math
import os
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import Optional

from PySide6.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout, QLabel, QComboBox, QCheckBox
from PySide6.QtCore import Signal, Qt, QPointF, QRectF
from PySide6.QtGui import QPainter, QPen, QColor, QPainterPath, QBrush, QPixmap


# ── Data class ────────────────────────────────────────────────────────────────

@dataclass
class ParsedGeo:
    """Parsed geometry data for a shape."""
    anchor_polys: list[list[tuple[float, float]]] = field(default_factory=list)
    ctrl_polys: list[list[tuple[float, float, float, float, float, float]]] = field(default_factory=list)
    closed_flags: list[bool] = field(default_factory=list)
    dot_positions: list[tuple[float, float]] = field(default_factory=list)


# ── XML parsing helpers (mirrors PolygonPreviewWidget._parse) ─────────────────

def _xy(elem) -> Optional[tuple[float, float]]:
    try:
        return float(elem.get('x', '')), float(elem.get('y', ''))
    except (ValueError, TypeError):
        return None


def _parse_curves(curves) -> tuple[list, list]:
    anchors, beziers = [], []
    for curve in curves:
        pts = [p for child in curve for p in [_xy(child)] if p is not None]
        if len(pts) < 4:
            continue
        a0, c1, c2, a1 = pts[0], pts[1], pts[2], pts[3]
        if not anchors:
            anchors.append(a0)
        anchors.append(a1)
        beziers.append((c1[0], c1[1], c2[0], c2[1], a1[0], a1[1]))
    return anchors, beziers


def _parse_flat_spline(all_pts) -> tuple[list, list]:
    anchors, beziers = [], []
    n = len(all_pts) // 4
    for i in range(n):
        a0 = all_pts[i * 4][0]
        c1 = all_pts[i * 4 + 1][0]
        c2 = all_pts[i * 4 + 2][0]
        a1 = all_pts[i * 4 + 3][0]
        if not anchors:
            anchors.append(a0)
        anchors.append(a1)
        beziers.append((c1[0], c1[1], c2[0], c2[1], a1[0], a1[1]))
    return anchors, beziers


def _parse_geo_from_root(root) -> ParsedGeo:
    """Parse XML root element into ParsedGeo."""
    geo = ParsedGeo()
    if root.tag == 'ovalSet':
        for oval_el in root.findall('oval'):
            try:
                cx = float(oval_el.get('cx', '0'))
                cy = float(oval_el.get('cy', '0'))
                rx = float(oval_el.get('rx', '0.1'))
                ry = float(oval_el.get('ry', '0.1'))
                steps = 60
                pts = [(cx + rx * math.cos(math.radians(i * 360.0 / steps)),
                        cy + ry * math.sin(math.radians(i * 360.0 / steps)))
                       for i in range(steps)]
                geo.anchor_polys.append(pts)
                geo.ctrl_polys.append([])
                geo.closed_flags.append(True)
            except (ValueError, TypeError):
                pass
        return geo

    if root.tag == 'pointSet':
        for pt in root.findall('point'):
            p = _xy(pt)
            if p:
                geo.dot_positions.append(p)
        return geo

    polygon_elems = list(root.iter('polygon'))
    open_curve_elems = list(root.iter('openCurve'))
    normalized = []
    for t in polygon_elems:
        normalized.append((t, t.get('isClosed', 'true').lower() != 'false'))
    for t in open_curve_elems:
        normalized.append((t, False))
    if not normalized:
        normalized = [(root, root.get('isClosed', 'true').lower() != 'false')]

    for poly_elem, is_closed in normalized:
        children = list(poly_elem)
        curves = [c for c in children if c.tag.lower() in ('curve', 'cubiccurve', 'edge')]
        if curves:
            anchors, beziers = _parse_curves(curves)
            if anchors:
                geo.anchor_polys.append(anchors)
                geo.ctrl_polys.append(beziers)
                geo.closed_flags.append(is_closed)
            continue

        all_pts = []
        for child in poly_elem.iter():
            p = _xy(child)
            if p:
                all_pts.append((p, child.tag.lower()))

        if len(all_pts) >= 4 and len(all_pts) % 4 == 0:
            anchors, beziers = _parse_flat_spline(all_pts)
            if anchors:
                geo.anchor_polys.append(anchors)
                geo.ctrl_polys.append(beziers)
                geo.closed_flags.append(is_closed)
                continue

        simple = [p for p, _ in all_pts]
        if len(simple) >= 2:
            geo.anchor_polys.append(simple)
            geo.ctrl_polys.append([])
            geo.closed_flags.append(is_closed)

    return geo


def _make_ngon(n: int) -> ParsedGeo:
    """Generate a regular n-gon as ParsedGeo (coords centered at 0, radius 0.5)."""
    pts = []
    for i in range(n):
        angle = math.radians(i * 360.0 / n - 90)
        pts.append((math.cos(angle) * 0.5, math.sin(angle) * 0.5))
    geo = ParsedGeo()
    geo.anchor_polys.append(pts)
    geo.ctrl_polys.append([])
    geo.closed_flags.append(True)
    return geo


def _parse_regular_polygon_xml(filepath: str) -> Optional[ParsedGeo]:
    """Parse a regularPolygon XML parameter file and generate star polygon geometry.

    Replicates Scala's createRegularPolygonSet → makePolygon2DStar pipeline:
      1. makePolygon2DStar(totalPoints*2, outerDiameter=1.0, proportion=internalRadius*2,
                           positiveSynch, synchMultiplier)
      2. Optional offset rotation
      3. Optional non-uniform scale
      4. Optional rotationAngle rotation
      5. Translation by (transX-0.5, transY-0.5)
    """
    try:
        tree = ET.parse(filepath, parser=ET.XMLParser(encoding='utf-8'))
        root = tree.getroot()

        def gf(tag, default=0.0):
            el = root.find(tag)
            return float(el.text.strip()) if (el is not None and el.text) else default

        def gb(tag, default=True):
            el = root.find(tag)
            return el.text.strip().lower() == 'true' if (el is not None and el.text) else default

        total_points    = int(gf('totalPoints', 3))
        internal_radius = gf('internalRadius', 0.5)
        offset          = gf('offset', 0.0)
        scale_x         = gf('scaleX', 1.0)
        scale_y         = gf('scaleY', 1.0)
        rotation_angle  = gf('rotationAngle', 0.0)
        trans_x         = gf('transX', 0.5)
        trans_y         = gf('transY', 0.5)
        positive_synch  = gb('positiveSynch', True)
        synch_mult      = gf('synchMultiplier', 1.0)

        n_sides    = total_points * 2
        proportion = max(internal_radius * 2.0, 1e-9)
        prop       = 1.0 / proportion
        ang_inc    = 360.0 / n_sides   # degrees

        def rot2d(x, y, deg):
            rad = math.radians(deg)
            c, s = math.cos(rad), math.sin(rad)
            return x * c - y * s, x * s + y * c

        pts = [None] * n_sides

        # Outer points (even indices), start at (0, -0.5)
        r_outer = 0.5
        pts[0] = (0.0, -r_outer)
        for i in range(1, n_sides):
            if i % 2 == 0:
                pts[i] = rot2d(pts[i - 2][0], pts[i - 2][1], 2 * ang_inc)

        # Inner points (odd indices)
        r_inner = r_outer / prop   # = internalRadius
        pts[1] = (0.0, -r_inner)
        if positive_synch:
            pts[1] = rot2d(pts[1][0], pts[1][1],  ang_inc * synch_mult)
        else:
            pts[1] = rot2d(pts[1][0], pts[1][1], -ang_inc * synch_mult)
        for i in range(2, n_sides):
            if i % 2 != 0:
                pts[i] = rot2d(pts[i - 2][0], pts[i - 2][1], 2 * ang_inc)

        if offset:
            pts = [rot2d(x, y, offset) for x, y in pts]
        if scale_x != 1.0 or scale_y != 1.0:
            pts = [(x * scale_x, y * scale_y) for x, y in pts]
        if rotation_angle:
            pts = [rot2d(x, y, rotation_angle) for x, y in pts]
        tx, ty = trans_x - 0.5, trans_y - 0.5
        if tx or ty:
            pts = [(x + tx, y + ty) for x, y in pts]

        geo = ParsedGeo()
        geo.anchor_polys.append(pts)
        geo.ctrl_polys.append([])
        geo.closed_flags.append(True)
        return geo
    except Exception:
        return None


# Handle → drag mode mapping
_HANDLE_MODES = {
    'TL': 'scale_xy',
    'T':  'scale_y',   # top/bottom edge: drag up/down changes height (size_y)
    'TR': 'rotate',
    'L':  'scale_x',   # left/right edge: drag left/right changes width (size_x)
    'R':  'scale_x',
    'BL': 'rotate',
    'B':  'scale_y',
    'BR': 'scale_xy',
}


# ── Canvas ────────────────────────────────────────────────────────────────────

class SpritePreviewCanvas(QWidget):
    """Canvas that renders all sprites in the current SpriteSet at configured positions."""

    transform_changed = Signal(float, float, float, float, float)
    selection_changed = Signal(int)  # emitted when user clicks a different sprite

    _HANDLE_SIZE = 8
    _HANDLE_HIT_RADIUS = 6
    _MARGIN = 20

    # Colour constants
    _COL_SELECTED   = QColor(80, 200, 120)    # bright green
    _COL_SAME_SET   = QColor(65, 110, 160)    # mid-blue  (same perceived luminance as grey)
    _COL_OTHER_SET  = QColor(100, 100, 100)   # mid-grey

    def __init__(self, parent=None):
        super().__init__(parent)
        self._sprite_set = None
        self._sprite_library = None            # full library for cross-set rendering
        # Background pixmap cache: redrawn only when scene changes, not every drag frame
        self._bg_pixmap: Optional[QPixmap] = None
        self._bg_dirty: bool = True
        self._selected_index: int = -1
        self._polygon_sets_dir: str = ""
        self._curve_sets_dir: str = ""
        self._point_sets_dir: str = ""
        self._oval_sets_dir: str = ""
        self._regular_polygons_dir: str = ""
        self._geo_cache: dict[str, Optional[ParsedGeo]] = {}
        self._polygon_registry: Optional[dict] = None   # lazily built from polygons.xml
        self._grid_size_pct: float = 10.0
        self._snap: bool = False
        self._canvas_w: int = 1080
        self._canvas_h: int = 1080
        # Active state override (for keyframe preview of the selected sprite)
        self._active_params: Optional[tuple] = None   # (loc_x, loc_y, size_x, size_y, rot)
        self._active_geo: Optional[ParsedGeo] = None
        # Drag state
        self._drag_mode: Optional[str] = None
        self._drag_start_screen: QPointF = QPointF()
        self._drag_start_params: tuple = (0.0, 0.0, 1.0, 1.0, 0.0)
        self.setMouseTracking(True)
        self.setMinimumSize(300, 300)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._bg_dirty = True

    # ── Public setters ─────────────────────────────────────────────────────

    def set_sprite_set(self, sprite_set, selected_index: int):
        self._sprite_set = sprite_set
        self._selected_index = selected_index
        self._bg_dirty = True
        self.update()

    def set_selected_index(self, index: int):
        if index == self._selected_index:
            # Same sprite — params may have changed but background sprites are untouched.
            # Don't mark the pixmap dirty; just schedule a repaint.
            self.update()
            return
        self._selected_index = index
        self._bg_dirty = True
        self.update()

    def set_sprite_library(self, lib):
        self._sprite_library = lib
        self._bg_dirty = True
        self.update()

    def set_directories(self, poly_dir: str, curve_dir: str, point_dir: str,
                        oval_dir: str = "", regular_dir: str = ""):
        # Short-circuit: don't clear the geo cache or invalidate the pixmap
        # if the directories haven't actually changed.  _notify_tabs_of_project_dir()
        # is called on every modified event (including every drag frame), so this
        # guard is critical to prevent clearing the geo cache on every mouse move.
        if (poly_dir == self._polygon_sets_dir and
                curve_dir == self._curve_sets_dir and
                point_dir == self._point_sets_dir and
                oval_dir == self._oval_sets_dir and
                regular_dir == self._regular_polygons_dir):
            return
        self._polygon_sets_dir = poly_dir
        self._curve_sets_dir = curve_dir
        self._point_sets_dir = point_dir
        self._oval_sets_dir = oval_dir
        self._regular_polygons_dir = regular_dir
        self._geo_cache.clear()
        self._polygon_registry = None   # reset so it's rebuilt for the new project
        self._bg_dirty = True
        self.update()

    def _get_polygon_registry(self) -> dict:
        """Lazily build a {polygon_set_name: filepath} dict from configuration/polygons.xml.

        This lets the preview resolve polygon sets whose name differs from their filename
        (e.g. name="Layer 1" → file="cat_byhand_layer_1.xml").
        """
        if self._polygon_registry is not None:
            return self._polygon_registry
        self._polygon_registry = {}
        if not self._polygon_sets_dir:
            return self._polygon_registry
        # polygons.xml lives at <project_dir>/configuration/polygons.xml
        project_dir = os.path.dirname(self._polygon_sets_dir)
        polygons_xml = os.path.join(project_dir, "configuration", "polygons.xml")
        if not os.path.isfile(polygons_xml):
            return self._polygon_registry
        try:
            tree = ET.parse(polygons_xml)
            for ps_elem in tree.getroot().iter("PolygonSet"):
                name = ps_elem.get("name", "").strip()
                src = ps_elem.find("Source")
                if src is None:
                    continue
                src_type = src.get("type", "")
                if src_type == "file":
                    filename = (src.findtext("Filename") or "").strip()
                    if name and filename:
                        self._polygon_registry[name] = os.path.join(
                            self._polygon_sets_dir, filename)
        except Exception:
            pass
        return self._polygon_registry

    def set_grid_size(self, pct: float):
        self._grid_size_pct = pct
        self._bg_dirty = True
        self.update()

    def set_snap(self, snap: bool):
        self._snap = snap

    def set_canvas_size(self, w: int, h: int):
        self._canvas_w = max(1, w)
        self._canvas_h = max(1, h)
        self._bg_dirty = True
        self.update()

    def set_active_state(self, loc_x: float, loc_y: float,
                         size_x: float, size_y: float, rot: float,
                         geo: Optional[ParsedGeo] = None):
        """Override display params/geometry for the selected sprite (keyframe preview)."""
        self._active_params = (loc_x, loc_y, size_x, size_y, rot)
        self._active_geo = geo
        self.update()

    def clear_active_state(self):
        self._active_params = None
        self._active_geo = None
        self.update()

    def _get_sprite_display_params(self, sprite, idx: int) -> tuple:
        """Return (loc_x, loc_y, size_x, size_y, rot) using active override for selected sprite."""
        if self._active_params is not None and idx == self._selected_index:
            return self._active_params
        p = sprite.params
        return p.location_x, p.location_y, p.size_x, p.size_y, p.start_rotation

    # ── Coordinate helpers ──────────────────────────────────────────────────

    def _canvas_rect(self) -> tuple[float, float, float, float]:
        """Returns (left, top, width, height) of the aspect-correct canvas area."""
        m = self._MARGIN
        r = self.rect()
        avail_w = r.width() - 2 * m
        avail_h = r.height() - 2 * m
        canvas_aspect = self._canvas_w / self._canvas_h
        avail_aspect = avail_w / max(1, avail_h)
        if canvas_aspect > avail_aspect:
            cw = avail_w
            ch = avail_w / canvas_aspect
        else:
            ch = avail_h
            cw = avail_h * canvas_aspect
        cx = m + (avail_w - cw) / 2
        cy = m + (avail_h - ch) / 2
        return cx, cy, cw, ch

    def _world_to_screen(self, wx: float, wy: float) -> tuple[float, float]:
        cx, cy, cw, ch = self._canvas_rect()
        sx = (wx + 1) / 2 * cw + cx
        sy = (1 - wy) / 2 * ch + cy
        return sx, sy

    def _screen_to_world(self, sx: float, sy: float) -> tuple[float, float]:
        cx, cy, cw, ch = self._canvas_rect()
        wx = (sx - cx) / cw * 2 - 1
        wy = 1 - (sy - cy) / ch * 2
        return wx, wy

    def _pixels_per_world(self) -> tuple[float, float]:
        _, _, cw, ch = self._canvas_rect()
        return cw / 2.0, ch / 2.0

    # ── Geometry resolution ─────────────────────────────────────────────────

    def _resolve_geometry(self, sprite) -> Optional[ParsedGeo]:
        """Look up and cache geometry for a sprite. Returns None on failure."""
        try:
            from models.sprite_config import GeoSourceType
            stype = sprite.geo_source_type

            if stype == GeoSourceType.REGULAR_POLYGON:
                return _make_ngon(max(3, sprite.geo_regular_polygon_sides))

            geo_map = {
                GeoSourceType.POLYGON_SET:    (sprite.geo_polygon_set_name,    self._polygon_sets_dir),
                GeoSourceType.OPEN_CURVE_SET: (sprite.geo_open_curve_set_name, self._curve_sets_dir),
                GeoSourceType.POINT_SET:      (sprite.geo_point_set_name,      self._point_sets_dir),
                GeoSourceType.OVAL_SET:       (sprite.geo_oval_set_name,       self._oval_sets_dir),
            }
            if stype not in geo_map:
                return None

            name, base_dir = geo_map[stype]
            if not name or not base_dir:
                return None

            filepath = os.path.join(base_dir, name + ".xml")
            if filepath in self._geo_cache:
                return self._geo_cache[filepath]

            if not os.path.isfile(filepath):
                if stype == GeoSourceType.POLYGON_SET:
                    # Fall back 1: look up actual filename via polygons.xml registry
                    # (handles cases where polygon set name ≠ filename, e.g. "Layer 1")
                    registry = self._get_polygon_registry()
                    if name in registry:
                        reg_filepath = registry[name]
                        if reg_filepath in self._geo_cache:
                            return self._geo_cache[reg_filepath]
                        if os.path.isfile(reg_filepath):
                            tree = ET.parse(reg_filepath, parser=ET.XMLParser(encoding='utf-8'))
                            geo = _parse_geo_from_root(tree.getroot())
                            self._geo_cache[reg_filepath] = geo
                            return geo

                    # Fall back 2: regularPolygons/ parameter file
                    if self._regular_polygons_dir:
                        reg_path = os.path.join(self._regular_polygons_dir, name + ".xml")
                        if reg_path in self._geo_cache:
                            return self._geo_cache[reg_path]
                        geo = _parse_regular_polygon_xml(reg_path)
                        self._geo_cache[reg_path] = geo
                        return geo
                self._geo_cache[filepath] = None
                return None

            tree = ET.parse(filepath, parser=ET.XMLParser(encoding='utf-8'))
            geo = _parse_geo_from_root(tree.getroot())
            self._geo_cache[filepath] = geo
            return geo
        except Exception:
            return None

    # ── Transform helpers ───────────────────────────────────────────────────

    @staticmethod
    def _transform_point(px: float, py: float,
                         loc_x: float, loc_y: float,
                         size_x: float, size_y: float,
                         rotation_deg: float) -> tuple[float, float]:
        """Transform a geometry point to world space.

        Scala pipeline (Sprite2DParams + Sprite2D constructor):
          1. standShapesUpright (rotate 180) then reverseShapesHorizontally (negate x)
             → net effect: negate Y only.
          2. size2D = canvas_px * scaleFactor  → a coord of 0.5 fills half-canvas,
             i.e. world ±1 in the preview corresponds to canvas_px / 2.
             Multiply by 2 so that coords in [−0.5, 0.5] map to world [−1, 1].
          3. locX = (pos_x / 200) / size_x  then scaled back by size2D
             → net offset = pos_x * canvas_px / 200; world equivalent: pos_x / 100.
        """
        cx = px * 2.0 * size_x          # scale + ×2 for canvas convention
        cy = -(py * 2.0 * size_y)       # negate Y (standShapesUpright net effect)
        if rotation_deg:
            rad = math.radians(rotation_deg)
            cos_r, sin_r = math.cos(rad), math.sin(rad)
            cx, cy = cx * cos_r - cy * sin_r, cx * sin_r + cy * cos_r
        return cx + loc_x / 100.0, cy + loc_y / 100.0

    def _build_path(self, geo: ParsedGeo,
                    loc_x: float, loc_y: float,
                    size_x: float, size_y: float,
                    rotation_deg: float,
                    cr: Optional[tuple] = None) -> tuple:
        """Build QPainterPath + world-space bbox in a single pass.

        Returns (path, world_bbox) where world_bbox = (min_wx, min_wy, max_wx, max_wy)
        or None if no points were processed.

        Optimisations vs. the previous version:
        - cos/sin computed ONCE per call (not once per point)
        - _transform_point inlined — no per-point Python function call overhead
        - World bbox accumulated here, eliminating the second pass in _sprite_bbox_world
        - cr passed in so _canvas_rect() is not called per-point
        """
        if cr is None:
            cr = self._canvas_rect()
        ccx, ccy, ccw, cch = cr

        # Precompute rotation constants once for all points
        loc_off_x = loc_x / 100.0
        loc_off_y = loc_y / 100.0
        if rotation_deg:
            _rad = math.radians(rotation_deg)
            cos_r = math.cos(_rad)
            sin_r = math.sin(_rad)
            has_rot = True
        else:
            cos_r = sin_r = 0.0
            has_rot = False

        min_wx = min_wy =  1e18
        max_wx = max_wy = -1e18

        def pt(px, py):
            nonlocal min_wx, min_wy, max_wx, max_wy
            # Inline _transform_point
            wx = px * 2.0 * size_x
            wy = -(py * 2.0 * size_y)
            if has_rot:
                wx, wy = wx * cos_r - wy * sin_r, wx * sin_r + wy * cos_r
            wx += loc_off_x
            wy += loc_off_y
            # Track world bbox
            if wx < min_wx: min_wx = wx
            if wx > max_wx: max_wx = wx
            if wy < min_wy: min_wy = wy
            if wy > max_wy: max_wy = wy
            # World → screen (inline _world_to_screen)
            return (wx + 1) / 2 * ccw + ccx, (1 - wy) / 2 * cch + ccy

        path = QPainterPath()
        for poly_idx, anchors in enumerate(geo.anchor_polys):
            if not anchors:
                continue
            beziers = geo.ctrl_polys[poly_idx] if poly_idx < len(geo.ctrl_polys) else []
            closed = geo.closed_flags[poly_idx] if poly_idx < len(geo.closed_flags) else True
            sx, sy = pt(anchors[0][0], anchors[0][1])
            path.moveTo(sx, sy)
            if beziers:
                for c1x, c1y, c2x, c2y, a1x, a1y in beziers:
                    sc1x, sc1y = pt(c1x, c1y)
                    sc2x, sc2y = pt(c2x, c2y)
                    sa1x, sa1y = pt(a1x, a1y)
                    path.cubicTo(sc1x, sc1y, sc2x, sc2y, sa1x, sa1y)
            else:
                for a in anchors[1:]:
                    sx, sy = pt(a[0], a[1])
                    path.lineTo(sx, sy)
            if closed:
                path.closeSubpath()

        world_bbox = (min_wx, min_wy, max_wx, max_wy) if min_wx < 1e17 else None
        return path, world_bbox

    def _sprite_bbox_world(self, sprite, geo: Optional[ParsedGeo],
                           idx: int = -1) -> Optional[tuple]:
        """Compute bounding box (min_wx, min_wy, max_wx, max_wy) in world coords.

        Includes bezier control points so the result matches _build_path's world_bbox
        and handle positions are consistent between painting and hit-testing.
        """
        loc_x, loc_y, size_x, size_y, rot = self._get_sprite_display_params(sprite, idx)

        if geo is None or (not geo.anchor_polys and not geo.dot_positions):
            cx, cy = loc_x / 100.0, loc_y / 100.0
            r = 0.05
            return cx - r, cy - r, cx + r, cy + r

        all_wx, all_wy = [], []
        for poly_idx, anchors in enumerate(geo.anchor_polys):
            for ax, ay in anchors:
                wx, wy = self._transform_point(ax, ay, loc_x, loc_y, size_x, size_y, rot)
                all_wx.append(wx)
                all_wy.append(wy)
            # Include control points — _build_path does the same so handles are
            # drawn and hit-tested at identical positions.
            beziers = geo.ctrl_polys[poly_idx] if poly_idx < len(geo.ctrl_polys) else []
            for c1x, c1y, c2x, c2y, _a1x, _a1y in beziers:
                for cpx, cpy in ((c1x, c1y), (c2x, c2y)):
                    wx, wy = self._transform_point(cpx, cpy, loc_x, loc_y, size_x, size_y, rot)
                    all_wx.append(wx)
                    all_wy.append(wy)
        for px, py in geo.dot_positions:
            wx, wy = self._transform_point(px, py, loc_x, loc_y, size_x, size_y, rot)
            all_wx.append(wx)
            all_wy.append(wy)

        if not all_wx:
            cx, cy = loc_x / 200.0, loc_y / 200.0
            r = 0.05
            return cx - r, cy - r, cx + r, cy + r

        return min(all_wx), min(all_wy), max(all_wx), max(all_wy)

    # ── Handle positions ────────────────────────────────────────────────────

    def _handle_positions(self, bbox: tuple) -> dict[str, QPointF]:
        """Return 8 handle centre positions in screen space."""
        min_wx, min_wy, max_wx, max_wy = bbox
        cx = (min_wx + max_wx) / 2
        cy = (min_wy + max_wy) / 2

        def s(wx, wy):
            x, y = self._world_to_screen(wx, wy)
            return QPointF(x, y)

        return {
            'TL': s(min_wx, max_wy),
            'T':  s(cx,     max_wy),
            'TR': s(max_wx, max_wy),
            'L':  s(min_wx, cy),
            'R':  s(max_wx, cy),
            'BL': s(min_wx, min_wy),
            'B':  s(cx,     min_wy),
            'BR': s(max_wx, min_wy),
        }

    # ── Paint ───────────────────────────────────────────────────────────────

    def _rebuild_bg_pixmap(self, cr: tuple):
        """Render background fill + grid + all non-selected sprites into _bg_pixmap."""
        w, h = self.width(), self.height()
        if w <= 0 or h <= 0:
            return
        self._bg_pixmap = QPixmap(w, h)
        bp = QPainter(self._bg_pixmap)
        bp.setRenderHint(QPainter.RenderHint.Antialiasing)
        bp.fillRect(0, 0, w, h, QColor(28, 28, 28))
        self._paint_grid(bp, cr)
        source = self._sprite_library.sprite_sets if self._sprite_library is not None else (
            [self._sprite_set] if self._sprite_set is not None else []
        )
        for sprite_set in source:
            same_set = (sprite_set is self._sprite_set)
            for i, sprite in enumerate(sprite_set.sprites):
                if not sprite.enabled:
                    continue
                if same_set and i == self._selected_index:
                    continue   # drawn separately each frame
                local_idx = i if same_set else -1
                self._paint_sprite(bp, sprite, local_idx, False, same_set, cr)
        bp.end()

    def paintEvent(self, event):
        cr = self._canvas_rect()   # compute once for the whole frame

        # Rebuild the background pixmap only when the scene has changed.
        # During drag only _active_params changes (selected sprite) — background is untouched.
        if self._bg_dirty or self._bg_pixmap is None:
            self._rebuild_bg_pixmap(cr)
            self._bg_dirty = False

        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # O(1) blit of cached background
        if self._bg_pixmap is not None:
            painter.drawPixmap(0, 0, self._bg_pixmap)

        # Draw only the selected sprite fresh each frame (O(N_points_selected))
        if (self._sprite_set is not None
                and 0 <= self._selected_index < len(self._sprite_set.sprites)):
            sprite = self._sprite_set.sprites[self._selected_index]
            self._paint_sprite(painter, sprite, self._selected_index, True, True, cr)

        painter.end()

    def _paint_sprite(self, painter: QPainter, sprite,
                      local_idx: int, is_selected: bool, is_same_set: bool,
                      cr: Optional[tuple] = None):
        """Draw a single sprite with colour determined by its selection/set status.

        Pass a pre-computed cr=(cx,cy,cw,ch) to avoid recomputing _canvas_rect()
        for every point across every sprite per frame.
        """
        if cr is None:
            cr = self._canvas_rect()
        geo = (self._active_geo if (is_selected and self._active_geo is not None)
               else self._resolve_geometry(sprite))
        loc_x, loc_y, size_x, size_y, rot = self._get_sprite_display_params(sprite, local_idx)

        if is_selected:
            color = self._COL_SELECTED
        elif is_same_set:
            color = self._COL_SAME_SET
        else:
            color = self._COL_OTHER_SET

        ccx, ccy, ccw, cch = cr
        world_bbox = None
        if geo is not None and (geo.anchor_polys or geo.dot_positions):
            if geo.anchor_polys:
                path, world_bbox = self._build_path(geo, loc_x, loc_y, size_x, size_y, rot, cr)
                pen = QPen(color)
                pen.setWidthF(1.5 if is_selected else 1.0)
                painter.setPen(pen)
                painter.setBrush(Qt.BrushStyle.NoBrush)
                painter.drawPath(path)
            if geo.dot_positions:
                painter.setPen(Qt.PenStyle.NoPen)
                painter.setBrush(QBrush(color))
                for dpx, dpy in geo.dot_positions:
                    wx, wy = self._transform_point(dpx, dpy, loc_x, loc_y, size_x, size_y, rot)
                    dsx = (wx + 1) / 2 * ccw + ccx
                    dsy = (1 - wy) / 2 * cch + ccy
                    painter.drawEllipse(QPointF(dsx, dsy), 4, 4)
        else:
            self._paint_placeholder(painter, self._sprite_bbox_world(sprite, None, local_idx), color)

        if is_selected:
            # Use bbox from path build if available — avoids a second full pass over all points
            if world_bbox is None:
                world_bbox = self._sprite_bbox_world(sprite, geo, local_idx)
            if world_bbox:
                self._paint_handles(painter, world_bbox)

    def _paint_grid(self, painter: QPainter, cr: Optional[tuple] = None):
        cx, cy, cw, ch = cr if cr is not None else self._canvas_rect()
        grid_world = self._grid_size_pct / 200.0
        if grid_world <= 0:
            return

        grid_pen = QPen(QColor(55, 55, 55))
        grid_pen.setWidthF(0.5)
        axis_pen = QPen(QColor(75, 75, 75))
        axis_pen.setWidthF(1.0)

        n = math.ceil(1.0 / grid_world) + 1
        for step in range(-n, n + 1):
            x_world = step * grid_world
            if x_world < -1.0 - 1e-9 or x_world > 1.0 + 1e-9:
                continue
            sx, _ = self._world_to_screen(x_world, 0)
            painter.setPen(axis_pen if abs(x_world) < 1e-9 else grid_pen)
            painter.drawLine(int(sx), int(cy), int(sx), int(cy + ch))

        for step in range(-n, n + 1):
            y_world = step * grid_world
            if y_world < -1.0 - 1e-9 or y_world > 1.0 + 1e-9:
                continue
            _, sy = self._world_to_screen(0, y_world)
            painter.setPen(axis_pen if abs(y_world) < 1e-9 else grid_pen)
            painter.drawLine(int(cx), int(sy), int(cx + cw), int(sy))

        # Canvas border (world [-1,+1] rectangle)
        border_pen = QPen(QColor(255, 255, 255, 60))
        border_pen.setWidthF(1.0)
        painter.setPen(border_pen)
        painter.setBrush(Qt.BrushStyle.NoBrush)
        sx1, sy1 = self._world_to_screen(-1.0, 1.0)
        sx2, sy2 = self._world_to_screen(1.0, -1.0)
        painter.drawRect(QRectF(sx1, sy1, sx2 - sx1, sy2 - sy1))

    def _paint_placeholder(self, painter: QPainter, bbox, color: QColor):
        if bbox is None:
            return
        min_wx, min_wy, max_wx, max_wy = bbox
        sx1, sy1 = self._world_to_screen(min_wx, max_wy)
        sx2, sy2 = self._world_to_screen(max_wx, min_wy)
        fill = QColor(color.red(), color.green(), color.blue(), 50)
        stroke = QColor(color.red(), color.green(), color.blue(), 120)
        painter.fillRect(QRectF(sx1, sy1, sx2 - sx1, sy2 - sy1), fill)
        painter.setPen(QPen(stroke))
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawRect(QRectF(sx1, sy1, sx2 - sx1, sy2 - sy1))

    def _paint_handles(self, painter: QPainter, bbox: tuple):
        min_wx, min_wy, max_wx, max_wy = bbox
        sx1, sy1 = self._world_to_screen(min_wx, max_wy)
        sx2, sy2 = self._world_to_screen(max_wx, min_wy)

        dash_pen = QPen(QColor(200, 200, 200))
        dash_pen.setWidthF(1.0)
        dash_pen.setStyle(Qt.PenStyle.DashLine)
        painter.setPen(dash_pen)
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawRect(QRectF(sx1, sy1, sx2 - sx1, sy2 - sy1))

        handles = self._handle_positions(bbox)
        hs = self._HANDLE_SIZE
        half = hs / 2
        _ROTATE = {'TR', 'BL'}
        scale_brush = QBrush(QColor(255, 255, 255))
        rotate_brush = QBrush(QColor(255, 220, 0))
        painter.setPen(QPen(QColor(160, 160, 160)))
        for name, pos in handles.items():
            painter.setBrush(rotate_brush if name in _ROTATE else scale_brush)
            painter.drawRect(QRectF(pos.x() - half, pos.y() - half, hs, hs))

    # ── Mouse interaction ───────────────────────────────────────────────────

    def mousePressEvent(self, event):
        if event.button() != Qt.MouseButton.LeftButton:
            return
        ep = event.position()

        if self._sprite_set is None:
            return

        # If a sprite is selected, check handles first
        if 0 <= self._selected_index < len(self._sprite_set.sprites):
            sprite = self._sprite_set.sprites[self._selected_index]
            geo = (self._active_geo if self._active_geo is not None
                   else self._resolve_geometry(sprite))
            bbox = self._sprite_bbox_world(sprite, geo, self._selected_index)
            if bbox:
                handles = self._handle_positions(bbox)
                for h_name, h_pos in handles.items():
                    if math.hypot(ep.x() - h_pos.x(), ep.y() - h_pos.y()) <= self._HANDLE_HIT_RADIUS:
                        self._start_drag(ep, sprite, _HANDLE_MODES[h_name])
                        return
                if self._point_in_bbox_screen(ep, bbox):
                    self._start_drag(ep, sprite, 'move')
                    return

        # Don't allow selection changes from canvas clicks — use the tree instead

    def _try_select(self, pos: QPointF):
        """Select the sprite whose bounding box contains pos."""
        if self._sprite_set is None:
            return
        for i, sprite in enumerate(self._sprite_set.sprites):
            if not sprite.enabled:
                continue
            geo = self._resolve_geometry(sprite)
            bbox = self._sprite_bbox_world(sprite, geo, i)
            if bbox and self._point_in_bbox_screen(pos, bbox):
                old_idx = self._selected_index
                self._selected_index = i
                self.update()
                if old_idx != i:
                    self.selection_changed.emit(i)
                return

    def _point_in_bbox_screen(self, pos: QPointF, bbox: tuple) -> bool:
        min_wx, min_wy, max_wx, max_wy = bbox
        sx1, sy1 = self._world_to_screen(min_wx, max_wy)
        sx2, sy2 = self._world_to_screen(max_wx, min_wy)
        left, right = min(sx1, sx2), max(sx1, sx2)
        top, bottom = min(sy1, sy2), max(sy1, sy2)
        return left <= pos.x() <= right and top <= pos.y() <= bottom

    def _start_drag(self, pos: QPointF, sprite, mode: str):
        self._drag_mode = mode
        self._drag_start_screen = QPointF(pos)
        if self._active_params is not None:
            self._drag_start_params = self._active_params
        else:
            p = sprite.params
            self._drag_start_params = (p.location_x, p.location_y, p.size_x, p.size_y, p.start_rotation)

    def mouseMoveEvent(self, event):
        if self._drag_mode is None:
            return
        if self._sprite_set is None:
            return
        if not (0 <= self._selected_index < len(self._sprite_set.sprites)):
            return

        sprite = self._sprite_set.sprites[self._selected_index]
        ep = event.position()
        sp = self._drag_start_screen
        orig_loc_x, orig_loc_y, orig_size_x, orig_size_y, orig_rot = self._drag_start_params

        ppwx, ppwy = self._pixels_per_world()
        dx_w = (ep.x() - sp.x()) / ppwx
        dy_w = -(ep.y() - sp.y()) / ppwy   # Y flip

        centre_wx = orig_loc_x / 100.0
        centre_wy = orig_loc_y / 100.0
        start_wx, start_wy = self._screen_to_world(sp.x(), sp.y())
        curr_wx, curr_wy = self._screen_to_world(ep.x(), ep.y())

        new_loc_x, new_loc_y = orig_loc_x, orig_loc_y
        new_size_x, new_size_y = orig_size_x, orig_size_y
        new_rot = orig_rot

        mode = self._drag_mode
        if mode == 'move':
            new_loc_x = orig_loc_x + dx_w * 100
            new_loc_y = orig_loc_y + dy_w * 100
            if self._snap:
                snap = self._grid_size_pct
                new_loc_x = round(new_loc_x / snap) * snap
                new_loc_y = round(new_loc_y / snap) * snap
            new_loc_x = max(-200.0, min(200.0, new_loc_x))
            new_loc_y = max(-200.0, min(200.0, new_loc_y))

        elif mode == 'scale_xy':
            dist_start = math.hypot(start_wx - centre_wx, start_wy - centre_wy)
            if dist_start > 1e-6:
                dist_curr = math.hypot(curr_wx - centre_wx, curr_wy - centre_wy)
                ratio = dist_curr / dist_start
                new_size_x = max(0.001, min(10.0, orig_size_x * ratio))
                new_size_y = max(0.001, min(10.0, orig_size_y * ratio))

        elif mode == 'scale_x':
            dx_start = abs(start_wx - centre_wx)
            if dx_start > 1e-6:
                dx_curr = abs(curr_wx - centre_wx)
                new_size_x = max(0.001, min(10.0, orig_size_x * dx_curr / dx_start))

        elif mode == 'scale_y':
            dy_start = abs(start_wy - centre_wy)
            if dy_start > 1e-6:
                dy_curr = abs(curr_wy - centre_wy)
                new_size_y = max(0.001, min(10.0, orig_size_y * dy_curr / dy_start))

        elif mode == 'rotate':
            a_start = math.atan2(start_wy - centre_wy, start_wx - centre_wx)
            a_curr = math.atan2(curr_wy - centre_wy, curr_wx - centre_wx)
            delta_deg = math.degrees(a_curr - a_start)
            new_rot = (orig_rot + delta_deg) % 360

        if self._active_params is not None:
            self._active_params = (new_loc_x, new_loc_y, new_size_x, new_size_y, new_rot)
        else:
            p = sprite.params
            p.location_x = new_loc_x
            p.location_y = new_loc_y
            p.size_x = new_size_x
            p.size_y = new_size_y
            p.start_rotation = new_rot

        self.update()
        self.transform_changed.emit(new_loc_x, new_loc_y, new_size_x, new_size_y, new_rot)

    def mouseReleaseEvent(self, event):
        self._drag_mode = None


# ── Public container widget ───────────────────────────────────────────────────

class SpritePreviewWidget(QWidget):
    """Thin container: canvas + control strip."""

    transform_changed = Signal(float, float, float, float, float)
    # Emitted when user drags sprite in keyframe mode with Edit KF checked.
    # Args: (kf_0based_row, loc_x, loc_y, size_x, size_y, rotation)
    kf_transform_changed = Signal(int, float, float, float, float, float)

    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        self._canvas = SpritePreviewCanvas()
        layout.addWidget(self._canvas, stretch=1)

        # ── Control strip ─────────────────────────────────────────────────
        strip = QHBoxLayout()
        strip.addWidget(QLabel("Grid:"))
        self._grid_combo = QComboBox()
        self._grid_combo.addItems(["5%", "10%", "25%", "50%"])
        self._grid_combo.setCurrentIndex(1)
        strip.addWidget(self._grid_combo)
        strip.addSpacing(16)
        self._snap_check = QCheckBox("Snap to Grid")
        strip.addWidget(self._snap_check)
        strip.addSpacing(16)
        strip.addWidget(QLabel("KF:"))
        self._kf_combo = QComboBox()
        self._kf_combo.setMinimumWidth(55)
        self._kf_combo.setEnabled(False)
        strip.addWidget(self._kf_combo)
        strip.addSpacing(8)
        self._edit_kf_check = QCheckBox("Edit KF")
        self._edit_kf_check.setChecked(True)
        self._edit_kf_check.setEnabled(False)
        strip.addWidget(self._edit_kf_check)
        strip.addStretch()
        self._transform_label = QLabel("")
        self._transform_label.setStyleSheet(
            "color: #00dd00; font-weight: bold; background-color: #000000;"
            " padding: 2px 8px; font-family: monospace;"
        )
        strip.addWidget(self._transform_label)
        layout.addLayout(strip)

        # ── Widget state ──────────────────────────────────────────────────
        self._keyframes: list = []
        self._animator_type: str = "random"
        self._morph_targets: list = []

        # ── Connections ───────────────────────────────────────────────────
        self._grid_combo.currentIndexChanged.connect(self._on_grid_changed)
        self._snap_check.toggled.connect(self._canvas.set_snap)
        self._kf_combo.currentIndexChanged.connect(self._apply_kf_selection)
        self._canvas.transform_changed.connect(self._on_canvas_transform_changed)
        self._canvas.selection_changed.connect(self._on_canvas_selection_changed)

    # ── Grid ──────────────────────────────────────────────────────────────

    def _on_grid_changed(self, idx: int):
        pcts = [5.0, 10.0, 25.0, 50.0]
        if 0 <= idx < len(pcts):
            self._canvas.set_grid_size(pcts[idx])

    # ── Transform label ───────────────────────────────────────────────────

    def _update_transform_label(self, loc_x: float, loc_y: float,
                                 size_x: float, size_y: float, rot: float):
        self._transform_label.setText(
            f"p {loc_x:.1f}, {loc_y:.1f}  "
            f"s {size_x:.3g}, {size_y:.3g}  "
            f"r {rot:.1f}"
        )

    def _refresh_transform_label(self):
        ss = self._canvas._sprite_set
        sprite_idx = self._canvas._selected_index
        if ss is None or not (0 <= sprite_idx < len(ss.sprites)):
            self._transform_label.setText("")
            return
        kf_idx = self._kf_combo.currentIndex()
        kf_data_idx = kf_idx - 1
        p = ss.sprites[sprite_idx].params
        if self._kf_combo.isEnabled() and kf_data_idx >= 0 and kf_data_idx < len(self._keyframes):
            # Show combined display values (base + absolute KF offset) to match what is drawn
            kf = self._keyframes[kf_data_idx]
            disp_loc_x = p.location_x + kf.pos_x
            disp_loc_y = p.location_y + kf.pos_y
            disp_size_x = p.size_x * kf.scale_x
            disp_size_y = p.size_y * kf.scale_y
            disp_rot = p.start_rotation + kf.rotation
            self._update_transform_label(disp_loc_x, disp_loc_y, disp_size_x, disp_size_y, disp_rot)
        else:
            self._update_transform_label(p.location_x, p.location_y,
                                         p.size_x, p.size_y, p.start_rotation)

    def _on_canvas_transform_changed(self, loc_x: float, loc_y: float,
                                      size_x: float, size_y: float, rot: float):
        self._update_transform_label(loc_x, loc_y, size_x, size_y, rot)
        kf_idx = self._kf_combo.currentIndex()
        kf_data_idx = kf_idx - 1
        if self._kf_combo.isEnabled() and kf_data_idx >= 0 and kf_data_idx < len(self._keyframes):
            if self._edit_kf_check.isChecked():
                # The canvas loc_x/loc_y/size/rot are the COMBINED (base + absolute KF) values.
                # Convert back to raw KF values: kf.pos = canvas_pos - base_pos, etc.
                ss = self._canvas._sprite_set
                si = self._canvas._selected_index
                if ss is not None and 0 <= si < len(ss.sprites):
                    p = ss.sprites[si].params
                    kf_pos_x = loc_x - p.location_x
                    kf_pos_y = loc_y - p.location_y
                    kf_scale_x = (size_x / p.size_x) if p.size_x != 0 else size_x
                    kf_scale_y = (size_y / p.size_y) if p.size_y != 0 else size_y
                    kf_rot = rot - p.start_rotation
                else:
                    kf_pos_x, kf_pos_y = loc_x, loc_y
                    kf_scale_x, kf_scale_y = size_x, size_y
                    kf_rot = rot
                self.kf_transform_changed.emit(kf_data_idx, kf_pos_x, kf_pos_y,
                                               kf_scale_x, kf_scale_y, kf_rot)
        else:
            self.transform_changed.emit(loc_x, loc_y, size_x, size_y, rot)

    # ── Canvas-selection reset ────────────────────────────────────────────

    def _on_canvas_selection_changed(self, sprite_idx: int):
        """User clicked a different sprite in the canvas — clear stale KF state."""
        self._canvas.clear_active_state()
        self._kf_combo.blockSignals(True)
        self._kf_combo.clear()
        self._kf_combo.setEnabled(False)
        self._edit_kf_check.setEnabled(False)
        self._kf_combo.blockSignals(False)
        self._keyframes = []
        self._animator_type = "random"
        self._morph_targets = []
        self._transform_label.setText("")

    # ── Keyframe support ──────────────────────────────────────────────────

    def set_keyframes(self, keyframes: list, animator_type: str,
                      morph_targets: list = None):
        """Called by sprite_tab when the selected sprite (or its data) changes."""
        self._keyframes = sorted(keyframes, key=lambda k: k.draw_cycle) if keyframes else []
        self._animator_type = animator_type
        self._morph_targets = list(morph_targets) if morph_targets else []

        enabled = (animator_type in ("keyframe", "keyframe_morph") and bool(self._keyframes))
        self._kf_combo.blockSignals(True)
        self._kf_combo.clear()
        if enabled:
            self._kf_combo.addItem("—")   # index 0 = no KF / show base params
            for i in range(len(self._keyframes)):
                self._kf_combo.addItem(str(i + 1))
            self._kf_combo.setCurrentIndex(0)  # start at "—" → sprites at params position
        self._kf_combo.setEnabled(enabled)
        self._edit_kf_check.setEnabled(enabled)
        self._kf_combo.blockSignals(False)
        self._apply_kf_selection()

    def _apply_kf_selection(self):
        """Sync canvas active state to the selected KF entry.

        Index 0 in the combo is the "—" sentinel → show sprites at base params (home state).
        Actual keyframes start at combo index 1 → self._keyframes[0].

        KF posX/posY/scaleX/scaleY/rotation are ABSOLUTE offsets from the sprite's base params:
          display_loc_x  = base.location_x  + kf.pos_x
          display_loc_y  = base.location_y  + kf.pos_y
          display_size_x = base.size_x      * kf.scale_x
          display_size_y = base.size_y      * kf.scale_y
          display_rot    = base.start_rotation + kf.rotation
        """
        idx = self._kf_combo.currentIndex()
        if not self._kf_combo.isEnabled() or idx <= 0:
            self._canvas.clear_active_state()
            self._refresh_transform_label()
            return
        kf_idx = idx - 1
        if kf_idx >= len(self._keyframes):
            self._canvas.clear_active_state()
            self._refresh_transform_label()
            return
        kf = self._keyframes[kf_idx]
        geo = (self._load_morph_geo_for_keyframe(kf)
               if self._animator_type == "keyframe_morph" else None)

        # KF values are absolute offsets from the sprite's base params.
        ss = self._canvas._sprite_set
        si = self._canvas._selected_index
        if ss is not None and 0 <= si < len(ss.sprites):
            p = ss.sprites[si].params
            loc_x = p.location_x + kf.pos_x
            loc_y = p.location_y + kf.pos_y
            size_x = p.size_x * kf.scale_x
            size_y = p.size_y * kf.scale_y
            rotation = p.start_rotation + kf.rotation
        else:
            loc_x, loc_y = kf.pos_x, kf.pos_y
            size_x, size_y = kf.scale_x, kf.scale_y
            rotation = kf.rotation

        self._canvas.set_active_state(loc_x, loc_y, size_x, size_y, rotation, geo)
        self._refresh_transform_label()

    def _load_morph_geo_for_keyframe(self, kf) -> Optional[ParsedGeo]:
        """Load the morph target geometry for kf.morph_amount.

        morph_amount: 0=base, 1=mt1, 2=mt2; fractional values blend adjacent targets.
        Preview snaps to nearest integer target (int truncation): 0.x → base, 1.x → mt1, etc.
        """
        mt_idx = int(kf.morph_amount) - 1   # morph_amount 1→index 0, 2→index 1, …
        # Clamp to valid range; morph_amount=N.0 at boundary still shows the last target
        mt_idx = min(mt_idx, len(self._morph_targets) - 1)
        if mt_idx < 0 or mt_idx >= len(self._morph_targets):
            return None
        poly_dir = self._canvas._polygon_sets_dir
        if not poly_dir:
            return None
        morph_dir = os.path.join(os.path.dirname(poly_dir.rstrip(os.sep)), 'morphTargets')
        ref = self._morph_targets[mt_idx]
        filepath = os.path.join(morph_dir, ref.file)
        if not os.path.isfile(filepath):
            return None
        try:
            tree = ET.parse(filepath, parser=ET.XMLParser(encoding='utf-8'))
            return _parse_geo_from_root(tree.getroot())
        except Exception:
            return None

    # ── Public setters ────────────────────────────────────────────────────

    def set_canvas_size(self, w: int, h: int):
        self._canvas.set_canvas_size(w, h)

    def set_sprite_set(self, sprite_set, selected_index: int):
        self._canvas.clear_active_state()
        self._canvas.set_sprite_set(sprite_set, selected_index)
        self._refresh_transform_label()

    def set_selected_index(self, index: int):
        # Clear stale KF state; sprite_tab will call set_keyframes next to re-arm it
        self._canvas.clear_active_state()
        self._kf_combo.blockSignals(True)
        self._kf_combo.clear()
        self._kf_combo.setEnabled(False)
        self._edit_kf_check.setEnabled(False)
        self._kf_combo.blockSignals(False)
        self._keyframes = []
        self._animator_type = "random"
        self._morph_targets = []
        self._canvas.set_selected_index(index)
        self._refresh_transform_label()

    def set_sprite_library(self, lib):
        self._canvas.set_sprite_library(lib)

    def refresh_for_params_change(self, canvas_index: int):
        """Called when sprite base params change.

        Updates the canvas selected index and re-applies the current KF combo
        selection (if any) with the new base params — without resetting the combo.
        """
        self._canvas.set_selected_index(canvas_index)
        self._apply_kf_selection()
        self._refresh_transform_label()

    def set_directories(self, poly_dir: str, curve_dir: str, point_dir: str,
                        oval_dir: str = "", regular_dir: str = ""):
        self._canvas.set_directories(poly_dir, curve_dir, point_dir, oval_dir, regular_dir)
