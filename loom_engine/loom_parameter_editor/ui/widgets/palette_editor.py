"""
Palette editor widget for PAL_SEQ / PAL_RAN color change kinds.
"""
from PyQt6.QtWidgets import (
    QWidget, QHBoxLayout, QVBoxLayout, QLabel, QPushButton, QScrollArea, QSizePolicy
)
from PyQt6.QtCore import pyqtSignal, Qt, QSize
from PyQt6.QtGui import QPainter, QColor, QPen, QBrush
from models.rendering import Color


_SWATCH = 28
_GAP = 3
_MAX_PALETTE = 32


class _PaletteCanvas(QWidget):
    """Row of colour swatches — internal widget used by PaletteEditorWidget."""

    selectionChanged = pyqtSignal(int)   # emits selected index (or -1)
    editRequested = pyqtSignal(int)      # double-click on a swatch

    def __init__(self, parent=None):
        super().__init__(parent)
        self._colors: list[QColor] = []
        self._selected: int = -1
        self.setMinimumHeight(_SWATCH + 8)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)

    def set_colors(self, colors: list[QColor]) -> None:
        self._colors = colors
        n = max(len(colors), 1)
        self.setMinimumWidth(n * (_SWATCH + _GAP))
        self._selected = min(self._selected, len(colors) - 1)
        self.update()

    def get_selected(self) -> int:
        return self._selected

    def set_selected(self, idx: int) -> None:
        self._selected = idx
        self.update()

    def sizeHint(self) -> QSize:
        n = max(len(self._colors), 1)
        return QSize(n * (_SWATCH + _GAP), _SWATCH + 8)

    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, False)
        y = 4
        for i, col in enumerate(self._colors):
            x = i * (_SWATCH + _GAP)
            painter.fillRect(x, y, _SWATCH, _SWATCH, col)
            if i == self._selected:
                # white inner border, dark outer border
                painter.setPen(QPen(QColor(0, 0, 0), 1))
                painter.drawRect(x, y, _SWATCH - 1, _SWATCH - 1)
                painter.setPen(QPen(QColor(255, 255, 255), 1))
                painter.drawRect(x + 1, y + 1, _SWATCH - 3, _SWATCH - 3)

    def _index_at(self, x: int) -> int:
        idx = x // (_SWATCH + _GAP)
        if 0 <= idx < len(self._colors):
            return idx
        return -1

    def mousePressEvent(self, event) -> None:
        idx = self._index_at(event.pos().x())
        self._selected = idx
        self.update()
        self.selectionChanged.emit(idx)

    def mouseDoubleClickEvent(self, event) -> None:
        idx = self._index_at(event.pos().x())
        if idx >= 0:
            self.editRequested.emit(idx)


class PaletteEditorWidget(QWidget):
    """Public widget for editing a list of palette colors (max 32)."""

    paletteChanged = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._colors: list[QColor] = []

        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(2)

        # Header row
        header = QHBoxLayout()
        self._count_label = QLabel("Palette (0 / 32)")
        header.addWidget(self._count_label)
        header.addStretch()

        self._add_btn = QPushButton("+")
        self._add_btn.setFixedWidth(28)
        self._add_btn.setToolTip("Add colour")
        self._add_btn.clicked.connect(self._on_add)
        header.addWidget(self._add_btn)

        self._dup_btn = QPushButton("Dup")
        self._dup_btn.setFixedWidth(36)
        self._dup_btn.setToolTip("Duplicate selected")
        self._dup_btn.clicked.connect(self._on_duplicate)
        header.addWidget(self._dup_btn)

        self._del_btn = QPushButton("×")
        self._del_btn.setFixedWidth(28)
        self._del_btn.setToolTip("Remove selected")
        self._del_btn.clicked.connect(self._on_remove)
        header.addWidget(self._del_btn)

        outer.addLayout(header)

        # Scroll area containing the canvas
        self._canvas = _PaletteCanvas()
        self._canvas.selectionChanged.connect(self._on_selection_changed)
        self._canvas.editRequested.connect(self._on_edit)

        scroll = QScrollArea()
        scroll.setFixedHeight(_SWATCH + 16)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        scroll.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setWidgetResizable(True)
        scroll.setWidget(self._canvas)
        outer.addWidget(scroll)

        self._refresh()

    # ── public API ──────────────────────────────────────────────────────────

    def set_palette(self, colors: list[Color]) -> None:
        self._colors = [QColor(c.r, c.g, c.b, c.a) for c in colors]
        self._canvas.set_colors(list(self._colors))
        self._canvas.set_selected(-1)
        self._refresh()

    def get_palette(self) -> list[Color]:
        return [Color(c.red(), c.green(), c.blue(), c.alpha()) for c in self._colors]

    # ── slots ────────────────────────────────────────────────────────────────

    def _on_add(self) -> None:
        from PyQt6.QtWidgets import QColorDialog
        if len(self._colors) >= _MAX_PALETTE:
            return
        col = QColorDialog.getColor(
            QColor(255, 255, 255, 255), self, "Add Palette Colour",
            QColorDialog.ColorDialogOption.ShowAlphaChannel
        )
        if col.isValid():
            self._colors.append(col)
            self._canvas.set_colors(list(self._colors))
            self._canvas.set_selected(len(self._colors) - 1)
            self._refresh()
            self.paletteChanged.emit()

    def _on_duplicate(self) -> None:
        idx = self._canvas.get_selected()
        if idx < 0 or len(self._colors) >= _MAX_PALETTE:
            return
        copy = QColor(self._colors[idx])
        self._colors.insert(idx + 1, copy)
        self._canvas.set_colors(list(self._colors))
        self._canvas.set_selected(idx + 1)
        self._refresh()
        self.paletteChanged.emit()

    def _on_remove(self) -> None:
        idx = self._canvas.get_selected()
        if idx < 0:
            return
        del self._colors[idx]
        new_sel = min(idx, len(self._colors) - 1)
        self._canvas.set_colors(list(self._colors))
        self._canvas.set_selected(new_sel)
        self._refresh()
        self.paletteChanged.emit()

    def _on_edit(self, idx: int) -> None:
        from PyQt6.QtWidgets import QColorDialog
        col = QColorDialog.getColor(
            self._colors[idx], self, "Edit Palette Colour",
            QColorDialog.ColorDialogOption.ShowAlphaChannel
        )
        if col.isValid():
            self._colors[idx] = col
            self._canvas.set_colors(list(self._colors))
            self._refresh()
            self.paletteChanged.emit()

    def _on_selection_changed(self, idx: int) -> None:
        self._refresh()

    # ── helpers ──────────────────────────────────────────────────────────────

    def _refresh(self) -> None:
        n = len(self._colors)
        self._count_label.setText(f"Palette ({n} / {_MAX_PALETTE})")
        sel = self._canvas.get_selected()
        self._add_btn.setEnabled(n < _MAX_PALETTE)
        self._dup_btn.setEnabled(sel >= 0 and n < _MAX_PALETTE)
        self._del_btn.setEnabled(sel >= 0)
