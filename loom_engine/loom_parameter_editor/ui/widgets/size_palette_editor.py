"""
Size palette editor for PAL_SEQ / PAL_RAN size-change kinds (stroke width, point size).
"""
import os
from PySide6.QtWidgets import (
    QWidget, QHBoxLayout, QVBoxLayout, QLabel, QPushButton,
    QScrollArea, QSizePolicy, QInputDialog
)
from PySide6.QtCore import Signal, Qt, QSize
from PySide6.QtGui import QPainter, QColor, QPen, QBrush, QFont


_BOX = 40          # preview box width & height (px)
_GAP = 3           # gap between boxes
_MAX_PALETTE = 12  # max palette entries


class _SizePaletteCanvas(QWidget):
    """Row of size-preview boxes — internal widget."""

    selectionChanged = Signal(int)
    editRequested = Signal(int)

    def __init__(self, preview_mode: str = 'point', parent=None):
        """preview_mode: 'point' draws a circle; 'stroke' draws a vertical line."""
        super().__init__(parent)
        self._values: list[float] = []
        self._selected: int = -1
        self._mode = preview_mode
        self.setMinimumHeight(_BOX + 8)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)

    def set_values(self, values: list[float]) -> None:
        self._values = values
        n = max(len(values), 1)
        self.setMinimumWidth(n * (_BOX + _GAP))
        self._selected = min(self._selected, len(values) - 1)
        self.update()

    def get_selected(self) -> int:
        return self._selected

    def set_selected(self, idx: int) -> None:
        self._selected = idx
        self.update()

    def sizeHint(self) -> QSize:
        n = max(len(self._values), 1)
        return QSize(n * (_BOX + _GAP), _BOX + 8)

    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        bg = QColor(235, 235, 235)
        shape_col = QColor(30, 30, 30)
        y = 4

        for i, val in enumerate(self._values):
            x = i * (_BOX + _GAP)
            cx = x + _BOX // 2
            cy = y + _BOX // 2

            # Background box
            painter.fillRect(x, y, _BOX, _BOX, bg)

            if self._mode == 'point':
                max_r = (_BOX - 2) / 2  # circle fits within box
                r = min(max(1, val / 2), max_r)
                if val / 2 <= max_r:
                    painter.setPen(Qt.PenStyle.NoPen)
                    painter.setBrush(QBrush(shape_col))
                    painter.drawEllipse(int(cx - r), int(cy - r), int(r * 2), int(r * 2))
                else:
                    painter.setPen(QPen(shape_col))
                    font = QFont()
                    font.setPointSize(7)
                    painter.setFont(font)
                    text = f"{val:.1f}" if val != int(val) else str(int(val))
                    painter.drawText(x, y, _BOX, _BOX, Qt.AlignmentFlag.AlignCenter, text)
            else:  # stroke
                max_w = _BOX - 2  # line fits within box
                w = int(val)
                if w <= max_w:
                    painter.setPen(Qt.PenStyle.NoPen)
                    painter.setBrush(QBrush(shape_col))
                    h = _BOX - 12
                    painter.fillRect(cx - w // 2, cy - h // 2, max(1, w), h, shape_col)
                else:
                    painter.setPen(QPen(shape_col))
                    font = QFont()
                    font.setPointSize(7)
                    painter.setFont(font)
                    text = f"{val:.1f}" if val != int(val) else str(int(val))
                    painter.drawText(x, y, _BOX, _BOX, Qt.AlignmentFlag.AlignCenter, text)

            # Selection highlight
            if i == self._selected:
                painter.setPen(QPen(QColor(0, 0, 0), 1))
                painter.setBrush(Qt.BrushStyle.NoBrush)
                painter.drawRect(x, y, _BOX - 1, _BOX - 1)
                painter.setPen(QPen(QColor(255, 255, 255), 1))
                painter.drawRect(x + 1, y + 1, _BOX - 3, _BOX - 3)

    def _index_at(self, x: int) -> int:
        idx = x // (_BOX + _GAP)
        if 0 <= idx < len(self._values):
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


class SizePaletteEditorWidget(QWidget):
    """Public widget for editing a list of size values (stroke width or point size)."""

    paletteChanged = Signal()

    def __init__(self, preview_mode: str = 'point', parent=None):
        super().__init__(parent)
        self._values: list[float] = []
        self._mode = preview_mode
        self._palettes_dir: str = ""

        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(2)

        # Input + buttons row
        row = QHBoxLayout()
        self._spin_label = QLabel("Value:")
        row.addWidget(self._spin_label)

        from PySide6.QtWidgets import QDoubleSpinBox
        self._spin = QDoubleSpinBox()
        self._spin.setRange(0.1, 999.9)
        self._spin.setDecimals(1)
        self._spin.setSingleStep(1.0)
        self._spin.setValue(2.0)
        self._spin.setFixedWidth(72)
        row.addWidget(self._spin)

        row.addStretch()

        self._count_label = QLabel(f"(0 / {_MAX_PALETTE})")
        row.addWidget(self._count_label)

        self._add_btn = QPushButton("+")
        self._add_btn.setFixedWidth(28)
        self._add_btn.setToolTip("Add value")
        self._add_btn.clicked.connect(self._on_add)
        row.addWidget(self._add_btn)

        self._dup_btn = QPushButton("Dup")
        self._dup_btn.setFixedWidth(36)
        self._dup_btn.setToolTip("Duplicate selected")
        self._dup_btn.clicked.connect(self._on_duplicate)
        row.addWidget(self._dup_btn)

        self._del_btn = QPushButton("×")
        self._del_btn.setFixedWidth(28)
        self._del_btn.setToolTip("Remove selected")
        self._del_btn.clicked.connect(self._on_remove)
        row.addWidget(self._del_btn)

        self._save_btn = QPushButton("Save…")
        self._save_btn.setFixedWidth(44)
        self._save_btn.setToolTip("Save palette to file")
        self._save_btn.clicked.connect(self._on_save)
        row.addWidget(self._save_btn)

        self._import_btn = QPushButton("Import…")
        self._import_btn.setFixedWidth(56)
        self._import_btn.setToolTip("Import palette from file")
        self._import_btn.clicked.connect(self._on_import)
        row.addWidget(self._import_btn)

        outer.addLayout(row)

        # Scroll area for canvas
        self._canvas = _SizePaletteCanvas(preview_mode)
        self._canvas.selectionChanged.connect(self._on_selection_changed)
        self._canvas.editRequested.connect(self._on_edit)

        scroll = QScrollArea()
        scroll.setFixedHeight(_BOX + 16)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        scroll.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setWidgetResizable(True)
        scroll.setWidget(self._canvas)
        outer.addWidget(scroll)

        self._refresh()

    # ── public API ────────────────────────────────────────────────────────────

    def set_palettes_dir(self, path: str) -> None:
        self._palettes_dir = path
        self._refresh()

    def set_palette(self, values: list[float]) -> None:
        self._values = list(values)
        self._canvas.set_values(list(self._values))
        self._canvas.set_selected(-1)
        self._refresh()

    def get_palette(self) -> list[float]:
        return list(self._values)

    # ── slots ─────────────────────────────────────────────────────────────────

    def _on_add(self) -> None:
        if len(self._values) >= _MAX_PALETTE:
            return
        val = round(self._spin.value(), 1)
        self._values.append(val)
        self._canvas.set_values(list(self._values))
        self._canvas.set_selected(len(self._values) - 1)
        self._refresh()
        self.paletteChanged.emit()

    def _on_duplicate(self) -> None:
        idx = self._canvas.get_selected()
        if idx < 0 or len(self._values) >= _MAX_PALETTE:
            return
        self._values.insert(idx + 1, self._values[idx])
        self._canvas.set_values(list(self._values))
        self._canvas.set_selected(idx + 1)
        self._refresh()
        self.paletteChanged.emit()

    def _on_remove(self) -> None:
        idx = self._canvas.get_selected()
        if idx < 0:
            return
        del self._values[idx]
        new_sel = min(idx, len(self._values) - 1)
        self._canvas.set_values(list(self._values))
        self._canvas.set_selected(new_sel)
        self._refresh()
        self.paletteChanged.emit()

    def _on_edit(self, idx: int) -> None:
        val, ok = QInputDialog.getDouble(
            self, "Edit Value", "Size:",
            self._values[idx], 0.1, 999.9, 1
        )
        if ok:
            self._values[idx] = round(val, 1)
            self._canvas.set_values(list(self._values))
            self._refresh()
            self.paletteChanged.emit()

    def _on_save(self) -> None:
        if not self._palettes_dir:
            return
        from PySide6.QtWidgets import QMessageBox
        name, ok = QInputDialog.getText(self, "Save Palette", "Palette name:")
        if not ok or not name.strip():
            return
        name = name.strip()
        path = os.path.join(self._palettes_dir, name + "_sizes.xml")
        try:
            from file_io.palette_io import SizePaletteIO
            SizePaletteIO.save(self.get_palette(), path)
        except Exception as e:
            QMessageBox.warning(self, "Save Failed", str(e))

    def _on_import(self) -> None:
        if not self._palettes_dir:
            return
        from PySide6.QtWidgets import QFileDialog, QMessageBox
        path, _ = QFileDialog.getOpenFileName(
            self, "Import Palette", self._palettes_dir, "Size palettes (*_sizes.xml)"
        )
        if not path:
            return
        try:
            from file_io.palette_io import SizePaletteIO
            values = SizePaletteIO.load(path)
            self.set_palette(values)
            self.paletteChanged.emit()
        except Exception as e:
            QMessageBox.warning(self, "Import Failed", str(e))

    def _on_selection_changed(self, idx: int) -> None:
        self._refresh()

    # ── helpers ───────────────────────────────────────────────────────────────

    def _refresh(self) -> None:
        n = len(self._values)
        self._count_label.setText(f"({n} / {_MAX_PALETTE})")
        sel = self._canvas.get_selected()
        self._add_btn.setEnabled(n < _MAX_PALETTE)
        self._dup_btn.setEnabled(sel >= 0 and n < _MAX_PALETTE)
        self._del_btn.setEnabled(sel >= 0)
        has_dir = bool(self._palettes_dir)
        self._save_btn.setEnabled(has_dir and n > 0)
        self._import_btn.setEnabled(has_dir)
