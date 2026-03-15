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

from PyQt6.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout, QLabel, QComboBox, QCheckBox
from PyQt6.QtCore import pyqtSignal, Qt, QPointF, QRectF
from PyQt6.QtGui import QPainter, QPen, QColor, QPainterPath, QBrush


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

    transform_changed = pyqtSignal(float, float, float, float, float)

    _HANDLE_SIZE = 8
    _HANDLE_HIT_RADIUS = 6
    _MARGIN = 20

    def __init__(self, parent=None):
        super().__init__(parent)
        self._sprite_set = None
        self._selected_index: int = -1
        self._shape_library = None
        self._polygon_sets_dir: str = ""
        self._curve_sets_dir: str = ""
        self._point_sets_dir: str = ""
        self._geo_cache: dict[str, Optional[ParsedGeo]] = {}
        self._grid_size_pct: float = 10.0
        self._snap: bool = False
        # Drag state
        self._drag_mode: Optional[str] = None
        self._drag_start_screen: QPointF = QPointF()
        self._drag_start_params: tuple = (0.0, 0.0, 1.0, 1.0, 0.0)
        self.setMouseTracking(True)
        self.setMinimumSize(300, 300)

    # ── Public setters ─────────────────────────────────────────────────────

    def set_sprite_set(self, sprite_set, selected_index: int):
        self._sprite_set = sprite_set
        self._selected_index = selected_index
        self.update()

    def set_selected_index(self, index: int):
        self._selected_index = index
        self.update()

    def set_shape_library(self, lib):
        self._shape_library = lib
        self._geo_cache.clear()
        self.update()

    def set_directories(self, poly_dir: str, curve_dir: str, point_dir: str):
        self._polygon_sets_dir = poly_dir
        self._curve_sets_dir = curve_dir
        self._point_sets_dir = point_dir
        self._geo_cache.clear()
        self.update()

    def set_grid_size(self, pct: float):
        self._grid_size_pct = pct
        self.update()

    def set_snap(self, snap: bool):
        self._snap = snap

    # ── Coordinate helpers ──────────────────────────────────────────────────

    def _world_to_screen(self, wx: float, wy: float) -> tuple[float, float]:
        r = self.rect()
        m = self._MARGIN
        dw = r.width() - 2 * m
        dh = r.height() - 2 * m
        sx = (wx + 1) / 2 * dw + m
        sy = (1 - wy) / 2 * dh + m
        return sx, sy

    def _screen_to_world(self, sx: float, sy: float) -> tuple[float, float]:
        r = self.rect()
        m = self._MARGIN
        dw = r.width() - 2 * m
        dh = r.height() - 2 * m
        wx = (sx - m) / dw * 2 - 1
        wy = 1 - (sy - m) / dh * 2
        return wx, wy

    def _pixels_per_world(self) -> tuple[float, float]:
        r = self.rect()
        m = self._MARGIN
        return (r.width() - 2 * m) / 2.0, (r.height() - 2 * m) / 2.0

    # ── Geometry resolution ─────────────────────────────────────────────────

    def _resolve_geometry(self, sprite) -> Optional[ParsedGeo]:
        """Look up and cache geometry for a sprite. Returns None on failure."""
        if self._shape_library is None:
            return None
        try:
            from models.shape_config import ShapeSourceType
            # Find the ShapeSet
            shape_set = None
            for ss in self._shape_library.shape_sets:
                if ss.name == sprite.shape_set_name:
                    shape_set = ss
                    break
            if shape_set is None:
                return None

            shape_def = shape_set.get(sprite.shape_name)
            if shape_def is None:
                return None

            stype = shape_def.source_type
            if stype == ShapeSourceType.REGULAR_POLYGON:
                n = max(3, shape_def.regular_polygon_sides)
                return _make_ngon(n)

            if stype == ShapeSourceType.POLYGON_SET:
                name = shape_def.polygon_set_name
                base_dir = self._polygon_sets_dir
            elif stype == ShapeSourceType.OPEN_CURVE_SET:
                name = shape_def.open_curve_set_name
                base_dir = self._curve_sets_dir
            elif stype == ShapeSourceType.POINT_SET:
                name = shape_def.point_set_name
                base_dir = self._point_sets_dir
            else:
                return None

            if not name or not base_dir:
                return None

            filepath = os.path.join(base_dir, name + ".xml")
            if filepath in self._geo_cache:
                return self._geo_cache[filepath]

            if not os.path.isfile(filepath):
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
                    rotation_deg: float) -> QPainterPath:
        """Build a QPainterPath from ParsedGeo in screen space."""
        path = QPainterPath()

        def pt_screen(px, py):
            wx, wy = self._transform_point(px, py, loc_x, loc_y, size_x, size_y, rotation_deg)
            return self._world_to_screen(wx, wy)

        for poly_idx, anchors in enumerate(geo.anchor_polys):
            if not anchors:
                continue
            beziers = geo.ctrl_polys[poly_idx] if poly_idx < len(geo.ctrl_polys) else []
            closed = geo.closed_flags[poly_idx] if poly_idx < len(geo.closed_flags) else True
            sx, sy = pt_screen(anchors[0][0], anchors[0][1])
            path.moveTo(sx, sy)
            if beziers:
                for c1x, c1y, c2x, c2y, a1x, a1y in beziers:
                    sc1x, sc1y = pt_screen(c1x, c1y)
                    sc2x, sc2y = pt_screen(c2x, c2y)
                    sa1x, sa1y = pt_screen(a1x, a1y)
                    path.cubicTo(sc1x, sc1y, sc2x, sc2y, sa1x, sa1y)
            else:
                for a in anchors[1:]:
                    sx, sy = pt_screen(a[0], a[1])
                    path.lineTo(sx, sy)
            if closed:
                path.closeSubpath()

        return path

    def _sprite_bbox_world(self, sprite, geo: Optional[ParsedGeo]) -> Optional[tuple]:
        """Compute bounding box (min_wx, min_wy, max_wx, max_wy) in world coords."""
        p = sprite.params
        loc_x, loc_y = p.location_x, p.location_y
        size_x, size_y = p.size_x, p.size_y
        rot = p.start_rotation

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

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        w, h = self.width(), self.height()
        painter.fillRect(0, 0, w, h, QColor(28, 28, 28))
        self._paint_grid(painter)

        if self._sprite_set is None:
            painter.end()
            return

        for i, sprite in enumerate(self._sprite_set.sprites):
            if not sprite.enabled:
                continue
            geo = self._resolve_geometry(sprite)
            p = sprite.params
            is_selected = (i == self._selected_index)

            if geo is not None and (geo.anchor_polys or geo.dot_positions):
                dot_color = QColor(80, 200, 120) if is_selected else QColor(140, 140, 140)
                if geo.anchor_polys:
                    path = self._build_path(geo, p.location_x, p.location_y,
                                            p.size_x, p.size_y, p.start_rotation)
                    if is_selected:
                        pen = QPen(QColor(80, 200, 120))
                        pen.setWidthF(1.5)
                    else:
                        pen = QPen(QColor(100, 100, 100))
                        pen.setWidthF(1.0)
                    painter.setPen(pen)
                    painter.setBrush(Qt.BrushStyle.NoBrush)
                    painter.drawPath(path)
                if geo.dot_positions:
                    painter.setPen(Qt.PenStyle.NoPen)
                    painter.setBrush(QBrush(dot_color))
                    for dpx, dpy in geo.dot_positions:
                        wx, wy = self._transform_point(dpx, dpy, p.location_x, p.location_y,
                                                       p.size_x, p.size_y, p.start_rotation)
                        dsx, dsy = self._world_to_screen(wx, wy)
                        painter.drawEllipse(QPointF(dsx, dsy), 4, 4)
            else:
                self._paint_placeholder(painter, self._sprite_bbox_world(sprite, None), is_selected)

            if is_selected:
                bbox = self._sprite_bbox_world(sprite, geo)
                if bbox:
                    self._paint_handles(painter, bbox)

        painter.end()

    def _paint_grid(self, painter: QPainter):
        m = self._MARGIN
        r = self.rect()
        dw = r.width() - 2 * m
        dh = r.height() - 2 * m
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
            painter.drawLine(int(sx), m, int(sx), m + int(dh))

        for step in range(-n, n + 1):
            y_world = step * grid_world
            if y_world < -1.0 - 1e-9 or y_world > 1.0 + 1e-9:
                continue
            _, sy = self._world_to_screen(0, y_world)
            painter.setPen(axis_pen if abs(y_world) < 1e-9 else grid_pen)
            painter.drawLine(m, int(sy), m + int(dw), int(sy))

        # Canvas border (world [-1,+1] rectangle)
        border_pen = QPen(QColor(255, 255, 255, 60))
        border_pen.setWidthF(1.0)
        painter.setPen(border_pen)
        painter.setBrush(Qt.BrushStyle.NoBrush)
        sx1, sy1 = self._world_to_screen(-1.0, 1.0)
        sx2, sy2 = self._world_to_screen(1.0, -1.0)
        painter.drawRect(QRectF(sx1, sy1, sx2 - sx1, sy2 - sy1))

    def _paint_placeholder(self, painter: QPainter, bbox, is_selected: bool):
        if bbox is None:
            return
        min_wx, min_wy, max_wx, max_wy = bbox
        sx1, sy1 = self._world_to_screen(min_wx, max_wy)
        sx2, sy2 = self._world_to_screen(max_wx, min_wy)
        if is_selected:
            fill = QColor(80, 200, 120, 50)
            stroke = QColor(80, 200, 120, 120)
        else:
            fill = QColor(100, 100, 100, 30)
            stroke = QColor(100, 100, 100, 70)
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
            geo = self._resolve_geometry(sprite)
            bbox = self._sprite_bbox_world(sprite, geo)
            if bbox:
                handles = self._handle_positions(bbox)
                for h_name, h_pos in handles.items():
                    if math.hypot(ep.x() - h_pos.x(), ep.y() - h_pos.y()) <= self._HANDLE_HIT_RADIUS:
                        self._start_drag(ep, sprite, _HANDLE_MODES[h_name])
                        return
                if self._point_in_bbox_screen(ep, bbox):
                    self._start_drag(ep, sprite, 'move')
                    return

        self._try_select(ep)

    def _try_select(self, pos: QPointF):
        """Select the sprite whose bounding box contains pos."""
        if self._sprite_set is None:
            return
        for i, sprite in enumerate(self._sprite_set.sprites):
            if not sprite.enabled:
                continue
            geo = self._resolve_geometry(sprite)
            bbox = self._sprite_bbox_world(sprite, geo)
            if bbox and self._point_in_bbox_screen(pos, bbox):
                self._selected_index = i
                self.update()
                return

    def _point_in_bbox_screen(self, pos: QPointF, bbox: tuple) -> bool:
        min_wx, min_wy, max_wx, max_wy = bbox
        sx1, sy1 = self._world_to_screen(min_wx, max_wy)
        sx2, sy2 = self._world_to_screen(max_wx, min_wy)
        left, right = min(sx1, sx2), max(sx1, sx2)
        top, bottom = min(sy1, sy2), max(sy1, sy2)
        return left <= pos.x() <= right and top <= pos.y() <= bottom

    def _start_drag(self, pos: QPointF, sprite, mode: str):
        p = sprite.params
        self._drag_mode = mode
        self._drag_start_screen = QPointF(pos)
        self._drag_start_params = (p.location_x, p.location_y, p.size_x, p.size_y, p.start_rotation)

    def mouseMoveEvent(self, event):
        if self._drag_mode is None:
            return
        if self._sprite_set is None:
            return
        if not (0 <= self._selected_index < len(self._sprite_set.sprites)):
            return

        sprite = self._sprite_set.sprites[self._selected_index]
        p = sprite.params
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

        mode = self._drag_mode
        if mode == 'move':
            new_loc_x = orig_loc_x + dx_w * 100
            new_loc_y = orig_loc_y + dy_w * 100
            if self._snap:
                snap = self._grid_size_pct
                new_loc_x = round(new_loc_x / snap) * snap
                new_loc_y = round(new_loc_y / snap) * snap
            p.location_x = max(-200.0, min(200.0, new_loc_x))
            p.location_y = max(-200.0, min(200.0, new_loc_y))

        elif mode == 'scale_xy':
            dist_start = math.hypot(start_wx - centre_wx, start_wy - centre_wy)
            if dist_start > 1e-6:
                dist_curr = math.hypot(curr_wx - centre_wx, curr_wy - centre_wy)
                ratio = dist_curr / dist_start
                p.size_x = max(0.001, min(10.0, orig_size_x * ratio))
                p.size_y = max(0.001, min(10.0, orig_size_y * ratio))

        elif mode == 'scale_x':  # L or R handle: horizontal drag changes size_x
            dx_start = abs(start_wx - centre_wx)
            if dx_start > 1e-6:
                dx_curr = abs(curr_wx - centre_wx)
                p.size_x = max(0.001, min(10.0, orig_size_x * dx_curr / dx_start))

        elif mode == 'scale_y':  # T or B handle: vertical drag changes size_y
            dy_start = abs(start_wy - centre_wy)
            if dy_start > 1e-6:
                dy_curr = abs(curr_wy - centre_wy)
                p.size_y = max(0.001, min(10.0, orig_size_y * dy_curr / dy_start))

        elif mode == 'rotate':
            a_start = math.atan2(start_wy - centre_wy, start_wx - centre_wx)
            a_curr = math.atan2(curr_wy - centre_wy, curr_wx - centre_wx)
            delta_deg = math.degrees(a_curr - a_start)
            p.start_rotation = (orig_rot + delta_deg) % 360

        self.update()
        self.transform_changed.emit(p.location_x, p.location_y, p.size_x, p.size_y, p.start_rotation)

    def mouseReleaseEvent(self, event):
        self._drag_mode = None


