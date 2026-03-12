"""
Editor widgets for renderer change configurations.
"""
from typing import Optional
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QGroupBox, QCheckBox,
    QLabel, QDoubleSpinBox, QSpinBox, QFormLayout
)
from PyQt6.QtCore import pyqtSignal
from .color_picker import ColorPickerWidget
from .enum_dropdown import EnumDropdown
from models.rendering import SizeChange, ColorChange, FillColorChange, Color
from models.constants import ChangeKind, Motion, Cycle, Scale, ColorChannel


class SizeChangeEditor(QGroupBox):
    """Editor for SizeChange (stroke width or point size)."""

    changed = pyqtSignal()

    def __init__(self, title: str, parent=None):
        super().__init__(title, parent)
        self._change: Optional[SizeChange] = None
        self._updating = False

        self.setCheckable(True)
        self.toggled.connect(self._on_enabled_changed)

        layout = QVBoxLayout(self)

        # Kind and Motion row
        row1 = QHBoxLayout()
        self.kind_dropdown = EnumDropdown(ChangeKind, "Kind:")
        self.kind_dropdown.valueChanged.connect(self._on_value_changed)
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
        row3 = QHBoxLayout()
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
        layout.addLayout(row3)

        # Pause Max row
        row4 = QHBoxLayout()
        row4.addWidget(QLabel("Pause Max:"))
        self.pause_max_spin = QSpinBox()
        self.pause_max_spin.setRange(0, 1000)
        self.pause_max_spin.valueChanged.connect(self._on_value_changed)
        row4.addWidget(self.pause_max_spin)
        row4.addStretch()
        layout.addLayout(row4)

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

        self._updating = False

    def get_change(self) -> SizeChange:
        if self._change is None:
            return SizeChange()

        return SizeChange(
            enabled=self.isChecked(),
            kind=self.kind_dropdown.get_value(),
            motion=self.motion_dropdown.get_value(),
            cycle=self.cycle_dropdown.get_value(),
            scale=self.scale_dropdown.get_value(),
            min_val=self.min_spin.value(),
            max_val=self.max_spin.value(),
            increment=self.inc_spin.value(),
            pause_max=self.pause_max_spin.value()
        )

    def _on_enabled_changed(self, enabled: bool) -> None:
        if not self._updating and self._change:
            self._change.enabled = enabled
            self.changed.emit()

    def _on_value_changed(self) -> None:
        if not self._updating:
            self.changed.emit()


class ColorChangeEditor(QGroupBox):
    """Editor for ColorChange (stroke color)."""

    changed = pyqtSignal()

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

        # Pause Max row
        row_pause = QHBoxLayout()
        row_pause.addWidget(QLabel("Pause Max:"))
        self.pause_max_spin = QSpinBox()
        self.pause_max_spin.setRange(0, 1000)
        self.pause_max_spin.valueChanged.connect(self._on_value_changed)
        row_pause.addWidget(self.pause_max_spin)
        row_pause.addStretch()
        layout.addLayout(row_pause)

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
        self.pause_max_spin.setValue(change.pause_max)

        self._updating = False

    def get_change(self) -> ColorChange:
        if self._change is None:
            return ColorChange()

        return ColorChange(
            enabled=self.isChecked(),
            kind=self.kind_dropdown.get_value(),
            motion=self.motion_dropdown.get_value(),
            cycle=self.cycle_dropdown.get_value(),
            scale=self.scale_dropdown.get_value(),
            min_color=self.min_color_picker.get_color(),
            max_color=self.max_color_picker.get_color(),
            increment=self.inc_color_picker.get_color(),
            pause_max=self.pause_max_spin.value()
        )

    def _on_enabled_changed(self, enabled: bool) -> None:
        if not self._updating and self._change:
            self._change.enabled = enabled
            self.changed.emit()

    def _on_value_changed(self, *args) -> None:
        if not self._updating:
            self.changed.emit()


class FillColorChangeEditor(QGroupBox):
    """Editor for FillColorChange with additional pause channel settings."""

    changed = pyqtSignal()

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

        # Pause Max row
        row_pause = QHBoxLayout()
        row_pause.addWidget(QLabel("Pause Max:"))
        self.pause_max_spin = QSpinBox()
        self.pause_max_spin.setRange(0, 1000)
        self.pause_max_spin.valueChanged.connect(self._on_value_changed)
        row_pause.addWidget(self.pause_max_spin)
        row_pause.addStretch()
        layout.addLayout(row_pause)

        # Pause channel section
        pause_group = QGroupBox("Pause Channel Settings")
        pause_layout = QVBoxLayout(pause_group)

        self.pause_channel_dropdown = EnumDropdown(ColorChannel, "Pause Channel:")
        self.pause_channel_dropdown.valueChanged.connect(self._on_value_changed)
        pause_layout.addWidget(self.pause_channel_dropdown)

        self.pause_color_min_picker = ColorPickerWidget("Pause Color Min:")
        self.pause_color_min_picker.colorChanged.connect(self._on_value_changed)
        pause_layout.addWidget(self.pause_color_min_picker)

        self.pause_color_max_picker = ColorPickerWidget("Pause Color Max:")
        self.pause_color_max_picker.colorChanged.connect(self._on_value_changed)
        pause_layout.addWidget(self.pause_color_max_picker)

        layout.addWidget(pause_group)

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
        self.pause_max_spin.setValue(change.pause_max)
        self.pause_channel_dropdown.set_value(change.pause_channel)
        self.pause_color_min_picker.set_color(change.pause_color_min)
        self.pause_color_max_picker.set_color(change.pause_color_max)

        self._updating = False

    def get_change(self) -> FillColorChange:
        if self._change is None:
            return FillColorChange()

        return FillColorChange(
            enabled=self.isChecked(),
            kind=self.kind_dropdown.get_value(),
            motion=self.motion_dropdown.get_value(),
            cycle=self.cycle_dropdown.get_value(),
            scale=self.scale_dropdown.get_value(),
            min_color=self.min_color_picker.get_color(),
            max_color=self.max_color_picker.get_color(),
            increment=self.inc_color_picker.get_color(),
            pause_max=self.pause_max_spin.value(),
            pause_channel=self.pause_channel_dropdown.get_value(),
            pause_color_min=self.pause_color_min_picker.get_color(),
            pause_color_max=self.pause_color_max_picker.get_color()
        )

    def _on_enabled_changed(self, enabled: bool) -> None:
        if not self._updating and self._change:
            self._change.enabled = enabled
            self.changed.emit()

    def _on_value_changed(self, *args) -> None:
        if not self._updating:
            self.changed.emit()


class ChangeEditorWidget(QWidget):
    """Combined widget for all change editors."""

    changed = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        self.stroke_width_editor = SizeChangeEditor("Stroke Width Change")
        self.stroke_width_editor.changed.connect(self.changed.emit)
        layout.addWidget(self.stroke_width_editor)

        self.stroke_color_editor = ColorChangeEditor("Stroke Color Change")
        self.stroke_color_editor.changed.connect(self.changed.emit)
        layout.addWidget(self.stroke_color_editor)

        self.fill_color_editor = FillColorChangeEditor("Fill Color Change")
        self.fill_color_editor.changed.connect(self.changed.emit)
        layout.addWidget(self.fill_color_editor)

        self.point_size_editor = SizeChangeEditor("Point Size Change")
        self.point_size_editor.changed.connect(self.changed.emit)
        layout.addWidget(self.point_size_editor)

        layout.addStretch()
