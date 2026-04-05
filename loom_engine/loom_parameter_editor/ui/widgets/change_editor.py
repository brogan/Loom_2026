"""
Editor widgets for renderer change configurations.
"""
from typing import Optional
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QGroupBox, QCheckBox,
    QLabel, QDoubleSpinBox, QSpinBox, QFormLayout
)
from PySide6.QtCore import Signal
from .color_picker import ColorPickerWidget
from .enum_dropdown import EnumDropdown
from .palette_editor import PaletteEditorWidget
from .size_palette_editor import SizePaletteEditorWidget
from models.rendering import SizeChange, ColorChange, FillColorChange, Color
from models.constants import ChangeKind, Motion, Cycle, Scale, ColorChannel


class SizeChangeEditor(QGroupBox):
    """Editor for SizeChange (stroke width or point size)."""

    changed = Signal()

    def __init__(self, title: str, preview_mode: str = None, parent=None):
        """preview_mode: 'stroke' or 'point' to enable size palette; None disables palette."""
        super().__init__(title, parent)
        self._change: Optional[SizeChange] = None
        self._updating = False
        self._has_palette = preview_mode is not None

        self.setCheckable(True)
        self.toggled.connect(self._on_enabled_changed)

        layout = QVBoxLayout(self)

        # Kind and Motion row
        row1 = QHBoxLayout()
        self.kind_dropdown = EnumDropdown(ChangeKind, "Kind:")
        self.kind_dropdown.valueChanged.connect(self._on_value_changed)
        if self._has_palette:
            self.kind_dropdown.valueChanged.connect(self._on_kind_changed)
        row1.addWidget(self.kind_dropdown)
        self.motion_dropdown = EnumDropdown(Motion, "Motion:")
        self.motion_dropdown.valueChanged.connect(self._on_value_changed)
        row1.addWidget(self.motion_dropdown)
        layout.addLayout(row1)

        # Cycle and Scale row
        row2 = QHBoxLayout()
        self.cycle_dropdown = EnumDropdown(Cycle, "Cycle:")
        self.cycle_dropdown.valueChanged.connect(self._on_value_changed)
        row2.addWidget(self.cycle_dropdown)
        self.scale_dropdown = EnumDropdown(Scale, "Scale:")
        self.scale_dropdown.valueChanged.connect(self._on_value_changed)
        row2.addWidget(self.scale_dropdown)
        layout.addLayout(row2)

        # Min, Max, Increment row
        self._min_max_widget = QWidget()
        row3 = QHBoxLayout(self._min_max_widget)
        row3.setContentsMargins(0, 0, 0, 0)
        row3.addWidget(QLabel("Min:"))
        self.min_spin = QDoubleSpinBox()
        self.min_spin.setRange(0, 100)
        self.min_spin.setDecimals(2)
        self.min_spin.valueChanged.connect(self._on_value_changed)
        row3.addWidget(self.min_spin)

        row3.addWidget(QLabel("Max:"))
        self.max_spin = QDoubleSpinBox()
        self.max_spin.setRange(0, 100)
        self.max_spin.setDecimals(2)
        self.max_spin.valueChanged.connect(self._on_value_changed)
        row3.addWidget(self.max_spin)

        row3.addWidget(QLabel("Inc:"))
        self.inc_spin = QDoubleSpinBox()
        self.inc_spin.setRange(0.01, 10)
        self.inc_spin.setDecimals(2)
        self.inc_spin.setSingleStep(0.1)
        self.inc_spin.valueChanged.connect(self._on_value_changed)
        row3.addWidget(self.inc_spin)
        layout.addWidget(self._min_max_widget)

        # Size palette (only for stroke width / point size editors)
        if self._has_palette:
            self.size_palette_editor = SizePaletteEditorWidget(preview_mode)
            self.size_palette_editor.paletteChanged.connect(self._on_value_changed)
            layout.addWidget(self.size_palette_editor)
            self.size_palette_editor.setVisible(False)

        # Pause Max row
        row4 = QHBoxLayout()
        row4.addWidget(QLabel("Pause Max:"))
        self.pause_max_spin = QSpinBox()
        self.pause_max_spin.setRange(0, 1000)
        self.pause_max_spin.valueChanged.connect(self._on_value_changed)
        row4.addWidget(self.pause_max_spin)
        row4.addStretch()
        layout.addLayout(row4)

    def _on_kind_changed(self, kind) -> None:
        is_palette = kind in (ChangeKind.SEQ, ChangeKind.RAN)
        self._min_max_widget.setVisible(not is_palette)
        if self._has_palette:
            self.size_palette_editor.setVisible(is_palette)

    def set_change(self, change: SizeChange) -> None:
        self._updating = True
        self._change = change

        self.setChecked(change.enabled)
        self.kind_dropdown.set_value(change.kind)
        self.motion_dropdown.set_value(change.motion)
        self.cycle_dropdown.set_value(change.cycle)
        self.scale_dropdown.set_value(change.scale)
        self.min_spin.setValue(change.min_val)
        self.max_spin.setValue(change.max_val)
        self.inc_spin.setValue(change.increment)
        self.pause_max_spin.setValue(change.pause_max)
        if self._has_palette:
            self.size_palette_editor.set_palette(change.size_palette)

        self._updating = False
        if self._has_palette:
            self._on_kind_changed(change.kind)

    def get_change(self) -> SizeChange:
        if self._change is None:
            return SizeChange()

        kind = self.kind_dropdown.get_value()
        is_pal = self._has_palette and kind in (ChangeKind.SEQ, ChangeKind.RAN)
        return SizeChange(
            enabled=self.isChecked(),
            kind=kind,
            motion=self.motion_dropdown.get_value(),
            cycle=self.cycle_dropdown.get_value(),
            scale=self.scale_dropdown.get_value(),
            min_val=self.min_spin.value(),
            max_val=self.max_spin.value(),
            increment=self.inc_spin.value(),
            pause_max=self.pause_max_spin.value(),
            size_palette=self.size_palette_editor.get_palette() if is_pal else []
        )

    def set_palettes_dir(self, path: str) -> None:
        if self._has_palette:
            self.size_palette_editor.set_palettes_dir(path)

    def _on_enabled_changed(self, enabled: bool) -> None:
        if not self._updating and self._change:
            self._change.enabled = enabled
            self.changed.emit()

    def _on_value_changed(self) -> None:
        if not self._updating:
            self.changed.emit()


