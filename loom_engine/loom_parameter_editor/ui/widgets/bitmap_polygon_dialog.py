"""
BitmapPolygonDialog — load an image, threshold to binary, then either:
  • Trace the boundary as a polygon set (outline), or
  • Fill the interior with a regular quad mesh (for mesh editing in Bezier).
"""
from __future__ import annotations

import bisect
import os
import math
import xml.etree.ElementTree as ET

import numpy as np
import cv2

from PySide6.QtCore import Qt, QRectF, Signal
from PySide6.QtGui import QImage, QPixmap, QPainter, QPen, QColor, QCursor
from PySide6.QtWidgets import (
    QComboBox, QDialog, QVBoxLayout, QHBoxLayout, QLabel, QPushButton,
    QSlider, QCheckBox, QSpinBox, QDoubleSpinBox, QLineEdit,
    QGroupBox, QFormLayout, QFileDialog, QMessageBox,
    QSizePolicy, QFrame,
)


# ── tiny preview widget ────────────────────────────────────────────────────────

class _Preview(QLabel):
    """Scales a QPixmap to fill the label while keeping aspect ratio."""
    clicked = Signal(float, float)   # normalised image coords [0,1]

    def __init__(self, cursor_on_enter: Qt.CursorShape | None = None):
        super().__init__()
        self._pixmap: QPixmap | None = None
        self._cursor = cursor_on_enter
        self.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setMinimumSize(200, 200)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)

    def set_pixmap(self, pix: QPixmap | None):
        self._pixmap = pix
        self.update()

    def paintEvent(self, event):
        super().paintEvent(event)
        if self._pixmap:
            p = QPainter(self)
            rect = self._scaled_rect()
            p.drawPixmap(rect, self._pixmap,
                         QRectF(0, 0, self._pixmap.width(), self._pixmap.height()))

    def _scaled_rect(self) -> QRectF:
        if not self._pixmap:
            return QRectF()
        w, h = self._pixmap.width(), self._pixmap.height()
        sw, sh = self.width(), self.height()
        scale = min(sw / w, sh / h)
        dw, dh = w * scale, h * scale
        return QRectF((sw - dw) / 2, (sh - dh) / 2, dw, dh)

    def mousePressEvent(self, event):
        if not self._pixmap:
            return
        r = self._scaled_rect()
        px = (event.position().x() - r.x()) / r.width()
        py = (event.position().y() - r.y()) / r.height()
        if 0 <= px <= 1 and 0 <= py <= 1:
            self.clicked.emit(px, py)

    def enterEvent(self, event):
        if self._cursor is not None:
            self.setCursor(QCursor(self._cursor))

    def leaveEvent(self, event):
        if self._cursor is not None:
            self.unsetCursor()


# ── main dialog ───────────────────────────────────────────────────────────────

