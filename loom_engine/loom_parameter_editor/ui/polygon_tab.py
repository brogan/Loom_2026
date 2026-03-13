"""
Polygon configuration tab for the parameter editor.
Provides UI for editing polygons.xml settings.
"""
from __future__ import annotations
import os
import shutil
import xml.etree.ElementTree as ET
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QSpinBox, QDoubleSpinBox, QComboBox, QTreeWidget,
    QTreeWidgetItem, QPushButton, QSplitter, QLabel, QStackedWidget,
    QMessageBox, QInputDialog, QFileDialog, QCheckBox, QSizePolicy
)
from PyQt6.QtCore import pyqtSignal, Qt, QProcess
from PyQt6.QtGui import QFont, QPainter, QPen, QColor, QPainterPath
from models.polygon_config import (
    PolygonSourceType, PolygonType, RegularPolygonParams,
    FileSource, PolygonSetDef, PolygonSetLibrary
)
from file_io.regular_polygon_io import RegularPolygonIO
from ui.regular_polygon_dialog import RegularPolygonDialog

BEZIER_JAR = "/Users/broganbunt/Loom_2026/bezier/out/artifacts/Bezier_jar/Bezier.jar"
BEZIER_WORKING_DIR = "/Users/broganbunt/Loom_2026/bezier"

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
        self.setMinimumHeight(200)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self.setToolTip("Polygon set shape preview")

    def clear(self):
        self._anchor_polys = []
        self._ctrl_polys = []
        self._closed_flags = []
        self._has_bezier = False
        self._dot_positions = []
        self.update()

    def load_polygon_set(self, filepath: str) -> None:
        self._anchor_polys = []
        self._ctrl_polys = []
        self._closed_flags = []
        self._has_bezier = False
        self._dot_positions = []
        if not filepath or not os.path.isfile(filepath):
            self.update()
            return
        try:
            tree = ET.parse(filepath, parser=ET.XMLParser(encoding='utf-8'))
            root = tree.getroot()
            self._parse(root)
        except Exception:
            pass
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