class ColorChangeEditor(QGroupBox):
    """Editor for ColorChange (stroke color)."""

    changed = Signal()

    def __init__(self, title: str, parent=None):
        super().__init__(title, parent)
        self._change: Optional[ColorChange] = None
        self._updating = False

        self.setCheckable(True)
        self.toggled.connect(self._on_enabled_changed)

        layout = QVBoxLayout(self)

        # Kind and Motion row
        row1 = QHBoxLayout()
        self.kind_dropdown = EnumDropdown(ChangeKind, "Kind:")
        self.kind_dropdown.valueChanged.connect(self._on_value_changed)
        self.kind_dropdown.valueChanged.connect(self._on_kind_changed)
        row1.addWidget(self.kind_dropdown)
        self.motion_dropdown = EnumDropdown(Motion, "Motion:")
        self.motion_dropdown.valueChanged.connect(self._on_value_changed)
        row1.addWidget(self.motion_dropdown)
        layout.addLayout(row1)

        # Cycle and Scale row
        row2 = QHBoxLayout()
        self.cycle_dropdown = EnumDropdown(Cycle, "Cycle:")
        self.cycle_dropdown.valueChanged.connect(self._on_value_changed)
        row2.addWidget(self.cycle_dropdown)
        self.scale_dropdown = EnumDropdown(Scale, "Scale:")
        self.scale_dropdown.valueChanged.connect(self._on_value_changed)
        row2.addWidget(self.scale_dropdown)
        layout.addLayout(row2)

        # Min color
        self.min_color_picker = ColorPickerWidget("Min Color:")
        self.min_color_picker.colorChanged.connect(self._on_value_changed)
        layout.addWidget(self.min_color_picker)

        # Max color
        self.max_color_picker = ColorPickerWidget("Max Color:")
        self.max_color_picker.colorChanged.connect(self._on_value_changed)
        layout.addWidget(self.max_color_picker)

        # Increment color
        self.inc_color_picker = ColorPickerWidget("Increment:")
        self.inc_color_picker.colorChanged.connect(self._on_value_changed)
        layout.addWidget(self.inc_color_picker)

        # Palette editor (shown only for PAL_SEQ / PAL_RAN)
        self.palette_editor = PaletteEditorWidget()
        self.palette_editor.paletteChanged.connect(self._on_value_changed)
        layout.addWidget(self.palette_editor)
        self.palette_editor.setVisible(False)

        # Pause Max row
        row_pause = QHBoxLayout()
        row_pause.addWidget(QLabel("Pause Max:"))
        self.pause_max_spin = QSpinBox()
        self.pause_max_spin.setRange(0, 1000)
        self.pause_max_spin.valueChanged.connect(self._on_value_changed)
        row_pause.addWidget(self.pause_max_spin)
        row_pause.addStretch()
        layout.addLayout(row_pause)

        # Pause channel section (hidden for PAL_*)
        self._pause_channel_group = QGroupBox("Pause Channel Settings")
        pause_layout = QVBoxLayout(self._pause_channel_group)
        self.pause_channel_dropdown = EnumDropdown(ColorChannel, "Pause Channel:")
        self.pause_channel_dropdown.valueChanged.connect(self._on_value_changed)
        pause_layout.addWidget(self.pause_channel_dropdown)
        self.pause_color_min_picker = ColorPickerWidget("Pause Color Min:")
        self.pause_color_min_picker.colorChanged.connect(self._on_value_changed)
        pause_layout.addWidget(self.pause_color_min_picker)
        self.pause_color_max_picker = ColorPickerWidget("Pause Color Max:")
        self.pause_color_max_picker.colorChanged.connect(self._on_value_changed)
        pause_layout.addWidget(self.pause_color_max_picker)
        layout.addWidget(self._pause_channel_group)

    def _on_kind_changed(self, kind) -> None:
        is_palette = kind in (ChangeKind.SEQ, ChangeKind.RAN)
        for w in (self.min_color_picker, self.max_color_picker, self.inc_color_picker):
            w.setVisible(not is_palette)
        self.palette_editor.setVisible(is_palette)
        self._pause_channel_group.setVisible(not is_palette)

    def set_change(self, change: ColorChange) -> None:
        self._updating = True
        self._change = change

        self.setChecked(change.enabled)
        self.kind_dropdown.set_value(change.kind)
        self.motion_dropdown.set_value(change.motion)
        self.cycle_dropdown.set_value(change.cycle)
        self.scale_dropdown.set_value(change.scale)
        self.min_color_picker.set_color(change.min_color)
        self.max_color_picker.set_color(change.max_color)
        self.inc_color_picker.set_color(change.increment)
        self.palette_editor.set_palette(change.palette)
        self.pause_max_spin.setValue(change.pause_max)
        self.pause_channel_dropdown.set_value(change.pause_channel)
        self.pause_color_min_picker.set_color(change.pause_color_min)
        self.pause_color_max_picker.set_color(change.pause_color_max)

        self._updating = False
        self._on_kind_changed(change.kind)

    def get_change(self) -> ColorChange:
        if self._change is None:
            return ColorChange()

        kind = self.kind_dropdown.get_value()
        is_pal = kind in (ChangeKind.SEQ, ChangeKind.RAN)
        return ColorChange(
            enabled=self.isChecked(),
            kind=kind,
            motion=self.motion_dropdown.get_value(),
            cycle=self.cycle_dropdown.get_value(),
            scale=self.scale_dropdown.get_value(),
            min_color=self.min_color_picker.get_color(),
            max_color=self.max_color_picker.get_color(),
            increment=self.inc_color_picker.get_color(),
            pause_max=self.pause_max_spin.value(),
            palette=self.palette_editor.get_palette() if is_pal else [],
            pause_channel=self.pause_channel_dropdown.get_value(),
            pause_color_min=self.pause_color_min_picker.get_color(),
            pause_color_max=self.pause_color_max_picker.get_color()
        )

    def set_palettes_dir(self, path: str) -> None:
        self.palette_editor.set_palettes_dir(path)

    def _on_enabled_changed(self, enabled: bool) -> None:
        if not self._updating and self._change:
            self._change.enabled = enabled
            self.changed.emit()

    def _on_value_changed(self, *args) -> None:
        if not self._updating:
            self.changed.emit()