class BitmapPolygonDialog(QDialog):
    """
    Bitmap → polygonSet dialog.  Two independent outputs:

    Outline:   boundary polygon traced from the binary mask.
               → <name>.xml   (one polygon per contour)

    Quad Mesh: regular grid of quads filling the white region.
               → <name>_mesh.xml   (one 4-point polygon per cell)
               After loading in Bezier: Edit → Weld All Adjacent registers all
               shared-edge welds, then RELATIONAL polygon mode lets you drag
               any quad and all connected quads follow.
    """

    def __init__(self, polygon_sets_dir: str, background_image_dir: str,
                 parent=None):
        super().__init__(parent)
        self.setWindowTitle("Create Polygon from Bitmap")
        self.setModal(False)
        self.resize(1200, 760)

        self._polygon_sets_dir    = polygon_sets_dir
        self._background_image_dir = background_image_dir

        self._grey: np.ndarray | None = None
        self._rgb:  np.ndarray | None = None

        self._threshold: int  = 128
        self._invert:    bool = False

        self._setup_ui()

    # ── UI ────────────────────────────────────────────────────────────────────

    def _setup_ui(self):
        root = QVBoxLayout(self)

        # top row — load
        top = QHBoxLayout()
        self._load_btn = QPushButton("Load Image…")
        self._load_btn.clicked.connect(self._on_load)
        self._path_lbl = QLabel("(no image loaded)")
        self._path_lbl.setSizePolicy(QSizePolicy.Policy.Expanding,
                                     QSizePolicy.Policy.Preferred)
        top.addWidget(self._load_btn)
        top.addWidget(self._path_lbl)
        root.addLayout(top)

        # preview row
        prev_row = QHBoxLayout()

        self._grey_preview = _Preview(Qt.CursorShape.CrossCursor)
        self._grey_preview.clicked.connect(self._on_eyedropper)
        lbl_orig = QLabel("Original  (click to sample → set threshold)")
        lbl_orig.setAlignment(Qt.AlignmentFlag.AlignCenter)

        self._bin_preview = _Preview()
        self._bin_lbl = QLabel()   # updated dynamically
        self._bin_lbl.setTextFormat(Qt.TextFormat.RichText)
        self._bin_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._set_bin_label(mesh=False)

        for pv, lbl in ((self._grey_preview, lbl_orig),
                        (self._bin_preview,  self._bin_lbl)):
            col = QVBoxLayout()
            col.addWidget(lbl)
            col.addWidget(pv)
            prev_row.addLayout(col)

        root.addLayout(prev_row, stretch=1)

        # controls row
        ctrl = QHBoxLayout()
        root.addLayout(ctrl)

        # — Threshold —
        tg = QGroupBox("Threshold")
        tl = QVBoxLayout(tg)
        row = QHBoxLayout()
        self._thresh_slider = QSlider(Qt.Orientation.Horizontal)
        self._thresh_slider.setRange(0, 255)
        self._thresh_slider.setValue(self._threshold)
        self._thresh_slider.valueChanged.connect(self._on_threshold_changed)
        self._thresh_val_lbl = QLabel(str(self._threshold))
        self._thresh_val_lbl.setFixedWidth(28)
        row.addWidget(self._thresh_slider)
        row.addWidget(self._thresh_val_lbl)
        tl.addLayout(row)
        row2 = QHBoxLayout()
        auto_btn = QPushButton("Auto (Median)")
        auto_btn.clicked.connect(self._on_auto_threshold)
        self._invert_chk = QCheckBox("Invert  (dark shape on light background)")
        self._invert_chk.stateChanged.connect(self._on_invert_changed)
        row2.addWidget(auto_btn)
        row2.addWidget(self._invert_chk)
        tl.addLayout(row2)
        ctrl.addWidget(tg)

        # — Outline quality —
        og = QGroupBox("Outline quality")
        of = QFormLayout(og)

        self._epsilon_spin = QDoubleSpinBox()
        self._epsilon_spin.setRange(0.1, 50.0)
        self._epsilon_spin.setValue(2.0)
        self._epsilon_spin.setSingleStep(0.5)
        self._epsilon_spin.setToolTip(
            "Douglas-Peucker simplification.\n"
            "Higher = smoother, fewer points.")
        self._epsilon_spin.valueChanged.connect(lambda: self._refresh_preview(mesh=False))
        of.addRow("Simplify:", self._epsilon_spin)

        self._seg_len_spin = QDoubleSpinBox()
        self._seg_len_spin.setRange(1.0, 200.0)
        self._seg_len_spin.setValue(20.0)
        self._seg_len_spin.setSingleStep(1.0)
        self._seg_len_spin.setToolTip(
            "Maximum edge length after subdivision.\n"
            "Lower = more evenly-spaced vertices.")
        self._seg_len_spin.valueChanged.connect(lambda: self._refresh_preview(mesh=False))
        of.addRow("Segment len:", self._seg_len_spin)

        self._min_area_spin = QSpinBox()
        self._min_area_spin.setRange(10, 500000)
        self._min_area_spin.setValue(500)
        self._min_area_spin.setSuffix(" px²")
        self._min_area_spin.setToolTip("Ignore regions smaller than this.")
        self._min_area_spin.valueChanged.connect(lambda: self._refresh_preview(mesh=False))
        of.addRow("Min area:", self._min_area_spin)

        self._create_outline_btn = QPushButton("Create Outline Set")
        self._create_outline_btn.setEnabled(False)
        self._create_outline_btn.clicked.connect(self._on_create_outline)
        of.addRow(self._create_outline_btn)
        ctrl.addWidget(og)

        # — Quad Mesh —
        mg = QGroupBox("Quad Mesh")
        mf = QFormLayout(mg)

        self._mesh_mode_combo = QComboBox()
        self._mesh_mode_combo.addItems([
            "Grid  (conforms to boundary)",
            "Shell  (quad rings follow curvature)",
            "Tessellated  (triangle rings follow curvature)",
            "Convex Decomp  (shell rings per convex region)",
        ])
        self._mesh_mode_combo.currentIndexChanged.connect(self._on_mesh_mode_changed)
        mf.addRow("Mode:", self._mesh_mode_combo)

        self._grid_size_spin = QSpinBox()
        self._grid_size_spin.setRange(4, 500)
        self._grid_size_spin.setValue(20)
        self._grid_size_spin.setSuffix(" px")
        self._grid_size_spin.setToolTip(
            "Grid cell size in image pixels.\n"
            "Smaller = finer mesh, more quads.")
        self._grid_size_spin.valueChanged.connect(lambda: self._refresh_preview(mesh=True))
        mf.addRow("Grid size:", self._grid_size_spin)

        self._margin_spin = QSpinBox()
        self._margin_spin.setRange(0, 200)
        self._margin_spin.setValue(0)
        self._margin_spin.setSuffix(" px")
        self._margin_spin.setToolTip(
            "Inset the mesh from the shape boundary by this many pixels.\n"
            "0 = mesh cells clip exactly to the outline.\n"
            "Larger values pull the boundary inward.")
        self._margin_spin.valueChanged.connect(lambda: self._refresh_preview(mesh=True))
        mf.addRow("Margin:", self._margin_spin)

        hint = QLabel(
            "<small>After loading in Bezier:<br>"
            "Edit → <b>Weld All Adjacent</b> links shared edges.<br>"
            "Then RELATIONAL polygon mode to deform.</small>")
        hint.setTextFormat(Qt.TextFormat.RichText)
        hint.setWordWrap(True)
        mf.addRow(hint)

        mesh_btns = QHBoxLayout()
        self._prev_mesh_btn = QPushButton("Preview Mesh")
        self._prev_mesh_btn.setCheckable(True)
        self._prev_mesh_btn.toggled.connect(self._on_mesh_preview_toggled)
        self._create_mesh_btn = QPushButton("Create Mesh Set")
        self._create_mesh_btn.setEnabled(False)
        self._create_mesh_btn.clicked.connect(self._on_create_mesh)
        mesh_btns.addWidget(self._prev_mesh_btn)
        mesh_btns.addWidget(self._create_mesh_btn)
        mf.addRow(mesh_btns)
        ctrl.addWidget(mg)

        # — Name —
        ng = QGroupBox("Output name")
        nf = QFormLayout(ng)
        self._name_edit = QLineEdit()
        self._name_edit.setPlaceholderText("polygon set name")
        nf.addRow("Name:", self._name_edit)
        self._curved_chk = QCheckBox(
            "Curved edges  (Catmull-Rom smooth control points)")
        self._curved_chk.setToolTip(
            "When checked, each edge's Bézier control points follow the\n"
            "natural spline tangent at that vertex (Catmull-Rom style)\n"
            "instead of lying on the straight chord.")
        nf.addRow(self._curved_chk)
        ctrl.addWidget(ng)

    def _set_bin_label(self, mesh: bool):
        if mesh:
            mode = self._current_mesh_mode()
            if mode == 'shell':
                self._bin_lbl.setText(
                    "Shell mesh preview  "
                    "<span style='color:#00dcff'>━━</span>  quad rings follow shape curvature"
                )
            elif mode == 'tessellated':
                self._bin_lbl.setText(
                    "Tessellated mesh preview  "
                    "<span style='color:#00dcff'>━━</span>  triangle rings follow shape curvature"
                )
            elif mode == 'convex':
                self._bin_lbl.setText(
                    "Convex Decomp mesh preview  "
                    "<span style='color:#00dcff'>━━</span>  shell rings per convex sub-region"
                )
            else:
                self._bin_lbl.setText(
                    "Grid mesh preview  "
                    "<span style='color:#00dcff'>━━</span>  cells clip to boundary"
                )
        else:
            self._bin_lbl.setText(
                "Outline wireframe  "
                "<span style='color:#19ff2e'>━━</span>  green = polygon boundary"
            )

    def _current_mesh_mode(self) -> str:
        """Return 'grid', 'shell', 'tessellated', or 'convex'."""
        if not hasattr(self, '_mesh_mode_combo'):
            return 'grid'
        return ['grid', 'shell', 'tessellated', 'convex'][
            min(self._mesh_mode_combo.currentIndex(), 3)]

    def _on_mesh_mode_changed(self):
        if self._prev_mesh_btn.isChecked():
            self._set_bin_label(mesh=True)
            self._update_binary_preview()

    # ── image loading ─────────────────────────────────────────────────────────

    def _on_load(self):
        start = (self._background_image_dir
                 if os.path.isdir(self._background_image_dir)
                 else os.path.expanduser("~"))
        path, _ = QFileDialog.getOpenFileName(
            self, "Load Image", start,
            "Images (*.png *.jpg *.jpeg *.bmp *.tiff *.tif *.gif *.webp)")
        if path:
            self._load_image(path)

    def _load_image(self, path: str):
        img_bgr = cv2.imread(path)
        if img_bgr is None:
            QMessageBox.warning(self, "Load Error", f"Could not load:\n{path}")
            return
        self._rgb  = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
        self._grey = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
        self._path_lbl.setText(path)
        if not self._name_edit.text():
            self._name_edit.setText(os.path.splitext(os.path.basename(path))[0])
        self._on_auto_threshold()
        self._update_grey_preview()
        self._create_outline_btn.setEnabled(True)
        self._create_mesh_btn.setEnabled(True)

    def _update_grey_preview(self):
        if self._rgb is None:
            return
        h, w = self._rgb.shape[:2]
        img = QImage(self._rgb.data, w, h, w * 3,
                     QImage.Format.Format_RGB888).copy()
        self._grey_preview.set_pixmap(QPixmap.fromImage(img))

    # ── binary + overlay preview ──────────────────────────────────────────────

    def _refresh_preview(self, mesh: bool):
        """Refresh the binary preview in the specified mode."""
        # If the other mode's button is toggled, keep the toggle state consistent
        if mesh and not self._prev_mesh_btn.isChecked():
            return   # not in mesh preview mode; outline will already be shown
        if not mesh and self._prev_mesh_btn.isChecked():
            return   # in mesh preview mode; outline preview suppressed
        self._update_binary_preview()

    def _on_mesh_preview_toggled(self, checked: bool):
        self._set_bin_label(mesh=checked)
        self._update_binary_preview()

    def _update_binary_preview(self):
        if self._grey is None:
            return
        binary = self._make_binary()
        h, w = binary.shape

        rgb = cv2.cvtColor(binary, cv2.COLOR_GRAY2RGB)
        img = QImage(rgb.data, w, h, w * 3, QImage.Format.Format_RGB888).copy()
        pix = QPixmap.fromImage(img)

        painter = QPainter(pix)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        line_w = max(1, w // 400)

        if self._prev_mesh_btn.isChecked():
            # ── cyan mesh (grid / shell / tessellated) ────────────────────────
            mode = self._current_mesh_mode()
            if mode == 'tessellated':
                quads_px = self._compute_shell_mesh(binary, triangulate=True)
            elif mode == 'shell':
                quads_px = self._compute_shell_mesh(binary, triangulate=False)
            elif mode == 'convex':
                quads_px = self._compute_convex_decomp_mesh(binary)
            else:
                quads_px = self._compute_conforming_mesh(binary)
            if quads_px:
                painter.setPen(QPen(QColor(0, 220, 255), line_w))
                dot_r = max(1, w // 500)
                for quad in quads_px:
                    n = len(quad)
                    for i in range(n):
                        x1, y1 = quad[i]
                        x2, y2 = quad[(i + 1) % n]
                        painter.drawLine(int(x1), int(y1), int(x2), int(y2))
                    for x, y in quad:
                        painter.drawEllipse(int(x) - dot_r, int(y) - dot_r,
                                            dot_r * 2, dot_r * 2)
        else:
            # ── green outline wireframe ───────────────────────────────────────
            contours_px = self._compute_preview_contours(binary)
            if contours_px:
                painter.setPen(QPen(QColor(25, 255, 46), line_w))
                dot_r = max(2, w // 250)
                for poly in contours_px:
                    n = len(poly)
                    for i in range(n):
                        x1, y1 = poly[i]
                        x2, y2 = poly[(i + 1) % n]
                        painter.drawLine(int(round(x1)), int(round(y1)),
                                         int(round(x2)), int(round(y2)))
                    for x, y in poly:
                        painter.drawEllipse(int(round(x)) - dot_r,
                                            int(round(y)) - dot_r,
                                            dot_r * 2, dot_r * 2)

        painter.end()
        self._bin_preview.set_pixmap(pix)

    def _make_binary(self) -> np.ndarray:
        _, binary = cv2.threshold(
            self._grey, self._threshold, 255, cv2.THRESH_BINARY)
        if self._invert:
            binary = cv2.bitwise_not(binary)
        return binary

    # ── threshold controls ────────────────────────────────────────────────────

    def _on_threshold_changed(self, value: int):
        self._threshold = value
        self._thresh_val_lbl.setText(str(value))
        self._update_binary_preview()

    def _on_auto_threshold(self):
        if self._grey is None:
            return
        self._threshold = int(np.median(self._grey))
        self._thresh_slider.setValue(self._threshold)   # fires _on_threshold_changed

    def _on_invert_changed(self, state):
        self._invert = (state == Qt.CheckState.Checked.value
                        or state == Qt.CheckState.Checked)
        self._update_binary_preview()

    def _on_eyedropper(self, nx: float, ny: float):
        if self._grey is None:
            return
        h, w = self._grey.shape
        px = max(0, min(int(nx * w), w - 1))
        py = max(0, min(int(ny * h), h - 1))
        self._threshold = int(self._grey[py, px])
        self._thresh_slider.setValue(self._threshold)

    # ── outline contour computation ───────────────────────────────────────────

    def _compute_preview_contours(
            self, binary: np.ndarray) -> list[list[tuple[float, float]]]:
        """Traced + simplified contours in pixel space."""
        eps     = self._epsilon_spin.value()
        seg_len = self._seg_len_spin.value()
        min_area = self._min_area_spin.value()

        contours, _ = cv2.findContours(
            binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        result = []
        for cnt in contours:
            if cv2.contourArea(cnt) < min_area:
                continue
            approx = cv2.approxPolyDP(cnt, eps, True)
            pts = [(float(p[0][0]), float(p[0][1])) for p in approx]
            if len(pts) < 3:
                continue
            result.append(self._subdivide(pts, seg_len))
        return result

    def _trace_contours(self) -> list[list[tuple[float, float]]]:
        """Contours normalised to [-0.5, 0.5]."""
        binary = self._make_binary()
        h, w = binary.shape
        return [
            [((x / w) - 0.5, (y / h) - 0.5) for x, y in poly]
            for poly in self._compute_preview_contours(binary)
        ]

    # ── conforming mesh computation ───────────────────────────────────────────

    def _compute_conforming_mesh(
            self, binary: np.ndarray) -> list[list[tuple[float, float]]]:
        """
        Boundary-conforming mesh in pixel space.

        Interior cells  → exact rectangle quads (fast, correct for welding).
        Boundary cells  → per-cell contour clip against the binary mask, so the
                          outer edge of the mesh follows the shape outline exactly
                          rather than leaving a staircase of included/excluded cells.

        Adjacent interior cells share EXACT vertex coordinates (same arithmetic),
        so Bezier's 'Weld All Adjacent' registers zero-distance welds throughout
        the interior.  Boundary-cell edges likewise share the grid coordinates of
        their interior neighbours.
        """
        h, w = binary.shape
        grid = int(self._grid_size_spin.value())

        margin = int(self._margin_spin.value())
        mask = binary
        if margin > 0:
            k = 2 * margin + 1
            mask = cv2.erode(binary, np.ones((k, k), np.uint8), iterations=1)

        polys: list[list[tuple[float, float]]] = []

        for row in range(0, h, grid):
            for col in range(0, w, grid):
                r1 = row;          r2 = min(row + grid, h)
                c1 = col;          c2 = min(col + grid, w)
                if r2 <= r1 or c2 <= c1:
                    continue

                cell = mask[r1:r2, c1:c2]
                white = int(np.count_nonzero(cell))
                if white == 0:
                    continue

                total = (r2 - r1) * (c2 - c1)
                if white == total:
                    # Fully inside: exact rectangle quad
                    polys.append([(c1, r1), (c2, r1), (c2, r2), (c1, r2)])
                else:
                    # Boundary cell: clip to the actual shape
                    cnts, _ = cv2.findContours(
                        cell.copy(), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
                    if not cnts:
                        continue
                    cnt = max(cnts, key=cv2.contourArea)
                    if cv2.contourArea(cnt) < 4:
                        continue
                    peri = cv2.arcLength(cnt, True)
                    eps  = max(1.0, 0.03 * peri)
                    approx = cv2.approxPolyDP(cnt, eps, True)
                    pts = approx.reshape(-1, 2).astype(float)
                    if len(pts) < 3:
                        continue
                    pts[:, 0] += c1   # offset to global image coords
                    pts[:, 1] += r1
                    polys.append([tuple(p) for p in pts])

        return polys

    def _get_outer_contour_simple(
            self, binary: np.ndarray) -> list[tuple[float, float]]:
        """
        Simplified outer contour for mesh use.

        Uses a finer epsilon than the outline polygon (half the user's Simplify
        value, minimum 1.0 px).  Shorter chords are less likely to cross outside
        the mask at shallow concave features, so more zipper triangles pass the
        boundary validation.  The user's Simplify setting still controls the
        separate outline polygon quality.
        """
        eps      = max(1.0, self._epsilon_spin.value() / 2.0)
        min_area = self._min_area_spin.value()
        cnts, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        if not cnts:
            return []
        cnts = [c for c in cnts if cv2.contourArea(c) >= min_area]
        if not cnts:
            return []
        cnt    = max(cnts, key=cv2.contourArea)
        approx = cv2.approxPolyDP(cnt, eps, True)
        return [(float(p[0][0]), float(p[0][1])) for p in approx]

    def _compute_shell_mesh(
            self, binary: np.ndarray,
            triangulate: bool = False) -> list[list[tuple[float, float]]]:
        """
        Concentric shell mesh with accurate outer boundary.

        Shell 0  = simplified outer contour (approxPolyDP, epsilon from UI).
                   Its edges are at most epsilon px from the true boundary, so
                   they never create chord-crossing gaps.

        Shells 1+ = distance-transform level sets at multiples of spacing.
                   Each is resampled to a coarser vertex count.

        Ring 0→1  = zipper triangulation: advances along both rings by
                   arc-length fraction, always emitting the smallest triangle.
                   Produces N_outer + N_inner triangles; every outer-side edge
                   lies exactly on the contour.

        Rings 1→2, 2→3, ...  = standard same-vertex-count stitching (quads, or
                   triangle pairs when triangulate=True).

        Innermost shell = single polygon (or fan of triangles when triangulate).
        """
        h, w    = binary.shape
        spacing = max(4, int(self._grid_size_spin.value()))
        margin  = int(self._margin_spin.value())

        # Shell 0: actual contour, closely followed
        outer_fine = self._get_outer_contour_simple(binary)
        if len(outer_fine) < 3:
            return []

        dist = cv2.distanceTransform(binary, cv2.DIST_L2, cv2.DIST_MASK_PRECISE)

        # Inner shells: distance-transform level sets
        inner_shells: list[list[tuple[float, float]]] = []
        k = 1
        while True:
            threshold = margin + k * spacing
            mask = (dist >= threshold).astype(np.uint8) * 255
            cnts, _ = cv2.findContours(
                mask.copy(), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
            if not cnts:
                break
            cnt = max(cnts, key=cv2.contourArea)
            if cv2.contourArea(cnt) < spacing * spacing / 2:
                break
            peri    = cv2.arcLength(cnt, True)
            n_verts = max(4, round(peri / spacing))
            pts_raw = [(float(p[0]), float(p[1])) for p in cnt.reshape(-1, 2)]
            inner_shells.append(self._resample_poly(pts_raw, n_verts))
            k += 1

        all_shells = [outer_fine] + inner_shells

        if len(all_shells) == 1:
            return [outer_fine]   # shape too thin for any inner shell

        def _angular_dist(a: float, b: float) -> float:
            d = (a - b) % (2 * math.pi)
            return min(d, 2 * math.pi - d)

        def _arc_fracs(pts: list[tuple[float, float]]) -> list[float]:
            """Cumulative arc-length fractions [0 … 1] for a closed polygon."""
            closed = pts + [pts[0]]
            cum = [0.0]
            for i in range(len(closed) - 1):
                dx = closed[i+1][0] - closed[i][0]
                dy = closed[i+1][1] - closed[i][1]
                cum.append(cum[-1] + math.hypot(dx, dy))
            total = cum[-1]
            return ([c / total for c in cum] if total > 1e-6
                    else [i / len(pts) for i in range(len(pts) + 1)])

        def _align(outer: list, inner: list) -> list:
            """Rotate inner so inner[0] faces outer[0] from inner's centroid."""
            N = len(inner)
            cx = sum(p[0] for p in inner) / N
            cy = sum(p[1] for p in inner) / N
            tgt = math.atan2(outer[0][1] - cy, outer[0][0] - cx)
            angs = [math.atan2(inner[k][1] - cy, inner[k][0] - cx)
                    for k in range(N)]
            bk = min(range(N), key=lambda k: _angular_dist(angs[k], tgt))
            return inner[bk:] + inner[:bk]

        polys: list[list[tuple[float, float]]] = []

        # ── Ring 0: zipper triangulation (fine outer → first inner shell) ──
        # N_outer can be much larger than N_inner.  Zipper advances through
        # both rings by arc-length fraction, emitting a triangle at each step.
        # Outer-side edges lie on the contour → always inside the mask.
        outer  = all_shells[0]
        inner0 = _align(outer, all_shells[1])
        N_o    = len(outer)
        N_i    = len(inner0)
        fo     = _arc_fracs(outer)
        fi     = _arc_fracs(inner0)
        i = 0;  j = 0
        while i < N_o or j < N_i:
            t_o = fo[i + 1] if i < N_o else 2.0
            t_i = fi[j + 1] if j < N_i else 2.0
            if t_o <= t_i and i < N_o:
                polys.append([outer[i], outer[(i+1) % N_o], inner0[j % N_i]])
                i += 1
            else:
                polys.append([outer[i % N_o], inner0[(j+1) % N_i], inner0[j]])
                j += 1

        # ── Rings 1+: standard same-vertex-count stitching ─────────────────
        for ring in range(1, len(all_shells) - 1):
            out_r  = all_shells[ring]
            inn_s  = all_shells[ring + 1]
            N      = len(out_r)
            inn_r  = _align(out_r, self._resample_poly(inn_s, N))
            for j in range(N):
                a = out_r[j];          b = out_r[(j+1) % N]
                c = inn_r[(j+1) % N];  d = inn_r[j]
                if triangulate:
                    polys.append([a, b, d])
                    polys.append([b, c, d])
                else:
                    polys.append([a, b, c, d])

        # ── Innermost shell ─────────────────────────────────────────────────
        innermost = all_shells[-1]
        if triangulate and len(innermost) >= 3:
            n_in = len(innermost)
            cx   = sum(p[0] for p in innermost) / n_in
            cy   = sum(p[1] for p in innermost) / n_in
            for j in range(n_in):
                polys.append([(cx, cy), innermost[j], innermost[(j+1) % n_in]])
        else:
            polys.append(innermost)

        # ── Validation ──────────────────────────────────────────────────────
        # Outer-side edges of zipper triangles are on the contour and always
        # pass.  Radial edges (contour → inner shell) are checked here to catch
        # the rare case where a radial edge crosses a concave feature.
        def _inside(x: float, y: float) -> bool:
            xi, yi = int(round(x)), int(round(y))
            return 0 <= yi < h and 0 <= xi < w and binary[yi, xi] > 0

        def _poly_ok(poly: list[tuple[float, float]]) -> bool:
            n = len(poly)
            for idx in range(n):
                x1, y1 = poly[idx];  x2, y2 = poly[(idx+1) % n]
                if not _inside(x1, y1):                              return False
                if not _inside((x1+x2)*0.5,   (y1+y2)*0.5):        return False
                if not _inside(x1*0.75+x2*0.25, y1*0.75+y2*0.25):  return False
                if not _inside(x1*0.25+x2*0.75, y1*0.25+y2*0.75):  return False
            return True

        return [p for p in polys if _poly_ok(p)]

    def _build_contour_caps(
            self,
            raw_outer: list[tuple[float, float]],
            resampled_outer: list[tuple[float, float]],
    ) -> list[list[tuple[float, float]]]:
        """
        Fill the wedge gaps between the coarsely-resampled outer ring and the
        actual contour.

        For each edge outer[j] → outer[j+1] of the resampled ring:
          1. Find the arc of raw_outer that lies between those two arc positions.
          2. Simplify the arc with the same epsilon as the outline quality setting.
          3. Build a cap polygon:  [outer[j]]  +  arc_interior  +  [outer[j+1]]

        These caps are thin fan-shaped polygons that hug the contour.  They are
        run through the same validation as the shell quads, so caps whose chord
        crosses a deeply concave feature are silently discarded (the same coarse
        spacing that created the gap means the chord itself exits the mask).
        For convex bumps and shallow concavities — the common case — the caps
        recover the missing silhouette area completely.
        """
        N = len(resampled_outer)
        raw_n = len(raw_outer)
        if N == 0 or raw_n < 3:
            return []

        # Arc-length parameterisation of the closed raw contour
        closed_raw = raw_outer + [raw_outer[0]]
        cuml: list[float] = [0.0]
        for i in range(len(closed_raw) - 1):
            dx = closed_raw[i + 1][0] - closed_raw[i][0]
            dy = closed_raw[i + 1][1] - closed_raw[i][1]
            cuml.append(cuml[-1] + math.hypot(dx, dy))
        total = cuml[-1]
        if total < 1e-6:
            return []

        eps = max(1.0, self._epsilon_spin.value())
        caps: list[list[tuple[float, float]]] = []

        for j in range(N):
            t0 = total * j / N
            t1 = total * (j + 1) / N

            # Raw pixels whose arc position falls strictly between t0 and t1
            arc_interior = [raw_outer[k] for k in range(raw_n)
                            if t0 < cuml[k] < t1]

            if not arc_interior:
                continue   # chord already touches the contour — no gap

            # Simplify the arc so caps don't have huge vertex counts
            if len(arc_interior) > 3:
                arc_arr = np.array(arc_interior, dtype=np.float32).reshape(-1, 1, 2)
                approx = cv2.approxPolyDP(arc_arr, eps, False)
                arc_interior = [(float(p[0][0]), float(p[0][1])) for p in approx]

            if not arc_interior:
                continue

            cap = ([resampled_outer[j]]
                   + arc_interior
                   + [resampled_outer[(j + 1) % N]])
            if len(cap) >= 3:
                caps.append(cap)

        return caps

    @staticmethod
    def _resample_poly(
            pts: list[tuple[float, float]], n: int) -> list[tuple[float, float]]:
        """Resample a closed polygon to exactly n evenly-spaced points by arc length."""
        if n <= 0 or not pts:
            return list(pts)
        closed = list(pts) + [pts[0]]
        cuml = [0.0]
        for i in range(len(closed) - 1):
            dx = closed[i + 1][0] - closed[i][0]
            dy = closed[i + 1][1] - closed[i][1]
            cuml.append(cuml[-1] + math.hypot(dx, dy))
        total = cuml[-1]
        if total < 1e-6:
            return [pts[0]] * n
        result = []
        for k in range(n):
            target = total * k / n
            idx = bisect.bisect_right(cuml, target) - 1
            idx = min(max(idx, 0), len(closed) - 2)
            seg = cuml[idx + 1] - cuml[idx]
            t   = (target - cuml[idx]) / seg if seg > 1e-9 else 0.0
            x   = closed[idx][0] + t * (closed[idx + 1][0] - closed[idx][0])
            y   = closed[idx][1] + t * (closed[idx + 1][1] - closed[idx][1])
            result.append((x, y))
        return result

    # ── convex decomposition mesh ─────────────────────────────────────────────

    @staticmethod
    def _poly_signed_area(pts: list[tuple[float, float]]) -> float:
        """Shoelace signed area.  Positive = CW winding in image coords (y-down)."""
        n = len(pts)
        s = 0.0
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            s += x0 * y1 - x1 * y0
        return s * 0.5

    @staticmethod
    def _cross_at_vertex(pts: list, i: int) -> float:
        """Signed cross product of (prev→cur) × (prev→next) at vertex i."""
        n = len(pts)
        ax, ay = pts[(i - 1) % n]
        bx, by = pts[i]
        cx, cy = pts[(i + 1) % n]
        return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)

    @staticmethod
    def _segs_strictly_cross(
            p1: tuple, p2: tuple,
            p3: tuple, p4: tuple) -> bool:
        """True if p1-p2 and p3-p4 intersect at strictly interior points."""
        def _c(o, a, b):
            return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
        return _c(p3, p4, p1) * _c(p3, p4, p2) < 0 and \
               _c(p1, p2, p3) * _c(p1, p2, p4) < 0

    def _diagonal_valid(
            self,
            pts: list[tuple[float, float]],
            i: int, j: int) -> bool:
        """True if the diagonal pts[i]→pts[j] lies fully inside the polygon."""
        n   = len(pts)
        a, b = pts[i], pts[j]
        # Midpoint must be interior
        mx, my = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
        pa = np.array(pts, dtype=np.float32).reshape(-1, 1, 2)
        if cv2.pointPolygonTest(pa, (float(mx), float(my)), False) < 0:
            return False
        # Must not cross any non-adjacent edge
        for k in range(n):
            k1 = (k + 1) % n
            if k in (i, j) or k1 in (i, j):
                continue
            if self._segs_strictly_cross(a, b, pts[k], pts[k1]):
                return False
        return True

    def _convex_decomp(
            self,
            pts: list[tuple[float, float]],
            depth: int = 0,
    ) -> list[list[tuple[float, float]]]:
        """
        Approximate convex decomposition by iterative diagonal cutting.

        For each reflex vertex (interior angle > 180°) a valid diagonal is
        found and the polygon is split into two sub-polygons.  Each sub-polygon
        is recursively processed.  Produces at most O(r) pieces for r reflex
        vertices.
        """
        if depth > 40 or len(pts) < 3:
            return [list(pts)] if len(pts) >= 3 else []

        n = len(pts)
        # Normalise to positive (CW in image coords) winding
        if self._poly_signed_area(pts) < 0:
            pts = list(reversed(pts))

        # Reflex vertices: cross product < 0 for CW polygon in image coords
        reflex = [i for i in range(n)
                  if self._cross_at_vertex(pts, i) < -1e-3]
        if not reflex:
            return [list(pts)]

        for ri in reflex:
            # All non-adjacent vertices, sorted closest-first
            candidates = sorted(
                (j for j in range(n)
                 if j != ri
                 and j != (ri - 1) % n
                 and j != (ri + 1) % n
                 and self._diagonal_valid(pts, ri, j)),
                key=lambda j: math.hypot(pts[ri][0] - pts[j][0],
                                         pts[ri][1] - pts[j][1]),
            )
            if not candidates:
                continue
            j = candidates[0]
            if ri > j:
                ri, j = j, ri
            poly1 = pts[ri: j + 1]
            poly2 = pts[j:] + pts[: ri + 1]
            return (self._convex_decomp(poly1, depth + 1) +
                    self._convex_decomp(poly2, depth + 1))

        return [list(pts)]   # no valid diagonal found; treat as convex

    @staticmethod
    def _inset_poly(
            pts: list[tuple[float, float]],
            offset: float,
    ) -> list[tuple[float, float]] | None:
        """
        Inset a convex polygon inward by `offset` pixels.

        For a CW polygon in image coords (positive shoelace area) the inward
        unit normal of each edge is the 90° CCW rotation of the edge direction.
        Consecutive offset lines are intersected to find the new vertices.
        Returns None when the inset degenerates (too small or didn't shrink).
        """
        # Normalise to CW (positive area)
        if BitmapPolygonDialog._poly_signed_area(pts) < 0:
            pts = list(reversed(pts))

        n = len(pts)
        pts_np = [np.array(p, dtype=float) for p in pts]

        # Offset lines: (point_on_line, unit_direction)
        lines: list[tuple[np.ndarray, np.ndarray]] = []
        for i in range(n):
            a = pts_np[i]
            b = pts_np[(i + 1) % n]
            d = b - a
            L = float(np.linalg.norm(d))
            if L < 1e-9:
                continue
            d /= L
            # 90° CCW rotation = inward normal for CW polygon in image coords
            n_in = np.array([-d[1], d[0]])
            lines.append((a + offset * n_in, d))

        if len(lines) < 3:
            return None

        m = len(lines)
        new_pts: list[tuple[float, float]] = []
        for i in range(m):
            p1, d1 = lines[i]
            p2, d2 = lines[(i + 1) % m]
            denom = float(d1[0] * d2[1] - d1[1] * d2[0])
            if abs(denom) < 1e-9:
                # Parallel edges – average the offset anchor points
                new_pts.append(tuple(float(v) for v in (p1 + p2) * 0.5))
            else:
                dp = p2 - p1
                t  = float(dp[0] * d2[1] - dp[1] * d2[0]) / denom
                pt = p1 + t * d1
                new_pts.append((float(pt[0]), float(pt[1])))

        if len(new_pts) < 3:
            return None

        orig_area = abs(BitmapPolygonDialog._poly_signed_area(pts))
        new_area  = abs(BitmapPolygonDialog._poly_signed_area(new_pts))
        if new_area < 4.0 or new_area >= orig_area * 0.98:
            return None   # degenerate or didn't shrink meaningfully

        return new_pts

    def _shell_rings_for_region(
            self,
            pts: list[tuple[float, float]],
            spacing: float,
    ) -> list[list[tuple[float, float]]]:
        """Build concentric inset rings for a convex polygon, outermost first."""
        rings = [list(pts)]
        current = list(pts)
        for _ in range(80):   # safety cap
            inset = self._inset_poly(current, spacing)
            if inset is None:
                break
            rings.append(inset)
            current = inset
        return rings

    def _compute_convex_decomp_mesh(
            self,
            binary: np.ndarray,
    ) -> list[list[tuple[float, float]]]:
        """
        Convex-decomposition shell mesh.

        Pipeline:
          1. Trace and simplify the outer contour.
          2. Decompose it into convex sub-polygons (diagonal cutting).
          3. For each convex piece build concentric rings via polygon inset.
          4. Stitch adjacent rings as quads; append innermost as a polygon.

        Because each sub-region is convex, inset vertex i directly corresponds
        to outer vertex i — no zipper triangulation or validation needed.
        """
        outer = self._get_outer_contour_simple(binary)
        if len(outer) < 3:
            return []

        spacing = float(max(4, int(self._grid_size_spin.value())))
        pieces  = self._convex_decomp(list(outer))
        polys: list[list[tuple[float, float]]] = []

        for piece in pieces:
            if len(piece) < 3:
                continue

            rings = self._shell_rings_for_region(piece, spacing)

            if len(rings) == 1:
                polys.append(rings[0])
                continue

            for r_idx in range(len(rings) - 1):
                out_r = rings[r_idx]
                inn_r = rings[r_idx + 1]
                N     = len(out_r)

                # Direct vertex correspondence when inset preserves count.
                # Fall back to resample + angular align if a degenerate edge
                # caused the inset to drop a vertex.
                if len(inn_r) != N:
                    inn_r = self._resample_poly(inn_r, N)
                    cx = sum(p[0] for p in inn_r) / N
                    cy = sum(p[1] for p in inn_r) / N
                    tgt  = math.atan2(out_r[0][1] - cy, out_r[0][0] - cx)
                    angs = [math.atan2(inn_r[k][1] - cy, inn_r[k][0] - cx)
                            for k in range(N)]
                    def _ad(a, b):
                        d = (a - b) % (2 * math.pi)
                        return min(d, 2 * math.pi - d)
                    bk    = min(range(N), key=lambda k: _ad(angs[k], tgt))
                    inn_r = inn_r[bk:] + inn_r[:bk]

                for j in range(N):
                    a = out_r[j]
                    b = out_r[(j + 1) % N]
                    c = inn_r[(j + 1) % N]
                    d = inn_r[j]
                    polys.append([a, b, c, d])

            polys.append(rings[-1])

        return polys

    def _generate_quad_mesh(self) -> list[list[tuple[float, float]]]:
        """Mesh normalised to [-0.5, 0.5]."""
        binary = self._make_binary()
        h, w   = binary.shape
        mode   = self._current_mesh_mode()
        if mode == 'tessellated':
            px_polys = self._compute_shell_mesh(binary, triangulate=True)
        elif mode == 'shell':
            px_polys = self._compute_shell_mesh(binary, triangulate=False)
        elif mode == 'convex':
            px_polys = self._compute_convex_decomp_mesh(binary)
        else:
            px_polys = self._compute_conforming_mesh(binary)
        return [
            [((x / w) - 0.5, (y / h) - 0.5) for x, y in poly]
            for poly in px_polys
        ]

    # ── subdivision helper (shared by outline + mesh) ─────────────────────────

    @staticmethod
    def _subdivide(pts: list[tuple[float, float]],
                   seg_len: float) -> list[tuple[float, float]]:
        """Insert extra points so no edge exceeds seg_len, keeping vertices."""
        result = []
        n = len(pts)
        for i in range(n):
            a = pts[i]
            b = pts[(i + 1) % n]
            result.append(a)
            dx = b[0] - a[0]; dy = b[1] - a[1]
            d = math.hypot(dx, dy)
            if d > seg_len:
                steps = int(math.ceil(d / seg_len))
                for s in range(1, steps):
                    t = s / steps
                    result.append((a[0] + dx * t, a[1] + dy * t))
        return result

    # ── create actions ────────────────────────────────────────────────────────

    def _on_create_outline(self):
        if self._grey is None:
            return
        name = self._name_edit.text().strip()
        if not name:
            QMessageBox.warning(self, "Missing Name", "Enter a name first.")
            return
        try:
            polys = self._trace_contours()
        except Exception as e:
            QMessageBox.critical(self, "Trace Error", str(e)); return
        if not polys:
            QMessageBox.warning(self, "No Polygons",
                                "No regions found. Adjust threshold or tick Invert.")
            return
        out_path = os.path.join(self._polygon_sets_dir, f"{name}.xml")
        if not self._confirm_overwrite(out_path):
            return
        try:
            self._write_xml(out_path, name, polys,
                            curved=self._curved_chk.isChecked())
        except Exception as e:
            QMessageBox.critical(self, "Write Error", str(e)); return
        QMessageBox.information(self, "Done",
                                f"Created {len(polys)} polygon(s):\n{out_path}")
        self.accept()

    def _on_create_mesh(self):
        if self._grey is None:
            return
        name = self._name_edit.text().strip()
        if not name:
            QMessageBox.warning(self, "Missing Name", "Enter a name first.")
            return
        try:
            quads = self._generate_quad_mesh()
        except Exception as e:
            QMessageBox.critical(self, "Mesh Error", str(e)); return
        if not quads:
            QMessageBox.warning(self, "No Quads",
                                "No cells inside the mask. Try reducing Grid size or Margin.")
            return
        mesh_name = f"{name}_mesh"
        out_path = os.path.join(self._polygon_sets_dir, f"{mesh_name}.xml")
        if not self._confirm_overwrite(out_path):
            return
        try:
            self._write_xml(out_path, mesh_name, quads,
                            curved=self._curved_chk.isChecked())
        except Exception as e:
            QMessageBox.critical(self, "Write Error", str(e)); return
        mode_label = ("shell rings" if self._current_mesh_mode() == 'shell'
                      else "grid cells")
        QMessageBox.information(
            self, "Done",
            f"Created {len(quads)} polygons ({mode_label}) → {out_path}\n\n"
            f"In Bezier: Edit → Weld All Adjacent, then use\n"
            f"RELATIONAL polygon mode to deform the mesh.")
        self.accept()

    def _confirm_overwrite(self, path: str) -> bool:
        if not os.path.exists(path):
            return True
        os.makedirs(os.path.dirname(path), exist_ok=True)
        reply = QMessageBox.question(
            self, "Overwrite?",
            f"'{os.path.basename(path)}' already exists. Overwrite?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        return reply == QMessageBox.StandardButton.Yes

    # ── XML writer ────────────────────────────────────────────────────────────

    def _write_xml(self, path: str, name: str,
                   polys: list[list[tuple[float, float]]],
                   curved: bool = False):
        """
        Write a polygonSet XML.

        curved=False  Each edge A→B is a straight cubic Bézier (C1 and C2
                      lie on the chord at ⅓ and ⅔).
        curved=True   Catmull-Rom style: C1 and C2 follow the tangent at each
                      vertex (direction from the previous to the next vertex),
                      giving naturally smooth curves that hug the contour or
                      ring shape.
        Subtract 0.02 from every coordinate (reader adds it back).
        """
        ADJUST = 0.02

        def fmt(v: float) -> str:
            return f"{v:.2f}"

        def _catmull_tangent(adj: list[tuple[float, float]], i: int):
            """Unit tangent at vertex i using Catmull-Rom formula."""
            n   = len(adj)
            px, py = adj[(i - 1) % n]
            nx, ny = adj[(i + 1) % n]
            tx, ty = nx - px, ny - py
            L = math.hypot(tx, ty)
            return (tx / L, ty / L) if L > 1e-9 else (1.0, 0.0)

        root_el = ET.Element("polygonSet", name=name)
        for poly in polys:
            poly_el = ET.SubElement(root_el, "polygon",
                                    closed="true", isClosed="true")
            n = len(poly)
            # Pre-adjust coordinates once; pre-compute tangents for curved mode
            adj = [(x - ADJUST, y - ADJUST) for x, y in poly]
            tangents = ([_catmull_tangent(adj, i) for i in range(n)]
                        if curved else None)

            for i in range(n):
                ax, ay = adj[i]
                bx, by = adj[(i + 1) % n]

                if curved and tangents is not None:
                    seg = math.hypot(bx - ax, by - ay)
                    tx_a, ty_a = tangents[i]
                    tx_b, ty_b = tangents[(i + 1) % n]
                    c1x = ax + (seg / 3.0) * tx_a
                    c1y = ay + (seg / 3.0) * ty_a
                    c2x = bx - (seg / 3.0) * tx_b
                    c2y = by - (seg / 3.0) * ty_b
                else:
                    c1x = ax + (bx - ax) / 3.0
                    c1y = ay + (by - ay) / 3.0
                    c2x = ax + 2.0 * (bx - ax) / 3.0
                    c2y = ay + 2.0 * (by - ay) / 3.0

                curve_el = ET.SubElement(poly_el, "curve")
                ET.SubElement(curve_el, "point", x=fmt(ax),  y=fmt(ay))
                ET.SubElement(curve_el, "point", x=fmt(c1x), y=fmt(c1y))
                ET.SubElement(curve_el, "point", x=fmt(c2x), y=fmt(c2y))
                ET.SubElement(curve_el, "point", x=fmt(bx),  y=fmt(by))

        ET.indent(root_el, space="  ")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
            f.write('<!DOCTYPE polygonSet SYSTEM "polygonSet.dtd">\n')
            ET.ElementTree(root_el).write(f, encoding="unicode",
                                          xml_declaration=False)
            f.write("\n")
