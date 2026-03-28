"""
Rendering configuration tab with full editing capabilities.
"""
from typing import Optional
import os
import json
from PyQt6.QtWidgets import (
    QWidget, QHBoxLayout, QVBoxLayout, QSplitter, QGroupBox,
    QLabel, QDoubleSpinBox, QSpinBox, QCheckBox, QComboBox,
    QScrollArea, QFrame, QListWidget, QPushButton, QInputDialog,
    QFileDialog, QListWidgetItem, QDialog, QMessageBox, QTabWidget,
    QTableWidget, QTableWidgetItem, QHeaderView, QAbstractItemView,
    QSizePolicy
)
from PyQt6.QtCore import pyqtSignal, Qt
from PyQt6.QtGui import QImage, QPainter, QColor, QPen, QPixmap
from .widgets.renderer_tree import RendererTreeWidget
from .widgets.brush_editor import BrushEditorWidget  # kept for legacy compatibility
from .widgets.color_picker import ColorPickerWidget
from .widgets.enum_dropdown import EnumDropdown
from .widgets.change_editor import (
    SizeChangeEditor, ColorChangeEditor, FillColorChangeEditor
)
from models.rendering import (
    RendererSetLibrary, RendererSet, Renderer, Color, BrushConfig, MeanderConfig, StencilConfig
)
from models.constants import RenderMode, PlaybackMode, BrushDrawMode, PostCompletionMode


# ---------------------------------------------------------------------------
# BrushPreviewWidget
# ---------------------------------------------------------------------------

