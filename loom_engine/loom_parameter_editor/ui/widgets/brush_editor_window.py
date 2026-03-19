"""
Enhanced brush editor — floating QMainWindow with:
  • Separate grid resolution vs output PNG size
  • Resolution multiplier (resamples grid content)
  • 11-swatch greyscale palette
  • Reference image overlay with auto/manual sampling
  • Full transform toolbar (shift, flip, mirror, rotate, select)
"""
import os
import math
import random
from typing import Optional

from PyQt6.QtWidgets import (
    QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QLabel,
    QSpinBox, QDoubleSpinBox, QPushButton, QCheckBox, QRadioButton,
    QButtonGroup, QGroupBox, QScrollArea, QSizePolicy,
    QToolBar, QStatusBar, QMenuBar, QFileDialog, QMessageBox,
    QApplication
)
from PyQt6.QtCore import Qt, pyqtSignal, QPoint, QSize, QRect
from PyQt6.QtGui import (
    QImage, QPainter, QColor, QPen, QMouseEvent, QKeySequence,
    QAction, QActionGroup, QPixmap, QBrush
)


# ---------------------------------------------------------------------------
# GreyscalePalette
# ---------------------------------------------------------------------------

class GreyscalePalette(QWidget):
    """Row of 11 greyscale swatches (0%–100%) that emits the selected value."""

    valueChanged = pyqtSignal(int)   # 0-255

    SWATCHES = [0, 25, 51, 76, 102, 128, 153, 178, 204, 229, 255]
    SWATCH_W = 24
    SWATCH_H = 24

    def __init__(self, parent=None):
        super().__init__(parent)
        self._selected_idx = len(self.SWATCHES) - 1  # white by default
        total_w = self.SWATCH_W * len(self.SWATCHES)
        self.setFixedSize(total_w, self.SWATCH_H)

    def paintEvent(self, event):
        painter = QPainter(self)
        for i, v in enumerate(self.SWATCHES):
            x = i * self.SWATCH_W
            painter.fillRect(x, 0, self.SWATCH_W, self.SWATCH_H, QColor(v, v, v))
            if i == self._selected_idx:
                painter.setPen(QPen(QColor(0, 120, 255), 2))
                painter.drawRect(x + 1, 1, self.SWATCH_W - 3, self.SWATCH_H - 3)
        painter.end()

    def mousePressEvent(self, event: QMouseEvent):
        idx = event.pos().x() // self.SWATCH_W
        idx = max(0, min(len(self.SWATCHES) - 1, idx))
        self._selected_idx = idx
        self.update()
        self.valueChanged.emit(self.SWATCHES[idx])

    def set_value(self, v: int):
        """Select nearest swatch for value v (0-255)."""
        best = 0
        best_dist = abs(self.SWATCHES[0] - v)
        for i, sv in enumerate(self.SWATCHES):
            d = abs(sv - v)
            if d < best_dist:
                best_dist = d
                best = i
        self._selected_idx = best
        self.update()


# ---------------------------------------------------------------------------
# BrushGridCanvas
# ---------------------------------------------------------------------------

DRAW = 0
ERASE = 1
IMAGE_DRAW = 2
SELECT = 3
DESELECT = 4


