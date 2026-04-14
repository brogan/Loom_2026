"""
ToolbarPanel — horizontal toolbar with drawing mode buttons.
Mirrors Java BezierToolBarPanel.
"""
from __future__ import annotations
import os
from PySide6.QtWidgets import (
    QWidget, QHBoxLayout, QVBoxLayout, QPushButton,
    QFrame, QSlider, QLabel, QSizePolicy,
)
from PySide6.QtGui import QIcon, QPixmap, QPalette, QColor
from PySide6.QtCore import QSize, Qt

# Icons live in the sibling Java project's resources directory
_ICON_DIR = os.path.normpath(
    os.path.join(os.path.dirname(__file__), '..', '..', 'bezier', 'resources', 'images')
)
_ICON_SIZE = QSize(32, 32)   # ~33% larger than previous 24×24
_BTN_SIZE  = 40              # square button side (40×40)

# Light-background stylesheet that works in both light and dark macOS mode.
# The explicit colours ensure icons (which use dark pixels) are always visible.
_TOOLBAR_STYLE = """
ToolbarPanel {
    background-color: #D8D8D8;
}
QPushButton {
    background-color: #E8E8E8;
    border: 1px solid #AAAAAA;
    border-radius: 4px;
    padding: 0px;
}
QPushButton:checked {
    background-color: #8CC28C;
    border: 1px solid #4A8A4A;
}
QPushButton[btnGroup="sel"]:checked {
    background-color: rgb(255, 149, 58);
    border: 1px solid rgb(200, 110, 30);
}
QPushButton[btnGroup="create"]:checked {
    background-color: rgb(25, 255, 46);
    border: 1px solid rgb(15, 200, 35);
}
QPushButton:pressed {
    background-color: #B0C8B0;
}
QPushButton:hover {
    background-color: #F2F2F2;
    border: 1px solid #888888;
}
"""


def _icon(name: str) -> QIcon:
    path = os.path.join(_ICON_DIR, f"{name}.png")
    return QIcon(path)


def _toggle_icon(name: str) -> QIcon:
    icon = QIcon()
    off_path = os.path.join(_ICON_DIR, f"{name}.png")
    on_path  = os.path.join(_ICON_DIR, f"{name}_selected.png")
    icon.addPixmap(QPixmap(off_path), QIcon.Mode.Normal, QIcon.State.Off)
    icon.addPixmap(QPixmap(on_path),  QIcon.Mode.Normal, QIcon.State.On)
    return icon


def _btn(icon_name: str, tip: str, checkable: bool = False,
         toggle: bool = False) -> QPushButton:
    b = QPushButton()
    b.setIcon(_toggle_icon(icon_name) if toggle else _icon(icon_name))
    b.setIconSize(_ICON_SIZE)
    b.setFixedSize(_BTN_SIZE, _BTN_SIZE)
    b.setToolTip(tip)
    b.setCheckable(checkable)
    return b


def _group(*buttons, spacing: int = 3) -> QFrame:
    """Wrap buttons in a visible-bordered QFrame group."""
    frame = QFrame()
    frame.setFrameShape(QFrame.Shape.Box)
    frame.setFrameShadow(QFrame.Shadow.Raised)
    frame.setLineWidth(1)
    layout = QHBoxLayout(frame)
    layout.setContentsMargins(4, 2, 4, 2)
    layout.setSpacing(spacing)
    for w in buttons:
        if isinstance(w, QWidget):
            layout.addWidget(w)
        else:
            layout.addWidget(w)
    return frame


def _group_with_extras(widgets, spacing: int = 3) -> QFrame:
    """Wrap a list of QWidget/QLayout items in a visible-bordered QFrame group."""
    frame = QFrame()
    frame.setFrameShape(QFrame.Shape.Box)
    frame.setFrameShadow(QFrame.Shadow.Raised)
    frame.setLineWidth(1)
    layout = QHBoxLayout(frame)
    layout.setContentsMargins(4, 2, 4, 2)
    layout.setSpacing(spacing)
    for w in widgets:
        layout.addWidget(w)
    return frame