class FillColorChangeEditor(QGroupBox):
    """Editor for FillColorChange with additional pause channel settings."""

    changed = Signal()

    def __init__(self, title: str, parent=None):
        super().__init__(title, parent)
        self._change: Optional[FillColorChange] = None
        self._updating = False

        self.setCheckable(True)
        self.toggled.connect(self._on_enabled_changed)

        layout = QVBoxLayout(self)

        # Kind and Motion row
        row1 = QHBoxLayout()
        self.kind_dropdown = EnumDropdown(ChangeKind, "Kind:")
        self.kind_dropdown.valueChanged.connect(self._on_value_changed)
        self.kind_dropdown.valueChanged.connect(self._on_kind_changed)
        row1.addWidget(self.kind_dropdown)
        self.motion_dropdown = EnumDropdown(Motion, "Motion:")
        self.motion_dropdown.valueChanged.connect(self._on_value_changed)
        row1.addWidget(self.motion_dropdown)
        layout.addLayout(row1)

        # Cycle and Scale row
        row2 = QHBoxLayout()
        self.cycle_dropdown = EnumDropdown(Cycle, "Cycle:")
        self.cycle_dropdown.valueChanged.connect(self._on_value_changed)
        row2.addWidget(self.cycle_dropdown)
        self.scale_dropdown = EnumDropdown(Scale, "Scale:")
        self.scale_dropdown.valueChanged.connect(self._on_value_changed)
        row2.addWidget(self.scale_dropdown)
        layout.addLayout(row2)

        # Min color
        self.min_color_picker = ColorPickerWidget("Min Color:")
        self.min_color_picker.colorChanged.connect(self._on_value_changed)
        layout.addWidget(self.min_color_picker)

        # Max color
        self.max_color_picker = ColorPickerWidget("Max Color:")
        self.max_color_picker.colorChanged.connect(self._on_value_changed)
        layout.addWidget(self.max_color_picker)

        # Increment color
        self.inc_color_picker = ColorPickerWidget("Increment:")
        self.inc_color_picker.colorChanged.connect(self._on_value_changed)
        layout.addWidget(self.inc_color_picker)

        # Palette editor (shown only for PAL_SEQ / PAL_RAN)
        self.palette_editor = PaletteEditorWidget()
        self.palette_editor.paletteChanged.connect(self._on_value_changed)
        layout.addWidget(self.palette_editor)
        self.palette_editor.setVisible(False)

        # Pause Max row
        row_pause = QHBoxLayout()
        row_pause.addWidget(QLabel("Pause Max:"))
        self.pause_max_spin = QSpinBox()
        self.pause_max_spin.setRange(0, 1000)
        self.pause_max_spin.valueChanged.connect(self._on_value_changed)
        row_pause.addWidget(self.pause_max_spin)
        row_pause.addStretch()
        layout.addLayout(row_pause)

        # Pause channel section (hidden for PAL_*)
        self._pause_channel_group = QGroupBox("Pause Channel Settings")
        pause_layout = QVBoxLayout(self._pause_channel_group)

        self.pause_channel_dropdown = EnumDropdown(ColorChannel, "Pause Channel:")
        self.pause_channel_dropdown.valueChanged.connect(self._on_value_changed)
        pause_layout.addWidget(self.pause_channel_dropdown)

        self.pause_color_min_picker = ColorPickerWidget("Pause Color Min:")
        self.pause_color_min_picker.colorChanged.connect(self._on_value_changed)
        pause_layout.addWidget(self.pause_color_min_picker)

        self.pause_color_max_picker = ColorPickerWidget("Pause Color Max:")
        self.pause_color_max_picker.colorChanged.connect(self._on_value_changed)
        pause_layout.addWidget(self.pause_color_max_picker)

        layout.addWidget(self._pause_channel_group)

    def _on_kind_changed(self, kind) -> None:
        is_palette = kind in (ChangeKind.SEQ, ChangeKind.RAN)
        for w in (self.min_color_picker, self.max_color_picker, self.inc_color_picker):
            w.setVisible(not is_palette)
        self.palette_editor.setVisible(is_palette)
        self._pause_channel_group.setVisible(not is_palette)

    def set_change(self, change: FillColorChange) -> None:
        self._updating = True
        self._change = change

        self.setChecked(change.enabled)
        self.kind_dropdown.set_value(change.kind)
        self.motion_dropdown.set_value(change.motion)
        self.cycle_dropdown.set_value(change.cycle)
        self.scale_dropdown.set_value(change.scale)
        self.min_color_picker.set_color(change.min_color)
        self.max_color_picker.set_color(change.max_color)
        self.inc_color_picker.set_color(change.increment)
        self.palette_editor.set_palette(change.palette)
        self.pause_max_spin.setValue(change.pause_max)
        self.pause_channel_dropdown.set_value(change.pause_channel)
        self.pause_color_min_picker.set_color(change.pause_color_min)
        self.pause_color_max_picker.set_color(change.pause_color_max)

        self._updating = False
        self._on_kind_changed(change.kind)

    def get_change(self) -> FillColorChange:
        if self._change is None:
            return FillColorChange()

        kind = self.kind_dropdown.get_value()
        is_pal = kind in (ChangeKind.SEQ, ChangeKind.RAN)
        return FillColorChange(
            enabled=self.isChecked(),
            kind=kind,
            motion=self.motion_dropdown.get_value(),
            cycle=self.cycle_dropdown.get_value(),
            scale=self.scale_dropdown.get_value(),
            min_color=self.min_color_picker.get_color(),
            max_color=self.max_color_picker.get_color(),
            increment=self.inc_color_picker.get_color(),
            pause_max=self.pause_max_spin.value(),
            palette=self.palette_editor.get_palette() if is_pal else [],
            pause_channel=self.pause_channel_dropdown.get_value(),
            pause_color_min=self.pause_color_min_picker.get_color(),
            pause_color_max=self.pause_color_max_picker.get_color()
        )

    def set_palettes_dir(self, path: str) -> None:
        self.palette_editor.set_palettes_dir(path)

    def _on_enabled_changed(self, enabled: bool) -> None:
        if not self._updating and self._change:
            self._change.enabled = enabled
            self.changed.emit()

    def _on_value_changed(self, *args) -> None:
        if not self._updating:
            self.changed.emit()


class ChangeEditorWidget(QWidget):
    """Combined widget for all change editors."""

    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        self.stroke_width_editor = SizeChangeEditor("Stroke Width Change", preview_mode='stroke')
        self.stroke_width_editor.changed.connect(self.changed.emit)
        layout.addWidget(self.stroke_width_editor)

        self.stroke_color_editor = ColorChangeEditor("Stroke Color Change")
        self.stroke_color_editor.changed.connect(self.changed.emit)
        layout.addWidget(self.stroke_color_editor)

        self.fill_color_editor = FillColorChangeEditor("Fill Color Change")
        self.fill_color_editor.changed.connect(self.changed.emit)
        layout.addWidget(self.fill_color_editor)

        self.point_size_editor = SizeChangeEditor("Point Size Change", preview_mode='point')
        self.point_size_editor.changed.connect(self.changed.emit)
        layout.addWidget(self.point_size_editor)

        layout.addStretch()