# ── Public container widget ───────────────────────────────────────────────────

class SpritePreviewWidget(QWidget):
    """Thin container: canvas + control strip."""

    transform_changed = pyqtSignal(float, float, float, float, float)

    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        self._canvas = SpritePreviewCanvas()
        layout.addWidget(self._canvas, stretch=1)

        strip = QHBoxLayout()
        strip.addWidget(QLabel("Grid:"))
        self._grid_combo = QComboBox()
        self._grid_combo.addItems(["5%", "10%", "25%", "50%"])
        self._grid_combo.setCurrentIndex(1)   # default 10%
        strip.addWidget(self._grid_combo)
        strip.addSpacing(16)
        self._snap_check = QCheckBox("Snap to Grid")
        strip.addWidget(self._snap_check)
        strip.addStretch()
        layout.addLayout(strip)

        self._grid_combo.currentIndexChanged.connect(self._on_grid_changed)
        self._snap_check.toggled.connect(self._canvas.set_snap)
        self._canvas.transform_changed.connect(self.transform_changed)

    def _on_grid_changed(self, idx: int):
        pcts = [5.0, 10.0, 25.0, 50.0]
        if 0 <= idx < len(pcts):
            self._canvas.set_grid_size(pcts[idx])

    def set_sprite_set(self, sprite_set, selected_index: int):
        self._canvas.set_sprite_set(sprite_set, selected_index)

    def set_selected_index(self, index: int):
        self._canvas.set_selected_index(index)

    def set_shape_library(self, lib):
        self._canvas.set_shape_library(lib)

    def set_directories(self, poly_dir: str, curve_dir: str, point_dir: str):
        self._canvas.set_directories(poly_dir, curve_dir, point_dir)
