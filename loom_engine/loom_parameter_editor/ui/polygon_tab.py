"""
Polygon configuration tab for the parameter editor.
Provides UI for editing polygons.xml settings.
"""
from __future__ import annotations
import os
import re
import shutil
import xml.etree.ElementTree as ET
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QSpinBox, QDoubleSpinBox, QComboBox, QTreeWidget,
    QTreeWidgetItem, QPushButton, QSplitter, QLabel, QStackedWidget,
    QMessageBox, QInputDialog, QFileDialog, QCheckBox, QSizePolicy
)
from PySide6.QtCore import Signal, Qt, QProcess, QFileSystemWatcher
from PySide6.QtGui import QFont, QPainter, QPen, QColor, QPainterPath, QBrush
from PySide6.QtWidgets import QStyledItemDelegate
from models.polygon_config import (
    PolygonSourceType, PolygonType, RegularPolygonParams,
    FileSource, PolygonSetDef, PolygonSetLibrary
)
from models.sprite_config import SpriteDef, SpriteSet, GeoSourceType
from models.subdivision_config import SubdivisionParams, SubdivisionParamsSet, SubdivisionType
from models.rendering import Renderer, RendererSet
from models.constants import RenderMode
from file_io.regular_polygon_io import RegularPolygonIO
from ui.regular_polygon_dialog import RegularPolygonDialog

_COL_ORANGE = QColor("#CC6600")   # editing-only (layers manifest / non-usable layer files)
_COL_GREEN  = QColor("#1A6B1A")   # usable by Loom
_COL_SEL_GREEN = "#1A6B1A"        # CSS string for selected convenience-combo text


class _FilenameDelegate(QStyledItemDelegate):
    """Item delegate that forces ForegroundRole colour rendering on macOS native combos."""

    def initStyleOption(self, option, index):
        super().initStyleOption(option, index)
        brush = index.data(Qt.ItemDataRole.ForegroundRole)
        if brush is not None:
            color = brush.color() if hasattr(brush, 'color') else brush
            option.palette.setColor(option.palette.ColorRole.Text, color)

BEZIER_PY        = "/Users/broganbunt/Loom_2026/bezier_py/main.py"
PYTHON           = "/Users/broganbunt/Loom_2026/loom_engine/loom_parameter_editor/.venv/bin/python"
_BEZIER_RESOURCES = "/Users/broganbunt/Loom_2026/bezier/resources"

POLYGONS_LIBRARY_DIR = os.path.expanduser("~/.loom_projects/polygons_library")


