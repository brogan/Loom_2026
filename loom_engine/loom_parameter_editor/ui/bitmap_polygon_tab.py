"""
BitmapPolygonTab — Geometry sub-tab for creating polygon sets from bitmap images.
"""
from __future__ import annotations

from PySide6.QtCore import Signal
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QPushButton, QLabel,
    QSizePolicy,
)

from .widgets.bitmap_polygon_dialog import BitmapPolygonDialog


class BitmapPolygonTab(QWidget):
    modified = Signal()

    # Unused but expected by GeometryTab signal-forwarding loop
    shapeLibraryChanged    = Signal()
    subdivisionChanged     = Signal()
    spriteLibraryChanged   = Signal()
    rendererLibraryChanged = Signal()
    newShapeCreated        = Signal(str, str)
    newSpriteCreated       = Signal(str, str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._polygon_sets_dir: str = ""
        self._background_image_dir: str = ""
        self._dialog: BitmapPolygonDialog | None = None

        self._setup_ui()

    # ── UI ────────────────────────────────────────────────────────────────────

    def _setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)

        desc = QLabel(
            "Trace a bitmap image and convert it to a polygon set.\n"
            "The result is saved to the project's polygonSets/ directory\n"
            "and will appear in the Spline Polygons tab."
        )
        desc.setWordWrap(True)
        layout.addWidget(desc)

        btn_row = QHBoxLayout()
        self._create_btn = QPushButton("Create from Bitmap…")
        self._create_btn.setSizePolicy(
            QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        self._create_btn.clicked.connect(self._on_create)
        btn_row.addWidget(self._create_btn)
        btn_row.addStretch()
        layout.addLayout(btn_row)

        layout.addStretch()

    # ── directory setters (called by GeometryTab / main_window) ───────────────

    def set_polygon_sets_directory(self, d: str):
        self._polygon_sets_dir = d

    def set_background_image_dir(self, d: str):
        self._background_image_dir = d

    # ── actions ───────────────────────────────────────────────────────────────

    def _on_create(self):
        if self._dialog and self._dialog.isVisible():
            self._dialog.raise_()
            self._dialog.activateWindow()
            return

        self._dialog = BitmapPolygonDialog(
            polygon_sets_dir=self._polygon_sets_dir,
            background_image_dir=self._background_image_dir,
            parent=self,
        )
        # When the dialog writes a file, signal the rest of the app
        self._dialog.accepted.connect(self.modified)
        self._dialog.show()
