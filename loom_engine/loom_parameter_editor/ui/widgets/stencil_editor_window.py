"""
Stencil editor — floating QMainWindow for creating/editing full-RGBA stencil PNGs.
Key differences from BrushEditorWindow:
  • Grid stores (r,g,b,a) tuples (0-255 each channel)
  • ColorSwatchWidget with QColorDialog for RGBA paint colour
  • Checkered background shows transparency
  • Saves ARGB32 PNGs (no greyscale conversion)
  • No presets panel (circle/scatter are greyscale-specific)
"""
import os
import json
from typing import Optional

import math
from PyQt6.QtWidgets import (
    QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QLabel,
    QSpinBox, QDoubleSpinBox, QPushButton, QCheckBox,
    QButtonGroup, QGroupBox, QScrollArea, QSlider,
    QToolBar, QStatusBar, QFileDialog, QMessageBox,
    QApplication, QRadioButton
)
from PyQt6.QtCore import Qt, pyqtSignal, QPoint, QSize, QRect
from PyQt6.QtGui import (
    QImage, QPainter, QColor, QPen, QMouseEvent, QKeySequence,
    QAction, QActionGroup, QPixmap, QBrush, QIcon
)


# ---------------------------------------------------------------------------
# Mode constants (same as brush editor)
# ---------------------------------------------------------------------------

DRAW = 0
ERASE = 1
IMAGE_DRAW = 2
SELECT = 3
DESELECT = 4


# ---------------------------------------------------------------------------
# ColorSwatchWidget
# ---------------------------------------------------------------------------