class BrushPreviewWidget(QWidget):
    """Shows a brush PNG on a dark background with optional grid lines."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._image: Optional[QImage] = None
        self.setMinimumHeight(100)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        self.setStyleSheet("background: #111111;")

    def set_image(self, image: Optional[QImage]):
        self._image = image
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor(17, 17, 17))

        if self._image is None or self._image.isNull():
            painter.setPen(QColor(80, 80, 80))
            painter.drawText(self.rect(), Qt.AlignmentFlag.AlignCenter, "No brush selected")
            painter.end()
            return

        w = self.width()
        h = self.height()
        img_w = self._image.width()
        img_h = self._image.height()

        pad = 6
        scale = min((w - pad * 2) / img_w, (h - pad * 2) / img_h) if img_w and img_h else 1.0
        draw_w = max(1, int(img_w * scale))
        draw_h = max(1, int(img_h * scale))
        ox = (w - draw_w) // 2
        oy = (h - draw_h) // 2

        # Draw image
        scaled = self._image.scaled(draw_w, draw_h,
                                    Qt.AspectRatioMode.IgnoreAspectRatio,
                                    Qt.TransformationMode.FastTransformation)
        painter.drawImage(ox, oy, scaled)

        # Grid lines when cells are big enough
        cell_w = draw_w / img_w
        cell_h = draw_h / img_h
        if cell_w >= 3 and cell_h >= 3:
            painter.setPen(QPen(QColor(50, 50, 50), 1))
            for c in range(img_w + 1):
                x = ox + int(c * cell_w)
                painter.drawLine(x, oy, x, oy + draw_h)
            for r in range(img_h + 1):
                y = oy + int(r * cell_h)
                painter.drawLine(ox, y, ox + draw_w, y)

        # Border
        painter.setPen(QPen(QColor(80, 80, 80), 1))
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawRect(ox, oy, draw_w, draw_h)

        painter.end()


# ---------------------------------------------------------------------------
# StencilPreviewWidget
# ---------------------------------------------------------------------------

class StencilPreviewWidget(QWidget):
    """Shows a stencil PNG over a checkered background to reveal alpha."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._image: Optional[QImage] = None
        self.setMinimumHeight(100)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)

    def set_image(self, image: Optional[QImage]):
        self._image = image
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)

        # Checkered background
        cell = 8
        light = QColor(200, 200, 200)
        dark = QColor(140, 140, 140)
        for y in range(0, self.height(), cell):
            for x in range(0, self.width(), cell):
                if ((x // cell + y // cell) % 2) == 0:
                    painter.fillRect(x, y, cell, cell, light)
                else:
                    painter.fillRect(x, y, cell, cell, dark)

        if self._image is None or self._image.isNull():
            painter.setPen(QColor(80, 80, 80))
            painter.drawText(self.rect(), Qt.AlignmentFlag.AlignCenter, "No stamp selected")
            painter.end()
            return

        w = self.width()
        h = self.height()
        img_w = self._image.width()
        img_h = self._image.height()

        pad = 6
        scale = min((w - pad * 2) / img_w, (h - pad * 2) / img_h) if img_w and img_h else 1.0
        draw_w = max(1, int(img_w * scale))
        draw_h = max(1, int(img_h * scale))
        ox = (w - draw_w) // 2
        oy = (h - draw_h) // 2

        scaled = self._image.scaled(draw_w, draw_h,
                                    Qt.AspectRatioMode.IgnoreAspectRatio,
                                    Qt.TransformationMode.FastTransformation)
        painter.drawImage(ox, oy, scaled)

        # Border
        painter.setPen(QPen(QColor(80, 80, 80), 1))
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawRect(ox, oy, draw_w, draw_h)

        painter.end()


# ---------------------------------------------------------------------------
# RendererEditor
# ---------------------------------------------------------------------------

class RendererEditor(QWidget):
    """Editor panel for a single renderer's properties."""

    changed = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._renderer: Optional[Renderer] = None
        self._updating = False
        self._brushes_dir: str = ""
        self._stencils_dir: str = ""
        self._palettes_dir: str = ""
        self._editor_window = None
        self._stencil_editor_window = None

        # Inner tabs: Basic Properties | Brushes | Stencils | Point Change | Stroke Change | Fill Change
        inner_tabs = QTabWidget()
        self._inner_tabs = inner_tabs

        # ------------------------------------------------------------------
        # Basic Properties tab
        # ------------------------------------------------------------------
        basic_scroll = QScrollArea()
        basic_scroll.setWidgetResizable(True)
        basic_scroll.setFrameShape(QFrame.Shape.NoFrame)
        basic_content = QWidget()
        layout = QVBoxLayout(basic_content)
        basic_scroll.setWidget(basic_content)
        inner_tabs.addTab(basic_scroll, "Basic Properties")

        basic_group = QGroupBox("Basic Properties")
        basic_layout = QVBoxLayout(basic_group)

        # Mode dropdown
        mode_row = QHBoxLayout()
        mode_row.addWidget(QLabel("Mode:"))
        self.mode_dropdown = EnumDropdown(RenderMode)
        self.mode_dropdown.valueChanged.connect(self._on_mode_changed)
        mode_row.addWidget(self.mode_dropdown)
        mode_row.addStretch()
        basic_layout.addLayout(mode_row)

        # Stroke width and color
        stroke_row = QHBoxLayout()
        stroke_row.addWidget(QLabel("Stroke Width:"))
        self.stroke_width_spin = QDoubleSpinBox()
        self.stroke_width_spin.setRange(0.1, 50.0)
        self.stroke_width_spin.setDecimals(1)
        self.stroke_width_spin.setSingleStep(0.5)
        self.stroke_width_spin.valueChanged.connect(self._on_changed)
        stroke_row.addWidget(self.stroke_width_spin)
        basic_layout.addLayout(stroke_row)

        self.stroke_color_picker = ColorPickerWidget("Stroke Color:")
        self.stroke_color_picker.colorChanged.connect(self._on_changed)
        basic_layout.addWidget(self.stroke_color_picker)

        # Fill color
        self.fill_color_picker = ColorPickerWidget("Fill Color:")
        self.fill_color_picker.colorChanged.connect(self._on_changed)
        basic_layout.addWidget(self.fill_color_picker)

        # Point size and hold length
        point_row = QHBoxLayout()
        point_row.addWidget(QLabel("Point Size:"))
        self.point_size_spin = QDoubleSpinBox()
        self.point_size_spin.setRange(0.1, 50.0)
        self.point_size_spin.setDecimals(1)
        self.point_size_spin.valueChanged.connect(self._on_changed)
        point_row.addWidget(self.point_size_spin)
        point_row.addWidget(QLabel("Hold Length:"))
        self.hold_length_spin = QSpinBox()
        self.hold_length_spin.setRange(1, 100)
        self.hold_length_spin.valueChanged.connect(self._on_changed)
        point_row.addWidget(self.hold_length_spin)
        point_row.addStretch()
        basic_layout.addLayout(point_row)

        # Point style
        point_style_row = QHBoxLayout()
        self.point_stroked_check = QCheckBox("Point Stroked")
        self.point_stroked_check.stateChanged.connect(self._on_point_style_changed)
        point_style_row.addWidget(self.point_stroked_check)
        self.point_filled_check = QCheckBox("Point Filled")
        self.point_filled_check.stateChanged.connect(self._on_point_style_changed)
        point_style_row.addWidget(self.point_filled_check)
        point_style_row.addStretch()
        basic_layout.addLayout(point_style_row)

        layout.addWidget(basic_group)
        layout.addStretch()

        # ------------------------------------------------------------------
        # Brushes tab  (dedicated, between Basic Properties and Point Change)
        # ------------------------------------------------------------------
        brush_scroll = QScrollArea()
        brush_scroll.setWidgetResizable(True)
        brush_scroll.setFrameShape(QFrame.Shape.NoFrame)
        brush_content = QWidget()
        brush_content_layout = QVBoxLayout(brush_content)
        brush_content_layout.setSpacing(4)
        brush_scroll.setWidget(brush_content)
        inner_tabs.addTab(brush_scroll, "Brushes")

        # Brush image table (Name | Grid | Pixels | Use)
        self.brush_table = QTableWidget()
        self.brush_table.setColumnCount(4)
        self.brush_table.setHorizontalHeaderLabels(["Name", "Grid", "Pixels", "Use"])
        hh = self.brush_table.horizontalHeader()
        hh.setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        hh.setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
        hh.setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        hh.setSectionResizeMode(3, QHeaderView.ResizeMode.Fixed)
        self.brush_table.setColumnWidth(3, 36)
        self.brush_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.brush_table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.brush_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.brush_table.setMaximumHeight(130)
        self.brush_table.itemSelectionChanged.connect(self._on_brush_selection_changed)
        self.brush_table.itemChanged.connect(self._on_brush_table_changed)
        brush_content_layout.addWidget(self.brush_table)

        # Brush buttons
        brush_btn_row = QHBoxLayout()
        self.add_brush_btn = QPushButton("Add...")
        self.add_brush_btn.setToolTip("Add an existing brush PNG from the project's brushes/ folder")
        self.add_brush_btn.clicked.connect(self._on_add_brush)
        brush_btn_row.addWidget(self.add_brush_btn)
        self.create_brush_btn = QPushButton("Create...")
        self.create_brush_btn.setToolTip("Open the brush editor to create a new brush")
        self.create_brush_btn.clicked.connect(self._on_create_brush)
        brush_btn_row.addWidget(self.create_brush_btn)
        self.edit_brush_btn = QPushButton("Edit...")
        self.edit_brush_btn.setToolTip("Edit the selected brush in the brush editor")
        self.edit_brush_btn.clicked.connect(self._on_edit_brush)
        brush_btn_row.addWidget(self.edit_brush_btn)
        self.remove_brush_btn = QPushButton("Remove")
        self.remove_brush_btn.clicked.connect(self._on_remove_brush)
        brush_btn_row.addWidget(self.remove_brush_btn)
        brush_btn_row.addStretch()
        brush_content_layout.addLayout(brush_btn_row)

        # Brush settings
        self.brush_settings_group = QGroupBox("Brush Settings")
        bs_layout = QVBoxLayout(self.brush_settings_group)

        # Draw mode
        draw_mode_row = QHBoxLayout()
        draw_mode_row.addWidget(QLabel("Draw Mode:"))
        self.draw_mode_combo = QComboBox()
        for dm in BrushDrawMode:
            self.draw_mode_combo.addItem(dm.name, dm)
        self.draw_mode_combo.currentIndexChanged.connect(self._on_brush_changed)
        draw_mode_row.addWidget(self.draw_mode_combo)
        draw_mode_row.addStretch()
        bs_layout.addLayout(draw_mode_row)

        # Stamp spacing + easing
        spacing_row = QHBoxLayout()
        spacing_row.addWidget(QLabel("Stamp Spacing:"))
        self.stamp_spacing_spin = QDoubleSpinBox()
        self.stamp_spacing_spin.setRange(0.5, 999.0)
        self.stamp_spacing_spin.setDecimals(1)
        self.stamp_spacing_spin.setSingleStep(0.5)
        self.stamp_spacing_spin.valueChanged.connect(self._on_brush_changed)
        spacing_row.addWidget(self.stamp_spacing_spin)
        spacing_row.addWidget(QLabel("Easing:"))
        self.spacing_easing_combo = QComboBox()
        easing_types = [
            "LINEAR", "EASE_IN_QUAD", "EASE_OUT_QUAD", "EASE_IN_OUT_QUAD",
            "EASE_IN_CUBIC", "EASE_OUT_CUBIC", "EASE_IN_OUT_CUBIC",
            "EASE_IN_QUART", "EASE_OUT_QUART", "EASE_IN_OUT_QUART",
            "EASE_IN_QUINT", "EASE_OUT_QUINT", "EASE_IN_OUT_QUINT",
            "EASE_IN_SINE", "EASE_OUT_SINE", "EASE_IN_OUT_SINE",
            "EASE_IN_EXPO", "EASE_OUT_EXPO", "EASE_IN_OUT_EXPO",
            "EASE_IN_CIRC", "EASE_OUT_CIRC", "EASE_IN_OUT_CIRC",
            "EASE_IN_ELASTIC", "EASE_OUT_ELASTIC", "EASE_IN_OUT_ELASTIC",
            "EASE_IN_BACK", "EASE_OUT_BACK", "EASE_IN_OUT_BACK",
            "EASE_IN_BOUNCE", "EASE_OUT_BOUNCE", "EASE_IN_OUT_BOUNCE",
        ]
        self.spacing_easing_combo.addItems(easing_types)
        self.spacing_easing_combo.currentTextChanged.connect(self._on_brush_changed)
        spacing_row.addWidget(self.spacing_easing_combo)
        bs_layout.addLayout(spacing_row)

        # Follow tangent
        self.follow_tangent_check = QCheckBox("Follow Tangent")
        self.follow_tangent_check.stateChanged.connect(self._on_brush_changed)
        bs_layout.addWidget(self.follow_tangent_check)

        # Perpendicular jitter
        perp_row = QHBoxLayout()
        perp_row.addWidget(QLabel("Perp. Jitter Min:"))
        self.perp_jitter_min_spin = QDoubleSpinBox()
        self.perp_jitter_min_spin.setRange(-50.0, 50.0)
        self.perp_jitter_min_spin.setDecimals(1)
        self.perp_jitter_min_spin.valueChanged.connect(self._on_brush_changed)
        perp_row.addWidget(self.perp_jitter_min_spin)
        perp_row.addWidget(QLabel("Max:"))
        self.perp_jitter_max_spin = QDoubleSpinBox()
        self.perp_jitter_max_spin.setRange(-50.0, 50.0)
        self.perp_jitter_max_spin.setDecimals(1)
        self.perp_jitter_max_spin.valueChanged.connect(self._on_brush_changed)
        perp_row.addWidget(self.perp_jitter_max_spin)
        bs_layout.addLayout(perp_row)

        # Scale min/max
        scale_row = QHBoxLayout()
        scale_row.addWidget(QLabel("Scale Min:"))
        self.brush_scale_min_spin = QDoubleSpinBox()
        self.brush_scale_min_spin.setRange(0.01, 10.0)
        self.brush_scale_min_spin.setDecimals(2)
        self.brush_scale_min_spin.setSingleStep(0.1)
        self.brush_scale_min_spin.valueChanged.connect(self._on_brush_changed)
        scale_row.addWidget(self.brush_scale_min_spin)
        scale_row.addWidget(QLabel("Max:"))
        self.brush_scale_max_spin = QDoubleSpinBox()
        self.brush_scale_max_spin.setRange(0.01, 10.0)
        self.brush_scale_max_spin.setDecimals(2)
        self.brush_scale_max_spin.setSingleStep(0.1)
        self.brush_scale_max_spin.valueChanged.connect(self._on_brush_changed)
        scale_row.addWidget(self.brush_scale_max_spin)
        bs_layout.addLayout(scale_row)

        # Opacity min/max
        opacity_row = QHBoxLayout()
        opacity_row.addWidget(QLabel("Opacity Min:"))
        self.opacity_min_spin = QDoubleSpinBox()
        self.opacity_min_spin.setRange(0.0, 1.0)
        self.opacity_min_spin.setDecimals(2)
        self.opacity_min_spin.setSingleStep(0.05)
        self.opacity_min_spin.valueChanged.connect(self._on_brush_changed)
        opacity_row.addWidget(self.opacity_min_spin)
        opacity_row.addWidget(QLabel("Max:"))
        self.opacity_max_spin = QDoubleSpinBox()
        self.opacity_max_spin.setRange(0.0, 1.0)
        self.opacity_max_spin.setDecimals(2)
        self.opacity_max_spin.setSingleStep(0.05)
        self.opacity_max_spin.valueChanged.connect(self._on_brush_changed)
        opacity_row.addWidget(self.opacity_max_spin)
        bs_layout.addLayout(opacity_row)

        # Progressive reveal
        self.progressive_group = QGroupBox("Progressive Reveal")
        prog_layout = QVBoxLayout(self.progressive_group)

        spf_row = QHBoxLayout()
        spf_row.addWidget(QLabel("Stamps/Frame:"))
        self.stamps_per_frame_spin = QSpinBox()
        self.stamps_per_frame_spin.setRange(1, 1000)
        self.stamps_per_frame_spin.valueChanged.connect(self._on_brush_changed)
        spf_row.addWidget(self.stamps_per_frame_spin)
        spf_row.addWidget(QLabel("Agents:"))
        self.agent_count_spin = QSpinBox()
        self.agent_count_spin.setRange(1, 50)
        self.agent_count_spin.valueChanged.connect(self._on_brush_changed)
        spf_row.addWidget(self.agent_count_spin)
        prog_layout.addLayout(spf_row)

        pcm_row = QHBoxLayout()
        pcm_row.addWidget(QLabel("Post-Completion:"))
        self.post_completion_combo = QComboBox()
        for pcm in PostCompletionMode:
            self.post_completion_combo.addItem(pcm.name, pcm)
        self.post_completion_combo.currentIndexChanged.connect(self._on_brush_changed)
        pcm_row.addWidget(self.post_completion_combo)
        pcm_row.addStretch()
        prog_layout.addLayout(pcm_row)

        bs_layout.addWidget(self.progressive_group)

        # Blur radius
        blur_row = QHBoxLayout()
        blur_row.addWidget(QLabel("Blur Radius:"))
        self.blur_radius_spin = QSpinBox()
        self.blur_radius_spin.setRange(0, 10)
        self.blur_radius_spin.valueChanged.connect(self._on_brush_changed)
        blur_row.addWidget(self.blur_radius_spin)
        blur_row.addStretch()
        bs_layout.addLayout(blur_row)

        # ------------------------------------------------------------------
        # Meander Path — collapsible section with separate Enabled checkbox
        # ------------------------------------------------------------------
        meander_header = QWidget()
        meander_header_layout = QHBoxLayout(meander_header)
        meander_header_layout.setContentsMargins(0, 4, 0, 0)

        self.meander_toggle_btn = QPushButton("▶ Meander Path")
        self.meander_toggle_btn.setCheckable(True)
        self.meander_toggle_btn.setChecked(False)
        self.meander_toggle_btn.setFlat(True)
        self.meander_toggle_btn.setStyleSheet("text-align: left; font-weight: bold;")
        self.meander_toggle_btn.toggled.connect(self._on_meander_panel_toggled)
        meander_header_layout.addWidget(self.meander_toggle_btn)

        self.meander_enabled_check = QCheckBox("Enabled")
        self.meander_enabled_check.stateChanged.connect(self._on_brush_changed)
        meander_header_layout.addWidget(self.meander_enabled_check)
        meander_header_layout.addStretch()

        bs_layout.addWidget(meander_header)

        # Collapsible panel (hidden until toggle is pressed)
        self.meander_panel = QWidget()
        self.meander_panel.setVisible(False)
        meander_layout = QVBoxLayout(self.meander_panel)
        meander_layout.setContentsMargins(8, 0, 0, 4)

        def _dspin(lo, hi, dec, step, val):
            s = QDoubleSpinBox()
            s.setRange(lo, hi)
            s.setDecimals(dec)
            s.setSingleStep(step)
            s.setValue(val)
            s.valueChanged.connect(self._on_brush_changed)
            return s

        def _ispin(lo, hi, val):
            s = QSpinBox()
            s.setRange(lo, hi)
            s.setValue(val)
            s.valueChanged.connect(self._on_brush_changed)
            return s

        # Amplitude + Frequency
        amp_row = QHBoxLayout()
        amp_row.addWidget(QLabel("Amplitude:"))
        self.meander_amplitude_spin = _dspin(0.1, 500.0, 1, 1.0, 8.0)
        amp_row.addWidget(self.meander_amplitude_spin)
        amp_row.addWidget(QLabel("Frequency:"))
        self.meander_frequency_spin = _dspin(0.001, 0.5, 3, 0.005, 0.03)
        amp_row.addWidget(self.meander_frequency_spin)
        meander_layout.addLayout(amp_row)

        # Samples + Seed
        samp_row = QHBoxLayout()
        samp_row.addWidget(QLabel("Samples:"))
        self.meander_samples_spin = _ispin(4, 200, 24)
        samp_row.addWidget(self.meander_samples_spin)
        samp_row.addWidget(QLabel("Seed (0=auto):"))
        self.meander_seed_spin = _ispin(0, 99999, 0)
        samp_row.addWidget(self.meander_seed_spin)
        meander_layout.addLayout(samp_row)

        # Animated + speed — note: animated drift only works in Full Path draw mode
        anim_row = QHBoxLayout()
        self.meander_animated_check = QCheckBox("Animated (Full Path only)")
        self.meander_animated_check.setToolTip(
            "Shifts the meander noise pattern each frame.\n"
            "Has no effect in Progressive draw mode — use Full Path for animated drift."
        )
        self.meander_animated_check.stateChanged.connect(self._on_meander_animated_toggled)
        anim_row.addWidget(self.meander_animated_check)
        anim_row.addWidget(QLabel("Speed:"))
        self.meander_anim_speed_spin = _dspin(0.001, 1.0, 3, 0.005, 0.01)
        anim_row.addWidget(self.meander_anim_speed_spin)
        anim_row.addStretch()
        meander_layout.addLayout(anim_row)

        # Scale along path
        sap_row = QHBoxLayout()
        self.meander_scale_along_path_check = QCheckBox("Scale Along Path")
        self.meander_scale_along_path_check.stateChanged.connect(self._on_brush_changed)
        sap_row.addWidget(self.meander_scale_along_path_check)
        sap_row.addWidget(QLabel("Freq:"))
        self.meander_sap_freq_spin = _dspin(0.001, 0.5, 3, 0.005, 0.05)
        sap_row.addWidget(self.meander_sap_freq_spin)
        sap_row.addWidget(QLabel("Range:"))
        self.meander_sap_range_spin = _dspin(0.0, 1.0, 2, 0.05, 0.4)
        sap_row.addWidget(self.meander_sap_range_spin)
        meander_layout.addLayout(sap_row)

        bs_layout.addWidget(self.meander_panel)

        brush_content_layout.addWidget(self.brush_settings_group)

        # Brush preview at bottom of Brushes tab
        preview_label = QLabel("Preview:")
        brush_content_layout.addWidget(preview_label)
        self.brush_preview = BrushPreviewWidget()
        self.brush_preview.setMinimumHeight(120)
        self.brush_preview.setMaximumHeight(180)
        brush_content_layout.addWidget(self.brush_preview)

        # ------------------------------------------------------------------
        # Stencils tab  (dedicated, after Brushes)
        # ------------------------------------------------------------------
        stencil_scroll = QScrollArea()
        stencil_scroll.setWidgetResizable(True)
        stencil_scroll.setFrameShape(QFrame.Shape.NoFrame)
        stencil_content = QWidget()
        stencil_content_layout = QVBoxLayout(stencil_content)
        stencil_content_layout.setSpacing(4)
        stencil_scroll.setWidget(stencil_content)
        self._stencils_tab_idx = inner_tabs.addTab(stencil_scroll, "Stamp")

        # Stencil image table (Name | Grid | Pixels | Use)
        self.stencil_table = QTableWidget()
        self.stencil_table.setColumnCount(4)
        self.stencil_table.setHorizontalHeaderLabels(["Name", "Grid", "Pixels", "Use"])
        sh = self.stencil_table.horizontalHeader()
        sh.setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        sh.setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
        sh.setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        sh.setSectionResizeMode(3, QHeaderView.ResizeMode.Fixed)
        self.stencil_table.setColumnWidth(3, 36)
        self.stencil_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.stencil_table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.stencil_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.stencil_table.setMaximumHeight(130)
        self.stencil_table.itemChanged.connect(self._on_stencil_table_changed)
        self.stencil_table.itemSelectionChanged.connect(self._update_stencil_preview)
        stencil_content_layout.addWidget(self.stencil_table)

        # Stencil buttons
        stencil_btn_row = QHBoxLayout()
        self.add_stencil_btn = QPushButton("Add...")
        self.add_stencil_btn.setToolTip("Add an existing stamp PNG from the project's stamps directory")
        self.add_stencil_btn.clicked.connect(self._on_add_stencil)
        stencil_btn_row.addWidget(self.add_stencil_btn)
        self.create_stencil_btn = QPushButton("Create...")
        self.create_stencil_btn.setToolTip("Open the stamp editor to create a new stamp")
        self.create_stencil_btn.clicked.connect(self._on_create_stencil)
        stencil_btn_row.addWidget(self.create_stencil_btn)
        self.edit_stencil_btn = QPushButton("Edit...")
        self.edit_stencil_btn.setToolTip("Edit the selected stamp in the stamp editor")
        self.edit_stencil_btn.clicked.connect(self._on_edit_stencil)
        stencil_btn_row.addWidget(self.edit_stencil_btn)
        self.remove_stencil_btn = QPushButton("Remove")
        self.remove_stencil_btn.clicked.connect(self._on_remove_stencil)
        stencil_btn_row.addWidget(self.remove_stencil_btn)
        stencil_btn_row.addStretch()
        stencil_content_layout.addLayout(stencil_btn_row)

        # Stencil settings
        self.stencil_settings_group = QGroupBox("Stamp Settings")
        ss_layout = QVBoxLayout(self.stencil_settings_group)

        # Draw mode
        s_draw_mode_row = QHBoxLayout()
        s_draw_mode_row.addWidget(QLabel("Draw Mode:"))
        self.stencil_draw_mode_combo = QComboBox()
        for dm in BrushDrawMode:
            self.stencil_draw_mode_combo.addItem(dm.name, dm)
        self.stencil_draw_mode_combo.currentIndexChanged.connect(self._on_stencil_changed)
        s_draw_mode_row.addWidget(self.stencil_draw_mode_combo)
        s_draw_mode_row.addStretch()
        ss_layout.addLayout(s_draw_mode_row)

        # Stamp spacing + easing
        s_spacing_row = QHBoxLayout()
        s_spacing_row.addWidget(QLabel("Stamp Spacing:"))
        self.stencil_stamp_spacing_spin = QDoubleSpinBox()
        self.stencil_stamp_spacing_spin.setRange(0.5, 999.0)
        self.stencil_stamp_spacing_spin.setDecimals(1)
        self.stencil_stamp_spacing_spin.setSingleStep(0.5)
        self.stencil_stamp_spacing_spin.valueChanged.connect(self._on_stencil_changed)
        s_spacing_row.addWidget(self.stencil_stamp_spacing_spin)
        s_spacing_row.addWidget(QLabel("Easing:"))
        self.stencil_spacing_easing_combo = QComboBox()
        easing_types = [
            "LINEAR", "EASE_IN_QUAD", "EASE_OUT_QUAD", "EASE_IN_OUT_QUAD",
            "EASE_IN_CUBIC", "EASE_OUT_CUBIC", "EASE_IN_OUT_CUBIC",
            "EASE_IN_QUART", "EASE_OUT_QUART", "EASE_IN_OUT_QUART",
            "EASE_IN_QUINT", "EASE_OUT_QUINT", "EASE_IN_OUT_QUINT",
            "EASE_IN_SINE", "EASE_OUT_SINE", "EASE_IN_OUT_SINE",
            "EASE_IN_EXPO", "EASE_OUT_EXPO", "EASE_IN_OUT_EXPO",
            "EASE_IN_CIRC", "EASE_OUT_CIRC", "EASE_IN_OUT_CIRC",
            "EASE_IN_ELASTIC", "EASE_OUT_ELASTIC", "EASE_IN_OUT_ELASTIC",
            "EASE_IN_BACK", "EASE_OUT_BACK", "EASE_IN_OUT_BACK",
            "EASE_IN_BOUNCE", "EASE_OUT_BOUNCE", "EASE_IN_OUT_BOUNCE",
        ]
        self.stencil_spacing_easing_combo.addItems(easing_types)
        self.stencil_spacing_easing_combo.currentTextChanged.connect(self._on_stencil_changed)
        s_spacing_row.addWidget(self.stencil_spacing_easing_combo)
        ss_layout.addLayout(s_spacing_row)

        # Follow tangent
        self.stencil_follow_tangent_check = QCheckBox("Follow Tangent")
        self.stencil_follow_tangent_check.stateChanged.connect(self._on_stencil_changed)
        ss_layout.addWidget(self.stencil_follow_tangent_check)

        # Perpendicular jitter
        s_perp_row = QHBoxLayout()
        s_perp_row.addWidget(QLabel("Perp. Jitter Min:"))
        self.stencil_perp_jitter_min_spin = QDoubleSpinBox()
        self.stencil_perp_jitter_min_spin.setRange(-50.0, 50.0)
        self.stencil_perp_jitter_min_spin.setDecimals(1)
        self.stencil_perp_jitter_min_spin.valueChanged.connect(self._on_stencil_changed)
        s_perp_row.addWidget(self.stencil_perp_jitter_min_spin)
        s_perp_row.addWidget(QLabel("Max:"))
        self.stencil_perp_jitter_max_spin = QDoubleSpinBox()
        self.stencil_perp_jitter_max_spin.setRange(-50.0, 50.0)
        self.stencil_perp_jitter_max_spin.setDecimals(1)
        self.stencil_perp_jitter_max_spin.valueChanged.connect(self._on_stencil_changed)
        s_perp_row.addWidget(self.stencil_perp_jitter_max_spin)
        ss_layout.addLayout(s_perp_row)

        # Scale min/max
        s_scale_row = QHBoxLayout()
        s_scale_row.addWidget(QLabel("Scale Min:"))
        self.stencil_scale_min_spin = QDoubleSpinBox()
        self.stencil_scale_min_spin.setRange(0.01, 10.0)
        self.stencil_scale_min_spin.setDecimals(2)
        self.stencil_scale_min_spin.setSingleStep(0.1)
        self.stencil_scale_min_spin.valueChanged.connect(self._on_stencil_changed)
        s_scale_row.addWidget(self.stencil_scale_min_spin)
        s_scale_row.addWidget(QLabel("Max:"))
        self.stencil_scale_max_spin = QDoubleSpinBox()
        self.stencil_scale_max_spin.setRange(0.01, 10.0)
        self.stencil_scale_max_spin.setDecimals(2)
        self.stencil_scale_max_spin.setSingleStep(0.1)
        self.stencil_scale_max_spin.valueChanged.connect(self._on_stencil_changed)
        s_scale_row.addWidget(self.stencil_scale_max_spin)
        ss_layout.addLayout(s_scale_row)

        # Progressive reveal
        self.stencil_progressive_group = QGroupBox("Progressive Reveal")
        s_prog_layout = QVBoxLayout(self.stencil_progressive_group)

        s_spf_row = QHBoxLayout()
        s_spf_row.addWidget(QLabel("Stamps/Frame:"))
        self.stencil_stamps_per_frame_spin = QSpinBox()
        self.stencil_stamps_per_frame_spin.setRange(1, 1000)
        self.stencil_stamps_per_frame_spin.valueChanged.connect(self._on_stencil_changed)
        s_spf_row.addWidget(self.stencil_stamps_per_frame_spin)
        s_spf_row.addWidget(QLabel("Agents:"))
        self.stencil_agent_count_spin = QSpinBox()
        self.stencil_agent_count_spin.setRange(1, 50)
        self.stencil_agent_count_spin.valueChanged.connect(self._on_stencil_changed)
        s_spf_row.addWidget(self.stencil_agent_count_spin)
        s_prog_layout.addLayout(s_spf_row)

        s_pcm_row = QHBoxLayout()
        s_pcm_row.addWidget(QLabel("Post-Completion:"))
        self.stencil_post_completion_combo = QComboBox()
        for pcm in PostCompletionMode:
            self.stencil_post_completion_combo.addItem(pcm.name, pcm)
        self.stencil_post_completion_combo.currentIndexChanged.connect(self._on_stencil_changed)
        s_pcm_row.addWidget(self.stencil_post_completion_combo)
        s_pcm_row.addStretch()
        s_prog_layout.addLayout(s_pcm_row)

        ss_layout.addWidget(self.stencil_progressive_group)

        stencil_content_layout.addWidget(self.stencil_settings_group)

        # Opacity Change — reuses SizeChangeEditor
        self.stencil_opacity_change_editor = SizeChangeEditor("Opacity Change")
        self.stencil_opacity_change_editor.setCheckable(False)
        self.stencil_opacity_change_editor.changed.connect(self._on_stencil_changed)
        stencil_content_layout.addWidget(self.stencil_opacity_change_editor)

        # Stencil preview at bottom
        stencil_preview_label = QLabel("Preview:")
        stencil_content_layout.addWidget(stencil_preview_label)
        self.stencil_preview = StencilPreviewWidget()
        self.stencil_preview.setMinimumHeight(120)
        self.stencil_preview.setMaximumHeight(180)
        stencil_content_layout.addWidget(self.stencil_preview)
        stencil_content_layout.addStretch()

        # Record the brushes tab index for show/hide logic
        self._brushes_tab_idx = inner_tabs.indexOf(brush_scroll)

        # ------------------------------------------------------------------
        # Point Change tab
        # ------------------------------------------------------------------
        point_scroll = QScrollArea()
        point_scroll.setWidgetResizable(True)
        point_scroll.setFrameShape(QFrame.Shape.NoFrame)
        point_content = QWidget()
        point_layout = QVBoxLayout(point_content)
        point_scroll.setWidget(point_content)
        inner_tabs.addTab(point_scroll, "Point Change")

        self.point_size_change_editor = SizeChangeEditor("Point Size Change", preview_mode='point')
        self.point_size_change_editor.setCheckable(False)
        self.point_size_change_editor.changed.connect(self._on_changed)
        point_layout.addWidget(self.point_size_change_editor)
        point_layout.addStretch()

        # ------------------------------------------------------------------
        # Stroke Change tab
        # ------------------------------------------------------------------
        stroke_scroll = QScrollArea()
        stroke_scroll.setWidgetResizable(True)
        stroke_scroll.setFrameShape(QFrame.Shape.NoFrame)
        stroke_content = QWidget()
        stroke_layout = QVBoxLayout(stroke_content)
        stroke_scroll.setWidget(stroke_content)
        inner_tabs.addTab(stroke_scroll, "Stroke Change")

        self.stroke_width_change_editor = SizeChangeEditor("Stroke Width Change", preview_mode='stroke')
        self.stroke_width_change_editor.setCheckable(False)
        self.stroke_width_change_editor.changed.connect(self._on_changed)
        stroke_layout.addWidget(self.stroke_width_change_editor)

        self.stroke_color_change_editor = ColorChangeEditor("Stroke Color Change")
        self.stroke_color_change_editor.setCheckable(False)
        self.stroke_color_change_editor.changed.connect(self._on_changed)
        stroke_layout.addWidget(self.stroke_color_change_editor)
        stroke_layout.addStretch()

        # ------------------------------------------------------------------
        # Fill Change tab
        # ------------------------------------------------------------------
        fill_scroll = QScrollArea()
        fill_scroll.setWidgetResizable(True)
        fill_scroll.setFrameShape(QFrame.Shape.NoFrame)
        fill_content = QWidget()
        fill_layout = QVBoxLayout(fill_content)
        fill_scroll.setWidget(fill_content)
        inner_tabs.addTab(fill_scroll, "Fill Change")

        self.fill_color_change_editor = FillColorChangeEditor("Fill Color Change")
        self.fill_color_change_editor.setCheckable(False)
        self.fill_color_change_editor.changed.connect(self._on_changed)
        fill_layout.addWidget(self.fill_color_change_editor)
        fill_layout.addStretch()

        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.addWidget(inner_tabs)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def set_renderer(self, renderer: Optional[Renderer]) -> None:
        self._updating = True
        self._renderer = renderer

        enabled = renderer is not None
        self.setEnabled(enabled)

        if renderer:
            self.mode_dropdown.set_value(renderer.mode)
            self.stroke_width_spin.setValue(renderer.stroke_width)
            self.stroke_color_picker.set_color(renderer.stroke_color)
            self.fill_color_picker.set_color(renderer.fill_color)
            self.point_size_spin.setValue(renderer.point_size)
            self.hold_length_spin.setValue(renderer.hold_length)
            self.point_stroked_check.setChecked(renderer.point_stroked)
            self.point_filled_check.setChecked(renderer.point_filled)

            self.stroke_width_change_editor.set_change(renderer.stroke_width_change)
            self.stroke_color_change_editor.set_change(renderer.stroke_color_change)
            self.fill_color_change_editor.set_change(renderer.fill_color_change)
            self.point_size_change_editor.set_change(renderer.point_size_change)

            self._load_brush_config(renderer.brush_config)
            self._load_stencil_config(renderer.stencil_config)
            self._update_mode_visibility()

        self._updating = False

    def set_brushes_dir(self, path: str) -> None:
        self._brushes_dir = path

    def set_stencils_dir(self, path: str) -> None:
        self._stencils_dir = path

    def set_palettes_dir(self, path: str) -> None:
        self._palettes_dir = path
        self.stroke_width_change_editor.set_palettes_dir(path)
        self.stroke_color_change_editor.set_palettes_dir(path)
        self.point_size_change_editor.set_palettes_dir(path)
        self.fill_color_change_editor.set_palettes_dir(path)
        self.stencil_opacity_change_editor.set_palettes_dir(path)

    # ------------------------------------------------------------------
    # Brush helpers
    # ------------------------------------------------------------------

    def _brush_dims(self, filename: str):
        """Return (grid_w, grid_h, px_w, px_h) for a brush PNG, or Nones if unavailable."""
        if not self._brushes_dir:
            return None, None, None, None
        filepath = os.path.join(self._brushes_dir, filename)
        if not os.path.exists(filepath):
            return None, None, None, None
        img = QImage(filepath)
        if img.isNull():
            return None, None, None, None
        px_w, px_h = img.width(), img.height()
        grid_w, grid_h = px_w, px_h  # default: same as pixel dims
        meta_path = filepath + ".meta.json"
        if os.path.exists(meta_path):
            try:
                with open(meta_path) as f:
                    meta = json.load(f)
                grid_w = meta.get("grid_w", px_w)
                grid_h = meta.get("grid_h", px_h)
            except Exception:
                pass
        return grid_w, grid_h, px_w, px_h

    def _add_brush_row(self, filename: str, enabled: bool = True):
        """Append a row to brush_table for the given filename."""
        row = self.brush_table.rowCount()
        self.brush_table.insertRow(row)

        name_item = QTableWidgetItem(filename)
        name_item.setFlags(name_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
        self.brush_table.setItem(row, 0, name_item)

        grid_w, grid_h, px_w, px_h = self._brush_dims(filename)
        grid_text = f"{grid_w}×{grid_h}" if grid_w is not None else "?"
        px_text = f"{px_w}×{px_h}" if px_w is not None else "?"

        grid_item = QTableWidgetItem(grid_text)
        grid_item.setFlags(grid_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
        grid_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
        self.brush_table.setItem(row, 1, grid_item)

        px_item = QTableWidgetItem(px_text)
        px_item.setFlags(px_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
        px_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
        self.brush_table.setItem(row, 2, px_item)

        use_item = QTableWidgetItem()
        use_item.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled)
        use_item.setCheckState(Qt.CheckState.Checked if enabled else Qt.CheckState.Unchecked)
        use_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
        self.brush_table.setItem(row, 3, use_item)

    def _update_brush_preview(self):
        """Load the selected brush image into the preview widget."""
        row = self.brush_table.currentRow()
        if row < 0 or not self._brushes_dir:
            self.brush_preview.set_image(None)
            return
        name_item = self.brush_table.item(row, 0)
        if not name_item:
            self.brush_preview.set_image(None)
            return
        filepath = os.path.join(self._brushes_dir, name_item.text())
        if not os.path.exists(filepath):
            self.brush_preview.set_image(None)
            return
        img = QImage(filepath)
        self.brush_preview.set_image(img if not img.isNull() else None)

    # ------------------------------------------------------------------
    # Mode / visibility
    # ------------------------------------------------------------------

    def _on_mode_changed(self, *args) -> None:
        self._update_mode_visibility()
        self._on_changed()

    def _update_mode_visibility(self) -> None:
        mode = self.mode_dropdown.get_value()

        has_stroke = mode in (RenderMode.STROKED, RenderMode.FILLED_STROKED)
        has_fill = mode in (RenderMode.FILLED, RenderMode.FILLED_STROKED)
        has_points = mode == RenderMode.POINTS
        has_brush = mode == RenderMode.BRUSHED
        has_stencil = mode == RenderMode.STAMPED

        point_stroked = has_points and self.point_stroked_check.isChecked()
        self.stroke_width_spin.setEnabled(has_stroke or point_stroked)
        self.stroke_color_picker.setEnabled(has_stroke or point_stroked or has_brush)
        self.stroke_width_change_editor.setEnabled(has_stroke or has_points)
        self.stroke_color_change_editor.setEnabled(has_stroke or has_brush or has_points)

        point_filled = has_points and self.point_filled_check.isChecked()
        self.fill_color_picker.setEnabled(has_fill or point_filled)
        self.fill_color_change_editor.setEnabled(has_fill)

        self.point_size_spin.setEnabled(has_points)
        self.point_stroked_check.setEnabled(has_points)
        self.point_filled_check.setEnabled(has_points)
        self.point_size_change_editor.setEnabled(has_points)

        # Brushes tab content enabled only in BRUSHED mode
        self.brush_table.setEnabled(has_brush)
        self.add_brush_btn.setEnabled(has_brush)
        self.create_brush_btn.setEnabled(has_brush)
        self.edit_brush_btn.setEnabled(has_brush)
        self.remove_brush_btn.setEnabled(has_brush)
        self.brush_settings_group.setEnabled(has_brush)
        self.brush_preview.setEnabled(has_brush)

        if has_brush:
            is_progressive = self.draw_mode_combo.currentData() == BrushDrawMode.PROGRESSIVE
            self.progressive_group.setVisible(is_progressive)
        else:
            self.progressive_group.setVisible(False)

        # Stencils tab content enabled only in STAMPED mode
        self.stencil_table.setEnabled(has_stencil)
        self.add_stencil_btn.setEnabled(has_stencil)
        self.create_stencil_btn.setEnabled(has_stencil)
        self.edit_stencil_btn.setEnabled(has_stencil)
        self.remove_stencil_btn.setEnabled(has_stencil)
        self.stencil_settings_group.setEnabled(has_stencil)
        self.stencil_opacity_change_editor.setEnabled(has_stencil)
        self.stencil_preview.setEnabled(has_stencil)

        if has_stencil:
            is_progressive = self.stencil_draw_mode_combo.currentData() == BrushDrawMode.PROGRESSIVE
            self.stencil_progressive_group.setVisible(is_progressive)
        else:
            self.stencil_progressive_group.setVisible(False)

        # Show/hide Brushes and Stencils tabs based on mode
        self._inner_tabs.setTabVisible(self._brushes_tab_idx, has_brush)
        self._inner_tabs.setTabVisible(self._stencils_tab_idx, has_stencil)

    def _on_point_style_changed(self, *args) -> None:
        self._update_mode_visibility()
        self._on_changed()

    # ------------------------------------------------------------------
    # Load / get brush config
    # ------------------------------------------------------------------

    def _load_brush_config(self, config: 'Optional[BrushConfig]') -> None:
        if config is None:
            config = BrushConfig()

        self.brush_table.blockSignals(True)
        self.brush_table.setRowCount(0)
        for i, name in enumerate(config.brush_names):
            en = config.brush_enabled[i] if i < len(config.brush_enabled) else True
            self._add_brush_row(name, en)
        self.brush_table.blockSignals(False)

        self._update_brush_preview()

        idx = self.draw_mode_combo.findData(config.draw_mode)
        if idx >= 0:
            self.draw_mode_combo.setCurrentIndex(idx)

        self.stamp_spacing_spin.setValue(config.stamp_spacing)
        easing_idx = self.spacing_easing_combo.findText(config.spacing_easing)
        if easing_idx >= 0:
            self.spacing_easing_combo.setCurrentIndex(easing_idx)

        self.follow_tangent_check.setChecked(config.follow_tangent)
        self.perp_jitter_min_spin.setValue(config.perpendicular_jitter_min)
        self.perp_jitter_max_spin.setValue(config.perpendicular_jitter_max)
        self.brush_scale_min_spin.setValue(config.scale_min)
        self.brush_scale_max_spin.setValue(config.scale_max)
        self.opacity_min_spin.setValue(config.opacity_min)
        self.opacity_max_spin.setValue(config.opacity_max)
        self.stamps_per_frame_spin.setValue(config.stamps_per_frame)
        self.agent_count_spin.setValue(config.agent_count)

        pcm_idx = self.post_completion_combo.findData(config.post_completion_mode)
        if pcm_idx >= 0:
            self.post_completion_combo.setCurrentIndex(pcm_idx)

        self.blur_radius_spin.setValue(config.blur_radius)

        mc = config.meander_config
        self.meander_enabled_check.setChecked(mc.enabled)
        if mc.enabled and not self.meander_toggle_btn.isChecked():
            self.meander_toggle_btn.setChecked(True)
        self.meander_amplitude_spin.setValue(mc.amplitude)
        self.meander_frequency_spin.setValue(mc.frequency)
        self.meander_samples_spin.setValue(mc.samples)
        self.meander_seed_spin.setValue(mc.seed)
        self.meander_animated_check.setChecked(mc.animated)
        self.meander_anim_speed_spin.setValue(mc.anim_speed)
        self.meander_anim_speed_spin.setEnabled(mc.animated)
        self.meander_scale_along_path_check.setChecked(mc.scale_along_path)
        self.meander_sap_freq_spin.setValue(mc.scale_along_path_frequency)
        self.meander_sap_range_spin.setValue(mc.scale_along_path_range)

    def _get_brush_config(self) -> BrushConfig:
        names, enabled = [], []
        for i in range(self.brush_table.rowCount()):
            ni = self.brush_table.item(i, 0)
            ui = self.brush_table.item(i, 3)
            if ni:
                names.append(ni.text())
                enabled.append(ui.checkState() == Qt.CheckState.Checked if ui else True)
        return BrushConfig(
            brush_names=names,
            brush_enabled=enabled,
            draw_mode=self.draw_mode_combo.currentData() or BrushDrawMode.FULL_PATH,
            stamp_spacing=self.stamp_spacing_spin.value(),
            spacing_easing=self.spacing_easing_combo.currentText(),
            follow_tangent=self.follow_tangent_check.isChecked(),
            perpendicular_jitter_min=self.perp_jitter_min_spin.value(),
            perpendicular_jitter_max=self.perp_jitter_max_spin.value(),
            scale_min=self.brush_scale_min_spin.value(),
            scale_max=self.brush_scale_max_spin.value(),
            opacity_min=self.opacity_min_spin.value(),
            opacity_max=self.opacity_max_spin.value(),
            stamps_per_frame=self.stamps_per_frame_spin.value(),
            agent_count=self.agent_count_spin.value(),
            post_completion_mode=self.post_completion_combo.currentData() or PostCompletionMode.HOLD,
            blur_radius=self.blur_radius_spin.value(),
            meander_config=MeanderConfig(
                enabled=self.meander_enabled_check.isChecked(),
                amplitude=self.meander_amplitude_spin.value(),
                frequency=self.meander_frequency_spin.value(),
                samples=self.meander_samples_spin.value(),
                seed=self.meander_seed_spin.value(),
                animated=self.meander_animated_check.isChecked(),
                anim_speed=self.meander_anim_speed_spin.value(),
                scale_along_path=self.meander_scale_along_path_check.isChecked(),
                scale_along_path_frequency=self.meander_sap_freq_spin.value(),
                scale_along_path_range=self.meander_sap_range_spin.value(),
            )
        )

    # ------------------------------------------------------------------
    # Brush list actions
    # ------------------------------------------------------------------

    def _on_brush_selection_changed(self) -> None:
        self._update_brush_preview()

    def _on_brush_table_changed(self, item: QTableWidgetItem) -> None:
        """Only the Use checkbox in col 3 is user-editable; treat as a brush change."""
        if item.column() == 3 and not self._updating:
            self._on_brush_changed()

    def _on_add_brush(self) -> None:
        if self._brushes_dir and os.path.isdir(self._brushes_dir):
            available = sorted(
                f for f in os.listdir(self._brushes_dir)
                if f.lower().endswith(".png")
            )
            if available:
                existing = {self.brush_table.item(i, 0).text()
                            for i in range(self.brush_table.rowCount())
                            if self.brush_table.item(i, 0)}
                choices = [f for f in available if f not in existing]
                if choices:
                    name, ok = QInputDialog.getItem(
                        self, "Add Brush", "Select a brush from the project:",
                        choices, 0, False
                    )
                    if ok and name:
                        self.brush_table.blockSignals(True)
                        self._add_brush_row(name, True)
                        self.brush_table.blockSignals(False)
                        self._on_brush_changed()
                    return
                else:
                    QMessageBox.information(
                        self, "No Brushes",
                        "All available brushes are already added.\n"
                        "Use 'Create...' to make a new brush."
                    )
                    return

        name, ok = QInputDialog.getText(self, "Add Brush", "Brush PNG filename:")
        if ok and name.strip():
            name = name.strip()
            if not name.lower().endswith(".png"):
                name += ".png"
            self.brush_table.blockSignals(True)
            self._add_brush_row(name, True)
            self.brush_table.blockSignals(False)
            self._on_brush_changed()

    def _open_brush_editor(self, initial_file=None) -> None:
        from .widgets.brush_editor_window import BrushEditorWindow
        if self._editor_window and self._editor_window.isVisible():
            self._editor_window.raise_()
            self._editor_window.activateWindow()
            if initial_file:
                self._editor_window.open_file(initial_file)
            return
        self._editor_window = BrushEditorWindow(
            self._brushes_dir, initial_file=initial_file, parent=None)
        def on_saved(filename):
            existing = {self.brush_table.item(i, 0).text()
                        for i in range(self.brush_table.rowCount())
                        if self.brush_table.item(i, 0)}
            if filename not in existing:
                self.brush_table.blockSignals(True)
                self._add_brush_row(filename, True)
                self.brush_table.blockSignals(False)
                self._on_brush_changed()
            else:
                # Refresh dims for the existing row
                for i in range(self.brush_table.rowCount()):
                    ni = self.brush_table.item(i, 0)
                    if ni and ni.text() == filename:
                        grid_w, grid_h, px_w, px_h = self._brush_dims(filename)
                        gi = self.brush_table.item(i, 1)
                        pi = self.brush_table.item(i, 2)
                        if gi:
                            gi.setText(f"{grid_w}×{grid_h}" if grid_w else "?")
                        if pi:
                            pi.setText(f"{px_w}×{px_h}" if px_w else "?")
                        break
                self._update_brush_preview()
        self._editor_window.brushSaved.connect(on_saved)
        self._editor_window.show()

    def _on_create_brush(self) -> None:
        if not self._brushes_dir:
            QMessageBox.warning(self, "No Project",
                                "Save or open a project first to create brushes.")
            return
        os.makedirs(self._brushes_dir, exist_ok=True)
        self._open_brush_editor(initial_file=None)

    def _on_edit_brush(self) -> None:
        row = self.brush_table.currentRow()
        ni = self.brush_table.item(row, 0) if row >= 0 else None
        if not ni:
            QMessageBox.information(self, "No Selection", "Select a brush to edit.")
            return
        if not self._brushes_dir:
            QMessageBox.warning(self, "No Project",
                                "Save or open a project first to edit brushes.")
            return
        filepath = os.path.join(self._brushes_dir, ni.text())
        if not os.path.exists(filepath):
            return
        self._open_brush_editor(initial_file=filepath)

    def _on_remove_brush(self) -> None:
        row = self.brush_table.currentRow()
        if row >= 0:
            self.brush_table.removeRow(row)
            self._update_brush_preview()
            self._on_brush_changed()

    def _on_meander_panel_toggled(self, checked: bool) -> None:
        self.meander_panel.setVisible(checked)
        self.meander_toggle_btn.setText("▼ Meander Path" if checked else "▶ Meander Path")

    def _on_meander_animated_toggled(self, state) -> None:
        self.meander_anim_speed_spin.setEnabled(bool(state))
        self._on_brush_changed()

    def _on_brush_changed(self, *args) -> None:
        if self._updating:
            return
        is_progressive = self.draw_mode_combo.currentData() == BrushDrawMode.PROGRESSIVE
        self.progressive_group.setVisible(is_progressive)
        self._on_changed()

    # ------------------------------------------------------------------
    # Stencil helpers
    # ------------------------------------------------------------------

    def _stencil_dims(self, filename: str):
        """Return (grid_w, grid_h, px_w, px_h) for a stencil PNG, or Nones if unavailable."""
        if not self._stencils_dir:
            return None, None, None, None
        filepath = os.path.join(self._stencils_dir, filename)
        if not os.path.exists(filepath):
            return None, None, None, None
        img = QImage(filepath)
        if img.isNull():
            return None, None, None, None
        px_w, px_h = img.width(), img.height()
        grid_w, grid_h = px_w, px_h
        meta_path = filepath + ".meta.json"
        if os.path.exists(meta_path):
            try:
                with open(meta_path) as f:
                    meta = json.load(f)
                grid_w = meta.get("grid_w", px_w)
                grid_h = meta.get("grid_h", px_h)
            except Exception:
                pass
        return grid_w, grid_h, px_w, px_h

    def _add_stencil_row(self, filename: str, enabled: bool = True):
        """Append a row to stencil_table for the given filename."""
        row = self.stencil_table.rowCount()
        self.stencil_table.insertRow(row)

        name_item = QTableWidgetItem(filename)
        name_item.setFlags(name_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
        self.stencil_table.setItem(row, 0, name_item)

        grid_w, grid_h, px_w, px_h = self._stencil_dims(filename)
        grid_text = f"{grid_w}×{grid_h}" if grid_w is not None else "?"
        px_text = f"{px_w}×{px_h}" if px_w is not None else "?"

        grid_item = QTableWidgetItem(grid_text)
        grid_item.setFlags(grid_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
        grid_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
        self.stencil_table.setItem(row, 1, grid_item)

        px_item = QTableWidgetItem(px_text)
        px_item.setFlags(px_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
        px_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
        self.stencil_table.setItem(row, 2, px_item)

        use_item = QTableWidgetItem()
        use_item.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled)
        use_item.setCheckState(Qt.CheckState.Checked if enabled else Qt.CheckState.Unchecked)
        use_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
        self.stencil_table.setItem(row, 3, use_item)

    def _load_stencil_config(self, config: 'Optional[StencilConfig]') -> None:
        if config is None:
            config = StencilConfig()

        self.stencil_table.blockSignals(True)
        self.stencil_table.setRowCount(0)
        for i, name in enumerate(config.stencil_names):
            en = config.stencil_enabled[i] if i < len(config.stencil_enabled) else True
            self._add_stencil_row(name, en)
        self.stencil_table.blockSignals(False)

        self._update_stencil_preview()

        idx = self.stencil_draw_mode_combo.findData(config.draw_mode)
        if idx >= 0:
            self.stencil_draw_mode_combo.setCurrentIndex(idx)

        self.stencil_stamp_spacing_spin.setValue(config.stamp_spacing)
        easing_idx = self.stencil_spacing_easing_combo.findText(config.spacing_easing)
        if easing_idx >= 0:
            self.stencil_spacing_easing_combo.setCurrentIndex(easing_idx)

        self.stencil_follow_tangent_check.setChecked(config.follow_tangent)
        self.stencil_perp_jitter_min_spin.setValue(config.perpendicular_jitter_min)
        self.stencil_perp_jitter_max_spin.setValue(config.perpendicular_jitter_max)
        self.stencil_scale_min_spin.setValue(config.scale_min)
        self.stencil_scale_max_spin.setValue(config.scale_max)
        self.stencil_stamps_per_frame_spin.setValue(config.stamps_per_frame)
        self.stencil_agent_count_spin.setValue(config.agent_count)

        pcm_idx = self.stencil_post_completion_combo.findData(config.post_completion_mode)
        if pcm_idx >= 0:
            self.stencil_post_completion_combo.setCurrentIndex(pcm_idx)

        self.stencil_opacity_change_editor.set_change(config.opacity_change)

    def _get_stencil_config(self) -> StencilConfig:
        names, enabled = [], []
        for i in range(self.stencil_table.rowCount()):
            ni = self.stencil_table.item(i, 0)
            ui = self.stencil_table.item(i, 3)
            if ni:
                names.append(ni.text())
                enabled.append(ui.checkState() == Qt.CheckState.Checked if ui else True)
        opacity_change = self.stencil_opacity_change_editor.get_change()
        opacity_change.enabled = self._renderer.stencil_config.opacity_change.enabled if (
            self._renderer and self._renderer.stencil_config
        ) else False
        return StencilConfig(
            stencil_names=names,
            stencil_enabled=enabled,
            draw_mode=self.stencil_draw_mode_combo.currentData() or BrushDrawMode.FULL_PATH,
            stamp_spacing=self.stencil_stamp_spacing_spin.value(),
            spacing_easing=self.stencil_spacing_easing_combo.currentText(),
            follow_tangent=self.stencil_follow_tangent_check.isChecked(),
            perpendicular_jitter_min=self.stencil_perp_jitter_min_spin.value(),
            perpendicular_jitter_max=self.stencil_perp_jitter_max_spin.value(),
            scale_min=self.stencil_scale_min_spin.value(),
            scale_max=self.stencil_scale_max_spin.value(),
            stamps_per_frame=self.stencil_stamps_per_frame_spin.value(),
            agent_count=self.stencil_agent_count_spin.value(),
            post_completion_mode=self.stencil_post_completion_combo.currentData() or PostCompletionMode.HOLD,
            opacity_change=opacity_change
        )

    def _on_stencil_table_changed(self, item: QTableWidgetItem) -> None:
        if item.column() == 3 and not self._updating:
            self._on_stencil_changed()

    def _on_add_stencil(self) -> None:
        if self._stencils_dir and os.path.isdir(self._stencils_dir):
            available = sorted(
                f for f in os.listdir(self._stencils_dir)
                if f.lower().endswith(".png")
            )
            if available:
                existing = {self.stencil_table.item(i, 0).text()
                            for i in range(self.stencil_table.rowCount())
                            if self.stencil_table.item(i, 0)}
                choices = [f for f in available if f not in existing]
                if choices:
                    name, ok = QInputDialog.getItem(
                        self, "Add Stamp", "Select a stamp from the project:",
                        choices, 0, False
                    )
                    if ok and name:
                        self.stencil_table.blockSignals(True)
                        self._add_stencil_row(name, True)
                        self.stencil_table.blockSignals(False)
                        self._on_stencil_changed()
                    return
                else:
                    QMessageBox.information(
                        self, "No Stamps",
                        "All available stencils are already added.\n"
                        "Use 'Create...' to make a new stamp."
                    )
                    return

        name, ok = QInputDialog.getText(self, "Add Stamp", "Stamp PNG filename:")
        if ok and name.strip():
            name = name.strip()
            if not name.lower().endswith(".png"):
                name += ".png"
            self.stencil_table.blockSignals(True)
            self._add_stencil_row(name, True)
            self.stencil_table.blockSignals(False)
            self._on_stencil_changed()

    def _open_stencil_editor(self, initial_file=None) -> None:
        from .widgets.stencil_editor_window import StencilEditorWindow
        if self._stencil_editor_window and self._stencil_editor_window.isVisible():
            self._stencil_editor_window.raise_()
            self._stencil_editor_window.activateWindow()
            if initial_file:
                self._stencil_editor_window.open_file(initial_file)
            return
        self._stencil_editor_window = StencilEditorWindow(
            self._stencils_dir, initial_file=initial_file, parent=None)
        def on_saved(filename):
            existing = {self.stencil_table.item(i, 0).text()
                        for i in range(self.stencil_table.rowCount())
                        if self.stencil_table.item(i, 0)}
            if filename not in existing:
                self.stencil_table.blockSignals(True)
                self._add_stencil_row(filename, True)
                self.stencil_table.blockSignals(False)
                self._on_stencil_changed()
            else:
                for i in range(self.stencil_table.rowCount()):
                    ni = self.stencil_table.item(i, 0)
                    if ni and ni.text() == filename:
                        grid_w, grid_h, px_w, px_h = self._stencil_dims(filename)
                        gi = self.stencil_table.item(i, 1)
                        pi = self.stencil_table.item(i, 2)
                        if gi:
                            gi.setText(f"{grid_w}×{grid_h}" if grid_w else "?")
                        if pi:
                            pi.setText(f"{px_w}×{px_h}" if px_w else "?")
                        break
        self._stencil_editor_window.stencilSaved.connect(on_saved)
        self._stencil_editor_window.show()

    def _on_create_stencil(self) -> None:
        if not self._stencils_dir:
            QMessageBox.warning(self, "No Project",
                                "Save or open a project first to create stamps.")
            return
        os.makedirs(self._stencils_dir, exist_ok=True)
        self._open_stencil_editor(initial_file=None)

    def _on_edit_stencil(self) -> None:
        row = self.stencil_table.currentRow()
        ni = self.stencil_table.item(row, 0) if row >= 0 else None
        if not ni:
            QMessageBox.information(self, "No Selection", "Select a stamp to edit.")
            return
        if not self._stencils_dir:
            QMessageBox.warning(self, "No Project",
                                "Save or open a project first to edit stamps.")
            return
        filepath = os.path.join(self._stencils_dir, ni.text())
        if not os.path.exists(filepath):
            return
        self._open_stencil_editor(initial_file=filepath)

    def _update_stencil_preview(self) -> None:
        row = self.stencil_table.currentRow()
        if row < 0 or not self._stencils_dir:
            self.stencil_preview.set_image(None)
            return
        name_item = self.stencil_table.item(row, 0)
        if not name_item:
            self.stencil_preview.set_image(None)
            return
        filepath = os.path.join(self._stencils_dir, name_item.text())
        if not os.path.exists(filepath):
            self.stencil_preview.set_image(None)
            return
        img = QImage(filepath)
        if not img.isNull():
            img = img.convertToFormat(QImage.Format.Format_ARGB32)
        self.stencil_preview.set_image(img if not img.isNull() else None)

    def _on_remove_stencil(self) -> None:
        row = self.stencil_table.currentRow()
        if row >= 0:
            self.stencil_table.removeRow(row)
            self._update_stencil_preview()
            self._on_stencil_changed()

    def _on_stencil_changed(self, *args) -> None:
        if self._updating:
            return
        is_progressive = self.stencil_draw_mode_combo.currentData() == BrushDrawMode.PROGRESSIVE
        self.stencil_progressive_group.setVisible(is_progressive)
        self._on_changed()

    def _on_changed(self, *args) -> None:
        if self._updating or self._renderer is None:
            return

        self._renderer.mode = self.mode_dropdown.get_value()
        self._renderer.stroke_width = self.stroke_width_spin.value()
        self._renderer.stroke_color = self.stroke_color_picker.get_color()
        self._renderer.fill_color = self.fill_color_picker.get_color()
        self._renderer.point_size = self.point_size_spin.value()
        self._renderer.hold_length = self.hold_length_spin.value()
        self._renderer.point_stroked = self.point_stroked_check.isChecked()
        self._renderer.point_filled = self.point_filled_check.isChecked()

        sw_change = self.stroke_width_change_editor.get_change()
        sw_change.enabled = self._renderer.stroke_width_change.enabled
        self._renderer.stroke_width_change = sw_change

        sc_change = self.stroke_color_change_editor.get_change()
        sc_change.enabled = self._renderer.stroke_color_change.enabled
        self._renderer.stroke_color_change = sc_change

        fc_change = self.fill_color_change_editor.get_change()
        fc_change.enabled = self._renderer.fill_color_change.enabled
        self._renderer.fill_color_change = fc_change

        ps_change = self.point_size_change_editor.get_change()
        ps_change.enabled = self._renderer.point_size_change.enabled
        self._renderer.point_size_change = ps_change

        if self._renderer.mode == RenderMode.BRUSHED:
            self._renderer.brush_config = self._get_brush_config()
        # preserve brush_config when mode changes away from BRUSHED

        if self._renderer.mode == RenderMode.STAMPED:
            self._renderer.stencil_config = self._get_stencil_config()
        # preserve stencil_config when mode changes away from STENCILED

        self.changed.emit()


class RendererSetConfigPanel(QGroupBox):
    """Configuration panel for renderer set playback settings."""

    changed = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__("Set Configuration", parent)
        self._renderer_set: Optional[RendererSet] = None
        self._updating = False

        layout = QVBoxLayout(self)

        # Playback mode
        mode_row = QHBoxLayout()
        mode_row.addWidget(QLabel("Mode:"))
        self.mode_combo = QComboBox()
        for mode in PlaybackMode:
            self.mode_combo.addItem(mode.name, mode)
        self.mode_combo.currentIndexChanged.connect(self._on_changed)
        mode_row.addWidget(self.mode_combo)
        layout.addLayout(mode_row)

        # Preferred renderer
        pref_row = QHBoxLayout()
        pref_row.addWidget(QLabel("Preferred:"))
        self.preferred_combo = QComboBox()
        self.preferred_combo.currentTextChanged.connect(self._on_changed)
        pref_row.addWidget(self.preferred_combo)
        layout.addLayout(pref_row)

        # Probability
        prob_row = QHBoxLayout()
        prob_row.addWidget(QLabel("Probability:"))
        self.probability_spin = QDoubleSpinBox()
        self.probability_spin.setRange(0.0, 100.0)
        self.probability_spin.setSuffix("%")
        self.probability_spin.valueChanged.connect(self._on_changed)
        prob_row.addWidget(self.probability_spin)
        layout.addLayout(prob_row)

        # Modify parameters checkbox
        self.modify_params_check = QCheckBox("Modify Internal Parameters")
        self.modify_params_check.setToolTip(
            "OFF: each draw cycle starts from the renderer's base values (clean slate).\n"
            "ON: dynamic rendering changes (colour cycling, stroke width progression, etc.) "
            "accumulate continuously across draw cycles."
        )
        self.modify_params_check.stateChanged.connect(self._on_changed)
        layout.addWidget(self.modify_params_check)

    def set_renderer_set(self, renderer_set: Optional[RendererSet]) -> None:
        self._updating = True
        self._renderer_set = renderer_set

        enabled = renderer_set is not None
        self.setEnabled(enabled)

        if renderer_set:
            index = self.mode_combo.findData(renderer_set.playback_mode)
            if index >= 0:
                self.mode_combo.setCurrentIndex(index)

            self.preferred_combo.clear()
            self.preferred_combo.addItem("")
            for r in renderer_set.renderers:
                self.preferred_combo.addItem(r.name)
            if renderer_set.preferred_renderer:
                index = self.preferred_combo.findText(renderer_set.preferred_renderer)
                if index >= 0:
                    self.preferred_combo.setCurrentIndex(index)

            self.probability_spin.setValue(renderer_set.preferred_probability)
            self.modify_params_check.setChecked(renderer_set.modify_internal_parameters)

        self._updating = False

    def _on_changed(self, *args) -> None:
        if self._updating or self._renderer_set is None:
            return

        self._renderer_set.playback_mode = self.mode_combo.currentData()
        self._renderer_set.preferred_renderer = self.preferred_combo.currentText()
        self._renderer_set.preferred_probability = self.probability_spin.value()
        self._renderer_set.modify_internal_parameters = self.modify_params_check.isChecked()

        self.changed.emit()


class RenderingTab(QWidget):
    """Main rendering configuration tab."""

    modified = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._library: Optional[RendererSetLibrary] = None
        self._current_set: Optional[RendererSet] = None
        self._current_renderer: Optional[Renderer] = None

        layout = QHBoxLayout(self)

        splitter = QSplitter(Qt.Orientation.Horizontal)

        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)
        left_layout.setContentsMargins(0, 0, 0, 0)

        self.library_label = QLabel("Library: (none)")
        left_layout.addWidget(self.library_label)

        self.tree_widget = RendererTreeWidget()
        self.tree_widget.selectionChanged.connect(self._on_selection_changed)
        self.tree_widget.libraryModified.connect(self._on_library_modified)
        left_layout.addWidget(self.tree_widget)

        self.set_config_panel = RendererSetConfigPanel()
        self.set_config_panel.changed.connect(self._on_library_modified)
        left_layout.addWidget(self.set_config_panel)

        splitter.addWidget(left_panel)

        right_panel = QWidget()
        right_layout = QVBoxLayout(right_panel)
        right_layout.setContentsMargins(0, 0, 0, 0)

        self.renderer_label = QLabel("Renderer: (none)")
        right_layout.addWidget(self.renderer_label)

        self.renderer_editor = RendererEditor()
        self.renderer_editor.changed.connect(self._on_library_modified)
        right_layout.addWidget(self.renderer_editor)

        splitter.addWidget(right_panel)
        splitter.setSizes([300, 600])

        layout.addWidget(splitter)

    def set_library(self, library: Optional[RendererSetLibrary]) -> None:
        self._library = library
        self._current_set = None
        self._current_renderer = None

        if library:
            self.library_label.setText(f"Library: {library.name}")
            self.tree_widget.set_library(library)
        else:
            self.library_label.setText("Library: (none)")
            self.tree_widget.set_library(RendererSetLibrary(name="Empty"))

        self.set_config_panel.set_renderer_set(None)
        self.renderer_editor.set_renderer(None)
        self.renderer_label.setText("Renderer: (none)")

    def set_project_dir(self, project_dir: str) -> None:
        brushes_dir = os.path.join(project_dir, "brushes")
        os.makedirs(brushes_dir, exist_ok=True)
        self.renderer_editor.set_brushes_dir(brushes_dir)

        stencils_dir = os.path.join(project_dir, "stamps")
        os.makedirs(stencils_dir, exist_ok=True)
        self.renderer_editor.set_stencils_dir(stencils_dir)

        palettes_dir = os.path.join(project_dir, "palettes")
        os.makedirs(palettes_dir, exist_ok=True)
        self.renderer_editor.set_palettes_dir(palettes_dir)

    def get_library(self) -> Optional[RendererSetLibrary]:
        return self._library

    def _on_selection_changed(self, set_name: str, renderer_name: Optional[str]) -> None:
        if not self._library:
            return

        self._current_set = self._library.get_renderer_set(set_name)
        self.set_config_panel.set_renderer_set(self._current_set)

        if renderer_name and self._current_set:
            self._current_renderer = self._current_set.get_renderer(renderer_name)
            self.renderer_label.setText(f"Renderer: {renderer_name}")
        else:
            self._current_renderer = None
            self.renderer_label.setText("Renderer: (none selected)")

        self.renderer_editor.set_renderer(self._current_renderer)

    def _on_library_modified(self) -> None:
        if self._current_set is not None:
            any_changes = any(r.has_any_changes() for r in self._current_set.renderers)
            if any_changes and not self._current_set.modify_internal_parameters:
                self._current_set.modify_internal_parameters = True
                self.set_config_panel.set_renderer_set(self._current_set)

        self.modified.emit()

    def create_default_library(self) -> RendererSetLibrary:
        library = RendererSetLibrary(name="MainLibrary")
        default_set = RendererSet(name="DefaultSet")
        default_renderer = Renderer(
            name="Default",
            mode=RenderMode.FILLED_STROKED,
            stroke_width=1.0,
            stroke_color=Color(0, 0, 0, 128),
            fill_color=Color(100, 150, 200, 200),
            point_size=3.0,
            hold_length=1
        )
        default_set.add_renderer(default_renderer)
        default_set.preferred_renderer = "Default"
        library.add_renderer_set(default_set)
        return library
