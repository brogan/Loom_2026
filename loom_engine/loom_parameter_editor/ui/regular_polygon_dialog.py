"""
Dialog for creating/editing regular polygons with live preview.
"""
import math
from PySide6.QtWidgets import (
    QDialog, QHBoxLayout, QVBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QSpinBox, QDoubleSpinBox, QDialogButtonBox, QWidget,
    QCheckBox
)
from PySide6.QtCore import Qt, QPointF
from PySide6.QtGui import QPainter, QPen, QBrush, QColor, QPolygonF
from models.polygon_config import RegularPolygonParams


class PolygonPreviewWidget(QWidget):
    """Widget that draws a live preview of a regular polygon."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumSize(250, 250)
        self._params = RegularPolygonParams()

    def set_params(self, params: RegularPolygonParams):
        self._params = params
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # Background
        painter.fillRect(self.rect(), QColor(40, 40, 40))

        p = self._params
        n = p.total_points
        if n < 3:
            painter.end()
            return

        # Generate points using PolygonCreator.makePolygon2DStar algorithm
        # numberOfSides = n * 2 (alternating outer/inner vertices)
        # Outer radius = 0.5, inner radius = internal_radius
        # positiveSynch + synchMultiplier control inner point angular offset
        total_verts = n * 2
        ang_inc = 360.0 / total_verts

        outer_r = 0.5
        inner_r = p.internal_radius

        # Build outer points (even indices): start at (0, -outer_r)
        # then each successive outer point rotated by 2*angInc from previous
        outer_points = {}
        outer_points[0] = (0.0, -outer_r)
        for i in range(2, total_verts, 2):
            # Rotate from i-2 by 2*angInc
            prev = outer_points[i - 2]
            angle_rad = math.radians(2 * ang_inc)
            cos_a = math.cos(angle_rad)
            sin_a = math.sin(angle_rad)
            outer_points[i] = (
                prev[0] * cos_a - prev[1] * sin_a,
                prev[0] * sin_a + prev[1] * cos_a
            )

        # Build inner points (odd indices): start at (0, -inner_r)
        # rotated by angInc * synchMultiplier (positive or negative)
        synch_angle = ang_inc * p.synch_multiplier
        if not p.positive_synch:
            synch_angle = -synch_angle
        inner_start_rad = math.radians(synch_angle)
        cos_s = math.cos(inner_start_rad)
        sin_s = math.sin(inner_start_rad)
        base_inner = (0.0, -inner_r)
        inner_points = {}
        inner_points[1] = (
            base_inner[0] * cos_s - base_inner[1] * sin_s,
            base_inner[0] * sin_s + base_inner[1] * cos_s
        )
        for i in range(3, total_verts, 2):
            prev = inner_points[i - 2]
            angle_rad = math.radians(2 * ang_inc)
            cos_a = math.cos(angle_rad)
            sin_a = math.sin(angle_rad)
            inner_points[i] = (
                prev[0] * cos_a - prev[1] * sin_a,
                prev[0] * sin_a + prev[1] * cos_a
            )

        # Combine into ordered list, apply scale
        points = []
        for i in range(total_verts):
            if i % 2 == 0:
                x, y = outer_points[i]
            else:
                x, y = inner_points[i]
            # Apply offset rotation
            if p.offset != 0.0:
                off_rad = math.radians(p.offset)
                cos_o = math.cos(off_rad)
                sin_o = math.sin(off_rad)
                x, y = x * cos_o - y * sin_o, x * sin_o + y * cos_o
            # Apply scale
            points.append((x * p.scale_x, y * p.scale_y))

        # Apply rotation
        if p.rotation_angle != 0.0:
            rot_rad = math.radians(p.rotation_angle)
            cos_r = math.cos(rot_rad)
            sin_r = math.sin(rot_rad)
            rotated = []
            for x, y in points:
                rx = x * cos_r - y * sin_r
                ry = x * sin_r + y * cos_r
                rotated.append((rx, ry))
            points = rotated

        # Apply translation (offset from 0.5, 0.5 center)
        tx = p.trans_x - 0.5
        ty = p.trans_y - 0.5
        if tx != 0.0 or ty != 0.0:
            points = [(x + tx, y + ty) for x, y in points]

        # Find bounding box for scaling to fit widget
        if not points:
            painter.end()
            return

        min_x = min(x for x, y in points)
        max_x = max(x for x, y in points)
        min_y = min(y for x, y in points)
        max_y = max(y for x, y in points)

        data_w = max_x - min_x
        data_h = max_y - min_y
        if data_w < 1e-6:
            data_w = 1.0
        if data_h < 1e-6:
            data_h = 1.0

        # Fit to widget with padding
        padding = 20
        avail_w = self.width() - 2 * padding
        avail_h = self.height() - 2 * padding
        scale = min(avail_w / data_w, avail_h / data_h)

        cx = (min_x + max_x) / 2
        cy = (min_y + max_y) / 2

        # Map to screen coordinates
        screen_points = []
        for x, y in points:
            sx = padding + avail_w / 2 + (x - cx) * scale
            sy = padding + avail_h / 2 + (y - cy) * scale
            screen_points.append(QPointF(sx, sy))

        # Draw polygon
        poly = QPolygonF(screen_points)
        painter.setBrush(QBrush(QColor(255, 255, 255, 40)))
        painter.setPen(QPen(QColor(255, 255, 255), 2))
        painter.drawPolygon(poly)

        # Draw vertices — outer (even) in blue, inner (odd) in orange
        painter.setPen(Qt.PenStyle.NoPen)
        for i, pt in enumerate(screen_points):
            if i % 2 == 0:
                painter.setBrush(QBrush(QColor(100, 180, 255)))  # outer: blue
                painter.drawEllipse(pt, 5, 5)
            else:
                painter.setBrush(QBrush(QColor(255, 160, 60)))   # inner: orange
                painter.drawEllipse(pt, 4, 4)

        painter.end()


class RegularPolygonDialog(QDialog):
    """Dialog for creating or editing a regular polygon definition."""

    def __init__(self, parent=None, name: str = "", params: RegularPolygonParams = None):
        super().__init__(parent)
        self.setWindowTitle("Regular Polygon" if not name else f"Edit: {name}")
        self.setMinimumSize(600, 400)

        self._setup_ui(name, params)

    def _setup_ui(self, name: str, params: RegularPolygonParams):
        layout = QHBoxLayout(self)

        # Left side — parameter fields
        left = QWidget()
        left_layout = QVBoxLayout(left)

        group = QGroupBox("Parameters")
        form = QFormLayout(group)

        self.name_edit = QLineEdit()
        self.name_edit.setText(name or "r_polygon")
        form.addRow("Name:", self.name_edit)

        self.total_points_spin = QSpinBox()
        self.total_points_spin.setRange(3, 64)
        self.total_points_spin.setValue(4)
        self.total_points_spin.valueChanged.connect(self._update_preview)
        form.addRow("Total Points:", self.total_points_spin)

        self.internal_radius_spin = QDoubleSpinBox()
        self.internal_radius_spin.setRange(0.01, 10.0)
        self.internal_radius_spin.setDecimals(3)
        self.internal_radius_spin.setSingleStep(0.05)
        self.internal_radius_spin.setValue(0.5)
        self.internal_radius_spin.valueChanged.connect(self._update_preview)
        form.addRow("Internal Radius:", self.internal_radius_spin)

        self.offset_spin = QDoubleSpinBox()
        self.offset_spin.setRange(-360.0, 360.0)
        self.offset_spin.setDecimals(1)
        self.offset_spin.setSingleStep(5.0)
        self.offset_spin.setValue(0.0)
        self.offset_spin.valueChanged.connect(self._update_preview)
        form.addRow("Offset:", self.offset_spin)

        self.scale_x_spin = QDoubleSpinBox()
        self.scale_x_spin.setRange(0.01, 10.0)
        self.scale_x_spin.setDecimals(3)
        self.scale_x_spin.setSingleStep(0.1)
        self.scale_x_spin.setValue(1.0)
        self.scale_x_spin.valueChanged.connect(self._update_preview)
        form.addRow("Scale X:", self.scale_x_spin)

        self.scale_y_spin = QDoubleSpinBox()
        self.scale_y_spin.setRange(0.01, 10.0)
        self.scale_y_spin.setDecimals(3)
        self.scale_y_spin.setSingleStep(0.1)
        self.scale_y_spin.setValue(1.0)
        self.scale_y_spin.valueChanged.connect(self._update_preview)
        form.addRow("Scale Y:", self.scale_y_spin)

        self.rotation_spin = QDoubleSpinBox()
        self.rotation_spin.setRange(-360.0, 360.0)
        self.rotation_spin.setDecimals(1)
        self.rotation_spin.setSingleStep(5.0)
        self.rotation_spin.setValue(0.0)
        self.rotation_spin.valueChanged.connect(self._update_preview)
        form.addRow("Rotation Angle:", self.rotation_spin)

        self.trans_x_spin = QDoubleSpinBox()
        self.trans_x_spin.setRange(-10.0, 10.0)
        self.trans_x_spin.setDecimals(3)
        self.trans_x_spin.setSingleStep(0.1)
        self.trans_x_spin.setValue(0.5)
        self.trans_x_spin.valueChanged.connect(self._update_preview)
        form.addRow("Translation X:", self.trans_x_spin)

        self.trans_y_spin = QDoubleSpinBox()
        self.trans_y_spin.setRange(-10.0, 10.0)
        self.trans_y_spin.setDecimals(3)
        self.trans_y_spin.setSingleStep(0.1)
        self.trans_y_spin.setValue(0.5)
        self.trans_y_spin.valueChanged.connect(self._update_preview)
        form.addRow("Translation Y:", self.trans_y_spin)

        self.positive_synch_check = QCheckBox("Positive")
        self.positive_synch_check.setChecked(True)
        self.positive_synch_check.toggled.connect(self._update_preview)
        form.addRow("Synch Direction:", self.positive_synch_check)

        self.synch_multiplier_spin = QDoubleSpinBox()
        self.synch_multiplier_spin.setRange(0.0, 10.0)
        self.synch_multiplier_spin.setDecimals(2)
        self.synch_multiplier_spin.setSingleStep(0.1)
        self.synch_multiplier_spin.setValue(1.0)
        self.synch_multiplier_spin.valueChanged.connect(self._update_preview)
        form.addRow("Synch Multiplier:", self.synch_multiplier_spin)

        left_layout.addWidget(group)

        # OK / Cancel
        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        left_layout.addWidget(buttons)

        layout.addWidget(left)

        # Right side — live preview
        self.preview = PolygonPreviewWidget()
        layout.addWidget(self.preview)

        # Pre-populate if editing
        if params is not None:
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

        self._update_preview()

    def _update_preview(self):
        params = self._build_params()
        self.preview.set_params(params)

    def _build_params(self) -> RegularPolygonParams:
        return RegularPolygonParams(
            total_points=self.total_points_spin.value(),
            internal_radius=self.internal_radius_spin.value(),
            offset=self.offset_spin.value(),
            scale_x=self.scale_x_spin.value(),
            scale_y=self.scale_y_spin.value(),
            rotation_angle=self.rotation_spin.value(),
            trans_x=self.trans_x_spin.value(),
            trans_y=self.trans_y_spin.value(),
            positive_synch=self.positive_synch_check.isChecked(),
            synch_multiplier=self.synch_multiplier_spin.value()
        )

    def get_result(self):
        """Return (name, RegularPolygonParams) after dialog accepted."""
        return (self.name_edit.text().strip(), self._build_params())
