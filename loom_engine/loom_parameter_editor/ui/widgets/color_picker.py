"""
RGBA color picker widget.
"""
from PyQt6.QtWidgets import (
    QWidget, QHBoxLayout, QVBoxLayout, QLabel, QSpinBox, QPushButton, QColorDialog
)
from PyQt6.QtGui import QColor, QPalette
from PyQt6.QtCore import pyqtSignal
from models.rendering import Color


class ColorPickerWidget(QWidget):
    """A widget for picking RGBA colors with numeric inputs and a color preview."""

    colorChanged = pyqtSignal(Color)

    def __init__(self, label: str = "", show_alpha: bool = True, parent=None):
        super().__init__(parent)
        self._color = Color()
        self._show_alpha = show_alpha
        self._updating = False

        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)

        if label:
            layout.addWidget(QLabel(label))

        # RGBA spinboxes
        self.r_spin = self._create_spinbox("R")
        self.g_spin = self._create_spinbox("G")
        self.b_spin = self._create_spinbox("B")
        self.a_spin = self._create_spinbox("A") if show_alpha else None

        layout.addWidget(self.r_spin)
        layout.addWidget(self.g_spin)
        layout.addWidget(self.b_spin)
        if self.a_spin:
            layout.addWidget(self.a_spin)

        # Color preview/picker button
        self.color_button = QPushButton()
        self.color_button.setFixedSize(28, 28)
        self.color_button.clicked.connect(self._open_color_dialog)
        layout.addWidget(self.color_button)

        self._update_preview()

    def _create_spinbox(self, label: str) -> QSpinBox:
        spin = QSpinBox()
        spin.setRange(0, 255)
        spin.setPrefix(f"{label}: ")
        spin.setFixedWidth(70)
        spin.valueChanged.connect(self._on_value_changed)
        return spin

    def _on_value_changed(self):
        if self._updating:
            return
        self._color.r = self.r_spin.value()
        self._color.g = self.g_spin.value()
        self._color.b = self.b_spin.value()
        if self.a_spin:
            self._color.a = self.a_spin.value()
        self._update_preview()
        self.colorChanged.emit(self._color)

    def _update_preview(self):
        qcolor = QColor(self._color.r, self._color.g, self._color.b, self._color.a)
        # Create a checkerboard pattern background to show alpha
        self.color_button.setStyleSheet(
            f"background-color: rgba({self._color.r}, {self._color.g}, {self._color.b}, {self._color.a});"
            "border: 1px solid #666;"
        )

    def _open_color_dialog(self):
        initial = QColor(self._color.r, self._color.g, self._color.b, self._color.a)
        options = QColorDialog.ColorDialogOption.ShowAlphaChannel if self._show_alpha else QColorDialog.ColorDialogOption(0)
        color = QColorDialog.getColor(initial, self, "Select Color", options)
        if color.isValid():
            self.set_color(Color(color.red(), color.green(), color.blue(), color.alpha()))

    def get_color(self) -> Color:
        return self._color.copy()

    def set_color(self, color: Color) -> None:
        self._updating = True
        self._color = color.copy()
        self.r_spin.setValue(color.r)
        self.g_spin.setValue(color.g)
        self.b_spin.setValue(color.b)
        if self.a_spin:
            self.a_spin.setValue(color.a)
        self._updating = False
        self._update_preview()
        self.colorChanged.emit(self._color)


class CompactColorPicker(QWidget):
    """A compact color picker showing just a button with preview."""

    colorChanged = pyqtSignal(Color)

    def __init__(self, label: str = "", show_alpha: bool = True, parent=None):
        super().__init__(parent)
        self._color = Color()
        self._show_alpha = show_alpha

        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        if label:
            layout.addWidget(QLabel(label))

        self.color_button = QPushButton()
        self.color_button.setFixedSize(60, 24)
        self.color_button.clicked.connect(self._open_color_dialog)
        layout.addWidget(self.color_button)

        self._update_preview()

    def _update_preview(self):
        self.color_button.setStyleSheet(
            f"background-color: rgba({self._color.r}, {self._color.g}, {self._color.b}, {self._color.a});"
            "border: 1px solid #666;"
        )
        self.color_button.setToolTip(f"R:{self._color.r} G:{self._color.g} B:{self._color.b} A:{self._color.a}")

    def _open_color_dialog(self):
        initial = QColor(self._color.r, self._color.g, self._color.b, self._color.a)
        options = QColorDialog.ColorDialogOption.ShowAlphaChannel if self._show_alpha else QColorDialog.ColorDialogOption(0)
        color = QColorDialog.getColor(initial, self, "Select Color", options)
        if color.isValid():
            self.set_color(Color(color.red(), color.green(), color.blue(), color.alpha()))

    def get_color(self) -> Color:
        return self._color.copy()

    def set_color(self, color: Color) -> None:
        self._color = color.copy()
        self._update_preview()
        self.colorChanged.emit(self._color)
