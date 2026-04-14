"""
NamePanel — name field + save/load/export buttons.
Mirrors the name/save area from Java CubicCurvePanel.
"""
from __future__ import annotations
import os
from PySide6.QtWidgets import (
    QWidget, QHBoxLayout, QLabel, QLineEdit, QPushButton, QFileDialog,
)
from PySide6.QtCore import Signal


class NamePanel(QWidget):
    """Emits save_requested(name, save_dir) when the user clicks Save."""

    save_requested = Signal(str, str)   # (name, save_dir)
    load_requested = Signal(str)        # (file_path,)

    def __init__(self, save_dir: str, initial_name: str = "shape",
                 parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._save_dir = save_dir
        self._setup_ui(initial_name)

    def _setup_ui(self, initial_name: str) -> None:
        layout = QHBoxLayout(self)
        layout.setContentsMargins(4, 2, 4, 2)
        layout.setSpacing(6)

        layout.addWidget(QLabel("Name:"))
        self._name_edit = QLineEdit(initial_name)
        self._name_edit.setMinimumWidth(160)
        layout.addWidget(self._name_edit)

        btn_save = QPushButton("Save")
        btn_save.clicked.connect(self._on_save)
        layout.addWidget(btn_save)

        btn_load = QPushButton("Load…")
        btn_load.clicked.connect(self._on_load)
        layout.addWidget(btn_load)

        layout.addStretch()

    # ── properties ────────────────────────────────────────────────────────────

    @property
    def name(self) -> str:
        return self._name_edit.text().strip() or "shape"

    @name.setter
    def name(self, value: str) -> None:
        self._name_edit.setText(value)

    @property
    def save_dir(self) -> str:
        return self._save_dir

    @save_dir.setter
    def save_dir(self, value: str) -> None:
        self._save_dir = value

    # ── slots ─────────────────────────────────────────────────────────────────

    def _on_save(self) -> None:
        self.save_requested.emit(self.name, self._save_dir)

    def _on_load(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "Open XML file", self._save_dir,
            "XML files (*.xml *.layers.xml);;All files (*)"
        )
        if path:
            self.load_requested.emit(path)
