"""
Dropdown widget for enum selection.
"""
from typing import Type, TypeVar
from enum import Enum
from PyQt6.QtWidgets import QComboBox, QWidget, QHBoxLayout, QLabel
from PyQt6.QtCore import pyqtSignal

E = TypeVar('E', bound=Enum)


class EnumDropdown(QWidget):
    """A dropdown widget for selecting enum values."""

    valueChanged = pyqtSignal(object)  # Emits the enum value

    def __init__(self, enum_class: Type[E], label: str = "", parent=None):
        super().__init__(parent)
        self._enum_class = enum_class
        self._updating = False

        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        if label:
            lbl = QLabel(label)
            lbl.setFixedWidth(80)
            layout.addWidget(lbl)

        self.combo = QComboBox()
        for member in enum_class:
            self.combo.addItem(member.name, member)

        self.combo.currentIndexChanged.connect(self._on_changed)
        layout.addWidget(self.combo)

    def _on_changed(self, index: int):
        if not self._updating:
            self.valueChanged.emit(self.combo.currentData())

    def get_value(self) -> E:
        return self.combo.currentData()

    def set_value(self, value: E) -> None:
        self._updating = True
        index = self.combo.findData(value)
        if index >= 0:
            self.combo.setCurrentIndex(index)
        self._updating = False


class LabeledEnumDropdown(QWidget):
    """An enum dropdown with a label on the same line."""

    valueChanged = pyqtSignal(object)

    def __init__(self, enum_class: Type[E], label: str, label_width: int = 80, parent=None):
        super().__init__(parent)
        self._enum_class = enum_class
        self._updating = False

        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        lbl = QLabel(label)
        lbl.setFixedWidth(label_width)
        layout.addWidget(lbl)

        self.combo = QComboBox()
        for member in enum_class:
            self.combo.addItem(member.name, member)

        self.combo.currentIndexChanged.connect(self._on_changed)
        layout.addWidget(self.combo)
        layout.addStretch()

    def _on_changed(self, index: int):
        if not self._updating:
            self.valueChanged.emit(self.combo.currentData())

    def get_value(self) -> E:
        return self.combo.currentData()

    def set_value(self, value: E) -> None:
        self._updating = True
        index = self.combo.findData(value)
        if index >= 0:
            self.combo.setCurrentIndex(index)
        self._updating = False