class PolygonTab(QWidget):
    """Tab widget for editing polygon configuration."""

    modified = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._library = PolygonSetLibrary.default()
        self._current_set: PolygonSetDef = None
        self._updating = False
        self._checking = False
        self._polygon_sets_dir: str = ""
        self._regular_polygons_dir: str = ""
        self._bezier_process: QProcess = None
        self._pre_launch_files: set = set()
        self._shape_library = None
        self._sprite_library = None

        self._setup_ui()
        self._refresh_list()

    def _setup_ui(self):
        """Set up the UI layout."""
        main_layout = QHBoxLayout(self)

        # Create splitter for left panel and right panel
        splitter = QSplitter(Qt.Orientation.Horizontal)
        main_layout.addWidget(splitter)

        # Left panel - polygon set list
        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)

        left_layout.addWidget(QLabel("Polygon Sets:"))

        self.set_list = QTreeWidget()
        # Col 0: narrow checkbox-only; Col 1: Name; Col 2: Shapes; Col 3: Sprites
        self.set_list.setHeaderLabels(["", "Name", "Shapes", "Sprites"])
        self.set_list.setRootIsDecorated(False)
        self.set_list.setColumnWidth(0, 22)   # checkbox column — just wide enough
        self.set_list.setColumnWidth(1, 130)
        self.set_list.setColumnWidth(2, 50)
        self.set_list.setColumnWidth(3, 50)
        self.set_list.header().setStretchLastSection(False)
        self.set_list.currentItemChanged.connect(self._on_set_selected)
        self.set_list.itemChanged.connect(self._on_item_check_changed)
        left_layout.addWidget(self.set_list)

        bold_font = QFont()
        bold_font.setBold(True)

        # Spline Polygon Sets section
        spline_label = QLabel("Spline Polygon Sets")
        spline_label.setFont(bold_font)
        left_layout.addWidget(spline_label)

        spline_btn_layout = QHBoxLayout()
        self.create_polygon_btn = QPushButton("Create")
        self.create_polygon_btn.setToolTip("Launch Bezier to create a new spline polygon set")
        self.create_polygon_btn.clicked.connect(self._create_polygon_set)
        spline_btn_layout.addWidget(self.create_polygon_btn)

        self.import_polygon_btn = QPushButton("Import")
        self.import_polygon_btn.setToolTip("Import a polygon set file from another location")
        self.import_polygon_btn.clicked.connect(self._import_polygon_set)
        spline_btn_layout.addWidget(self.import_polygon_btn)
        left_layout.addLayout(spline_btn_layout)

        # Regular Polygons section
        regular_label = QLabel("Regular Polygons")
        regular_label.setFont(bold_font)
        left_layout.addWidget(regular_label)

        regular_btn_layout = QHBoxLayout()
        self.create_regular_btn = QPushButton("Create")
        self.create_regular_btn.setToolTip("Create a new regular polygon with live preview")
        self.create_regular_btn.clicked.connect(self._create_regular_polygon)
        regular_btn_layout.addWidget(self.create_regular_btn)

        self.import_regular_btn = QPushButton("Import")
        self.import_regular_btn.setToolTip("Import a regular polygon XML file")
        self.import_regular_btn.clicked.connect(self._import_regular_polygon)
        regular_btn_layout.addWidget(self.import_regular_btn)
        left_layout.addLayout(regular_btn_layout)

        # Manage section
        manage_label = QLabel("Manage")
        manage_label.setFont(bold_font)
        left_layout.addWidget(manage_label)

        manage_btn_layout = QHBoxLayout()
        self.delete_btn = QPushButton("Delete")
        self.delete_btn.setToolTip("Permanently delete checked polygon set files from the project")
        self.delete_btn.clicked.connect(self._delete_deep_selected)
        manage_btn_layout.addWidget(self.delete_btn)

        self.move_btn = QPushButton("Move")
        self.move_btn.setToolTip("Move checked polygon set files to another directory")
        self.move_btn.clicked.connect(self._move_selected)
        manage_btn_layout.addWidget(self.move_btn)
        manage_btn_layout.addStretch()
        left_layout.addLayout(manage_btn_layout)

        splitter.addWidget(left_panel)

        # Right panel - properties editor
        right_panel = QWidget()
        right_layout = QVBoxLayout(right_panel)

        # Name
        name_group = QGroupBox("Polygon Set")
        name_layout = QFormLayout(name_group)

        self.name_edit = QLineEdit()
        self.name_edit.textChanged.connect(self._on_name_changed)
        name_layout.addRow("Name:", self.name_edit)

        self.source_type_combo = QComboBox()
        self.source_type_combo.addItems(["File Reference", "Regular Polygon"])
        self.source_type_combo.currentIndexChanged.connect(self._on_source_type_changed)
        name_layout.addRow("Source Type:", self.source_type_combo)

        right_layout.addWidget(name_group)

        # Stacked widget for source-specific editors
        self.source_stack = QStackedWidget()

        # File source editor
        self.file_editor = self._create_file_editor()
        self.source_stack.addWidget(self.file_editor)

        # Regular polygon editor
        self.regular_editor = self._create_regular_editor()
        self.source_stack.addWidget(self.regular_editor)

        right_layout.addWidget(self.source_stack)
        right_layout.addStretch()

        splitter.addWidget(right_panel)
        splitter.setSizes([250, 550])

    def _create_file_editor(self) -> QWidget:
        """Create the file source editor widget."""
        widget = QWidget()
        layout = QVBoxLayout(widget)

        group = QGroupBox("File Source")
        form = QFormLayout(group)

        self.folder_edit = QLineEdit()
        self.folder_edit.textChanged.connect(self._on_modified)
        form.addRow("Folder:", self.folder_edit)

        # Filename as dropdown populated from polygonSets directory
        self.filename_combo = QComboBox()
        self.filename_combo.setEditable(True)  # Allow custom entry if file not in list
        self.filename_combo.currentTextChanged.connect(self._on_modified)
        self.filename_combo.currentTextChanged.connect(self._update_preview)
        form.addRow("Filename:", self.filename_combo)

        # Edit and Refresh buttons
        file_btn_layout = QHBoxLayout()
        self.edit_polygon_btn = QPushButton("Edit Polygon Set")
        self.edit_polygon_btn.clicked.connect(self._edit_polygon_set)
        file_btn_layout.addWidget(self.edit_polygon_btn)

        self.refresh_files_btn = QPushButton("Refresh File List")
        self.refresh_files_btn.clicked.connect(self._refresh_file_list)
        file_btn_layout.addStretch()
        file_btn_layout.addWidget(self.refresh_files_btn)
        form.addRow("", file_btn_layout)

        self.poly_type_combo = QComboBox()
        self.poly_type_combo.addItems(["SPLINE_POLYGON", "LINE_POLYGON"])
        self.poly_type_combo.currentTextChanged.connect(self._on_modified)
        form.addRow("Polygon Type:", self.poly_type_combo)

        layout.addWidget(group)

        # Preview panel
        preview_group = QGroupBox("Preview")
        preview_layout = QVBoxLayout(preview_group)
        preview_layout.setContentsMargins(4, 4, 4, 4)
        self.preview_widget = PolygonPreviewWidget()
        preview_layout.addWidget(self.preview_widget)
        layout.addWidget(preview_group)

        layout.addStretch()
        return widget

    def _create_regular_editor(self) -> QWidget:
        """Create the regular polygon parameters editor widget."""
        widget = QWidget()
        layout = QVBoxLayout(widget)

        group = QGroupBox("Regular Polygon Parameters")
        form = QFormLayout(group)

        self.total_points_spin = QSpinBox()
        self.total_points_spin.setRange(3, 64)
        self.total_points_spin.valueChanged.connect(self._on_modified)
        form.addRow("Total Points:", self.total_points_spin)

        self.internal_radius_spin = QDoubleSpinBox()
        self.internal_radius_spin.setRange(0.01, 10.0)
        self.internal_radius_spin.setDecimals(3)
        self.internal_radius_spin.setSingleStep(0.1)
        self.internal_radius_spin.valueChanged.connect(self._on_modified)
        form.addRow("Internal Radius:", self.internal_radius_spin)

        self.offset_spin = QDoubleSpinBox()
        self.offset_spin.setRange(-360.0, 360.0)
        self.offset_spin.setDecimals(1)
        self.offset_spin.valueChanged.connect(self._on_modified)
        form.addRow("Offset:", self.offset_spin)

        # Scale
        scale_layout = QHBoxLayout()
        self.scale_x_spin = QDoubleSpinBox()
        self.scale_x_spin.setRange(0.01, 10.0)
        self.scale_x_spin.setDecimals(3)
        self.scale_x_spin.setSingleStep(0.1)
        self.scale_x_spin.valueChanged.connect(self._on_modified)
        scale_layout.addWidget(QLabel("X:"))
        scale_layout.addWidget(self.scale_x_spin)

        self.scale_y_spin = QDoubleSpinBox()
        self.scale_y_spin.setRange(0.01, 10.0)
        self.scale_y_spin.setDecimals(3)
        self.scale_y_spin.setSingleStep(0.1)
        self.scale_y_spin.valueChanged.connect(self._on_modified)
        scale_layout.addWidget(QLabel("Y:"))
        scale_layout.addWidget(self.scale_y_spin)
        form.addRow("Scale:", scale_layout)

        self.rotation_spin = QDoubleSpinBox()
        self.rotation_spin.setRange(-360.0, 360.0)
        self.rotation_spin.setDecimals(1)
        self.rotation_spin.valueChanged.connect(self._on_modified)
        form.addRow("Rotation Angle:", self.rotation_spin)

        # Translation
        trans_layout = QHBoxLayout()
        self.trans_x_spin = QDoubleSpinBox()
        self.trans_x_spin.setRange(-10.0, 10.0)
        self.trans_x_spin.setDecimals(3)
        self.trans_x_spin.setSingleStep(0.1)
        self.trans_x_spin.valueChanged.connect(self._on_modified)
        trans_layout.addWidget(QLabel("X:"))
        trans_layout.addWidget(self.trans_x_spin)

        self.trans_y_spin = QDoubleSpinBox()
        self.trans_y_spin.setRange(-10.0, 10.0)
        self.trans_y_spin.setDecimals(3)
        self.trans_y_spin.setSingleStep(0.1)
        self.trans_y_spin.valueChanged.connect(self._on_modified)
        trans_layout.addWidget(QLabel("Y:"))
        trans_layout.addWidget(self.trans_y_spin)
        form.addRow("Translation:", trans_layout)

        self.positive_synch_check = QCheckBox("Positive")
        self.positive_synch_check.setChecked(True)
        self.positive_synch_check.toggled.connect(self._on_modified)
        form.addRow("Synch Direction:", self.positive_synch_check)

        self.synch_multiplier_spin = QDoubleSpinBox()
        self.synch_multiplier_spin.setRange(0.0, 10.0)
        self.synch_multiplier_spin.setDecimals(2)
        self.synch_multiplier_spin.setSingleStep(0.1)
        self.synch_multiplier_spin.valueChanged.connect(self._on_modified)
        form.addRow("Synch Multiplier:", self.synch_multiplier_spin)

        # Edit button to open dialog with live preview
        edit_btn_layout = QHBoxLayout()
        self.edit_regular_btn = QPushButton("Edit in Dialog...")
        self.edit_regular_btn.setToolTip("Open the regular polygon editor with live preview")
        self.edit_regular_btn.clicked.connect(self._edit_regular_polygon)
        edit_btn_layout.addWidget(self.edit_regular_btn)
        edit_btn_layout.addStretch()
        form.addRow("", edit_btn_layout)

        layout.addWidget(group)
        layout.addStretch()
        return widget

    def _refresh_list(self):
        """Refresh the polygon set list."""
        # Remember the currently selected name so we can restore it
        selected_name = None
        current = self.set_list.currentItem()
        if current:
            ps = current.data(0, Qt.ItemDataRole.UserRole)
            if ps:
                selected_name = ps.name

        self._checking = True
        self.set_list.clear()
        counts = self._compute_usage_counts()
        restore_item = None
        for ps in self._library.polygon_sets:
            shape_count, sprite_count = counts.get(ps.name, (0, 0))
            # Col 0 = checkbox only (no text); Col 1 = Name; Col 2 = Shapes; Col 3 = Sprites
            item = QTreeWidgetItem(["", ps.name, str(shape_count), str(sprite_count)])
            item.setData(0, Qt.ItemDataRole.UserRole, ps)   # store ref on the checkbox col
            item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
            item.setCheckState(0, Qt.CheckState.Unchecked)
            item.setTextAlignment(2, Qt.AlignmentFlag.AlignCenter)
            item.setTextAlignment(3, Qt.AlignmentFlag.AlignCenter)
            self.set_list.addTopLevelItem(item)
            if ps.name == selected_name:
                restore_item = item
        self._checking = False

        if restore_item:
            self.set_list.setCurrentItem(restore_item)
        elif self.set_list.topLevelItemCount() > 0:
            self.set_list.setCurrentItem(self.set_list.topLevelItem(0))

    def _on_set_selected(self, current, previous):
        """Handle polygon set selection."""
        if current is None:
            self._current_set = None
            self._clear_ui()
            return

        self._current_set = current.data(0, Qt.ItemDataRole.UserRole)
        self._load_set_to_ui(self._current_set)

    def _on_item_check_changed(self, item, column):
        """Guard against recursive signals during programmatic refresh."""
        if self._checking:
            return

    def _clear_ui(self):
        """Clear all property fields when no polygon set is selected."""
        self._updating = True
        try:
            self.name_edit.clear()
            self.source_type_combo.setCurrentIndex(0)
            self.source_stack.setCurrentIndex(0)
            self.folder_edit.clear()
            self.filename_combo.setCurrentText("")
            self.poly_type_combo.setCurrentIndex(0)
            self.total_points_spin.setValue(3)
            self.internal_radius_spin.setValue(1.0)
            self.offset_spin.setValue(0.0)
            self.scale_x_spin.setValue(1.0)
            self.scale_y_spin.setValue(1.0)
            self.rotation_spin.setValue(0.0)
            self.trans_x_spin.setValue(0.0)
            self.trans_y_spin.setValue(0.0)
            self.positive_synch_check.setChecked(True)
            self.synch_multiplier_spin.setValue(1.0)
        finally:
            self._updating = False

    def _load_set_to_ui(self, polygon_set: PolygonSetDef):
        """Load a polygon set's values into the UI."""
        self._updating = True
        try:
            self.name_edit.setText(polygon_set.name)

            if polygon_set.source_type == PolygonSourceType.FILE:
                self.source_type_combo.setCurrentIndex(0)
                self.source_stack.setCurrentIndex(0)
                if polygon_set.file_source:
                    self.folder_edit.setText(polygon_set.file_source.folder)
                    self.filename_combo.setCurrentText(polygon_set.file_source.filename)
                    self.poly_type_combo.setCurrentText(polygon_set.file_source.polygon_type.value)
            else:
                self.source_type_combo.setCurrentIndex(1)
                self.source_stack.setCurrentIndex(1)
                if polygon_set.regular_params:
                    params = polygon_set.regular_params
                    self.total_points_spin.setValue(params.total_points)
                    self.internal_radius_spin.setValue(params.internal_radius)
                    self.offset_spin.setValue(params.offset)
                    self.scale_x_spin.setValue(params.scale_x)
                    self.scale_y_spin.setValue(params.scale_y)
                    self.rotation_spin.setValue(params.rotation_angle)
                    self.trans_x_spin.setValue(params.trans_x)
                    self.trans_y_spin.setValue(params.trans_y)
                    self.positive_synch_check.setChecked(params.positive_synch)
                    self.synch_multiplier_spin.setValue(params.synch_multiplier)
        finally:
            self._updating = False

        self._update_preview()

    def _save_ui_to_set(self):
        """Save UI values back to the current polygon set."""
        if self._current_set is None:
            return

        self._current_set.name = self.name_edit.text()

        if self.source_type_combo.currentIndex() == 0:  # File
            self._current_set.source_type = PolygonSourceType.FILE
            if self._current_set.file_source is None:
                self._current_set.file_source = FileSource()
            self._current_set.file_source.folder = self.folder_edit.text()
            self._current_set.file_source.filename = self.filename_combo.currentText()
            try:
                self._current_set.file_source.polygon_type = PolygonType(self.poly_type_combo.currentText())
            except ValueError:
                self._current_set.file_source.polygon_type = PolygonType.SPLINE_POLYGON
        else:  # Regular
            self._current_set.source_type = PolygonSourceType.REGULAR
            if self._current_set.regular_params is None:
                self._current_set.regular_params = RegularPolygonParams()
            params = self._current_set.regular_params
            params.total_points = self.total_points_spin.value()
            params.internal_radius = self.internal_radius_spin.value()
            params.offset = self.offset_spin.value()
            params.scale_x = self.scale_x_spin.value()
            params.scale_y = self.scale_y_spin.value()
            params.rotation_angle = self.rotation_spin.value()
            params.trans_x = self.trans_x_spin.value()
            params.trans_y = self.trans_y_spin.value()
            params.positive_synch = self.positive_synch_check.isChecked()
            params.synch_multiplier = self.synch_multiplier_spin.value()

        # Update list item text
        current_item = self.set_list.currentItem()
        if current_item:
            current_item.setText(1, self._current_set.name)

    def _on_name_changed(self):
        """Handle name change."""
        if self._updating:
            return
        self._save_ui_to_set()
        self.modified.emit()

    def _on_source_type_changed(self, index):
        """Handle source type change."""
        self.source_stack.setCurrentIndex(index)
        if not self._updating:
            self._save_ui_to_set()
            self.modified.emit()

    def _on_modified(self):
        """Handle any value change."""
        if self._updating:
            return
        self._save_ui_to_set()
        self.modified.emit()

    def _create_regular_polygon(self):
        """Create a new regular polygon via dialog with live preview."""
        if not self._regular_polygons_dir:
            QMessageBox.warning(self, "No Project",
                                "Please save the project first.")
            return

        dialog = RegularPolygonDialog(self)
        if dialog.exec() != RegularPolygonDialog.DialogCode.Accepted:
            return

        name, params = dialog.get_result()
        if not name:
            QMessageBox.warning(self, "No Name", "Name cannot be empty.")
            return

        if self._library.get_polygon_set(name):
            QMessageBox.warning(self, "Duplicate Name",
                                f"A polygon set named '{name}' already exists.")
            return

        # Save XML to regularPolygons/
        os.makedirs(self._regular_polygons_dir, exist_ok=True)
        filepath = os.path.join(self._regular_polygons_dir, f"{name}.xml")
        RegularPolygonIO.save(name, params, filepath)

        new_set = PolygonSetDef(
            name=name,
            source_type=PolygonSourceType.REGULAR,
            regular_params=params
        )
        self._library.add_polygon_set(new_set)
        self._refresh_list()
        last = self.set_list.topLevelItem(self.set_list.topLevelItemCount() - 1)
        if last:
            self.set_list.setCurrentItem(last)
        self.modified.emit()

    def _import_regular_polygon(self):
        """Import a regular polygon XML file."""
        if not self._regular_polygons_dir:
            QMessageBox.warning(self, "No Project",
                                "Please save the project first.")
            return

        default_dir = os.path.expanduser("~/.loom_projects/")
        if not os.path.isdir(default_dir):
            default_dir = os.path.expanduser("~")

        filepath, _ = QFileDialog.getOpenFileName(
            self, "Import Regular Polygon", default_dir,
            "XML Files (*.xml);;All Files (*)"
        )
        if not filepath:
            return

        try:
            name, params = RegularPolygonIO.load(filepath)
        except Exception as e:
            QMessageBox.critical(self, "Parse Error",
                                 f"Failed to parse regular polygon file:\n{e}")
            return

        if not name:
            name = os.path.splitext(os.path.basename(filepath))[0]

        # Copy file to regularPolygons/
        os.makedirs(self._regular_polygons_dir, exist_ok=True)
        dest = os.path.join(self._regular_polygons_dir, os.path.basename(filepath))
        if os.path.abspath(filepath) != os.path.abspath(dest):
            shutil.copy2(filepath, dest)

        # Strip XML headers if present
        self._strip_xml_headers(dest)

        if self._library.get_polygon_set(name):
            # Make unique name
            base = name
            counter = 1
            while self._library.get_polygon_set(name):
                name = f"{base}_{counter}"
                counter += 1

        new_set = PolygonSetDef(
            name=name,
            source_type=PolygonSourceType.REGULAR,
            regular_params=params
        )
        self._library.add_polygon_set(new_set)
        self._refresh_list()
        last = self.set_list.topLevelItem(self.set_list.topLevelItemCount() - 1)
        if last:
            self.set_list.setCurrentItem(last)
        self.modified.emit()

    def _edit_regular_polygon(self):
        """Open the regular polygon dialog pre-filled with current params."""
        if self._current_set is None or self._current_set.source_type != PolygonSourceType.REGULAR:
            return
        if self._current_set.regular_params is None:
            return

        dialog = RegularPolygonDialog(
            self, self._current_set.name, self._current_set.regular_params
        )
        if dialog.exec() != RegularPolygonDialog.DialogCode.Accepted:
            return

        name, params = dialog.get_result()
        if not name:
            return

        self._current_set.name = name
        self._current_set.regular_params = params
        self._load_set_to_ui(self._current_set)

        # Update list item text
        current_item = self.set_list.currentItem()
        if current_item:
            current_item.setText(1, name)

        # Save XML to regularPolygons/ if directory exists
        if self._regular_polygons_dir:
            os.makedirs(self._regular_polygons_dir, exist_ok=True)
            filepath = os.path.join(self._regular_polygons_dir, f"{name}.xml")
            RegularPolygonIO.save(name, params, filepath)

        self.modified.emit()

    def set_regular_polygons_directory(self, directory: str) -> None:
        """Set the directory for regular polygon asset files."""
        self._regular_polygons_dir = directory

    def get_library(self) -> PolygonSetLibrary:
        """Get the current library."""
        return self._library

    def set_library(self, library: PolygonSetLibrary) -> None:
        """Set the library to display."""
        self._library = library
        self._refresh_list()

    def create_default_library(self) -> PolygonSetLibrary:
        """Create a default library."""
        return PolygonSetLibrary.default()

    def _update_preview(self) -> None:
        """Refresh the polygon preview from the currently-selected filename."""
        if not hasattr(self, 'preview_widget'):
            return
        fname = self.filename_combo.currentText() if hasattr(self, 'filename_combo') else ""
        if fname and self._polygon_sets_dir:
            fpath = os.path.join(self._polygon_sets_dir, fname)
            self.preview_widget.load_polygon_set(fpath)
        else:
            self.preview_widget.clear()

    # ── Shared-file check ────────────────────────────────────────────────

    def _file_is_shared(self, ps, checked_set_ids: set) -> bool:
        """Return True if ps's file is also referenced by a non-checked library entry."""
        if (ps.source_type != PolygonSourceType.FILE
                or not ps.file_source or not ps.file_source.filename):
            return False
        fname = ps.file_source.filename
        return any(
            id(other) not in checked_set_ids
            and other.source_type == PolygonSourceType.FILE
            and other.file_source
            and other.file_source.filename == fname
            for other in self._library.polygon_sets
        )

    # ── Deep-delete ──────────────────────────────────────────────────────

    def _delete_deep_selected(self) -> None:
        """Delete checked polygon sets: remove files from disk AND from the library.

        If the referenced file is also used by a different (unchecked) entry,
        only the library entry is removed — the file is left untouched.
        """
        checked = self._get_checked_sets()
        if not checked:
            QMessageBox.information(self, "No Selection",
                                    "Check one or more polygon sets to delete.")
            return

        checked_ids = {id(ps) for ps in checked}

        # Classify each checked entry
        will_delete_file: list[tuple] = []   # (ps, fname) — file will be removed
        entry_only: list = []                # ps — only library entry removed

        for ps in checked:
            if (ps.source_type == PolygonSourceType.FILE
                    and ps.file_source and ps.file_source.filename
                    and self._polygon_sets_dir
                    and os.path.isfile(os.path.join(self._polygon_sets_dir,
                                                    ps.file_source.filename))
                    and not self._file_is_shared(ps, checked_ids)):
                will_delete_file.append((ps, ps.file_source.filename))
            else:
                entry_only.append(ps)

        # Build an informative warning listing exactly what will happen
        lines = []
        if will_delete_file:
            lines.append("Files that will be PERMANENTLY DELETED from disk:")
            for ps, fname in will_delete_file:
                base = os.path.splitext(fname)[0]
                svg_path = os.path.join(self._polygon_sets_dir, base + ".svg")
                files_str = fname + (f" + {base}.svg" if os.path.isfile(svg_path) else "")
                lines.append(f"  \u2022 {ps.name}  \u2192  {files_str}")
        if entry_only:
            if lines:
                lines.append("")
            lines.append("Library entries to be removed (files kept \u2014 shared or not on disk):")
            for ps in entry_only:
                fname = (ps.file_source.filename if ps.file_source
                         else "(regular polygon)")
                lines.append(f"  \u2022 {ps.name}  \u2192  {fname}")
        lines.append("\nThis cannot be undone.")

        result = QMessageBox.warning(
            self, "Permanently Delete Polygon Sets", "\n".join(lines),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No
        )
        if result != QMessageBox.StandardButton.Yes:
            return

        errors = []
        for ps, fname in will_delete_file:
            base = os.path.splitext(fname)[0]
            for fn in [fname, base + ".svg"]:
                fpath = os.path.join(self._polygon_sets_dir, fn)
                if os.path.isfile(fpath):
                    try:
                        os.remove(fpath)
                    except OSError as e:
                        errors.append(f"{fn}: {e}")
            self._library.remove_polygon_set(ps.name)

        for ps in entry_only:
            self._library.remove_polygon_set(ps.name)

        if errors:
            QMessageBox.warning(self, "Delete Errors",
                                "Some files could not be deleted:\n" + "\n".join(errors))
        self._current_set = None
        self._refresh_list()
        self.modified.emit()

    # ── Move ─────────────────────────────────────────────────────────────

    def _move_selected(self) -> None:
        """Move checked polygon set files to a chosen directory.

        If the referenced file is also used by a different (unchecked) entry,
        only the library entry is removed — the file is left untouched.
        """
        checked = [ps for ps in self._get_checked_sets()
                   if ps.source_type == PolygonSourceType.FILE
                   and ps.file_source and ps.file_source.filename]
        if not checked:
            QMessageBox.information(self, "No Selection",
                                    "Check one or more file-type polygon sets to move.")
            return

        checked_ids = {id(ps) for ps in checked}

        # Ensure default library directory exists
        os.makedirs(POLYGONS_LIBRARY_DIR, exist_ok=True)

        dest_dir = QFileDialog.getExistingDirectory(
            self, "Move Polygon Sets To — New Folder button creates sub-directories",
            POLYGONS_LIBRARY_DIR,
            QFileDialog.Option.ShowDirsOnly | QFileDialog.Option.DontUseNativeDialog
        )
        if not dest_dir:
            return

        os.makedirs(dest_dir, exist_ok=True)
        errors = []
        moved = []
        skipped_shared = []

        for ps in checked:
            if self._file_is_shared(ps, checked_ids):
                # File is used by another entry — only remove this library entry
                skipped_shared.append(ps)
                self._library.remove_polygon_set(ps.name)
                continue

            base = os.path.splitext(ps.file_source.filename)[0]
            for fn in [ps.file_source.filename, base + ".svg"]:
                src = os.path.join(self._polygon_sets_dir, fn)
                if os.path.isfile(src):
                    dst = os.path.join(dest_dir, fn)
                    try:
                        shutil.move(src, dst)
                    except Exception as e:
                        errors.append(f"{fn}: {e}")
            moved.append(ps.name)
            self._library.remove_polygon_set(ps.name)

        if errors:
            QMessageBox.warning(self, "Move Errors",
                                "Some files could not be moved:\n" + "\n".join(errors))
        msg_parts = []
        if moved:
            msg_parts.append(f"Moved {len(moved)} polygon set(s) to:\n{dest_dir}")
        if skipped_shared:
            names = ", ".join(ps.name for ps in skipped_shared)
            msg_parts.append(
                f"The following entries were removed from the library but their files "
                f"were NOT moved because they are shared with other entries: {names}"
            )
        if msg_parts:
            QMessageBox.information(self, "Move Complete", "\n\n".join(msg_parts))

        self._current_set = None
        self._refresh_list()
        self.modified.emit()

    def _get_checked_sets(self) -> list:
        """Return a list of PolygonSetDef objects whose list item is checked."""
        result = []
        for i in range(self.set_list.topLevelItemCount()):
            item = self.set_list.topLevelItem(i)
            if item.checkState(0) == Qt.CheckState.Checked:
                ps = item.data(0, Qt.ItemDataRole.UserRole)
                if ps:
                    result.append(ps)
        return result

    def set_shape_library(self, library) -> None:
        """Set the shape library used to compute per-polygon-set shape usage counts."""
        self._shape_library = library
        self._refresh_list()

    def set_sprite_library(self, library) -> None:
        """Set the sprite library used to compute per-polygon-set sprite usage counts."""
        self._sprite_library = library
        self._refresh_list()

    def _compute_usage_counts(self) -> dict:
        """Return {polygon_set_name: (shape_count, sprite_count)} for all polygon sets."""
        shape_counts: dict[str, int] = {}
        sprite_counts: dict[str, int] = {}

        # Shape counts: one per ShapeDef that references each polygon set
        if self._shape_library is not None:
            for shape_set in getattr(self._shape_library, 'shape_sets', []):
                for shape in getattr(shape_set, 'shapes', []):
                    name = getattr(shape, 'polygon_set_name', '')
                    if name:
                        shape_counts[name] = shape_counts.get(name, 0) + 1

        # Sprite counts: number of SpriteDefs whose shape_set_name maps back to
        # a ShapeSet that uses each polygon set.
        if self._sprite_library is not None and self._shape_library is not None:
            # Build map: shape_set_name → set of polygon_set_names it uses
            shape_set_to_polys: dict[str, set] = {}
            for shape_set in getattr(self._shape_library, 'shape_sets', []):
                polys = set()
                for shape in getattr(shape_set, 'shapes', []):
                    name = getattr(shape, 'polygon_set_name', '')
                    if name:
                        polys.add(name)
                if polys:
                    shape_set_to_polys[shape_set.name] = polys

            for sprite_set in getattr(self._sprite_library, 'sprite_sets', []):
                for sprite in getattr(sprite_set, 'sprites', []):
                    ssn = getattr(sprite, 'shape_set_name', '')
                    for poly_name in shape_set_to_polys.get(ssn, set()):
                        sprite_counts[poly_name] = sprite_counts.get(poly_name, 0) + 1

        all_names = set(shape_counts) | set(sprite_counts)
        return {n: (shape_counts.get(n, 0), sprite_counts.get(n, 0)) for n in all_names}

    def set_polygon_sets_directory(self, directory: str) -> None:
        """Set the directory to scan for polygon set files."""
        self._polygon_sets_dir = directory
        self._refresh_file_list()
        self._reconcile_polygon_sets()

    def _reconcile_polygon_sets(self) -> None:
        """Synchronise the library with the polygonSets directory.

        Step 1 — Remove stale entries: any FILE-type PolygonSetDef whose XML
                  file no longer exists on disk is removed from the library.
        Step 2 — Add new entries: any XML file in the directory not yet
                  referenced by a FILE-type library entry gets added.

        Calls _refresh_list() + modified.emit() only when the library changed.
        """
        if not self._polygon_sets_dir or not os.path.isdir(self._polygon_sets_dir):
            return

        changed = False

        # ── Step 1: remove stale FILE-type entries ─────────────────────────
        stale_names = []
        for ps in self._library.polygon_sets:
            if (ps.source_type == PolygonSourceType.FILE
                    and ps.file_source and ps.file_source.filename):
                fpath = os.path.join(self._polygon_sets_dir,
                                     ps.file_source.filename)
                if not os.path.isfile(fpath):
                    stale_names.append(ps.name)
        for name in stale_names:
            self._library.remove_polygon_set(name)
        if stale_names:
            changed = True

        # ── Step 2: build set of filenames still referenced ────────────────
        referenced_files = set()
        for ps in self._library.polygon_sets:
            if ps.source_type == PolygonSourceType.FILE and ps.file_source:
                referenced_files.add(ps.file_source.filename)

        # ── Step 3: add XML files not yet in the library ───────────────────
        try:
            all_files = sorted(os.listdir(self._polygon_sets_dir))
        except OSError:
            all_files = []

        for fname in all_files:
            if not fname.lower().endswith('.xml'):
                continue
            if fname in referenced_files:
                continue
            fpath = os.path.join(self._polygon_sets_dir, fname)
            if not os.path.isfile(fpath):
                continue

            name = self._parse_polygon_set_name(fpath)
            base_name = name
            counter = 1
            while self._library.get_polygon_set(name):
                name = f"{base_name}_{counter}"
                counter += 1

            self._library.add_polygon_set(PolygonSetDef(
                name=name,
                source_type=PolygonSourceType.FILE,
                file_source=FileSource(
                    folder="polygonSet",
                    filename=fname,
                    polygon_type=PolygonType.SPLINE_POLYGON
                )
            ))
            changed = True

        if changed:
            self._refresh_list()
            self.modified.emit()

    def _refresh_file_list(self) -> None:
        """Refresh the filename dropdown with files from the polygonSets directory."""
        # Block signals to prevent triggering _on_modified during refresh
        self._updating = True
        try:
            # Remember current selection
            current_text = self.filename_combo.currentText()

            self.filename_combo.clear()

            if self._polygon_sets_dir and os.path.isdir(self._polygon_sets_dir):
                # List all files with common polygon file extensions
                extensions = ('.xml', '.json', '.txt', '.poly')
                files = []
                try:
                    for f in os.listdir(self._polygon_sets_dir):
                        if os.path.isfile(os.path.join(self._polygon_sets_dir, f)):
                            if f.lower().endswith(extensions) or '.' not in f:
                                files.append(f)
                    files.sort()
                    self.filename_combo.addItems(files)
                except OSError:
                    pass  # Directory not accessible

            # Restore previous selection if it exists
            if current_text:
                index = self.filename_combo.findText(current_text)
                if index >= 0:
                    self.filename_combo.setCurrentIndex(index)
                else:
                    # If not found, set as custom text
                    self.filename_combo.setCurrentText(current_text)
        finally:
            self._updating = False

    # ── Bezier integration ──────────────────────────────────────────

    def _strip_xml_headers(self, filepath: str) -> None:
        """Remove XML declaration and DOCTYPE lines from a polygon set file."""
        with open(filepath, 'r', encoding='latin-1') as f:
            lines = f.readlines()
        cleaned = [l for l in lines
                   if not l.strip().startswith('<?xml')
                   and not l.strip().startswith('<!DOCTYPE')]
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(cleaned)

    def _add_xml_headers(self, filepath: str) -> None:
        """Add XML declaration and DOCTYPE lines required by Bezier's XOM parser.
        Also ensures the DTD file exists at the expected relative path."""
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        # Don't add if already present
        if content.lstrip().startswith('<?xml'):
            return
        header = ('<?xml version="1.0" encoding="ISO-8859-1"?>\n'
                  '<!DOCTYPE polygonSet SYSTEM "../dtd/polygonSet.dtd">\n')
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(header + content)

        # Ensure DTD is available at ../dtd/ relative to the XML file
        xml_dir = os.path.dirname(filepath)
        dtd_dir = os.path.join(os.path.dirname(xml_dir), "dtd")
        dtd_dest = os.path.join(dtd_dir, "polygonSet.dtd")
        if not os.path.isfile(dtd_dest):
            # Copy from Bezier's resources
            dtd_source = os.path.join(BEZIER_WORKING_DIR, "resources", "dtd", "polygonSet.dtd")
            if os.path.isfile(dtd_source):
                os.makedirs(dtd_dir, exist_ok=True)
                shutil.copy2(dtd_source, dtd_dest)

    def _add_xml_headers_layerset(self, filepath: str) -> None:
        """Add XML declaration for a .layers.xml manifest or layer XML file.
        Bezier loads these with a non-validating parser so no DOCTYPE is needed."""
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        if content.lstrip().startswith('<?xml'):
            return
        header = '<?xml version="1.0" encoding="ISO-8859-1"?>\n'
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(header + content)

    def _add_xml_headers_for_bundle_layers(self, layers_xml_path: str) -> None:
        """Add XML declarations to all layer XML files referenced in a .layers.xml manifest."""
        base_dir = os.path.dirname(layers_xml_path)
        try:
            tree = ET.parse(layers_xml_path)
            for layer_elem in tree.getroot().findall('layer'):
                file_elem = layer_elem.find('file')
                if file_elem is not None and file_elem.text:
                    fpath = os.path.join(base_dir, file_elem.text.strip())
                    if os.path.isfile(fpath):
                        self._add_xml_headers_layerset(fpath)
        except Exception:
            pass

    def _parse_layers_manifest_name(self, filepath: str) -> str:
        """Read <overallName> from a .layers.xml manifest."""
        try:
            tree = ET.parse(filepath)
            el = tree.getroot().find('overallName')
            return el.text.strip() if el is not None and el.text else ''
        except Exception:
            return ''

    def _parse_polygon_set_name(self, filepath: str) -> str:
        """Extract the <name> text from a polygon set XML file.
        Always strips .xml extension from the result."""
        name = None
        try:
            tree = ET.parse(filepath, parser=ET.XMLParser(encoding='utf-8'))
            name_elem = tree.find('name')
            if name_elem is not None and name_elem.text:
                name = name_elem.text.strip()
        except Exception:
            pass
        if not name:
            # Fallback: use filename without extension
            name = os.path.splitext(os.path.basename(filepath))[0]
        # Strip .xml extension if present in the name
        if name.lower().endswith('.xml'):
            name = name[:-4]
        return name

    def _snapshot_polygon_files(self) -> set:
        """Return the set of filenames currently in the polygonSets directory."""
        if not self._polygon_sets_dir or not os.path.isdir(self._polygon_sets_dir):
            return set()
        return set(os.listdir(self._polygon_sets_dir))

    def _auto_populate_fields(self, filename: str, filepath: str) -> None:
        """Auto-populate the current polygon set fields from a new/imported file."""
        name = self._parse_polygon_set_name(filepath)

        # If no polygon set is selected, create one
        if self._current_set is None:
            new_set = PolygonSetDef(
                name=name,
                source_type=PolygonSourceType.FILE,
                file_source=FileSource(
                    folder="polygonSet",
                    filename=filename,
                    polygon_type=PolygonType.SPLINE_POLYGON
                )
            )
            self._library.add_polygon_set(new_set)
            self._refresh_list()
            last = self.set_list.topLevelItem(self.set_list.topLevelItemCount() - 1)
            if last:
                self.set_list.setCurrentItem(last)
        else:
            # Update current set
            self._updating = True
            try:
                self._current_set.name = name
                self._current_set.source_type = PolygonSourceType.FILE
                if self._current_set.file_source is None:
                    self._current_set.file_source = FileSource()
                self._current_set.file_source.folder = "polygonSet"
                self._current_set.file_source.filename = filename
                self._current_set.file_source.polygon_type = PolygonType.SPLINE_POLYGON
                self._load_set_to_ui(self._current_set)
                # Update list item text
                current_item = self.set_list.currentItem()
                if current_item:
                    current_item.setText(1, self._current_set.name)
            finally:
                self._updating = False

        self._refresh_file_list()
        self.modified.emit()

    def _create_polygon_set(self) -> None:
        """Launch Bezier to create a new polygon set."""
        if not self._polygon_sets_dir or not os.path.isdir(self._polygon_sets_dir):
            QMessageBox.warning(self, "No Project",
                                "Please save the project first.")
            return

        if self._bezier_process is not None and self._bezier_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.information(self, "Bezier Running",
                                    "Bezier is already running.")
            return

        self._pre_launch_files = self._snapshot_polygon_files()

        self._bezier_process = QProcess(self)
        self._bezier_process.setWorkingDirectory(BEZIER_WORKING_DIR)
        self._bezier_process.finished.connect(self._on_create_bezier_finished)
        self._bezier_process.start("java", [
            "-Xmx4G", "-jar", BEZIER_JAR,
            "--save-dir", self._polygon_sets_dir
        ])

    def _on_create_bezier_finished(self, exit_code, exit_status) -> None:
        """Handle Bezier process finishing after create."""
        if not self._polygon_sets_dir or not os.path.isdir(self._polygon_sets_dir):
            return

        current_files = self._snapshot_polygon_files()
        new_files = current_files - self._pre_launch_files

        # Strip XML headers from all new files
        for fname in new_files:
            fpath = os.path.join(self._polygon_sets_dir, fname)
            if os.path.isfile(fpath):
                self._strip_xml_headers(fpath)

        # Exclude .layers.xml manifests — only process actual polygon set XML files
        polygon_files = sorted(
            f for f in new_files
            if f.endswith('.xml') and not f.endswith('.layers.xml')
        )

        if len(polygon_files) == 1:
            fname = polygon_files[0]
            fpath = os.path.join(self._polygon_sets_dir, fname)
            self._auto_populate_fields(fname, fpath)
        elif len(polygon_files) > 1:
            # Multiple layer files — add a new PolygonSetDef for each one
            for fname in polygon_files:
                fpath = os.path.join(self._polygon_sets_dir, fname)
                name = self._parse_polygon_set_name(fpath)
                new_set = PolygonSetDef(
                    name=name,
                    source_type=PolygonSourceType.FILE,
                    file_source=FileSource(
                        folder="polygonSet",
                        filename=fname,
                        polygon_type=PolygonType.SPLINE_POLYGON
                    )
                )
                self._library.add_polygon_set(new_set)

            # Also add a bundle entry for the .layers.xml manifest so the user
            # has an edit handle that opens the full multi-layer set in Bezier.
            manifest_files = [f for f in new_files if f.endswith('.layers.xml')]
            if manifest_files:
                manifest_fname = manifest_files[0]
                manifest_fpath = os.path.join(self._polygon_sets_dir, manifest_fname)
                overall_name = self._parse_layers_manifest_name(manifest_fpath)
                if not overall_name:
                    overall_name = manifest_fname.replace('.layers.xml', '')
                bundle_set = PolygonSetDef(
                    name=f"{overall_name} (bundle)",
                    source_type=PolygonSourceType.FILE,
                    file_source=FileSource(
                        folder="polygonSet",
                        filename=manifest_fname,
                        polygon_type=PolygonType.SPLINE_POLYGON
                    )
                )
                self._library.add_polygon_set(bundle_set)

            self._refresh_list()
            self._refresh_file_list()
            self.modified.emit()
        else:
            # No recognisable polygon files — just refresh the file list
            self._refresh_file_list()

    def _import_polygon_set(self) -> None:
        """Import a polygon set file from another location."""
        if not self._polygon_sets_dir or not os.path.isdir(self._polygon_sets_dir):
            QMessageBox.warning(self, "No Project",
                                "Please save the project first.")
            return

        default_dir = os.path.expanduser("~/.loom_projects/")
        if not os.path.isdir(default_dir):
            default_dir = os.path.expanduser("~")

        filepath, _ = QFileDialog.getOpenFileName(
            self, "Import Polygon Set", default_dir,
            "XML Files (*.xml);;All Files (*)"
        )
        if not filepath:
            return

        filename = os.path.basename(filepath)
        dest_path = os.path.join(self._polygon_sets_dir, filename)

        # Handle name collision
        if os.path.exists(dest_path) and os.path.abspath(filepath) != os.path.abspath(dest_path):
            result = QMessageBox.question(
                self, "File Exists",
                f"'{filename}' already exists in the polygon sets directory. Overwrite?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
            if result != QMessageBox.StandardButton.Yes:
                return

        try:
            shutil.copy2(filepath, dest_path)
            self._strip_xml_headers(dest_path)
            self._auto_populate_fields(filename, dest_path)
        except Exception as e:
            QMessageBox.critical(self, "Import Failed",
                                 f"Could not import '{filename}':\n{e}")

    def _edit_polygon_set(self) -> None:
        """Launch Bezier to edit the currently selected polygon set file."""
        if not self._polygon_sets_dir or not os.path.isdir(self._polygon_sets_dir):
            QMessageBox.warning(self, "No Project",
                                "Please save the project first.")
            return

        if self._current_set is None:
            QMessageBox.warning(self, "No Selection",
                                "Please select a polygon set first.")
            return

        if self._current_set.source_type != PolygonSourceType.FILE:
            QMessageBox.warning(self, "Not a File Source",
                                "Edit is only available for file-referenced polygon sets.")
            return

        if not self._current_set.file_source or not self._current_set.file_source.filename:
            QMessageBox.warning(self, "No Filename",
                                "The selected polygon set has no filename set.")
            return

        full_path = os.path.join(self._polygon_sets_dir,
                                 self._current_set.file_source.filename)
        if not os.path.isfile(full_path):
            QMessageBox.warning(self, "File Not Found",
                                f"File not found:\n{full_path}")
            return

        if self._bezier_process is not None and self._bezier_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.information(self, "Bezier Running",
                                    "Bezier is already running.")
            return

        self._edit_file_path = full_path

        # Bezier's XOM parser requires XML headers
        if full_path.endswith('.layers.xml'):
            self._add_xml_headers_for_bundle_layers(full_path)
            self._add_xml_headers_layerset(full_path)
        else:
            self._add_xml_headers(full_path)

        self._bezier_process = QProcess(self)
        self._bezier_process.setWorkingDirectory(BEZIER_WORKING_DIR)
        self._bezier_process.finished.connect(self._on_edit_bezier_finished)
        self._bezier_process.start("java", [
            "-Xmx4G", "-jar", BEZIER_JAR,
            "--save-dir", self._polygon_sets_dir,
            "--load", full_path
        ])

    def _on_edit_bezier_finished(self, exit_code, exit_status) -> None:
        """Handle Bezier process finishing after edit."""
        if hasattr(self, '_edit_file_path') and os.path.isfile(self._edit_file_path):
            if self._edit_file_path.endswith('.layers.xml'):
                # Strip headers from manifest and all layer XML files Bezier may have rewritten
                if self._polygon_sets_dir and os.path.isdir(self._polygon_sets_dir):
                    for fname in os.listdir(self._polygon_sets_dir):
                        if fname.endswith('.xml'):
                            fpath = os.path.join(self._polygon_sets_dir, fname)
                            if os.path.isfile(fpath):
                                self._strip_xml_headers(fpath)
            else:
                self._strip_xml_headers(self._edit_file_path)