class ToolbarPanel(QWidget):

    def __init__(self, bezier_widget, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._bw = bezier_widget
        self.setAutoFillBackground(True)
        self._setup_ui()
        self._bw.mode_changed.connect(self._sync_buttons)

    def _setup_ui(self) -> None:
        layout = QHBoxLayout(self)
        layout.setContentsMargins(6, 3, 6, 3)
        layout.setSpacing(6)

        # ── 1. Selection modes (a s d f) + mesh build (⌃A) ──────────────────
        self._btn_sel_point = _btn("selectPoint",   "Point Selection (a)",         checkable=True, toggle=True)
        self._btn_sel_edge  = _btn("selectEdge",    "Edge Selection (s)",          checkable=True, toggle=True)
        self._btn_sel_open  = _btn("curve",         "Open Curve Selection (d)",    checkable=True, toggle=True)
        self._btn_sel_poly  = _btn("selectPolygon", "Polygon Selection (f)",       checkable=True, toggle=True)
        # Mesh build mode: hover points → 'p' to commit polygon faces (⌃A)
        self._btn_mesh_build = QPushButton("Mesh")
        self._btn_mesh_build.setFixedSize(_BTN_SIZE, _BTN_SIZE)
        self._btn_mesh_build.setToolTip(
            "Mesh Build Mode — hover over points to sequence them,\n"
            "'p' to commit polygon face, Backspace to undo last,\n"
            "Space to clear sequence  (⌃A)"
        )
        self._btn_mesh_build.setCheckable(True)
        for _b in (self._btn_sel_point, self._btn_sel_edge, self._btn_sel_open,
                   self._btn_sel_poly, self._btn_mesh_build):
            _b.setProperty("btnGroup", "sel")

        self._btn_sel_point.toggled.connect(self._on_point_sel_toggled)
        self._btn_sel_edge.toggled.connect(self._on_edge_sel_toggled)
        self._btn_sel_open.toggled.connect(self._on_open_sel_toggled)
        self._btn_sel_poly.toggled.connect(self._on_poly_sel_toggled)
        self._btn_mesh_build.toggled.connect(self._on_mesh_build_toggled)

        layout.addWidget(_group(self._btn_sel_point, self._btn_sel_edge,
                                self._btn_sel_open, self._btn_sel_poly,
                                self._btn_mesh_build))

        # ── 2. Creation modes (h j k l) ──────────────────────────────────────
        self._btn_point     = _btn("createPoint",   "Point Mode (h)",                 checkable=True, toggle=True)
        self._btn_oval      = _btn("oval",          "Oval Mode — click+drag to create (j)", checkable=True, toggle=True)
        self._btn_draw_poly = _btn("createPolygon", "Drawing Mode — clear all modes (k)", checkable=True, toggle=True)
        self._btn_freehand  = _btn("draw",          "Freehand Draw Mode (l)",         checkable=True, toggle=True)
        for _b in (self._btn_point, self._btn_oval, self._btn_draw_poly, self._btn_freehand):
            _b.setProperty("btnGroup", "create")

        self._btn_point.toggled.connect(self._on_point_mode_toggled)
        self._btn_oval.toggled.connect(self._on_oval_mode_toggled)
        self._btn_draw_poly.toggled.connect(self._on_drawing_mode_toggled)
        self._btn_freehand.toggled.connect(self._on_freehand_toggled)

        layout.addWidget(_group(self._btn_point, self._btn_oval,
                                self._btn_draw_poly, self._btn_freehand))

        # ── 3. Detail slider (for freehand) ───────────────────────────────────
        lbl_detail = QLabel("Detail:")
        self._detail_slider = QSlider(Qt.Orientation.Horizontal)
        self._detail_slider.setRange(1, 50)
        self._detail_slider.setValue(10)
        self._detail_slider.setFixedWidth(70)
        self._detail_slider.setToolTip("Freehand detail (1=loose, 50=tight)")
        self._detail_slider.valueChanged.connect(
            lambda v: self._bw.set_freehand_error_threshold(51.0 - v)
        )
        layout.addWidget(_group_with_extras([lbl_detail, self._detail_slider]))

        # ── 4. Finalise buttons ───────────────────────────────────────────────
        btn_finish = _btn("closePolygon", "Close / Finish Polygon (⌘F)")
        btn_open   = _btn("OpenCurve",   "Finish Open Curve")
        btn_finish.clicked.connect(self._bw.finish_curve)
        btn_open.clicked.connect(self._bw.finish_open_curve)
        layout.addWidget(_group(btn_finish, btn_open))

        # ── 5. Weld ───────────────────────────────────────────────────────────
        # Weld button is a toggle: checked = auto-weld on drag enabled (default on).
        # In edge mode with 2 weldable edges selected it acts as a one-shot manual
        # weld button (Java behaviour: reverts toggle state so auto-weld stays on).
        self._btn_weld = _btn("weld", "Auto-weld on drag (toggle); click with 2 edges to weld manually",
                              checkable=True, toggle=True)
        self._btn_weld.setChecked(True)          # auto-weld on by default
        btn_weld_all = _btn("weldAll", "Weld All Adjacent Edges (threshold 5px)")
        self._btn_weld.clicked.connect(self._on_weld_clicked)
        btn_weld_all.clicked.connect(lambda: self._bw.weld_all_adjacent(5.0))
        layout.addWidget(_group(self._btn_weld, btn_weld_all))

        # ── 6. Duplicate / Knife / Intersect ─────────────────────────────────
        btn_dup       = _btn("duplicatePolygon", "Duplicate Selected")
        self._btn_knife = _btn("knife", "Knife Tool — drag to cut (k*)", checkable=True, toggle=True)
        btn_intersect = _btn("Intersect", "Intersect Selected Polygons")

        btn_dup.clicked.connect(self._bw.duplicate_selected)
        self._btn_knife.toggled.connect(self._on_knife_toggled)
        btn_intersect.clicked.connect(self._bw.perform_intersect)

        layout.addWidget(_group(btn_dup, self._btn_knife, btn_intersect))

        # ── 7. Flip ───────────────────────────────────────────────────────────
        btn_flip_h = _btn("flipHorizontal", "Flip Horizontal")
        btn_flip_v = _btn("flipVertical",   "Flip Vertical")
        btn_flip_h.clicked.connect(lambda: self._bw.perform_flip(True))
        btn_flip_v.clicked.connect(lambda: self._bw.perform_flip(False))
        layout.addWidget(_group(btn_flip_h, btn_flip_v))

        # ── 8. Snap + Centre ─────────────────────────────────────────────────
        btn_snap_anchors = _btn("snapAnchors",         "Snap Anchors to Grid")
        btn_snap_all     = _btn("snapAnchorsControls", "Snap Anchors + Reset Control Points")
        btn_centre       = _btn("center",              "Centre Selected Polygons")
        btn_snap_anchors.clicked.connect(lambda: self._bw.snap_to_grid(False))
        btn_snap_all.clicked.connect(lambda: self._bw.snap_to_grid(True))
        btn_centre.clicked.connect(self._bw.perform_centre)
        layout.addWidget(_group(btn_snap_anchors, btn_snap_all, btn_centre))

        # ── 9. Zoom ───────────────────────────────────────────────────────────
        btn_zoom_in  = _btn("zoomIn",  "Zoom In")
        btn_zoom_out = _btn("zoomOut", "Zoom Out")
        btn_zoom_in.clicked.connect(self._bw.zoom_in)
        btn_zoom_out.clicked.connect(self._bw.zoom_out)
        layout.addWidget(_group(btn_zoom_in, btn_zoom_out))

        # ── 10. View toggles: Grid / Control Points ───────────────────────────
        self._btn_grid = _btn("hideGrid",          "Toggle Grid Display",   checkable=True, toggle=True)
        self._btn_cp   = _btn("hideControlPoints", "Toggle Control Points", checkable=True, toggle=True)
        self._btn_grid.toggled.connect(self._on_grid_toggled)
        self._btn_cp.toggled.connect(self._on_cp_toggled)
        layout.addWidget(_group(self._btn_grid, self._btn_cp))

        # ── 11. Clear / Erase ─────────────────────────────────────────────────
        btn_clear = _btn("clearGeometry",        "Clear All Geometry")
        btn_erase = _btn("eraseSelectedPolygons","Delete Selected Shapes")
        btn_clear.clicked.connect(self._bw.clear_grid)
        btn_erase.clicked.connect(self._bw.delete_selected)
        layout.addWidget(_group(btn_clear, btn_erase))

        layout.addStretch()
        # Apply stylesheet after all buttons have their properties set
        self.setStyleSheet(_TOOLBAR_STYLE)

    # ── mode toggle handlers ──────────────────────────────────────────────────

    def _on_point_sel_toggled(self, checked: bool) -> None:
        if checked:
            self._btn_sel_edge.setChecked(False)
            self._btn_sel_open.setChecked(False)
            self._btn_sel_poly.setChecked(False)
            self._btn_mesh_build.setChecked(False)
            self._btn_point.setChecked(False)
            self._btn_oval.setChecked(False)
            self._btn_freehand.setChecked(False)
            self._btn_knife.setChecked(False)
            self._btn_draw_poly.setChecked(False)
        self._bw.set_point_selection_mode(checked)

    def _on_edge_sel_toggled(self, checked: bool) -> None:
        if checked:
            self._btn_sel_point.setChecked(False)
            self._btn_sel_open.setChecked(False)
            self._btn_sel_poly.setChecked(False)
            self._btn_mesh_build.setChecked(False)
            self._btn_point.setChecked(False)
            self._btn_oval.setChecked(False)
            self._btn_freehand.setChecked(False)
            self._btn_knife.setChecked(False)
            self._btn_draw_poly.setChecked(False)
        self._bw.set_edge_selection_mode(checked)

    def _on_open_sel_toggled(self, checked: bool) -> None:
        if checked:
            self._btn_sel_point.setChecked(False)
            self._btn_sel_edge.setChecked(False)
            self._btn_sel_poly.setChecked(False)
            self._btn_mesh_build.setChecked(False)
            self._btn_point.setChecked(False)
            self._btn_oval.setChecked(False)
            self._btn_freehand.setChecked(False)
            self._btn_knife.setChecked(False)
            self._btn_draw_poly.setChecked(False)
        self._bw.set_open_curve_selection_mode(checked)

    def _on_poly_sel_toggled(self, checked: bool) -> None:
        if checked:
            self._btn_sel_point.setChecked(False)
            self._btn_sel_edge.setChecked(False)
            self._btn_sel_open.setChecked(False)
            self._btn_mesh_build.setChecked(False)
            self._btn_point.setChecked(False)
            self._btn_oval.setChecked(False)
            self._btn_freehand.setChecked(False)
            self._btn_knife.setChecked(False)
            self._btn_draw_poly.setChecked(False)
        self._bw.set_polygon_selection_mode(checked)

    def _on_mesh_build_toggled(self, checked: bool) -> None:
        if checked:
            self._btn_sel_point.setChecked(False)
            self._btn_sel_edge.setChecked(False)
            self._btn_sel_open.setChecked(False)
            self._btn_sel_poly.setChecked(False)
            self._btn_point.setChecked(False)
            self._btn_oval.setChecked(False)
            self._btn_freehand.setChecked(False)
            self._btn_knife.setChecked(False)
            self._btn_draw_poly.setChecked(False)
        bw = self._bw
        bw._clear_all_modes()
        if checked:
            bw.set_mesh_build_mode(True)
        bw.mode_changed.emit()

    def _on_point_mode_toggled(self, checked: bool) -> None:
        if checked:
            self._btn_sel_point.setChecked(False)
            self._btn_sel_edge.setChecked(False)
            self._btn_sel_open.setChecked(False)
            self._btn_sel_poly.setChecked(False)
            self._btn_mesh_build.setChecked(False)
            self._btn_oval.setChecked(False)
            self._btn_freehand.setChecked(False)
            self._btn_knife.setChecked(False)
            self._btn_draw_poly.setChecked(False)
        self._bw.set_point_mode(checked)

    def _on_oval_mode_toggled(self, checked: bool) -> None:
        if checked:
            self._btn_sel_point.setChecked(False)
            self._btn_sel_edge.setChecked(False)
            self._btn_sel_open.setChecked(False)
            self._btn_sel_poly.setChecked(False)
            self._btn_mesh_build.setChecked(False)
            self._btn_point.setChecked(False)
            self._btn_freehand.setChecked(False)
            self._btn_knife.setChecked(False)
            self._btn_draw_poly.setChecked(False)
        self._bw.set_oval_mode(checked)

    def _on_freehand_toggled(self, checked: bool) -> None:
        if checked:
            self._btn_sel_point.setChecked(False)
            self._btn_sel_edge.setChecked(False)
            self._btn_sel_open.setChecked(False)
            self._btn_sel_poly.setChecked(False)
            self._btn_mesh_build.setChecked(False)
            self._btn_point.setChecked(False)
            self._btn_oval.setChecked(False)
            self._btn_knife.setChecked(False)
            self._btn_draw_poly.setChecked(False)
        self._bw.set_freehand_mode(checked)

    def _on_knife_toggled(self, checked: bool) -> None:
        if checked:
            self._btn_sel_point.setChecked(False)
            self._btn_sel_edge.setChecked(False)
            self._btn_sel_open.setChecked(False)
            self._btn_sel_poly.setChecked(False)
            self._btn_mesh_build.setChecked(False)
            self._btn_point.setChecked(False)
            self._btn_oval.setChecked(False)
            self._btn_freehand.setChecked(False)
            self._btn_draw_poly.setChecked(False)
        self._bw.set_knife_mode(checked)

    def _on_drawing_mode_toggled(self, checked: bool) -> None:
        """Drawing mode = clear all other modes. Stays 'checked' when no mode active."""
        if checked:
            self._btn_sel_point.setChecked(False)
            self._btn_sel_edge.setChecked(False)
            self._btn_sel_open.setChecked(False)
            self._btn_sel_poly.setChecked(False)
            self._btn_mesh_build.setChecked(False)
            self._btn_point.setChecked(False)
            self._btn_oval.setChecked(False)
            self._btn_freehand.setChecked(False)
            self._btn_knife.setChecked(False)
            self._bw._clear_all_modes()

    def _on_grid_toggled(self, checked: bool) -> None:
        # checked = "hide" icon is toggled = grid hidden
        self._bw.show_grid = not checked

    def _on_cp_toggled(self, checked: bool) -> None:
        self._bw.show_control_points = not checked

    def _on_weld_clicked(self) -> None:
        bw = self._bw
        if bw.edge_selection_mode and bw.selected_edges and bw._are_edges_weldable():
            # Manual edge weld — act as a one-shot button, keep auto-weld state
            bw.perform_weld()
            # Restore the toggle visual state so auto-weld stays enabled
            self._btn_weld.blockSignals(True)
            self._btn_weld.setChecked(bw._auto_weld_enabled)
            self._btn_weld.blockSignals(False)
        elif bw.point_selection_mode and bw.selected_points:
            # Point weld — also one-shot, preserve toggle state
            bw.weld_selected_points()
            self._btn_weld.blockSignals(True)
            self._btn_weld.setChecked(bw._auto_weld_enabled)
            self._btn_weld.blockSignals(False)
        else:
            # Pure toggle — enable/disable auto-weld on drag
            bw.set_auto_weld_enabled(self._btn_weld.isChecked())

    # ── sync button states from canvas mode flags ──────────────────────────────

    def _sync_buttons(self) -> None:
        bw = self._bw

        def _set(btn: QPushButton, val: bool) -> None:
            btn.blockSignals(True)
            btn.setChecked(val)
            btn.blockSignals(False)

        _set(self._btn_sel_point,  bw.point_selection_mode)
        _set(self._btn_sel_edge,   bw.edge_selection_mode)
        _set(self._btn_sel_open,   bw.open_curve_selection_mode)
        _set(self._btn_sel_poly,   bw.polygon_selection_mode)
        _set(self._btn_mesh_build, bw.mesh_build_mode)
        _set(self._btn_point,      bw.point_mode)
        _set(self._btn_oval,       bw.oval_mode)
        _set(self._btn_freehand,   bw.freehand_mode)
        _set(self._btn_knife,      bw.knife_mode)
        # Drawing mode = no special mode active
        no_mode = not (bw.any_selection_mode() or bw.point_mode
                       or bw.oval_mode or bw.freehand_mode or bw.knife_mode
                       or bw.mesh_build_mode)
        _set(self._btn_draw_poly, no_mode)
        # Weld toggle reflects auto-weld state
        _set(self._btn_weld, bw._auto_weld_enabled)
        # Grid/CP toggles: checked means "hidden"
        _set(self._btn_grid, not bw.show_grid)
        _set(self._btn_cp,   not bw.show_control_points)