class ColorSwatchWidget(QWidget):
    """Single colour swatch button — opens QColorDialog to pick RGBA."""

    colorChanged = pyqtSignal(QColor)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._color = QColor(255, 255, 255, 255)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)

        layout.addWidget(QLabel("Colour:"))

        self._swatch_btn = QPushButton()
        self._swatch_btn.setFixedSize(40, 24)
        self._swatch_btn.clicked.connect(self._on_click)
        layout.addWidget(self._swatch_btn)

        self._update_swatch()
        layout.addStretch()

    def get_color(self) -> QColor:
        return self._color

    def set_color(self, color: QColor):
        self._color = color
        self._update_swatch()

    def _on_click(self):
        from PyQt6.QtWidgets import QColorDialog
        color = QColorDialog.getColor(
            self._color, self,
            "Pick paint colour",
            QColorDialog.ColorDialogOption.ShowAlphaChannel
        )
        if color.isValid():
            self._color = color
            self._update_swatch()
            self.colorChanged.emit(color)

    def _update_swatch(self):
        pix = QPixmap(40, 24)
        # Checkered background
        painter = QPainter(pix)
        painter.fillRect(0, 0, 40, 24, QColor(200, 200, 200))
        light = QColor(255, 255, 255)
        dark = QColor(160, 160, 160)
        cell = 6
        for y in range(0, 24, cell):
            for x in range(0, 40, cell):
                if ((x // cell + y // cell) % 2) == 0:
                    painter.fillRect(x, y, cell, cell, light)
                else:
                    painter.fillRect(x, y, cell, cell, dark)
        painter.fillRect(0, 0, 40, 24, self._color)
        painter.end()
        self._swatch_btn.setIcon(QIcon(pix))
        self._swatch_btn.setIconSize(QSize(40, 24))


# ---------------------------------------------------------------------------
# StencilGridCanvas
# ---------------------------------------------------------------------------

class StencilGridCanvas(QWidget):
    """Zoomable grid canvas that stores a list[list[tuple(r,g,b,a)]] paint grid."""

    modified = pyqtSignal()
    cellPainted = pyqtSignal(int, int)  # row, col

    CELL_SIZE = 16

    def __init__(self, parent=None):
        super().__init__(parent)
        self._rows = 32
        self._cols = 32
        self._grid: list = [[(0, 0, 0, 0)] * 32 for _ in range(32)]
        self._sel: Optional[tuple] = None
        self._sel_start: Optional[tuple] = None
        self._show_grid = True
        self._ref_scaled: Optional[QImage] = None
        self._ref_opacity: float = 0.4
        self._mode = DRAW
        self._paint_color: tuple = (255, 255, 255, 255)
        self._painting = False
        self._wrapping = False
        self._update_fixed_size()
        self.setMouseTracking(True)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def set_mode(self, mode: int):
        self._mode = mode

    def set_paint_color(self, color: QColor):
        self._paint_color = (color.red(), color.green(), color.blue(), color.alpha())

    def set_wrapping(self, w: bool):
        self._wrapping = w

    def set_show_grid(self, v: bool):
        self._show_grid = v
        self.update()

    def set_ref_scaled(self, img: Optional[QImage]):
        self._ref_scaled = img
        self.update()

    def set_ref_opacity(self, op: float):
        self._ref_opacity = op
        self.update()

    def get_cell(self, r: int, c: int) -> tuple:
        return self._grid[r][c]

    def get_grid(self) -> list:
        return self._grid

    def set_grid(self, grid: list, rows: int, cols: int):
        self._rows = rows
        self._cols = cols
        self._grid = grid
        self._sel = None
        self._update_fixed_size()
        self.update()
        self.modified.emit()

    def get_dims(self) -> tuple:
        return self._rows, self._cols

    # ------------------------------------------------------------------
    # Transforms (operate on RGBA tuples)
    # ------------------------------------------------------------------

    def shift(self, dr: int, dc: int):
        g = self._grid
        rows, cols = self._rows, self._cols
        blank = (0, 0, 0, 0)
        blank_row = [blank] * cols
        if self._wrapping:
            if dr == -1:
                self._grid = g[1:] + [g[0][:]]
            elif dr == 1:
                self._grid = [g[-1][:]] + g[:-1]
            elif dc == -1:
                self._grid = [[r[(c + 1) % cols] for c in range(cols)] for r in g]
            elif dc == 1:
                self._grid = [[r[(c - 1) % cols] for c in range(cols)] for r in g]
        else:
            if dr == -1:
                self._grid = g[1:] + [blank_row[:]]
            elif dr == 1:
                self._grid = [blank_row[:]] + g[:-1]
            elif dc == -1:
                self._grid = [[r[c + 1] if c < cols - 1 else blank for c in range(cols)] for r in g]
            elif dc == 1:
                self._grid = [[r[c - 1] if c > 0 else blank for c in range(cols)] for r in g]
        self.update()
        self.modified.emit()

    def flip_h(self):
        self._grid = [row[::-1] for row in self._grid]
        self.update(); self.modified.emit()

    def flip_v(self):
        self._grid = self._grid[::-1]
        self.update(); self.modified.emit()

    def mirror_h(self):
        half = self._cols // 2
        self._grid = [row[:half] + row[:half][::-1] for row in self._grid]
        self.update(); self.modified.emit()

    def mirror_v(self):
        half = self._rows // 2
        self._grid = self._grid[:half] + self._grid[:half][::-1]
        self.update(); self.modified.emit()

    def rotate_left(self):
        rows, cols = self._rows, self._cols
        self._grid = [[self._grid[c][rows - 1 - r] for c in range(cols)] for r in range(rows)]
        self._rows, self._cols = cols, rows
        self._update_fixed_size()
        self.update(); self.modified.emit()

    def rotate_right(self):
        rows, cols = self._rows, self._cols
        self._grid = [[self._grid[rows - 1 - c][r] for c in range(cols)] for r in range(rows)]
        self._rows, self._cols = cols, rows
        self._update_fixed_size()
        self.update(); self.modified.emit()

    def clear(self, sel_only: bool = False):
        blank = (0, 0, 0, 0)
        if sel_only and self._sel:
            r1, c1, r2, c2 = self._sel
            for r in range(r1, r2 + 1):
                for c in range(c1, c2 + 1):
                    self._grid[r][c] = blank
        else:
            self._grid = [[blank] * self._cols for _ in range(self._rows)]
        self.update(); self.modified.emit()

    def deselect(self):
        self._sel = None
        self.update()

    def apply_ref_to_all(self):
        if not self._ref_scaled:
            return
        r1, c1, r2, c2 = self._sel if self._sel else (0, 0, self._rows - 1, self._cols - 1)
        for r in range(r1, r2 + 1):
            for c in range(c1, c2 + 1):
                px = self._ref_scaled.pixelColor(c, r)
                self._grid[r][c] = (px.red(), px.green(), px.blue(), px.alpha())
        self.update(); self.modified.emit()

    def apply_color_select(self, target: tuple, tolerance: int):
        """Set cells whose RGB Euclidean distance from target <= tolerance to transparent."""
        tr, tg, tb = target[0], target[1], target[2]
        changed = False
        for r in range(self._rows):
            for c in range(self._cols):
                rv, gv, bv, av = self._grid[r][c]
                if av == 0:
                    continue  # already transparent
                dist = math.sqrt((rv - tr) ** 2 + (gv - tg) ** 2 + (bv - tb) ** 2)
                if dist <= tolerance:
                    self._grid[r][c] = (0, 0, 0, 0)
                    changed = True
        if changed:
            self.update()
            self.modified.emit()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _update_fixed_size(self):
        cs = self.CELL_SIZE
        self.setFixedSize(self._cols * cs, self._rows * cs)

    def _cell_at(self, pos: QPoint) -> Optional[tuple]:
        cs = self.CELL_SIZE
        r = pos.y() // cs
        c = pos.x() // cs
        if 0 <= r < self._rows and 0 <= c < self._cols:
            return r, c
        return None

    # ------------------------------------------------------------------
    # Mouse events
    # ------------------------------------------------------------------

    def mousePressEvent(self, event: QMouseEvent):
        if event.button() != Qt.MouseButton.LeftButton:
            return
        self._painting = True
        cell = self._cell_at(event.pos())
        if cell is None:
            return
        r, c = cell
        if self._mode == SELECT:
            self._sel_start = (r, c)
            self._sel = (r, c, r, c)
            self.update()
        elif self._mode == DESELECT:
            self._sel = None
            self.update()
        else:
            self._apply_paint(r, c)

    def mouseMoveEvent(self, event: QMouseEvent):
        if not self._painting:
            return
        cell = self._cell_at(event.pos())
        if cell is None:
            return
        r, c = cell
        if self._mode == SELECT and self._sel_start:
            r0, c0 = self._sel_start
            self._sel = (min(r0, r), min(c0, c), max(r0, r), max(c0, c))
            self.update()
        elif self._mode in (DRAW, ERASE, IMAGE_DRAW):
            self._apply_paint(r, c)

    def mouseReleaseEvent(self, event: QMouseEvent):
        if event.button() == Qt.MouseButton.LeftButton:
            self._painting = False

    def _apply_paint(self, r: int, c: int):
        if self._mode == DRAW:
            self._grid[r][c] = self._paint_color
        elif self._mode == ERASE:
            self._grid[r][c] = (0, 0, 0, 0)
        elif self._mode == IMAGE_DRAW:
            if self._ref_scaled:
                px = self._ref_scaled.pixelColor(c, r)
                self._grid[r][c] = (px.red(), px.green(), px.blue(), px.alpha())
        self.update()
        self.cellPainted.emit(r, c)
        self.modified.emit()

    # ------------------------------------------------------------------
    # Paint event — checkered background + RGBA cells
    # ------------------------------------------------------------------

    def paintEvent(self, event):
        painter = QPainter(self)
        cs = self.CELL_SIZE

        # Checkered background (light/dark grey) to show transparency
        light = QColor(200, 200, 200)
        dark = QColor(140, 140, 140)
        check = cs // 2 if cs >= 4 else 2
        for r in range(self._rows):
            for c in range(self._cols):
                x, y = c * cs, r * cs
                for dy in range(0, cs, check):
                    for dx in range(0, cs, check):
                        if ((dx // check + dy // check) % 2) == 0:
                            painter.fillRect(x + dx, y + dy, check, check, light)
                        else:
                            painter.fillRect(x + dx, y + dy, check, check, dark)

        # Grid cells
        for r in range(self._rows):
            for c in range(self._cols):
                rv, gv, bv, av = self._grid[r][c]
                if av > 0:
                    painter.fillRect(c * cs, r * cs, cs, cs, QColor(rv, gv, bv, av))

        # Reference image overlay
        if self._ref_scaled and self._ref_opacity > 0:
            painter.setOpacity(self._ref_opacity)
            scaled_to_canvas = self._ref_scaled.scaled(
                self._cols * cs, self._rows * cs,
                Qt.AspectRatioMode.IgnoreAspectRatio,
                Qt.TransformationMode.SmoothTransformation
            )
            painter.drawImage(0, 0, scaled_to_canvas)
            painter.setOpacity(1.0)

        # Grid lines
        if self._show_grid:
            painter.setPen(QPen(QColor(80, 80, 80), 1))
            for col in range(self._cols + 1):
                painter.drawLine(col * cs, 0, col * cs, self._rows * cs)
            for row in range(self._rows + 1):
                painter.drawLine(0, row * cs, self._cols * cs, row * cs)

        # Selection rect
        if self._sel:
            r1, c1, r2, c2 = self._sel
            pen = QPen(QColor(0, 120, 255), 2, Qt.PenStyle.DashLine)
            painter.setPen(pen)
            painter.setBrush(Qt.BrushStyle.NoBrush)
            painter.drawRect(c1 * cs, r1 * cs,
                             (c2 - c1 + 1) * cs, (r2 - r1 + 1) * cs)

        painter.end()


# ---------------------------------------------------------------------------
# StencilEditorWindow
# ---------------------------------------------------------------------------

class StencilEditorWindow(QMainWindow):
    """Floating standalone stencil editor window for RGBA PNG stencils."""

    stencilSaved = pyqtSignal(str)   # emits filename (basename) on save

    def __init__(self, stencils_dir: str = "", initial_file: Optional[str] = None,
                 parent=None):
        super().__init__(parent)
        self._stencils_dir = stencils_dir
        self._current_file: Optional[str] = initial_file
        self._modified = False
        self._rows = 32
        self._cols = 32
        self._out_w = 32
        self._out_h = 32
        self._ref_image: Optional[QImage] = None
        self._ref_scaled: Optional[QImage] = None

        self.setWindowTitle("Stamp Editor")
        self.setMinimumSize(620, 520)

        self._canvas = StencilGridCanvas()
        self._canvas.modified.connect(self._on_canvas_modified)

        self._build_menu()
        self._build_toolbar()
        self._build_central()
        self._build_status_bar()
        self._update_title()
        self._update_status()

        if initial_file:
            self._load_file(initial_file)

    # ------------------------------------------------------------------
    # Menu
    # ------------------------------------------------------------------

    def _build_menu(self):
        mb = self.menuBar()

        file_menu = mb.addMenu("File")
        act_new = QAction("New", self)
        act_new.setShortcut(QKeySequence.StandardKey.New)
        act_new.triggered.connect(self._on_new)
        file_menu.addAction(act_new)

        act_open = QAction("Open...", self)
        act_open.setShortcut(QKeySequence.StandardKey.Open)
        act_open.triggered.connect(self._on_open)
        file_menu.addAction(act_open)

        file_menu.addSeparator()

        act_save = QAction("Save", self)
        act_save.setShortcut(QKeySequence.StandardKey.Save)
        act_save.triggered.connect(self._on_save)
        file_menu.addAction(act_save)

        act_save_as = QAction("Save As...", self)
        act_save_as.setShortcut(QKeySequence("Ctrl+Shift+S"))
        act_save_as.triggered.connect(self._on_save_as)
        file_menu.addAction(act_save_as)

        file_menu.addSeparator()
        act_close = QAction("Close", self)
        act_close.triggered.connect(self.close)
        file_menu.addAction(act_close)

        xform_menu = mb.addMenu("Transform")

        for label, shortcut, slot in [
            ("Shift Left",  "Ctrl+Left",  lambda: self._canvas.shift(0, -1)),
            ("Shift Right", "Ctrl+Right", lambda: self._canvas.shift(0,  1)),
            ("Shift Up",    "Ctrl+Up",    lambda: self._canvas.shift(-1, 0)),
            ("Shift Down",  "Ctrl+Down",  lambda: self._canvas.shift(1,  0)),
        ]:
            a = QAction(label, self)
            a.setShortcut(QKeySequence(shortcut))
            a.triggered.connect(slot)
            xform_menu.addAction(a)

        xform_menu.addSeparator()
        for label, shortcut, slot in [
            ("Flip H",       "Ctrl+Y", self._canvas.flip_h),
            ("Flip V",       "Ctrl+U", self._canvas.flip_v),
            ("Mirror H",     "Ctrl+J", self._canvas.mirror_h),
            ("Mirror V",     "Ctrl+K", self._canvas.mirror_v),
            ("Rotate Left",  "Ctrl+,", self._canvas_rotate_left),
            ("Rotate Right", "Ctrl+.", self._canvas_rotate_right),
        ]:
            a = QAction(label, self)
            a.setShortcut(QKeySequence(shortcut))
            a.triggered.connect(slot)
            xform_menu.addAction(a)

    def _canvas_rotate_left(self):
        self._canvas.rotate_left()
        self._sync_dims_from_canvas()

    def _canvas_rotate_right(self):
        self._canvas.rotate_right()
        self._sync_dims_from_canvas()

    def _sync_dims_from_canvas(self):
        rows, cols = self._canvas.get_dims()
        self._rows, self._cols = rows, cols
        self._rows_spin.blockSignals(True)
        self._cols_spin.blockSignals(True)
        self._rows_spin.setValue(rows)
        self._cols_spin.setValue(cols)
        self._rows_spin.blockSignals(False)
        self._cols_spin.blockSignals(False)
        self._resample_ref()
        self._update_status()

    # ------------------------------------------------------------------
    # Toolbar
    # ------------------------------------------------------------------

    def _build_toolbar(self):
        tb = QToolBar("Tools", self)
        tb.setMovable(False)
        self.addToolBar(tb)

        mode_group = QActionGroup(self)
        mode_group.setExclusive(True)

        def make_mode(label, tooltip, mode_val):
            a = QAction(label, self)
            a.setToolTip(tooltip)
            a.setCheckable(True)
            a.triggered.connect(lambda checked, m=mode_val: self._canvas.set_mode(m))
            mode_group.addAction(a)
            tb.addAction(a)
            return a

        a_draw = make_mode("Draw", "Draw (paint cells with selected colour)", DRAW)
        a_draw.setChecked(True)
        make_mode("Erase",   "Erase (set cells to transparent)", ERASE)
        make_mode("ImgDraw", "Image Draw (sample from reference image)", IMAGE_DRAW)
        make_mode("Select",  "Select rectangle", SELECT)
        make_mode("Desel",   "Deselect", DESELECT)

        tb.addSeparator()

        act_grid = QAction("Grid", self)
        act_grid.setToolTip("Toggle grid lines")
        act_grid.setCheckable(True)
        act_grid.setChecked(True)
        act_grid.triggered.connect(self._canvas.set_show_grid)
        tb.addAction(act_grid)

        tb.addSeparator()

        def tb_act(label, tooltip, slot):
            a = QAction(label, self)
            a.setToolTip(tooltip)
            a.triggered.connect(slot)
            tb.addAction(a)

        tb_act("Clear",  "Clear entire grid", lambda: self._canvas.clear(False))
        tb_act("ClrSel", "Clear selection",   lambda: self._canvas.clear(True))

        tb.addSeparator()
        tb_act("FlipH", "Flip horizontal",        self._canvas.flip_h)
        tb_act("FlipV", "Flip vertical",          self._canvas.flip_v)
        tb_act("MirH",  "Mirror H",               self._canvas.mirror_h)
        tb_act("MirV",  "Mirror V",               self._canvas.mirror_v)
        tb_act("RotL",  "Rotate 90° left",        self._canvas_rotate_left)
        tb_act("RotR",  "Rotate 90° right",       self._canvas_rotate_right)

        tb.addSeparator()
        tb_act("◄", "Shift left",  lambda: self._canvas.shift(0, -1))
        tb_act("►", "Shift right", lambda: self._canvas.shift(0,  1))
        tb_act("▲", "Shift up",    lambda: self._canvas.shift(-1, 0))
        tb_act("▼", "Shift down",  lambda: self._canvas.shift(1,  0))

    # ------------------------------------------------------------------
    # Central widget
    # ------------------------------------------------------------------

    def _build_central(self):
        central = QWidget()
        self.setCentralWidget(central)
        main_row = QHBoxLayout(central)
        main_row.setContentsMargins(4, 4, 4, 4)
        main_row.setSpacing(6)

        left = QWidget()
        left.setFixedWidth(230)
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(6)

        left_layout.addWidget(self._build_output_size_group())
        left_layout.addWidget(self._build_grid_res_group())
        left_layout.addWidget(self._build_color_group())
        left_layout.addWidget(self._build_select_group())
        left_layout.addWidget(self._build_image_group())
        left_layout.addStretch()

        main_row.addWidget(left)

        scroll = QScrollArea()
        scroll.setWidget(self._canvas)
        scroll.setWidgetResizable(False)
        scroll.setAlignment(Qt.AlignmentFlag.AlignCenter)
        scroll.setStyleSheet("background: #333;")
        main_row.addWidget(scroll, 1)

    def _build_output_size_group(self) -> QGroupBox:
        grp = QGroupBox("Output Size (px)")
        lay = QHBoxLayout(grp)
        lay.addWidget(QLabel("W:"))
        self._out_w_spin = QSpinBox()
        self._out_w_spin.setRange(8, 512)
        self._out_w_spin.setValue(32)
        self._out_w_spin.valueChanged.connect(lambda v: setattr(self, '_out_w', v))
        lay.addWidget(self._out_w_spin)
        lay.addWidget(QLabel("H:"))
        self._out_h_spin = QSpinBox()
        self._out_h_spin.setRange(8, 512)
        self._out_h_spin.setValue(32)
        self._out_h_spin.valueChanged.connect(lambda v: setattr(self, '_out_h', v))
        lay.addWidget(self._out_h_spin)
        return grp

    def _build_grid_res_group(self) -> QGroupBox:
        grp = QGroupBox("Grid Resolution")
        lay = QVBoxLayout(grp)

        rc_row = QHBoxLayout()
        rc_row.addWidget(QLabel("Rows:"))
        self._rows_spin = QSpinBox()
        self._rows_spin.setRange(1, 128)
        self._rows_spin.setValue(32)
        self._rows_spin.valueChanged.connect(self._on_grid_res_changed)
        rc_row.addWidget(self._rows_spin)
        rc_row.addWidget(QLabel("Cols:"))
        self._cols_spin = QSpinBox()
        self._cols_spin.setRange(1, 128)
        self._cols_spin.setValue(32)
        self._cols_spin.valueChanged.connect(self._on_grid_res_changed)
        rc_row.addWidget(self._cols_spin)
        lay.addLayout(rc_row)

        mult_row = QHBoxLayout()
        mult_row.addWidget(QLabel("×:"))
        self._mult_spin = QDoubleSpinBox()
        self._mult_spin.setRange(0.1, 8.0)
        self._mult_spin.setSingleStep(0.1)
        self._mult_spin.setValue(1.0)
        self._mult_spin.setDecimals(1)
        mult_row.addWidget(self._mult_spin)
        apply_mult_btn = QPushButton("Apply ×")
        apply_mult_btn.clicked.connect(self._apply_multiplier)
        mult_row.addWidget(apply_mult_btn)
        lay.addLayout(mult_row)

        self._wrap_check = QCheckBox("Wrap shifts")
        self._wrap_check.toggled.connect(self._canvas.set_wrapping)
        lay.addWidget(self._wrap_check)

        return grp

    def _build_color_group(self) -> QGroupBox:
        grp = QGroupBox("Paint Colour")
        lay = QVBoxLayout(grp)

        self._color_swatch = ColorSwatchWidget()
        self._color_swatch.colorChanged.connect(self._on_color_changed)
        lay.addWidget(self._color_swatch)

        return grp

    def _build_select_group(self) -> QGroupBox:
        grp = QGroupBox("Colour Select")
        lay = QVBoxLayout(grp)

        # Target colour swatch
        self._select_swatch = ColorSwatchWidget()
        self._select_swatch._color_swatch_label = None  # reuse widget, label already built in
        lay.addWidget(self._select_swatch)

        # Tolerance slider
        tol_row = QHBoxLayout()
        tol_row.addWidget(QLabel("Tolerance:"))
        self._tolerance_slider = QSlider(Qt.Orientation.Horizontal)
        self._tolerance_slider.setRange(0, 255)
        self._tolerance_slider.setValue(30)
        self._tolerance_slider.setTickInterval(32)
        self._tolerance_slider.setTickPosition(QSlider.TickPosition.TicksBelow)
        tol_row.addWidget(self._tolerance_slider)
        self._tolerance_label = QLabel("30")
        self._tolerance_label.setFixedWidth(28)
        tol_row.addWidget(self._tolerance_label)
        self._tolerance_slider.valueChanged.connect(
            lambda v: self._tolerance_label.setText(str(v)))
        lay.addLayout(tol_row)

        # Action button
        apply_btn = QPushButton("Make Transparent")
        apply_btn.setToolTip(
            "Set cells whose colour is within tolerance of the target to transparent")
        apply_btn.clicked.connect(self._on_apply_color_select)
        lay.addWidget(apply_btn)

        return grp

    def _on_apply_color_select(self):
        c = self._select_swatch.get_color()
        target = (c.red(), c.green(), c.blue())
        tolerance = self._tolerance_slider.value()
        self._canvas.apply_color_select(target, tolerance)

    def _build_image_group(self) -> QGroupBox:
        grp = QGroupBox("Reference Image")
        lay = QVBoxLayout(grp)

        load_row = QHBoxLayout()
        load_btn = QPushButton("Load Image...")
        load_btn.clicked.connect(self._on_load_ref)
        load_row.addWidget(load_btn)
        self._ref_label = QLabel("(none)")
        self._ref_label.setWordWrap(True)
        load_row.addWidget(self._ref_label, 1)
        lay.addLayout(load_row)

        op_row = QHBoxLayout()
        op_row.addWidget(QLabel("Opacity:"))
        self._ref_opacity_spin = QDoubleSpinBox()
        self._ref_opacity_spin.setRange(0.0, 1.0)
        self._ref_opacity_spin.setSingleStep(0.05)
        self._ref_opacity_spin.setValue(0.4)
        self._ref_opacity_spin.setDecimals(2)
        self._ref_opacity_spin.valueChanged.connect(self._on_ref_opacity_changed)
        op_row.addWidget(self._ref_opacity_spin)
        op_row.addStretch()
        lay.addLayout(op_row)

        apply_all_btn = QPushButton("Apply to All")
        apply_all_btn.clicked.connect(self._canvas.apply_ref_to_all)
        lay.addWidget(apply_all_btn)

        return grp

    # ------------------------------------------------------------------
    # Status bar
    # ------------------------------------------------------------------

    def _build_status_bar(self):
        self._status_bar = QStatusBar()
        self.setStatusBar(self._status_bar)

    def _update_status(self):
        rows, cols = self._canvas.get_dims()
        fname = os.path.basename(self._current_file) if self._current_file else "new"
        self._status_bar.showMessage(
            f"{rows}×{cols} grid → {self._out_w}×{self._out_h} output  |  {fname}"
        )

    def _update_title(self):
        fname = os.path.basename(self._current_file) if self._current_file else "Untitled"
        mod = " *" if self._modified else ""
        self.setWindowTitle(f"Stencil Editor — {fname}{mod}")

    # ------------------------------------------------------------------
    # Signal handlers
    # ------------------------------------------------------------------

    def _on_canvas_modified(self):
        self._modified = True
        self._update_title()
        self._update_status()

    def _on_color_changed(self, color: QColor):
        self._canvas.set_paint_color(color)

    def _on_ref_opacity_changed(self, v: float):
        self._canvas.set_ref_opacity(v)

    def _on_load_ref(self):
        project_dir = os.path.dirname(self._stencils_dir) if self._stencils_dir else ""
        start = os.path.join(project_dir, "background_image") if project_dir else ""
        if start and not os.path.isdir(start):
            start = project_dir
        path, _ = QFileDialog.getOpenFileName(
            self, "Load Reference Image", start,
            "Images (*.png *.jpg *.jpeg *.bmp *.tiff *.gif)"
        )
        if not path:
            return
        img = QImage(path)
        if img.isNull():
            QMessageBox.warning(self, "Load Error", f"Could not load image:\n{path}")
            return
        # Keep colour for RGBA sampling
        self._ref_image = img.convertToFormat(QImage.Format.Format_ARGB32)
        self._ref_label.setText(os.path.basename(path))
        self._resample_ref()

    def _resample_ref(self):
        if not self._ref_image:
            self._ref_scaled = None
        else:
            self._ref_scaled = self._ref_image.scaled(
                self._cols, self._rows,
                Qt.AspectRatioMode.IgnoreAspectRatio,
                Qt.TransformationMode.SmoothTransformation
            )
        self._canvas.set_ref_scaled(self._ref_scaled)

    def _on_grid_res_changed(self):
        new_rows = self._rows_spin.value()
        new_cols = self._cols_spin.value()
        if new_rows == self._rows and new_cols == self._cols:
            return
        old_img = self._grid_to_qimage()
        scaled = old_img.scaled(
            new_cols, new_rows,
            Qt.AspectRatioMode.IgnoreAspectRatio,
            Qt.TransformationMode.SmoothTransformation
        )
        new_grid = self._qimage_to_grid(scaled, new_rows, new_cols)
        self._rows = new_rows
        self._cols = new_cols
        self._canvas.set_grid(new_grid, new_rows, new_cols)
        self._resample_ref()
        self._update_status()

    def _apply_multiplier(self):
        mult = self._mult_spin.value()
        new_rows = max(1, round(self._rows * mult))
        new_cols = max(1, round(self._cols * mult))
        old_img = self._grid_to_qimage()
        scaled = old_img.scaled(
            new_cols, new_rows,
            Qt.AspectRatioMode.IgnoreAspectRatio,
            Qt.TransformationMode.SmoothTransformation
        )
        new_grid = self._qimage_to_grid(scaled, new_rows, new_cols)
        self._rows = new_rows
        self._cols = new_cols
        self._rows_spin.blockSignals(True)
        self._cols_spin.blockSignals(True)
        self._rows_spin.setValue(new_rows)
        self._cols_spin.setValue(new_cols)
        self._rows_spin.blockSignals(False)
        self._cols_spin.blockSignals(False)
        self._canvas.set_grid(new_grid, new_rows, new_cols)
        self._resample_ref()
        self._update_status()

    # ------------------------------------------------------------------
    # Grid ↔ QImage helpers (ARGB32)
    # ------------------------------------------------------------------

    def _grid_to_qimage(self) -> QImage:
        rows, cols = self._canvas.get_dims()
        img = QImage(cols, rows, QImage.Format.Format_ARGB32)
        for r in range(rows):
            for c in range(cols):
                rv, gv, bv, av = self._canvas.get_cell(r, c)
                img.setPixelColor(c, r, QColor(rv, gv, bv, av))
        return img

    def _qimage_to_grid(self, img: QImage, rows: int, cols: int) -> list:
        argb = img.convertToFormat(QImage.Format.Format_ARGB32)
        grid = []
        for r in range(rows):
            row = []
            for c in range(cols):
                px = argb.pixelColor(c, r)
                row.append((px.red(), px.green(), px.blue(), px.alpha()))
            grid.append(row)
        return grid

    # ------------------------------------------------------------------
    # File operations
    # ------------------------------------------------------------------

    def _on_new(self):
        if self._modified:
            reply = QMessageBox.question(
                self, "Unsaved Changes", "Discard changes and create new stencil?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
            if reply != QMessageBox.StandardButton.Yes:
                return
        self._current_file = None
        self._rows = 32
        self._cols = 32
        self._rows_spin.blockSignals(True)
        self._cols_spin.blockSignals(True)
        self._rows_spin.setValue(32)
        self._cols_spin.setValue(32)
        self._rows_spin.blockSignals(False)
        self._cols_spin.blockSignals(False)
        grid = [[(0, 0, 0, 0)] * 32 for _ in range(32)]
        self._canvas.set_grid(grid, 32, 32)
        self._modified = False
        self._update_title()
        self._update_status()

    def _on_open(self):
        start = self._stencils_dir or ""
        path, _ = QFileDialog.getOpenFileName(
            self, "Open Stencil", start, "PNG Files (*.png)"
        )
        if path:
            self._load_file(path)

    def _load_file(self, path: str):
        img = QImage(path)
        if img.isNull():
            QMessageBox.warning(self, "Load Error", f"Could not load:\n{path}")
            return
        argb = img.convertToFormat(QImage.Format.Format_ARGB32)
        rows = argb.height()
        cols = argb.width()
        grid = self._qimage_to_grid(argb, rows, cols)
        self._rows = rows
        self._cols = cols
        self._rows_spin.blockSignals(True)
        self._cols_spin.blockSignals(True)
        self._rows_spin.setValue(rows)
        self._cols_spin.setValue(cols)
        self._rows_spin.blockSignals(False)
        self._cols_spin.blockSignals(False)
        self._out_w_spin.setValue(cols)
        self._out_h_spin.setValue(rows)
        self._out_w = cols
        self._out_h = rows
        self._canvas.set_grid(grid, rows, cols)
        self._current_file = path
        self._modified = False
        self._resample_ref()
        self._update_title()
        self._update_status()

    def open_file(self, path: str):
        """Public entry-point — called by stencil_library when re-raising window."""
        self._load_file(path)

    def _on_save(self):
        if self._current_file:
            self._export_png(self._current_file)
        else:
            self._on_save_as()

    def _on_save_as(self):
        start = self._stencils_dir or (
            os.path.dirname(self._current_file) if self._current_file else ""
        )
        path, _ = QFileDialog.getSaveFileName(
            self, "Save Stamp As", start, "PNG Files (*.png)"
        )
        if path:
            if not path.lower().endswith(".png"):
                path += ".png"
            self._current_file = path
            self._export_png(path)

    def _export_png(self, path: str):
        """Export the grid as a full-RGBA ARGB32 PNG (no greyscale conversion)."""
        grid_img = self._grid_to_qimage()
        output = grid_img.scaled(
            self._out_w, self._out_h,
            Qt.AspectRatioMode.IgnoreAspectRatio,
            Qt.TransformationMode.SmoothTransformation
        )
        if not output.save(path, "PNG"):
            QMessageBox.critical(self, "Save Error", f"Could not save:\n{path}")
            return
        # Save grid metadata sidecar (grid dims vs output dims)
        try:
            rows, cols = self._canvas.get_dims()
            meta = {"grid_w": cols, "grid_h": rows, "out_w": self._out_w, "out_h": self._out_h}
            with open(path + ".meta.json", "w") as f:
                json.dump(meta, f)
        except Exception:
            pass
        self._modified = False
        self._update_title()
        self._update_status()
        self.stencilSaved.emit(os.path.basename(path))

    # ------------------------------------------------------------------
    # Close guard
    # ------------------------------------------------------------------

    def closeEvent(self, event):
        if self._modified:
            reply = QMessageBox.question(
                self, "Unsaved Changes", "Save before closing?",
                QMessageBox.StandardButton.Save |
                QMessageBox.StandardButton.Discard |
                QMessageBox.StandardButton.Cancel
            )
            if reply == QMessageBox.StandardButton.Save:
                self._on_save()
                event.accept()
            elif reply == QMessageBox.StandardButton.Discard:
                event.accept()
            else:
                event.ignore()
        else:
            event.accept()