class BrushGridCanvas(QWidget):
    """Zoomable grid canvas that stores a float[row][col] paint grid."""

    modified = pyqtSignal()
    cellPainted = pyqtSignal(int, int)   # row, col

    CELL_SIZE = 16  # display pixels per cell

    def __init__(self, parent=None):
        super().__init__(parent)
        self._rows = 32
        self._cols = 32
        self._grid: list[list[float]] = [[0.0] * 32 for _ in range(32)]
        self._sel: Optional[tuple] = None   # (r1,c1,r2,c2) inclusive
        self._sel_start: Optional[tuple] = None
        self._show_grid = True
        self._ref_scaled: Optional[QImage] = None
        self._ref_opacity: float = 0.4
        self._mode = DRAW
        self._paint_value: float = 1.0
        self._painting = False
        self._wrapping = False
        self._last_paint_pos: Optional[tuple] = None   # (r, c) of last painted cell
        self._last_paint_value: float = 1.0            # value that was painted there
        self._update_fixed_size()
        self.setMouseTracking(True)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def set_mode(self, mode: int):
        self._mode = mode

    def set_paint_value(self, v: float):
        self._paint_value = max(0.0, min(1.0, v))

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

    def get_cell(self, r: int, c: int) -> float:
        return self._grid[r][c]

    def get_grid(self) -> list[list[float]]:
        return self._grid

    def set_grid(self, grid: list[list[float]], rows: int, cols: int):
        self._rows = rows
        self._cols = cols
        self._grid = grid
        self._sel = None
        self._update_fixed_size()
        self.update()
        self.modified.emit()

    def get_dims(self) -> tuple[int, int]:
        return self._rows, self._cols

    # ------------------------------------------------------------------
    # Transforms
    # ------------------------------------------------------------------

    def shift(self, dr: int, dc: int):
        g = self._grid
        rows, cols = self._rows, self._cols
        black_row = [0.0] * cols
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
                self._grid = g[1:] + [black_row[:]]
            elif dr == 1:
                self._grid = [black_row[:]] + g[:-1]
            elif dc == -1:
                self._grid = [[r[c + 1] if c < cols - 1 else 0.0 for c in range(cols)] for r in g]
            elif dc == 1:
                self._grid = [[r[c - 1] if c > 0 else 0.0 for c in range(cols)] for r in g]
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

    def invert(self):
        self._grid = [[1.0 - v for v in row] for row in self._grid]
        self.update(); self.modified.emit()

    def clear(self, sel_only: bool = False):
        if sel_only and self._sel:
            r1, c1, r2, c2 = self._sel
            for r in range(r1, r2 + 1):
                for c in range(c1, c2 + 1):
                    self._grid[r][c] = 0.0
        else:
            self._grid = [[0.0] * self._cols for _ in range(self._rows)]
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
                self._grid[r][c] = px.red() / 255.0
        self.update(); self.modified.emit()

    # ------------------------------------------------------------------
    # Presets (delegate logic from BrushCanvas)
    # ------------------------------------------------------------------

    def generate_circle(self, soft: bool = False):
        cx = self._cols / 2.0
        cy = self._rows / 2.0
        radius = min(cx, cy) - 1
        for r in range(self._rows):
            for c in range(self._cols):
                dist = math.sqrt((c - cx + 0.5) ** 2 + (r - cy + 0.5) ** 2)
                if soft:
                    val = max(0.0, 1.0 - dist / radius) if radius > 0 else 0.0
                else:
                    val = 1.0 if dist <= radius else 0.0
                self._grid[r][c] = val
        self.update(); self.modified.emit()

    def generate_scatter(self):
        self._grid = [[0.0] * self._cols for _ in range(self._rows)]
        cx = self._cols / 2.0
        cy = self._rows / 2.0
        radius = min(cx, cy) - 1
        num_dots = max(3, (self._rows * self._cols) // 8)
        for _ in range(num_dots):
            c = random.randint(0, self._cols - 1)
            r = random.randint(0, self._rows - 1)
            dist = math.sqrt((c - cx + 0.5) ** 2 + (r - cy + 0.5) ** 2)
            if dist <= radius:
                self._grid[r][c] = random.randint(100, 255) / 255.0
        self.update(); self.modified.emit()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _update_fixed_size(self):
        cs = self.CELL_SIZE
        self.setFixedSize(self._cols * cs, self._rows * cs)

    def _cell_at(self, pos: QPoint) -> Optional[tuple[int, int]]:
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
        elif (self._mode in (DRAW, ERASE) and
              event.modifiers() & Qt.KeyboardModifier.ShiftModifier and
              self._last_paint_pos is not None):
            # Shift+click: draw interpolated line from last painted cell to here
            r0, c0 = self._last_paint_pos
            v0 = self._last_paint_value
            v1 = self._paint_value if self._mode == DRAW else 0.0
            self._paint_line(r0, c0, v0, r, c, v1)
            self._last_paint_pos = (r, c)
            self._last_paint_value = v1
            self.update()
            self.modified.emit()
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
            self._grid[r][c] = self._paint_value
            self._last_paint_pos = (r, c)
            self._last_paint_value = self._paint_value
        elif self._mode == ERASE:
            self._grid[r][c] = 0.0
            self._last_paint_pos = (r, c)
            self._last_paint_value = 0.0
        elif self._mode == IMAGE_DRAW:
            if self._ref_scaled:
                px = self._ref_scaled.pixelColor(c, r)
                self._grid[r][c] = px.red() / 255.0
                self._last_paint_pos = (r, c)
                self._last_paint_value = self._grid[r][c]
        self.update()
        self.cellPainted.emit(r, c)
        self.modified.emit()

    def _bresenham(self, r0: int, c0: int, r1: int, c1: int) -> list:
        """Return list of (r, c) cells on a line from (r0,c0) to (r1,c1)."""
        cells = []
        dr = abs(r1 - r0)
        dc = abs(c1 - c0)
        sr = 1 if r1 > r0 else -1
        sc = 1 if c1 > c0 else -1
        err = dr - dc
        r, c = r0, c0
        while True:
            cells.append((r, c))
            if r == r1 and c == c1:
                break
            e2 = 2 * err
            if e2 > -dc:
                err -= dc
                r += sr
            if e2 < dr:
                err += dr
                c += sc
        return cells

    def _paint_line(self, r0: int, c0: int, v0: float,
                    r1: int, c1: int, v1: float):
        """Paint a Bresenham line from (r0,c0) to (r1,c1), interpolating v0→v1."""
        cells = self._bresenham(r0, c0, r1, c1)
        n = len(cells) - 1
        for i, (r, c) in enumerate(cells):
            if 0 <= r < self._rows and 0 <= c < self._cols:
                t = i / n if n > 0 else 0.0
                self._grid[r][c] = max(0.0, min(1.0, v0 + t * (v1 - v0)))

    # ------------------------------------------------------------------
    # Paint
    # ------------------------------------------------------------------

    def paintEvent(self, event):
        painter = QPainter(self)
        cs = self.CELL_SIZE

        # Background
        painter.fillRect(self.rect(), QColor(17, 17, 17))

        # Grid cells
        for r in range(self._rows):
            for c in range(self._cols):
                v = int(self._grid[r][c] * 255)
                painter.fillRect(c * cs, r * cs, cs, cs, QColor(v, v, v))

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
            painter.setPen(QPen(QColor(50, 50, 50), 1))
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
# BrushEditorWindow
# ---------------------------------------------------------------------------

class BrushEditorWindow(QMainWindow):
    """Floating standalone brush editor window."""

    brushSaved = pyqtSignal(str)   # emits filename (basename) on save

    def __init__(self, brushes_dir: str = "", initial_file: Optional[str] = None,
                 parent=None):
        super().__init__(parent)
        self._brushes_dir = brushes_dir
        self._current_file: Optional[str] = initial_file
        self._modified = False
        self._rows = 32
        self._cols = 32
        self._out_w = 32
        self._out_h = 32
        self._ref_image: Optional[QImage] = None
        self._ref_scaled: Optional[QImage] = None

        self.setWindowTitle("Brush Editor")
        self.setMinimumSize(600, 500)

        # Create canvas first — toolbar and left-panel spinboxes reference it
        # during construction (direct method-reference binds, setValue signals)
        self._canvas = BrushGridCanvas()
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

        # File
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

        # Transform > Grid
        xform_menu = mb.addMenu("Transform")

        act_sl = QAction("Shift Left", self)
        act_sl.setShortcut(QKeySequence("Ctrl+Left"))
        act_sl.triggered.connect(lambda: self._canvas.shift(0, -1))
        xform_menu.addAction(act_sl)

        act_sr = QAction("Shift Right", self)
        act_sr.setShortcut(QKeySequence("Ctrl+Right"))
        act_sr.triggered.connect(lambda: self._canvas.shift(0, 1))
        xform_menu.addAction(act_sr)

        act_su = QAction("Shift Up", self)
        act_su.setShortcut(QKeySequence("Ctrl+Up"))
        act_su.triggered.connect(lambda: self._canvas.shift(-1, 0))
        xform_menu.addAction(act_su)

        act_sd = QAction("Shift Down", self)
        act_sd.setShortcut(QKeySequence("Ctrl+Down"))
        act_sd.triggered.connect(lambda: self._canvas.shift(1, 0))
        xform_menu.addAction(act_sd)

        xform_menu.addSeparator()

        act_fh = QAction("Flip H", self)
        act_fh.setShortcut(QKeySequence("Ctrl+Y"))
        act_fh.triggered.connect(self._canvas_flip_h)
        xform_menu.addAction(act_fh)

        act_fv = QAction("Flip V", self)
        act_fv.setShortcut(QKeySequence("Ctrl+U"))
        act_fv.triggered.connect(self._canvas_flip_v)
        xform_menu.addAction(act_fv)

        act_mh = QAction("Mirror H", self)
        act_mh.setShortcut(QKeySequence("Ctrl+J"))
        act_mh.triggered.connect(self._canvas_mirror_h)
        xform_menu.addAction(act_mh)

        act_mv = QAction("Mirror V", self)
        act_mv.setShortcut(QKeySequence("Ctrl+K"))
        act_mv.triggered.connect(self._canvas_mirror_v)
        xform_menu.addAction(act_mv)

        act_rl = QAction("Rotate Left", self)
        act_rl.setShortcut(QKeySequence("Ctrl+,"))
        act_rl.triggered.connect(self._canvas_rotate_left)
        xform_menu.addAction(act_rl)

        act_rr = QAction("Rotate Right", self)
        act_rr.setShortcut(QKeySequence("Ctrl+."))
        act_rr.triggered.connect(self._canvas_rotate_right)
        xform_menu.addAction(act_rr)

        xform_menu.addSeparator()
        act_inv = QAction("Invert", self)
        act_inv.triggered.connect(self._canvas_invert)
        xform_menu.addAction(act_inv)

    # Wrappers that also sync grid dims after rotate
    def _canvas_flip_h(self): self._canvas.flip_h()
    def _canvas_flip_v(self): self._canvas.flip_v()
    def _canvas_mirror_h(self): self._canvas.mirror_h()
    def _canvas_mirror_v(self): self._canvas.mirror_v()
    def _canvas_invert(self): self._canvas.invert()

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

        # Mode group (mutually exclusive)
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

        a_draw = make_mode("Draw", "Draw (paint cells)", DRAW)
        a_draw.setChecked(True)
        make_mode("Erase", "Erase (clear cells to black)", ERASE)
        make_mode("ImgDraw", "Image Draw (sample from reference)", IMAGE_DRAW)
        make_mode("Select", "Select rectangle", SELECT)
        a_desel = make_mode("Desel", "Deselect", DESELECT)

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

        tb_act("Clear", "Clear entire grid", lambda: self._canvas.clear(False))
        tb_act("ClrSel", "Clear selection", lambda: self._canvas.clear(True))
        tb_act("Inv", "Invert values", self._canvas_invert)

        tb.addSeparator()
        tb_act("FlipH", "Flip horizontal", self._canvas_flip_h)
        tb_act("FlipV", "Flip vertical", self._canvas_flip_v)
        tb_act("MirH", "Mirror H (copy left→right)", self._canvas_mirror_h)
        tb_act("MirV", "Mirror V (copy top→bottom)", self._canvas_mirror_v)
        tb_act("RotL", "Rotate 90° left", self._canvas_rotate_left)
        tb_act("RotR", "Rotate 90° right", self._canvas_rotate_right)

        tb.addSeparator()
        tb_act("◄", "Shift left", lambda: self._canvas.shift(0, -1))
        tb_act("►", "Shift right", lambda: self._canvas.shift(0, 1))
        tb_act("▲", "Shift up", lambda: self._canvas.shift(-1, 0))
        tb_act("▼", "Shift down", lambda: self._canvas.shift(1, 0))

    # ------------------------------------------------------------------
    # Central widget
    # ------------------------------------------------------------------

    def _build_central(self):
        central = QWidget()
        self.setCentralWidget(central)
        main_row = QHBoxLayout(central)
        main_row.setContentsMargins(4, 4, 4, 4)
        main_row.setSpacing(6)

        # ---- Left panel ----
        left = QWidget()
        left.setFixedWidth(230)
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(6)

        left_layout.addWidget(self._build_output_size_group())
        left_layout.addWidget(self._build_grid_res_group())
        left_layout.addWidget(self._build_palette_group())
        left_layout.addWidget(self._build_image_group())
        left_layout.addWidget(self._build_presets_group())
        left_layout.addStretch()

        main_row.addWidget(left)

        # ---- Canvas scroll area ----
        scroll = QScrollArea()
        scroll.setWidget(self._canvas)
        scroll.setWidgetResizable(False)
        scroll.setAlignment(Qt.AlignmentFlag.AlignCenter)
        scroll.setStyleSheet("background: #222;")
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

    def _build_palette_group(self) -> QGroupBox:
        grp = QGroupBox("Palette")
        lay = QVBoxLayout(grp)

        self._palette = GreyscalePalette()
        self._palette.valueChanged.connect(self._on_palette_changed)
        lay.addWidget(self._palette)

        spin_row = QHBoxLayout()
        spin_row.addWidget(QLabel("Value:"))
        self._value_spin = QSpinBox()
        self._value_spin.setRange(0, 255)
        self._value_spin.setValue(255)
        self._value_spin.valueChanged.connect(self._on_value_spin_changed)
        spin_row.addWidget(self._value_spin)
        spin_row.addStretch()
        lay.addLayout(spin_row)

        return grp

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

        mode_row = QHBoxLayout()
        self._auto_radio = QRadioButton("Auto sample")
        self._auto_radio.setChecked(True)
        self._manual_radio = QRadioButton("Manual")
        mode_row.addWidget(self._auto_radio)
        mode_row.addWidget(self._manual_radio)
        lay.addLayout(mode_row)

        apply_all_btn = QPushButton("Apply to All")
        apply_all_btn.clicked.connect(self._canvas.apply_ref_to_all)
        lay.addWidget(apply_all_btn)

        return grp

    def _build_presets_group(self) -> QGroupBox:
        grp = QGroupBox("Presets")
        lay = QHBoxLayout(grp)
        circle_btn = QPushButton("Circle")
        circle_btn.clicked.connect(lambda: self._canvas.generate_circle(soft=False))
        lay.addWidget(circle_btn)
        soft_btn = QPushButton("Soft Circle")
        soft_btn.clicked.connect(lambda: self._canvas.generate_circle(soft=True))
        lay.addWidget(soft_btn)
        scatter_btn = QPushButton("Scatter")
        scatter_btn.clicked.connect(self._canvas.generate_scatter)
        lay.addWidget(scatter_btn)
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
        self.setWindowTitle(f"Brush Editor — {fname}{mod}")

    # ------------------------------------------------------------------
    # Signal handlers
    # ------------------------------------------------------------------

    def _on_canvas_modified(self):
        self._modified = True
        self._update_title()
        self._update_status()

    def _on_palette_changed(self, v: int):
        self._value_spin.blockSignals(True)
        self._value_spin.setValue(v)
        self._value_spin.blockSignals(False)
        self._canvas.set_paint_value(v / 255.0)

    def _on_value_spin_changed(self, v: int):
        self._palette.set_value(v)
        self._canvas.set_paint_value(v / 255.0)

    def _on_ref_opacity_changed(self, v: float):
        self._canvas.set_ref_opacity(v)

    def _on_load_ref(self):
        project_dir = os.path.dirname(self._brushes_dir) if self._brushes_dir else ""
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
        self._ref_image = img.convertToFormat(QImage.Format.Format_Grayscale8)
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
        # Resample existing grid
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
    # Grid ↔ QImage helpers
    # ------------------------------------------------------------------

    def _grid_to_qimage(self) -> QImage:
        rows, cols = self._canvas.get_dims()
        img = QImage(cols, rows, QImage.Format.Format_Grayscale8)
        for r in range(rows):
            for c in range(cols):
                v = int(self._canvas.get_cell(r, c) * 255)
                img.setPixelColor(c, r, QColor(v, v, v))
        return img

    def _qimage_to_grid(self, img: QImage,
                         rows: int, cols: int) -> list[list[float]]:
        grid = []
        for r in range(rows):
            row = []
            for c in range(cols):
                row.append(img.pixelColor(c, r).red() / 255.0)
            grid.append(row)
        return grid

    # ------------------------------------------------------------------
    # File operations
    # ------------------------------------------------------------------

    def _on_new(self):
        if self._modified:
            reply = QMessageBox.question(
                self, "Unsaved Changes", "Discard changes and create new brush?",
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
        grid = [[0.0] * 32 for _ in range(32)]
        self._canvas.set_grid(grid, 32, 32)
        self._modified = False
        self._update_title()
        self._update_status()

    def _on_open(self):
        start = self._brushes_dir or ""
        path, _ = QFileDialog.getOpenFileName(
            self, "Open Brush", start, "PNG Files (*.png)"
        )
        if path:
            self._load_file(path)

    def _load_file(self, path: str):
        img = QImage(path)
        if img.isNull():
            QMessageBox.warning(self, "Load Error", f"Could not load:\n{path}")
            return
        grey = img.convertToFormat(QImage.Format.Format_Grayscale8)
        rows = grey.height()
        cols = grey.width()
        grid = self._qimage_to_grid(grey, rows, cols)
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
        """Public entry-point — called by brush_library when re-raising window."""
        self._load_file(path)

    def _on_save(self):
        if self._current_file:
            self._export_png(self._current_file)
        else:
            self._on_save_as()

    def _on_save_as(self):
        start = self._brushes_dir or (
            os.path.dirname(self._current_file) if self._current_file else ""
        )
        path, _ = QFileDialog.getSaveFileName(
            self, "Save Brush As", start, "PNG Files (*.png)"
        )
        if path:
            if not path.lower().endswith(".png"):
                path += ".png"
            self._current_file = path
            self._export_png(path)

    def _export_png(self, path: str):
        grid_img = self._grid_to_qimage()
        output = grid_img.scaled(
            self._out_w, self._out_h,
            Qt.AspectRatioMode.IgnoreAspectRatio,
            Qt.TransformationMode.SmoothTransformation
        )
        if not output.save(path, "PNG"):
            QMessageBox.critical(self, "Save Error", f"Could not save:\n{path}")
            return
        # Save grid metadata sidecar so the rendering tab can show grid vs output dims
        try:
            import json
            rows, cols = self._canvas.get_dims()
            meta = {"grid_w": cols, "grid_h": rows, "out_w": self._out_w, "out_h": self._out_h}
            with open(path + ".meta.json", "w") as f:
                json.dump(meta, f)
        except Exception:
            pass
        self._modified = False
        self._update_title()
        self._update_status()
        self.brushSaved.emit(os.path.basename(path))

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
