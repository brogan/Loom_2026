"""
Rendering configuration tab with full editing capabilities.
"""
from typing import Optional
import os
from PyQt6.QtWidgets import (
    QWidget, QHBoxLayout, QVBoxLayout, QSplitter, QGroupBox,
    QLabel, QDoubleSpinBox, QSpinBox, QCheckBox, QComboBox,
    QScrollArea, QFrame, QListWidget, QPushButton, QInputDialog,
    QFileDialog, QListWidgetItem, QDialog, QMessageBox, QTabWidget
)
from PyQt6.QtCore import pyqtSignal, Qt
from .widgets.renderer_tree import RendererTreeWidget
from .widgets.brush_editor import BrushEditorWidget
from .widgets.color_picker import ColorPickerWidget
from .widgets.enum_dropdown import EnumDropdown
from .widgets.change_editor import (
    SizeChangeEditor, ColorChangeEditor, FillColorChangeEditor
)
from models.rendering import (
    RendererSetLibrary, RendererSet, Renderer, Color, BrushConfig
)
from models.constants import RenderMode, PlaybackMode, BrushDrawMode, PostCompletionMode


class RendererEditor(QWidget):
    """Editor panel for a single renderer's properties."""

    changed = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._renderer: Optional[Renderer] = None
        self._updating = False
        self._brushes_dir: str = ""

        # Inner tabs: Basic Properties | Dynamic Changes
        inner_tabs = QTabWidget()

        # Basic Properties tab
        basic_scroll = QScrollArea()
        basic_scroll.setWidgetResizable(True)
        basic_scroll.setFrameShape(QFrame.Shape.NoFrame)
        basic_content = QWidget()
        layout = QVBoxLayout(basic_content)
        basic_scroll.setWidget(basic_content)
        inner_tabs.addTab(basic_scroll, "Basic Properties")

        # Point Change tab
        point_scroll = QScrollArea()
        point_scroll.setWidgetResizable(True)
        point_scroll.setFrameShape(QFrame.Shape.NoFrame)
        point_content = QWidget()
        point_layout = QVBoxLayout(point_content)
        point_scroll.setWidget(point_content)
        inner_tabs.addTab(point_scroll, "Point Change")

        # Stroke Change tab
        stroke_scroll = QScrollArea()
        stroke_scroll.setWidgetResizable(True)
        stroke_scroll.setFrameShape(QFrame.Shape.NoFrame)
        stroke_content = QWidget()
        stroke_layout = QVBoxLayout(stroke_content)
        stroke_scroll.setWidget(stroke_content)
        inner_tabs.addTab(stroke_scroll, "Stroke Change")

        # Fill Change tab
        fill_scroll = QScrollArea()
        fill_scroll.setWidgetResizable(True)
        fill_scroll.setFrameShape(QFrame.Shape.NoFrame)
        fill_content = QWidget()
        fill_layout = QVBoxLayout(fill_content)
        fill_scroll.setWidget(fill_content)
        inner_tabs.addTab(fill_scroll, "Fill Change")

        # Basic Properties group
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

        # Point Change tab content (enabled controlled by tree PC checkbox)
        self.point_size_change_editor = SizeChangeEditor("Point Size Change")
        self.point_size_change_editor.setCheckable(False)
        self.point_size_change_editor.changed.connect(self._on_changed)
        point_layout.addWidget(self.point_size_change_editor)

        # Stroke Change tab content (enabled controlled by tree SC checkbox)
        self.stroke_width_change_editor = SizeChangeEditor("Stroke Width Change")
        self.stroke_width_change_editor.setCheckable(False)
        self.stroke_width_change_editor.changed.connect(self._on_changed)
        stroke_layout.addWidget(self.stroke_width_change_editor)

        self.stroke_color_change_editor = ColorChangeEditor("Stroke Color Change")
        self.stroke_color_change_editor.setCheckable(False)
        self.stroke_color_change_editor.changed.connect(self._on_changed)
        stroke_layout.addWidget(self.stroke_color_change_editor)

        # Fill Change tab content (enabled controlled by tree FC checkbox)
        self.fill_color_change_editor = FillColorChangeEditor("Fill Color Change")
        self.fill_color_change_editor.setCheckable(False)
        self.fill_color_change_editor.changed.connect(self._on_changed)
        fill_layout.addWidget(self.fill_color_change_editor)

        # Brush Config group (only visible when mode == BRUSHED)
        self.brush_group = QGroupBox("Brush Configuration")
        brush_layout = QVBoxLayout(self.brush_group)

        # Brush names list
        brush_names_label = QLabel("Brush Images:")
        brush_layout.addWidget(brush_names_label)
        self.brush_list = QListWidget()
        self.brush_list.setMaximumHeight(80)
        brush_layout.addWidget(self.brush_list)

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
        brush_layout.addLayout(brush_btn_row)

        # Draw mode
        draw_mode_row = QHBoxLayout()
        draw_mode_row.addWidget(QLabel("Draw Mode:"))
        self.draw_mode_combo = QComboBox()
        for dm in BrushDrawMode:
            self.draw_mode_combo.addItem(dm.name, dm)
        self.draw_mode_combo.currentIndexChanged.connect(self._on_brush_changed)
        draw_mode_row.addWidget(self.draw_mode_combo)
        draw_mode_row.addStretch()
        brush_layout.addLayout(draw_mode_row)

        # Stamp spacing + easing
        spacing_row = QHBoxLayout()
        spacing_row.addWidget(QLabel("Stamp Spacing:"))
        self.stamp_spacing_spin = QDoubleSpinBox()
        self.stamp_spacing_spin.setRange(0.5, 100.0)
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
        brush_layout.addLayout(spacing_row)

        # Follow tangent
        self.follow_tangent_check = QCheckBox("Follow Tangent")
        self.follow_tangent_check.stateChanged.connect(self._on_brush_changed)
        brush_layout.addWidget(self.follow_tangent_check)

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
        brush_layout.addLayout(perp_row)

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
        brush_layout.addLayout(scale_row)

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
        brush_layout.addLayout(opacity_row)

        # Progressive reveal settings
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

        brush_layout.addWidget(self.progressive_group)

        # Blur radius
        blur_row = QHBoxLayout()
        blur_row.addWidget(QLabel("Blur Radius:"))
        self.blur_radius_spin = QSpinBox()
        self.blur_radius_spin.setRange(0, 10)
        self.blur_radius_spin.valueChanged.connect(self._on_brush_changed)
        blur_row.addWidget(self.blur_radius_spin)
        blur_row.addStretch()
        brush_layout.addLayout(blur_row)

        point_layout.addWidget(self.brush_group)

        layout.addStretch()
        point_layout.addStretch()
        stroke_layout.addStretch()
        fill_layout.addStretch()

        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.addWidget(inner_tabs)

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

            # Brush config
            self._load_brush_config(renderer.brush_config)

            self._update_mode_visibility()

        self._updating = False

    def _on_mode_changed(self, *args) -> None:
        """Handle mode changes - update visibility and trigger change."""
        self._update_mode_visibility()
        self._on_changed()

    def _update_mode_visibility(self) -> None:
        """Enable/disable options based on current render mode."""
        mode = self.mode_dropdown.get_value()

        has_stroke = mode in (RenderMode.STROKED, RenderMode.FILLED_STROKED)
        has_fill = mode in (RenderMode.FILLED, RenderMode.FILLED_STROKED)
        has_points = mode == RenderMode.POINTS
        has_brush = mode == RenderMode.BRUSHED

        # Stroke controls — also enabled in POINTS mode when point_stroked is true
        # In BRUSHED mode, stroke color is used as brush tint
        point_stroked = has_points and self.point_stroked_check.isChecked()
        self.stroke_width_spin.setEnabled(has_stroke or point_stroked)
        self.stroke_color_picker.setEnabled(has_stroke or point_stroked or has_brush)
        self.stroke_width_change_editor.setEnabled(has_stroke or has_points)
        self.stroke_color_change_editor.setEnabled(has_stroke or has_brush or has_points)

        # Fill controls — also enabled in POINTS mode when point_filled is true
        point_filled = has_points and self.point_filled_check.isChecked()
        self.fill_color_picker.setEnabled(has_fill or point_filled)
        self.fill_color_change_editor.setEnabled(has_fill)

        # Point controls - only relevant in POINTS mode
        self.point_size_spin.setEnabled(has_points)
        self.point_stroked_check.setEnabled(has_points)
        self.point_filled_check.setEnabled(has_points)
        self.point_size_change_editor.setEnabled(has_points)

        # Brush config - only visible in BRUSHED mode
        self.brush_group.setVisible(has_brush)

        # Progressive reveal settings - only visible when draw mode is PROGRESSIVE
        if has_brush:
            is_progressive = self.draw_mode_combo.currentData() == BrushDrawMode.PROGRESSIVE
            self.progressive_group.setVisible(is_progressive)
        else:
            self.progressive_group.setVisible(False)


    def _on_point_style_changed(self, *args) -> None:
        """Handle point stroked/filled checkbox changes — update visibility and trigger change."""
        self._update_mode_visibility()
        self._on_changed()

    def _load_brush_config(self, config: 'Optional[BrushConfig]') -> None:
        """Load brush config values into the UI."""
        if config is None:
            config = BrushConfig()

        self.brush_list.clear()
        for name in config.brush_names:
            self.brush_list.addItem(name)

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

    def _get_brush_config(self) -> BrushConfig:
        """Build a BrushConfig from current UI state."""
        names = []
        for i in range(self.brush_list.count()):
            names.append(self.brush_list.item(i).text())
        if not names:
            names = ["default.png"]

        return BrushConfig(
            brush_names=names,
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
            blur_radius=self.blur_radius_spin.value()
        )

    def set_brushes_dir(self, path: str) -> None:
        """Set the brushes directory for this editor."""
        self._brushes_dir = path

    def _on_add_brush(self) -> None:
        """Add a brush from the project's brushes/ folder or by typing a name."""
        if self._brushes_dir and os.path.isdir(self._brushes_dir):
            # List available PNGs in the brushes directory
            available = sorted(
                f for f in os.listdir(self._brushes_dir)
                if f.lower().endswith(".png")
            )
            if available:
                # Filter out already-added brushes
                existing = set()
                for i in range(self.brush_list.count()):
                    existing.add(self.brush_list.item(i).text())
                choices = [f for f in available if f not in existing]
                if choices:
                    name, ok = QInputDialog.getItem(
                        self, "Add Brush", "Select a brush from the project:",
                        choices, 0, False
                    )
                    if ok and name:
                        self.brush_list.addItem(name)
                        self._on_brush_changed()
                    return
                else:
                    QMessageBox.information(
                        self, "No Brushes",
                        "All available brushes are already added.\n"
                        "Use 'Create...' to make a new brush."
                    )
                    return

        # Fallback: manual text entry
        name, ok = QInputDialog.getText(self, "Add Brush", "Brush PNG filename:")
        if ok and name.strip():
            name = name.strip()
            if not name.lower().endswith(".png"):
                name += ".png"
            self.brush_list.addItem(name)
            self._on_brush_changed()

    def _on_create_brush(self) -> None:
        """Open the brush editor to create a new brush."""
        if not self._brushes_dir:
            QMessageBox.warning(
                self, "No Project",
                "Save or open a project first to create brushes."
            )
            return

        os.makedirs(self._brushes_dir, exist_ok=True)

        dialog = QDialog(self)
        dialog.setWindowTitle("Create Brush")
        dialog.setMinimumSize(500, 650)
        dlg_layout = QVBoxLayout(dialog)

        editor = BrushEditorWidget(self._brushes_dir)

        def on_saved(filename):
            # Auto-add the new brush to the list
            self.brush_list.addItem(filename)
            self._on_brush_changed()
            dialog.accept()

        editor.brushSaved.connect(on_saved)
        dlg_layout.addWidget(editor)
        dialog.exec()

    def _on_edit_brush(self) -> None:
        """Open the brush editor for the selected brush."""
        current = self.brush_list.currentItem()
        if current is None:
            QMessageBox.information(self, "No Selection", "Select a brush to edit.")
            return

        filename = current.text()
        if not self._brushes_dir:
            QMessageBox.warning(
                self, "No Project",
                "Save or open a project first to edit brushes."
            )
            return

        filepath = os.path.join(self._brushes_dir, filename)

        dialog = QDialog(self)
        dialog.setWindowTitle(f"Edit Brush: {filename}")
        dialog.setMinimumSize(500, 650)
        dlg_layout = QVBoxLayout(dialog)

        editor = BrushEditorWidget(self._brushes_dir)
        if os.path.exists(filepath):
            editor.canvas.load_image(filepath)

        editor.brushSaved.connect(lambda name: dialog.accept())
        dlg_layout.addWidget(editor)
        dialog.exec()

    def _on_remove_brush(self) -> None:
        """Remove the selected brush from the list."""
        current = self.brush_list.currentRow()
        if current >= 0:
            self.brush_list.takeItem(current)
            self._on_brush_changed()

    def _on_brush_changed(self, *args) -> None:
        """Handle any brush config UI change."""
        if self._updating:
            return
        # Update progressive group visibility
        is_progressive = self.draw_mode_combo.currentData() == BrushDrawMode.PROGRESSIVE
        self.progressive_group.setVisible(is_progressive)
        self._on_changed()

    def _on_changed(self, *args) -> None:
        if self._updating or self._renderer is None:
            return

        # Update renderer from UI (enabled is controlled by tree checkbox, not here)
        self._renderer.mode = self.mode_dropdown.get_value()
        self._renderer.stroke_width = self.stroke_width_spin.value()
        self._renderer.stroke_color = self.stroke_color_picker.get_color()
        self._renderer.fill_color = self.fill_color_picker.get_color()
        self._renderer.point_size = self.point_size_spin.value()
        self._renderer.hold_length = self.hold_length_spin.value()
        self._renderer.point_stroked = self.point_stroked_check.isChecked()
        self._renderer.point_filled = self.point_filled_check.isChecked()

        # Preserve enabled flags (controlled by tree checkboxes, not by non-checkable editors)
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

        # Update brush config
        if self._renderer.mode == RenderMode.BRUSHED:
            self._renderer.brush_config = self._get_brush_config()
        elif self._renderer.brush_config is not None and self._renderer.mode != RenderMode.BRUSHED:
            # Keep brush config if previously set (user may switch back to BRUSHED)
            pass

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
            # Update mode
            index = self.mode_combo.findData(renderer_set.playback_mode)
            if index >= 0:
                self.mode_combo.setCurrentIndex(index)

            # Update preferred renderer dropdown
            self.preferred_combo.clear()
            self.preferred_combo.addItem("")  # Empty option
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

        # Create splitter for left/right panels
        splitter = QSplitter(Qt.Orientation.Horizontal)

        # Left panel: tree view and set config
        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)
        left_layout.setContentsMargins(0, 0, 0, 0)

        # Library name label
        self.library_label = QLabel("Library: (none)")
        left_layout.addWidget(self.library_label)

        # Tree view
        self.tree_widget = RendererTreeWidget()
        self.tree_widget.selectionChanged.connect(self._on_selection_changed)
        self.tree_widget.libraryModified.connect(self._on_library_modified)
        left_layout.addWidget(self.tree_widget)

        # Set configuration
        self.set_config_panel = RendererSetConfigPanel()
        self.set_config_panel.changed.connect(self._on_library_modified)
        left_layout.addWidget(self.set_config_panel)

        splitter.addWidget(left_panel)

        # Right panel: renderer editor
        right_panel = QWidget()
        right_layout = QVBoxLayout(right_panel)
        right_layout.setContentsMargins(0, 0, 0, 0)

        self.renderer_label = QLabel("Renderer: (none)")
        right_layout.addWidget(self.renderer_label)

        self.renderer_editor = RendererEditor()
        self.renderer_editor.changed.connect(self._on_library_modified)
        right_layout.addWidget(self.renderer_editor)

        splitter.addWidget(right_panel)

        # Set splitter sizes
        splitter.setSizes([300, 600])

        layout.addWidget(splitter)

    def set_library(self, library: Optional[RendererSetLibrary]) -> None:
        """Set the library to edit."""
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
        """Set the project directory — forwards brushes/ path to the renderer editor."""
        brushes_dir = os.path.join(project_dir, "brushes")
        os.makedirs(brushes_dir, exist_ok=True)
        self.renderer_editor.set_brushes_dir(brushes_dir)

    def get_library(self) -> Optional[RendererSetLibrary]:
        return self._library

    def _on_selection_changed(self, set_name: str, renderer_name: Optional[str]) -> None:
        """Handle tree selection changes."""
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
        """Handle library modifications.
        Auto-enables ModifyInternalParameters when any renderer in the
        current set has dynamic changes enabled.
        """
        if self._current_set is not None:
            any_changes = any(r.has_any_changes() for r in self._current_set.renderers)
            if any_changes and not self._current_set.modify_internal_parameters:
                self._current_set.modify_internal_parameters = True
                self.set_config_panel.set_renderer_set(self._current_set)

        self.modified.emit()

    def create_default_library(self) -> RendererSetLibrary:
        """Create a default library with one set and one renderer."""
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