class PolygonPreviewWidget(QWidget):
    """Renders a visual preview of a spline or line polygon set XML file."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._anchor_polys: list[list[tuple[float, float]]] = []
        self._ctrl_polys: list[list[tuple[float, float, float, float, float, float]]] = []
        self._closed_flags: list[bool] = []
        self._has_bezier = False
        self._dot_positions: list[tuple[float, float]] = []
        self._oval_defs: list[tuple[float, float, float, float]] = []  # (cx, cy, rx, ry)
        self.setMinimumHeight(120)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        self.setToolTip("Polygon set shape preview")

    def clear(self):
        self._anchor_polys = []
        self._ctrl_polys = []
        self._closed_flags = []
        self._has_bezier = False
        self._dot_positions = []
        self._oval_defs = []
        self.update()

    def load_regular_polygon(self, params) -> None:
        """Generate a preview from RegularPolygonParams using the makePolygon2DStar algorithm."""
        import math
        self._anchor_polys = []
        self._ctrl_polys = []
        self._closed_flags = []
        self._has_bezier = False
        self._dot_positions = []
        self._oval_defs = []
        n = max(params.total_points, 3)
        total_verts = n * 2
        ang_inc = 360.0 / total_verts
        outer_r = 0.5
        inner_r = params.internal_radius

        # Build outer points (even indices): start at (0, -outer_r), rotate by 2*ang_inc each step
        outer = {}
        outer[0] = (0.0, -outer_r)
        for i in range(2, total_verts, 2):
            px, py = outer[i - 2]
            a = math.radians(2 * ang_inc)
            ca, sa = math.cos(a), math.sin(a)
            outer[i] = (px * ca - py * sa, px * sa + py * ca)

        # Build inner points (odd indices): start at (0, -inner_r) rotated by synch angle
        synch_angle = ang_inc * params.synch_multiplier
        if not params.positive_synch:
            synch_angle = -synch_angle
        cs, ss = math.cos(math.radians(synch_angle)), math.sin(math.radians(synch_angle))
        inner = {}
        bx, by = 0.0, -inner_r
        inner[1] = (bx * cs - by * ss, bx * ss + by * cs)
        for i in range(3, total_verts, 2):
            px, py = inner[i - 2]
            a = math.radians(2 * ang_inc)
            ca, sa = math.cos(a), math.sin(a)
            inner[i] = (px * ca - py * sa, px * sa + py * ca)

        # Interleave outer/inner, apply offset rotation + scale
        pts = []
        for i in range(total_verts):
            x, y = outer[i] if i % 2 == 0 else inner[i]
            if params.offset != 0.0:
                co, so = math.cos(math.radians(params.offset)), math.sin(math.radians(params.offset))
                x, y = x * co - y * so, x * so + y * co
            pts.append((x * params.scale_x, y * params.scale_y))

        # Apply rotation_angle
        if params.rotation_angle != 0.0:
            cr, sr = math.cos(math.radians(params.rotation_angle)), math.sin(math.radians(params.rotation_angle))
            pts = [(x * cr - y * sr, x * sr + y * cr) for x, y in pts]

        # Apply translation (relative to 0.5, 0.5 centre)
        tx, ty = params.trans_x - 0.5, params.trans_y - 0.5
        if tx != 0.0 or ty != 0.0:
            pts = [(x + tx, y + ty) for x, y in pts]

        if pts:
            self._anchor_polys = [pts]
            self._ctrl_polys = [[]]
            self._closed_flags = [True]
        self.update()

    def load_polygon_set(self, filepath: str, filter_open: bool = False) -> None:
        self._anchor_polys = []
        self._ctrl_polys = []
        self._closed_flags = []
        self._has_bezier = False
        self._dot_positions = []
        self._oval_defs = []
        if not filepath or not os.path.isfile(filepath):
            self.update()
            return
        try:
            tree = ET.parse(filepath, parser=ET.XMLParser(encoding='utf-8'))
            root = tree.getroot()
            self._parse(root)
        except Exception:
            pass
        if filter_open:
            filtered = [(a, c, cl) for a, c, cl in
                        zip(self._anchor_polys, self._ctrl_polys, self._closed_flags) if cl]
            if filtered:
                self._anchor_polys, self._ctrl_polys, self._closed_flags = map(list, zip(*filtered))
            else:
                self._anchor_polys, self._ctrl_polys, self._closed_flags = [], [], []
        self.update()

    # ── XML parsing ───────────────────────────────────────────────────────

    @staticmethod
    def _xy(elem) -> tuple[float, float] | None:
        try:
            return float(elem.get('x', '')), float(elem.get('y', ''))
        except (ValueError, TypeError):
            return None

    def _parse(self, root) -> None:
        """Try to extract polygon outlines.  Three strategies are attempted in order:
        1. Per-curve structure  (<curve> with child anchor/ctrl elements)
        2. Flat interleaved structure  (every 4th element is an anchor point)
        3. All x/y pairs  (LINE_POLYGON or fallback)
        Also handles <pointSet> root with direct <point x y/> children.
        """
        # Handle ovalSet: collect <oval cx cy rx ry/> elements
        if root.tag == 'ovalSet':
            for oval_el in root.findall('oval'):
                try:
                    cx = float(oval_el.get('cx', '0'))
                    cy = float(oval_el.get('cy', '0'))
                    rx = float(oval_el.get('rx', '0.1'))
                    ry = float(oval_el.get('ry', '0.1'))
                    self._oval_defs.append((cx, cy, rx, ry))
                except (ValueError, TypeError):
                    pass
            return

        # Handle pointSet: collect top-level <point> elements as dots
        if root.tag == 'pointSet':
            for pt in root.findall('point'):
                xy = self._xy(pt)
                if xy:
                    self._dot_positions.append(xy)
            return

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

            # Strategy 1: look for <curve> children
            curves = [c for c in children if c.tag.lower() in ('curve', 'cubicCurve', 'edge')]
            if curves:
                anchors, beziers = self._parse_curves(curves)
                if anchors:
                    self._anchor_polys.append(anchors)
                    self._ctrl_polys.append(beziers)
                    self._closed_flags.append(is_closed)
                    self._has_bezier = bool(beziers)
                continue

            # Strategy 2: flat list — assume anchor, ctrl1, ctrl2, anchor pattern
            all_pts = []
            for child in poly_elem.iter():
                p = self._xy(child)
                if p:
                    all_pts.append((p, child.tag.lower()))

            if len(all_pts) >= 4 and len(all_pts) % 4 == 0:
                anchors, beziers = self._parse_flat_spline(all_pts)
                if anchors:
                    self._anchor_polys.append(anchors)
                    self._ctrl_polys.append(beziers)
                    self._closed_flags.append(is_closed)
                    self._has_bezier = bool(beziers)
                    continue

            # Strategy 3: just connect whatever x/y pairs we find
            simple = [p for p, _ in all_pts]
            if len(simple) >= 2:
                self._anchor_polys.append(simple)
                self._ctrl_polys.append([])
                self._closed_flags.append(is_closed)

    def _parse_curves(self, curves):
        """Parse a list of <curve> elements each containing 4 child points."""
        anchors = []
        beziers = []
        for curve in curves:
            pts = []
            for child in curve:
                p = self._xy(child)
                if p:
                    pts.append(p)
            if len(pts) < 4:
                continue
            a0, c1, c2, a1 = pts[0], pts[1], pts[2], pts[3]
            if not anchors:
                anchors.append(a0)
            anchors.append(a1)
            beziers.append((c1[0], c1[1], c2[0], c2[1], a1[0], a1[1]))
        return anchors, beziers

    def _parse_flat_spline(self, all_pts):
        """Interpret a flat list of 4N points as N cubic bezier curves."""
        anchors = []
        beziers = []
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

    # ── Painting ──────────────────────────────────────────────────────────

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        w, h = self.width(), self.height()

        painter.fillRect(0, 0, w, h, QColor(28, 28, 28))

        # Render discrete point set (dots)
        if self._dot_positions:
            all_x = [p[0] for p in self._dot_positions]
            all_y = [p[1] for p in self._dot_positions]
            min_x, max_x = min(all_x), max(all_x)
            min_y, max_y = min(all_y), max(all_y)
            dx = max_x - min_x or 1.0
            dy = max_y - min_y or 1.0
            margin = 16
            scale = min((w - 2 * margin) / dx, (h - 2 * margin) / dy)
            ox = margin + ((w - 2 * margin) - dx * scale) / 2 - min_x * scale
            oy = margin + ((h - 2 * margin) - dy * scale) / 2 - min_y * scale
            painter.setBrush(QColor(255, 0, 255, 200))
            painter.setPen(Qt.PenStyle.NoPen)
            r = 4
            for (px, py) in self._dot_positions:
                cx = int(px * scale + ox)
                cy = int(py * scale + oy)
                painter.drawEllipse(cx - r, cy - r, r * 2, r * 2)
            return

        # Render oval set
        if self._oval_defs:
            all_x = [cx - rx for cx, cy, rx, ry in self._oval_defs] + \
                    [cx + rx for cx, cy, rx, ry in self._oval_defs]
            all_y = [cy - ry for cx, cy, rx, ry in self._oval_defs] + \
                    [cy + ry for cx, cy, rx, ry in self._oval_defs]
            min_x, max_x = min(all_x), max(all_x)
            min_y, max_y = min(all_y), max(all_y)
            dx = max_x - min_x or 1.0
            dy = max_y - min_y or 1.0
            margin = 16
            sc = min((w - 2 * margin) / dx, (h - 2 * margin) / dy)
            ox = margin + ((w - 2 * margin) - dx * sc) / 2 - min_x * sc
            oy = margin + ((h - 2 * margin) - dy * sc) / 2 - min_y * sc
            painter.setPen(QPen(QColor(80, 200, 120), 1.5))
            painter.setBrush(Qt.BrushStyle.NoBrush)
            for (cx, cy, rx, ry) in self._oval_defs:
                scx = cx * sc + ox
                scy = cy * sc + oy
                srx = rx * sc
                sry = ry * sc
                painter.drawEllipse(int(scx - srx), int(scy - sry),
                                    int(srx * 2), int(sry * 2))
            return

        if not self._anchor_polys:
            painter.setPen(QColor(90, 90, 90))
            painter.drawText(self.rect(), Qt.AlignmentFlag.AlignCenter, "No preview")
            return

        # Bounding box across all polygons
        all_x = [p[0] for poly in self._anchor_polys for p in poly]
        all_y = [p[1] for poly in self._anchor_polys for p in poly]
        min_x, max_x = min(all_x), max(all_x)
        min_y, max_y = min(all_y), max(all_y)
        dx = max_x - min_x or 1.0
        dy = max_y - min_y or 1.0

        margin = 16
        scale = min((w - 2 * margin) / dx, (h - 2 * margin) / dy)
        ox = margin + ((w - 2 * margin) - dx * scale) / 2 - min_x * scale
        oy = margin + ((h - 2 * margin) - dy * scale) / 2 - min_y * scale

        def sx(px): return px * scale + ox
        def sy(py): return py * scale + oy

        painter.setPen(QPen(QColor(80, 200, 120), 1.5))

        for anchors, beziers, is_closed in zip(self._anchor_polys, self._ctrl_polys, self._closed_flags):
            if len(anchors) < 2:
                continue
            path = QPainterPath()
            path.moveTo(sx(anchors[0][0]), sy(anchors[0][1]))
            if beziers and len(beziers) == len(anchors) - 1:
                for (c1x, c1y, c2x, c2y, ax, ay) in beziers:
                    path.cubicTo(sx(c1x), sy(c1y), sx(c2x), sy(c2y), sx(ax), sy(ay))
            else:
                for pt in anchors[1:]:
                    path.lineTo(sx(pt[0]), sy(pt[1]))
            if is_closed:
                path.closeSubpath()
            painter.drawPath(path)

