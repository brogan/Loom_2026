"""
BezierWidget — embeddable QWidget canvas.
Mirrors Java BezierDrawPanel. Can be used standalone or embedded in the Loom editor.
"""
from __future__ import annotations
import math
from collections import deque

from PySide6.QtCore import QPointF, QRectF, QTimer, Qt, Signal, QEvent
from PySide6.QtGui import QImage, QPainter, QMouseEvent, QKeyEvent, QTabletEvent
from PySide6.QtWidgets import QWidget, QFileDialog

from model.layer_manager import LayerManager
from model.polygon_manager import PolygonManager
from model.oval_manager import OvalManager
from model.cubic_curve_manager import CubicCurveManager
from model.cubic_point import CubicPoint, PointType
from model.geometry_snapshot import GeometrySnapshot
from canvas.render_engine import RenderEngine
from canvas.mouse_handler import MouseHandler
from canvas.selection_state import SelectionSubMode, SelectedEdge, SelectionSnapshot
from canvas.curve_fitter import fit as _curve_fit

# ── canvas constants (identical to Java) ─────────────────────────────────────
WIDTH       = 1040
HEIGHT      = 1040
GRIDWIDTH   = 1000
GRIDHEIGHT  = 1000
EDGE_OFFSET = 20

SELECTION_HISTORY_MAX = 10

# Rotation axis modes (match CubicCurvePanel.java constants)
ROTATE_LOCAL    = 0   # each polygon around its own centroid
ROTATE_COMMON   = 1   # all targets share one common centroid
ROTATE_ABSOLUTE = 2   # around the absolute canvas centre

# Scale axis modes
SCALE_XY = 0
SCALE_X  = 1
SCALE_Y  = 2

# Scale target modes — which point types are affected by the scale slider
SCALE_TARGET_BOTH     = 0   # anchors + control points (default)
SCALE_TARGET_ANCHORS  = 1   # anchor points only; control points hold world position
SCALE_TARGET_CONTROLS = 2   # control points only; anchors hold position


def _make_linear_bezier_pts(anchors: list[QPointF]) -> list[QPointF]:
    """Build the flat [A0,C1,C2,A1, A1,C1',C2',A2, …] list needed by
    CubicCurveManager.set_all_points() for a closed polygon with straight
    (linear) edges.  Control points are placed at 1/3 and 2/3 along each edge.
    """
    n = len(anchors)
    pts: list[QPointF] = []
    for i in range(n):
        a0 = anchors[i]
        a1 = anchors[(i + 1) % n]
        dx = a1.x() - a0.x()
        dy = a1.y() - a0.y()
        c1 = QPointF(a0.x() + dx / 3.0, a0.y() + dy / 3.0)
        c2 = QPointF(a0.x() + 2.0 * dx / 3.0, a0.y() + 2.0 * dy / 3.0)
        pts += [a0, c1, c2, a1]
    return pts


class BezierWidget(QWidget):
    """
    Self-contained Bézier curve editor canvas.
    No window, no menus — embed in any QWidget hierarchy.
    """

    modified      = Signal()
    layer_changed = Signal()
    mode_changed  = Signal()   # emitted when any mode flag changes (for toolbar sync)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setMinimumSize(400, 400)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        self.setMouseTracking(True)

        # ── off-screen buffer ─────────────────────────────────────────────────
        self.dBuffer = QImage(WIDTH, HEIGHT, QImage.Format.Format_ARGB32)

        # ── layer system ──────────────────────────────────────────────────────
        self.layer_manager: LayerManager = LayerManager()

        # ── geometry data ─────────────────────────────────────────────────────
        self.polygon_manager: PolygonManager = PolygonManager(self.layer_manager)
        self.oval_list: list[OvalManager] = []
        self.selected_ovals: list[OvalManager] = []
        self.point_list: list[QPointF] = []
        self.point_pressures: list[float] = []

        # ── drawing mode flags ────────────────────────────────────────────────
        self.point_mode: bool = False       # discrete point placement
        self.oval_mode: bool = False        # click+drag to create oval
        self.oval_drag_active: bool = False

        self.current_mouse_pos: QPointF = QPointF(WIDTH / 2, HEIGHT / 2)
        self.selected_discrete_point_index: int = -1

        # ── selection mode flags ──────────────────────────────────────────────
        self.polygon_selection_mode: bool = False
        self.edge_selection_mode: bool = False
        self.point_selection_mode: bool = False
        self.open_curve_selection_mode: bool = False

        self.point_sub_mode:  SelectionSubMode = SelectionSubMode.RELATIONAL
        self.edge_sub_mode:   SelectionSubMode = SelectionSubMode.RELATIONAL
        self.poly_sub_mode:   SelectionSubMode = SelectionSubMode.RELATIONAL

        # ── selection state ───────────────────────────────────────────────────
        self.selected_points:   list[CubicPoint]        = []
        self.selected_edges:    list[SelectedEdge]       = []
        self.selected_polygons: list[CubicCurveManager]  = []  # closed + open
        self.scoped_manager:    CubicCurveManager | None = None

        # ── rubber-band (Shift+drag in any selection mode) ────────────────────
        self.rubber_banding:    bool            = False
        self.rubber_band_start: QPointF | None  = None
        self.rubber_band_end:   QPointF | None  = None

        # ── selection history (Space=deselect, ←/→ navigate) ─────────────────
        self._sel_history:        deque[SelectionSnapshot] = deque(maxlen=SELECTION_HISTORY_MAX)
        self._sel_history_cursor: int  = -1
        self._navigating_history: bool = False
        self._history_layer_id:   int  = -1

        # ── undo / redo stacks (max 20 each) ─────────────────────────────────
        self._undo_stack: deque[GeometrySnapshot] = deque(maxlen=20)
        self._redo_stack: deque[GeometrySnapshot] = deque(maxlen=20)

        # ── clipboard ─────────────────────────────────────────────────────────
        self._clipboard: list[tuple[list, bool]] = []   # (pts, is_closed)

        # ── reference image overlay ───────────────────────────────────────────
        self._reference_image: QImage | None = None
        self._show_reference_image: bool = False

        # ── trace image drag ──────────────────────────────────────────────────
        self._trace_drag_last: QPointF | None = None

        # ── view toggles ──────────────────────────────────────────────────────
        self.show_grid:           bool = True
        self.show_control_points: bool = True

        # ── tablet / stylus pressure ──────────────────────────────────────────
        self._current_pressure: float = 1.0   # updated by tabletEvent
        self._tablet_active: bool = False       # True while stylus is pressed

        # ── freehand mode ─────────────────────────────────────────────────────
        self.freehand_mode: bool = False
        self._freehand_raw: list[QPointF] = []
        self._freehand_pressures: list[float] = []   # parallel to _freehand_raw
        self._freehand_active: bool = False
        self._freehand_first: QPointF | None = None
        self._freehand_error_threshold: float = 41.0   # slider default 10 → 51-10
        self._FREEHAND_MIN_STEP:   float = 3.0
        self._FREEHAND_SNAP_RADIUS: float = 20.0

        # ── drawing rubber-line pause (Space in drawing mode) ─────────────────
        self._drawing_paused: bool = False

        # ── polygon deferred click-through (Java polygonClickCandidate) ────────
        self._polygon_click_candidate: CubicCurveManager | None = None
        self._polygon_mouse_moved:     bool = False

        # ── auto-weld on drag (default on, matches Java) ───────────────────────
        self._auto_weld_enabled: bool = True
        self._pending_weld_pairs: list = []   # list of (SelectedEdge, SelectedEdge)

        # ── knife mode ────────────────────────────────────────────────────────
        self.knife_mode: bool = False
        self._knife_start: QPointF | None = None
        self._knife_end:   QPointF | None = None
        self._pre_knife_selection: set = set()

        # ── mesh build mode ───────────────────────────────────────────────────
        # Entered via Ctrl+A.  User hovers over discrete points to build
        # polygon faces; 'p' commits, Backspace undoes last, Space clears.
        self.mesh_build_mode: bool = False
        self._mesh_seq: list[QPointF] = []   # ordered hover sequence (canvas px)
        self._mesh_layer_id: int = -1         # auto-created target mesh layer

        # ── extrude state ─────────────────────────────────────────────────────
        self._extrude_on_drag: bool = False
        self._extruding:       bool = False
        self._extrude_live_edges: list[CubicCurveManager] = []

        # ── transform state ───────────────────────────────────────────────────
        # One undo snapshot per slider gesture (reset when slider released)
        self._scale_rotate_snapshot_pending: bool = True
        # Which point types the scale slider affects (SCALE_TARGET_*)
        self._scale_target: int = SCALE_TARGET_BOTH

        # ── sub-systems ───────────────────────────────────────────────────────
        self._renderer = RenderEngine()
        self._mouse_handler = MouseHandler(self)

        # ── animation timer (20 ms ≈ 50 fps) ─────────────────────────────────
        self._timer = QTimer(self)
        self._timer.timeout.connect(self.update)
        self._timer.start(20)

    # ── coordinate helper ─────────────────────────────────────────────────────

    def scale_mouse(self, event: QMouseEvent) -> QPointF:
        pos = event.position()
        x = pos.x() * WIDTH  / max(1, self.width())
        y = pos.y() * HEIGHT / max(1, self.height())
        return QPointF(x, y)

    # ── painting ──────────────────────────────────────────────────────────────

    def paintEvent(self, event) -> None:
        self._draw_to_buffer()
        p = QPainter(self)
        p.drawImage(self.rect(), self.dBuffer)
        p.end()

    def _draw_to_buffer(self) -> None:
        p = QPainter(self.dBuffer)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)

        self._renderer.draw_background(p, WIDTH, HEIGHT, EDGE_OFFSET,
                                       GRIDWIDTH, GRIDHEIGHT, self.show_grid)

        if self._show_reference_image and self._reference_image is not None:
            p.setOpacity(0.2)
            p.drawImage(
                QRectF(EDGE_OFFSET, EDGE_OFFSET, GRIDWIDTH, GRIDHEIGHT),
                self._reference_image,
            )
            p.setOpacity(1.0)

        # Trace image — above reference image, below all geometry layers.
        # Always drawn at the user-configured alpha (never dimmed for inactivity).
        _trace = self.layer_manager.get_trace_layer()
        if _trace is not None and _trace.visible:
            self._renderer.draw_trace_image(p, _trace)

        lm = self.layer_manager
        active_id = lm.active_layer_id
        for mgr in self.polygon_manager.committed_managers():
            layer = lm.get_layer_by_id(mgr.layer_id)
            if layer is None or not layer.visible:
                continue
            is_active = (mgr.layer_id == active_id)
            opacity = 1.0 if is_active else 0.2
            self._renderer.draw_manager(p, mgr,
                                        show_handles=is_active and self.show_control_points,
                                        opacity=opacity)
            if is_active:
                self._renderer.draw_edge_highlights(p, mgr)
                self._renderer.draw_point_highlights(p, mgr)

        self._renderer.draw_in_progress(
            p,
            self.polygon_manager.current_manager(),
            mouse_pos=self.current_mouse_pos,
            paused=self._drawing_paused,
        )

        visible_ovals = [
            o for o in self.oval_list
            if (layer := lm.get_layer_by_id(o.layer_id)) is not None
            and layer.visible
        ]
        self._renderer.draw_ovals(p, visible_ovals)

        self._renderer.draw_discrete_points(
            p, self.point_list, self.point_pressures,
            self.selected_discrete_point_index
        )

        if self.rubber_banding and self.rubber_band_start and self.rubber_band_end:
            self._renderer.draw_rubber_band(p, self.rubber_band_start,
                                            self.rubber_band_end)

        if self.knife_mode and self._knife_start and self._knife_end:
            self._renderer.draw_knife_line(p, self._knife_start, self._knife_end)

        if self.freehand_mode and self._freehand_active and self._freehand_raw:
            self._renderer.draw_freehand_preview(
                p, self._freehand_raw,
                pressures=self._freehand_pressures,
                first_pt=self._freehand_first,
                snap_radius=self._FREEHAND_SNAP_RADIUS,
            )

        if self.mesh_build_mode:
            self._renderer.draw_mesh_build_overlay(
                p, self._mesh_seq, self.current_mouse_pos, self.point_list
            )

        p.end()

    # ── mouse events ──────────────────────────────────────────────────────────

    def mousePressEvent(self, event: QMouseEvent) -> None:
        if self._tablet_active:
            return   # handled by tabletEvent; ignore synthetic mouse press
        self.setFocus()
        # If the trace layer is active, start a trace-image drag instead of
        # any geometry interaction ("trace drag always wins").
        _active = self.layer_manager.get_active_layer()
        if _active is not None and _active.is_trace:
            self._trace_drag_last = self.scale_mouse(event)
            return
        # Placing a new anchor resumes the rubber line
        if not self.any_selection_mode() and not self.freehand_mode \
                and not self.knife_mode and not self.point_mode and not self.oval_mode:
            self._drawing_paused = False
        self._mouse_handler.press(event)
        self.modified.emit()

    def mouseMoveEvent(self, event: QMouseEvent) -> None:
        if self._tablet_active:
            return   # handled by tabletEvent
        if event.buttons() & Qt.MouseButton.LeftButton:
            _active = self.layer_manager.get_active_layer()
            if _active is not None and _active.is_trace:
                self._drag_trace_image(event)
                self.modified.emit()
            else:
                self._mouse_handler.drag(event)
                self.modified.emit()
        else:
            self._mouse_handler.move(event)

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        if self._tablet_active:
            return   # handled by tabletEvent; ignore synthetic mouse release
        self._trace_drag_last = None
        _active = self.layer_manager.get_active_layer()
        if _active is not None and _active.is_trace:
            return   # no geometry release when trace layer is active
        self._mouse_handler.release(event)

    # ── tablet events (stylus pressure) ───────────────────────────────────────

    def tabletEvent(self, event: QTabletEvent) -> None:
        self._current_pressure = max(0.05, min(1.0, event.pressure()))
        t = event.type()
        if t == QEvent.Type.TabletPress:
            self._tablet_active = True
            self.setFocus()
            if not self.any_selection_mode() and not self.freehand_mode \
                    and not self.knife_mode and not self.point_mode:
                self._drawing_paused = False
            self._mouse_handler.press(event)
            self.modified.emit()
        elif t == QEvent.Type.TabletMove:
            if self._tablet_active:
                self._mouse_handler.drag(event)
                self.modified.emit()
            else:
                self._mouse_handler.move(event)
        elif t == QEvent.Type.TabletRelease:
            self._tablet_active = False
            self._mouse_handler.release(event)
            self.modified.emit()
        event.accept()
        self.update()

    # ── key events ────────────────────────────────────────────────────────────

    def keyPressEvent(self, event: QKeyEvent) -> None:
        key  = event.key()
        mods = event.modifiers()

        # ── Ctrl+A: toggle mesh build mode ───────────────────────────────────
        if mods == Qt.KeyboardModifier.ControlModifier:
            if key == Qt.Key.Key_A:
                new_val = not self.mesh_build_mode
                self._clear_all_modes()
                if new_val:
                    self.set_mesh_build_mode(True)
                self.mode_changed.emit()
                return

        if mods == Qt.KeyboardModifier.NoModifier:
            # ── mesh build mode: intercept Space / P / Backspace ─────────────
            if self.mesh_build_mode:
                if key == Qt.Key.Key_P:
                    self._mesh_build_commit()
                    return
                if key in (Qt.Key.Key_Backspace, Qt.Key.Key_Delete):
                    if self._mesh_seq:
                        self._mesh_seq.pop()
                    self.update()
                    return
                if key == Qt.Key.Key_Space:
                    self._mesh_seq.clear()
                    self.update()
                    return

            if key == Qt.Key.Key_Space:
                if self.any_selection_mode():
                    self.deselect_all()
                else:
                    # Toggle rubber-line pause in drawing mode
                    self._drawing_paused = not self._drawing_paused
                return
            if key == Qt.Key.Key_O:
                self.finish_open_curve()
                return
            if key == Qt.Key.Key_P:
                self.finish_curve()
                return
            if key == Qt.Key.Key_Left:
                self.navigate_selection_back()
                return
            if key == Qt.Key.Key_Right:
                self.navigate_selection_forward()
                return
            if key in (Qt.Key.Key_Backspace, Qt.Key.Key_Delete):
                self.delete_selected()
                return
            # ── selection mode shortcuts ───────────────────────────────────
            if key == Qt.Key.Key_A:
                self._key_toggle_selection('point')
                return
            if key == Qt.Key.Key_S:
                self._key_toggle_selection('edge')
                return
            if key == Qt.Key.Key_D:
                self._key_toggle_selection('open')
                return
            if key == Qt.Key.Key_F:
                self._key_toggle_selection('poly')
                return
            # ── creation mode shortcuts ────────────────────────────────────
            if key == Qt.Key.Key_H:
                new_val = not self.point_mode
                self._clear_all_modes()
                self.set_point_mode(new_val)
                self.mode_changed.emit()
                return
            if key == Qt.Key.Key_J:
                new_val = not self.oval_mode
                self._clear_all_modes()
                self.set_oval_mode(new_val)
                self.mode_changed.emit()
                return
            if key == Qt.Key.Key_K:
                self._clear_all_modes()
                self.mode_changed.emit()
                return
            if key == Qt.Key.Key_L:
                new_val = not self.mesh_build_mode
                self._clear_all_modes()
                if new_val:
                    self.set_mesh_build_mode(True)
                self.mode_changed.emit()
                return
            if key == Qt.Key.Key_Semicolon:
                new_val = not self.freehand_mode
                self._clear_all_modes()
                self.set_freehand_mode(new_val)
                self.mode_changed.emit()
                return
        super().keyPressEvent(event)

    def _key_toggle_selection(self, mode: str) -> None:
        """Toggle one selection mode exclusively (a/s/d/f shortcuts)."""
        was_on = {
            'point': self.point_selection_mode,
            'edge':  self.edge_selection_mode,
            'open':  self.open_curve_selection_mode,
            'poly':  self.polygon_selection_mode,
        }[mode]
        self._clear_all_modes()
        if not was_on:
            if mode == 'point':
                self.set_point_selection_mode(True)
            elif mode == 'edge':
                self.set_edge_selection_mode(True)
            elif mode == 'open':
                self.set_open_curve_selection_mode(True)
            elif mode == 'poly':
                self.set_polygon_selection_mode(True)
        self.mode_changed.emit()

    def _clear_all_modes(self) -> None:
        """Turn off every mode flag. Drawing mode (default) is the result."""
        self.set_point_selection_mode(False)
        self.set_edge_selection_mode(False)
        self.set_open_curve_selection_mode(False)
        self.set_polygon_selection_mode(False)
        self.set_point_mode(False)
        self.set_oval_mode(False)
        self.set_freehand_mode(False)
        self.set_knife_mode(False)
        self.set_mesh_build_mode(False)

    # ── toolbar / menu actions ────────────────────────────────────────────────

    def finish_curve(self) -> None:
        self._drawing_paused = False
        self.take_undo_snapshot()
        self.polygon_manager.finish_closed()
        # Auto-switch to polygon selection mode when in default drawing mode
        if not self.any_selection_mode():
            self._clear_all_modes()
            self.set_polygon_selection_mode(True)
            self.mode_changed.emit()
        self.modified.emit()

    def finish_open_curve(self) -> None:
        self._drawing_paused = False
        self.take_undo_snapshot()
        self.polygon_manager.finish_open()
        # Auto-switch to open curve selection mode when in default drawing mode
        if not self.any_selection_mode():
            self._clear_all_modes()
            self.set_open_curve_selection_mode(True)
            self.mode_changed.emit()
        self.modified.emit()

    def clear_grid(self) -> None:
        self.take_undo_snapshot()
        self.polygon_manager = PolygonManager(self.layer_manager)
        self.oval_list.clear()
        self.selected_ovals.clear()
        self.point_list.clear()
        self.point_pressures.clear()
        self.selected_discrete_point_index = -1
        self.point_mode = False
        self.deselect_all()
        self.modified.emit()

    def create_oval(self) -> None:
        self.take_undo_snapshot()
        cx = EDGE_OFFSET + GRIDWIDTH  / 2.0
        cy = EDGE_OFFSET + GRIDHEIGHT / 2.0
        rx = GRIDWIDTH  / 6.0
        ry = GRIDHEIGHT / 6.0
        oval = OvalManager(cx, cy, rx, ry)
        oval.layer_id = self.layer_manager.active_layer_id
        self.oval_list.append(oval)
        for o in self.selected_ovals:
            o.selected = False
        self.selected_ovals.clear()
        oval.selected = True
        self.selected_ovals.append(oval)
        self.modified.emit()

    def set_point_mode(self, enabled: bool) -> None:
        self.point_mode = enabled
        if not enabled:
            self.selected_discrete_point_index = -1

    def set_oval_mode(self, enabled: bool) -> None:
        self.oval_mode = enabled

    def set_mesh_build_mode(self, enabled: bool) -> None:
        self.mesh_build_mode = enabled
        if not enabled:
            self._mesh_seq.clear()

    # ── freehand mode ─────────────────────────────────────────────────────────

    def set_freehand_mode(self, enabled: bool) -> None:
        self.freehand_mode = enabled
        if not enabled:
            self._freehand_active = False
            self._freehand_raw.clear()
            self._freehand_pressures.clear()

    def set_freehand_error_threshold(self, threshold: float) -> None:
        self._freehand_error_threshold = threshold

    def finalize_freehand(self) -> None:
        """Fit freehand raw samples to Bézier curves and commit to polygon manager."""
        self._freehand_active = False
        pts = list(self._freehand_raw)
        raw_pressures = list(self._freehand_pressures)
        self._freehand_raw.clear()
        self._freehand_pressures.clear()
        if len(pts) < 2:
            return
        do_close = (len(pts) > 5 and self._freehand_first is not None and
                    math.hypot(pts[-1].x() - self._freehand_first.x(),
                               pts[-1].y() - self._freehand_first.y())
                    < self._FREEHAND_SNAP_RADIUS)
        if do_close and self._freehand_first is not None:
            pts.append(QPointF(self._freehand_first))
        fitted = _curve_fit(pts, self._freehand_error_threshold)
        if fitted and len(fitted) >= 4:
            active_id = self.layer_manager.active_layer_id
            if do_close:
                mgr = self.polygon_manager.add_closed_from_points(fitted, active_id)
            else:
                mgr = self.polygon_manager.add_open_from_points(fitted, active_id)
            # Map raw pressure samples to per-anchor pressures (same as Java)
            if raw_pressures:
                num_segments = len(fitted) // 4
                num_anchors  = num_segments + 1
                raw_n = len(raw_pressures)
                anchor_pressures = []
                for k in range(num_anchors):
                    if raw_n > 1:
                        raw_idx = round(k * (raw_n - 1) / (num_anchors - 1))
                    else:
                        raw_idx = 0
                    raw_idx = max(0, min(raw_n - 1, raw_idx))
                    anchor_pressures.append(raw_pressures[raw_idx])
                mgr.anchor_pressures = anchor_pressures
        self.modified.emit()

    # ── knife mode ────────────────────────────────────────────────────────────

    def set_knife_mode(self, enabled: bool) -> None:
        if enabled:
            self._pre_knife_selection = set(self.selected_polygons)
            self.knife_mode = True
            self._knife_start = None
            self._knife_end = None
        else:
            self.knife_mode = False
            self._knife_start = None
            self._knife_end = None
            self._pre_knife_selection.clear()

    # ── mesh build mode helpers ───────────────────────────────────────────────

    _MESH_HOVER_ADD_R  = 10.0   # px — add to sequence when mouse enters this radius
    _MESH_WELD_THRESH  =  5.0   # px — weld new anchors to existing at same position

    def _get_or_create_mesh_layer(self) -> int:
        """Return the ID of the 'Mesh' layer, creating it if it does not exist."""
        if self._mesh_layer_id >= 0:
            if self.layer_manager.get_layer_by_id(self._mesh_layer_id) is not None:
                return self._mesh_layer_id
        # Re-use an existing layer named "Mesh" (in case of reload / undo)
        for layer in self.layer_manager.geometry_layers():
            if layer.name == "Mesh":
                self._mesh_layer_id = layer.id
                return self._mesh_layer_id
        layer = self.layer_manager.create_layer("Mesh")
        self._mesh_layer_id = layer.id
        self.layer_changed.emit()
        return self._mesh_layer_id

    def _mesh_hover_update(self, pos: QPointF) -> None:
        """Called on every mouse-move in mesh_build_mode.

        Adds the nearest discrete point (within MESH_HOVER_ADD_R) to the
        hover sequence, but only if it is not already present.
        """
        nearest_pos: QPointF | None = None
        nearest_dist = self._MESH_HOVER_ADD_R
        for pt in self.point_list:
            d = math.hypot(pt.x() - pos.x(), pt.y() - pos.y())
            if d < nearest_dist:
                nearest_dist = d
                nearest_pos = pt

        if nearest_pos is None:
            return

        # Skip if already in the sequence (proximity check)
        for s in self._mesh_seq:
            if math.hypot(nearest_pos.x() - s.x(),
                          nearest_pos.y() - s.y()) < 3.0:
                return

        self._mesh_seq.append(QPointF(nearest_pos))

    def _mesh_build_commit(self) -> None:
        """Build a closed polygon from _mesh_seq, auto-weld to the mesh layer."""
        if len(self._mesh_seq) < 3:
            return

        self.take_undo_snapshot()
        layer_id = self._get_or_create_mesh_layer()

        # Build flat [A0,C1,C2,A1, A1,C1',C2',A2, ...] with linear control pts
        pts = _make_linear_bezier_pts(self._mesh_seq)

        mgr = self.polygon_manager.add_closed_from_points(pts, layer_id)

        # Gather unique new anchor CubicPoints (curves[i].points[0] per segment)
        seen_new: set[int] = set()
        new_anchors: list = []
        for cv in mgr.curves:
            pt = cv.points[0]
            if pt is not None and id(pt) not in seen_new:
                seen_new.add(id(pt))
                new_anchors.append(pt)

        # Auto-weld to existing mesh-layer anchors at the same position
        wr = self.polygon_manager.weld_registry
        thresh = self._MESH_WELD_THRESH
        for ex_mgr in self.polygon_manager.committed_managers():
            if ex_mgr is mgr or ex_mgr.layer_id != layer_id:
                continue
            seen_ex: set[int] = set()
            for cv in ex_mgr.curves:
                ex_pt = cv.points[0]
                if ex_pt is None or id(ex_pt) in seen_ex:
                    continue
                seen_ex.add(id(ex_pt))
                for new_pt in new_anchors:
                    d = math.hypot(new_pt.pos.x() - ex_pt.pos.x(),
                                   new_pt.pos.y() - ex_pt.pos.y())
                    if d <= thresh:
                        wr.register_weld(new_pt, ex_pt)

        # Clear sequence but stay in mesh_build_mode
        self._mesh_seq.clear()
        self.modified.emit()
        self.layer_changed.emit()

    # ── reference image ───────────────────────────────────────────────────────

    def load_reference_image(self, file_path: str) -> bool:
        """Load an image file for use as a 20%-opacity overlay behind geometry."""
        img = QImage(file_path)
        if img.isNull():
            return False
        self._reference_image = img
        self._show_reference_image = True
        return True

    # ── trace image ───────────────────────────────────────────────────────────

    def load_trace_image(self, file_path: str) -> bool:
        """
        Load an image as the trace layer.

        If a trace layer already exists its image is replaced and position /
        scale are reset to defaults; alpha is preserved.  The trace layer
        becomes the active layer so canvas drags immediately move the image.
        """
        img = QImage(file_path)
        if img.isNull():
            return False
        lm = self.layer_manager
        trace = lm.get_trace_layer()
        if trace is None:
            trace = lm.create_trace_layer(file_path)
        else:
            trace.trace_image_path = file_path
            trace.trace_x     = 520.0
            trace.trace_y     = 520.0
            trace.trace_scale = 1.0
            # trace_alpha intentionally preserved across reloads
        trace.trace_image = img
        lm.set_active_layer_id(trace.id)
        self.layer_changed.emit()
        self.update()
        return True

    def _drag_trace_image(self, event: QMouseEvent) -> None:
        """Translate the trace image by the mouse delta since the last drag event."""
        pos   = self.scale_mouse(event)
        trace = self.layer_manager.get_trace_layer()
        if trace is not None and self._trace_drag_last is not None:
            trace.trace_x += pos.x() - self._trace_drag_last.x()
            trace.trace_y += pos.y() - self._trace_drag_last.y()
        self._trace_drag_last = pos

    def toggle_reference_image(self) -> None:
        """Show/hide the reference image overlay."""
        if self._reference_image is not None:
            self._show_reference_image = not self._show_reference_image

    def clear_reference_image(self) -> None:
        self._reference_image = None
        self._show_reference_image = False

    # ── view toggles ──────────────────────────────────────────────────────────

    def toggle_grid(self) -> None:
        self.show_grid = not self.show_grid
        self.mode_changed.emit()

    def toggle_control_points(self) -> None:
        self.show_control_points = not self.show_control_points
        self.mode_changed.emit()

    # ── duplicate selected ────────────────────────────────────────────────────

    def duplicate_selected(self) -> None:
        """Deep-copy all selected polygons and ovals, offset by 20px."""
        if not self.selected_polygons and not self.selected_ovals:
            return
        OFFSET = 20.0
        self.take_undo_snapshot()
        new_mgrs: list[CubicCurveManager] = []
        for mgr in list(self.selected_polygons):
            new_mgr = self.polygon_manager.add_duplicate_of(mgr, OFFSET, OFFSET)
            new_mgrs.append(new_mgr)
        new_ovals: list[OvalManager] = []
        for oval in list(self.selected_ovals):
            from model.oval_manager import OvalManager as _OvalManager
            new_oval = _OvalManager(oval.cx + OFFSET, oval.cy + OFFSET, oval.rx, oval.ry)
            new_oval.layer_id = oval.layer_id
            self.oval_list.append(new_oval)
            new_ovals.append(new_oval)
        # Deselect originals, select duplicates
        for mgr in self.selected_polygons:
            mgr.selected = False
        for oval in self.selected_ovals:
            oval.selected = False
        self.selected_polygons.clear()
        self.selected_ovals.clear()
        for mgr in new_mgrs:
            mgr.selected = True
            self.selected_polygons.append(mgr)
        for oval in new_ovals:
            oval.selected = True
            self.selected_ovals.append(oval)
        self.modified.emit()

    def execute_knife_cut(self) -> None:
        """Called from mouse_handler on release when a valid cut line exists."""
        if not (self._knife_start and self._knife_end):
            return
        dx = self._knife_end.x() - self._knife_start.x()
        dy = self._knife_end.y() - self._knife_start.y()
        if math.hypot(dx, dy) < 5:
            return
        self.take_undo_snapshot()
        from canvas.knife_tool import perform_cut
        perform_cut(self.polygon_manager, self._knife_start, self._knife_end,
                    self._pre_knife_selection, self.selected_polygons)
        self._knife_start = None
        self._knife_end = None
        self.modified.emit()

    # ── extrude ───────────────────────────────────────────────────────────────

    def start_extrude(self) -> None:
        """Duplicate selected edges as live preview managers."""
        self._extruding = True
        self._extrude_on_drag = False
        self._extrude_live_edges.clear()
        active_id = self.layer_manager.active_layer_id
        for se in self.selected_edges:
            if se.curve_index >= len(se.manager.curves):
                continue
            cv = se.manager.curves[se.curve_index]
            pts = cv.points
            if any(p is None for p in pts):
                continue
            new_pts = [QPointF(p.pos) for p in pts]
            live_mgr = self.polygon_manager.add_open_from_points(new_pts, active_id)
            self._extrude_live_edges.append(live_mgr)

    def finalize_extrude(self) -> None:
        """Build quads from original + live edges, commit, select top edges."""
        wr = self.polygon_manager.weld_registry
        active_id = self.layer_manager.active_layer_id
        new_selection: list[SelectedEdge] = []

        for i, se in enumerate(self.selected_edges):
            if i >= len(self._extrude_live_edges):
                break
            live_mgr = self._extrude_live_edges[i]
            if se.curve_index >= len(se.manager.curves):
                continue
            orig_pts = se.manager.curves[se.curve_index].points
            if live_mgr.curves:
                live_pts = live_mgr.curves[0].points
            else:
                continue
            if any(p is None for p in orig_pts) or any(p is None for p in live_pts):
                continue

            # Snapshot positions before removing live manager
            oA0 = QPointF(orig_pts[0].pos); oC1 = QPointF(orig_pts[1].pos)
            oC2 = QPointF(orig_pts[2].pos); oA3 = QPointF(orig_pts[3].pos)
            lA0 = QPointF(live_pts[0].pos); lC1 = QPointF(live_pts[1].pos)
            lC2 = QPointF(live_pts[2].pos); lA3 = QPointF(live_pts[3].pos)

            # Remove live preview
            for j in range(self.polygon_manager.polygon_count):
                if self.polygon_manager.get_manager(j) is live_mgr:
                    self.polygon_manager.remove_manager_at(j)
                    break

            # Build 4-curve closed quad (16 control points)
            def lerp_pt(a: QPointF, b: QPointF, t: float) -> QPointF:
                return QPointF(a.x() + (b.x() - a.x()) * t,
                               a.y() + (b.y() - a.y()) * t)

            quad_pts = [
                # curve 0: bottom = original edge
                oA0, oC1, oC2, oA3,
                # curve 1: right connector
                oA3, lerp_pt(oA3, lA3, 1/3), lerp_pt(oA3, lA3, 2/3), lA3,
                # curve 2: top = live edge reversed
                lA3, lC2, lC1, lA0,
                # curve 3: left connector
                lA0, lerp_pt(lA0, oA0, 1/3), lerp_pt(lA0, oA0, 2/3), oA0,
            ]
            quad_mgr = self.polygon_manager.add_closed_from_points(quad_pts, active_id)

            # Weld bottom edge to original source
            if se.manager.is_closed:
                qa0 = quad_mgr.curves[0].points[0]
                qa3 = quad_mgr.curves[0].points[3]
                if qa0 and qa3:
                    wr.register_weld(orig_pts[0], qa0)
                    wr.register_weld(orig_pts[3], qa3)

            # Select curve[2] (far/top edge) for chain-extrusion
            new_selection.append(SelectedEdge(quad_mgr, 2))

        # Clear old edge highlights, update selection
        for se in self.selected_edges:
            se.manager.clear_all_highlights()
        self.selected_edges.clear()
        self.selected_edges.extend(new_selection)
        self._update_edge_highlights()
        self._extrude_live_edges.clear()

    # ── weld operations ───────────────────────────────────────────────────────

    def weld_selected_points(self) -> None:
        """Replace all selected points with the first, sharing one object reference.
        Mirrors Java replacePoints(): dragging one polygon now automatically drags
        every curve that references the same CubicPoint object.
        """
        if len(self.selected_points) < 2:
            return
        self.take_undo_snapshot()
        anchor = self.selected_points[0]
        wr = self.polygon_manager.weld_registry
        for pt in self.selected_points[1:]:
            self.polygon_manager.replace_point(pt, anchor)
            wr.register_weld(anchor, pt)
        self.selected_points = [anchor]
        self._update_point_highlights()
        self.modified.emit()

    def _are_edges_weldable(self) -> bool:
        """Java areEdgesWeldable guard: 2 edges from different managers,
        midpoints ≤80px, directions |dot|>0.7, endpoint pair distance ≤140px.
        """
        if len(self.selected_edges) != 2:
            return False
        e0, e1 = self.selected_edges[0], self.selected_edges[1]
        if e0.manager is e1.manager:
            return False
        if (e0.curve_index >= len(e0.manager.curves) or
                e1.curve_index >= len(e1.manager.curves)):
            return False
        p0 = e0.manager.curves[e0.curve_index].points
        p1 = e1.manager.curves[e1.curve_index].points
        if any(pt is None for pt in p0) or any(pt is None for pt in p1):
            return False
        # Midpoint proximity ≤ 80px
        mid0x = (p0[0].pos.x() + p0[3].pos.x()) / 2
        mid0y = (p0[0].pos.y() + p0[3].pos.y()) / 2
        mid1x = (p1[0].pos.x() + p1[3].pos.x()) / 2
        mid1y = (p1[0].pos.y() + p1[3].pos.y()) / 2
        if math.hypot(mid0x - mid1x, mid0y - mid1y) > 80:
            return False
        # Direction parallelism: |dot| > 0.7
        dx0 = p0[3].pos.x() - p0[0].pos.x(); dy0 = p0[3].pos.y() - p0[0].pos.y()
        dx1 = p1[3].pos.x() - p1[0].pos.x(); dy1 = p1[3].pos.y() - p1[0].pos.y()
        len0 = math.hypot(dx0, dy0); len1 = math.hypot(dx1, dy1)
        if len0 < 1 or len1 < 1:
            return False
        dot = (dx0 * dx1 + dy0 * dy1) / (len0 * len1)
        if abs(dot) <= 0.7:
            return False
        # Endpoint pair proximity ≤ 140px
        dist_same = (math.hypot(p0[0].pos.x()-p1[0].pos.x(), p0[0].pos.y()-p1[0].pos.y()) +
                     math.hypot(p0[3].pos.x()-p1[3].pos.x(), p0[3].pos.y()-p1[3].pos.y()))
        dist_rev  = (math.hypot(p0[0].pos.x()-p1[3].pos.x(), p0[0].pos.y()-p1[3].pos.y()) +
                     math.hypot(p0[3].pos.x()-p1[0].pos.x(), p0[3].pos.y()-p1[0].pos.y()))
        return min(dist_same, dist_rev) <= 140

    def perform_weld(self) -> None:
        """Java performWeld dispatcher: edge mode with edges → edge weld; else → point weld."""
        if self.edge_selection_mode and self.selected_edges:
            self.weld_selected_edges()
        else:
            self.weld_selected_points()

    def weld_selected_edges(self) -> None:
        """Average-merge two selected edges and register their point welds."""
        if not self._are_edges_weldable():
            return
        self.take_undo_snapshot()
        e0, e1 = self.selected_edges[0], self.selected_edges[1]
        if (e0.curve_index >= len(e0.manager.curves) or
                e1.curve_index >= len(e1.manager.curves)):
            return
        p0 = e0.manager.curves[e0.curve_index].points
        p1 = e1.manager.curves[e1.curve_index].points
        if any(p is None for p in p0) or any(p is None for p in p1):
            return

        # Determine weld direction by minimising total anchor distance
        dx0 = p0[3].pos.x() - p0[0].pos.x(); dy0 = p0[3].pos.y() - p0[0].pos.y()
        dx1 = p1[3].pos.x() - p1[0].pos.x(); dy1 = p1[3].pos.y() - p1[0].pos.y()
        dot = dx0 * dx1 + dy0 * dy1
        dist_same = (math.hypot(p0[0].pos.x()-p1[0].pos.x(), p0[0].pos.y()-p1[0].pos.y()) +
                     math.hypot(p0[3].pos.x()-p1[3].pos.x(), p0[3].pos.y()-p1[3].pos.y()))
        dist_rev  = (math.hypot(p0[0].pos.x()-p1[3].pos.x(), p0[0].pos.y()-p1[3].pos.y()) +
                     math.hypot(p0[3].pos.x()-p1[0].pos.x(), p0[3].pos.y()-p1[0].pos.y()))
        reversed_ = (dot < 0) if abs(dist_same - dist_rev) < 1.0 else (dist_rev < dist_same)

        pa0, pa3 = p0[0], p0[3]
        pb0 = p1[3] if reversed_ else p1[0]
        pb3 = p1[0] if reversed_ else p1[3]
        pc0n, pc0f = p0[1], p0[2]
        pc1n = p1[2] if reversed_ else p1[1]
        pc1f = p1[1] if reversed_ else p1[2]

        def midpt(a, b) -> QPointF:
            return QPointF((a.pos.x() + b.pos.x()) / 2, (a.pos.y() + b.pos.y()) / 2)

        m0, m3   = midpt(pa0, pb0), midpt(pa3, pb3)
        cm0, cm3 = midpt(pc0n, pc1n), midpt(pc0f, pc1f)

        for pt, mp in ((pa0, m0), (pb0, m0), (pa3, m3), (pb3, m3),
                       (pc0n, cm0), (pc1n, cm0), (pc0f, cm3), (pc1f, cm3)):
            pt.pos = QPointF(mp); pt.set_orig_to_pos()

        wr = self.polygon_manager.weld_registry
        wr.register_weld(pa0, pb0); wr.register_weld(pa3, pb3)
        wr.register_weld(pc0n, pc1n); wr.register_weld(pc0f, pc1f)

        self.selected_edges.clear()
        self._update_edge_highlights()
        self.modified.emit()

    def perform_intersect(self) -> None:
        """Build N annular quads from two selected concentric polygons.
        Mirrors Java BezierIntersectTool.performIntersect().
        Silently does nothing if validation fails.
        """
        if len(self.selected_polygons) != 2:
            return
        a, b = self.selected_polygons[0], self.selected_polygons[1]
        self.take_undo_snapshot()
        from canvas.intersect_tool import perform_intersect as _do_intersect
        if not _do_intersect(self.polygon_manager, a, b,
                             self.layer_manager.active_layer_id,
                             self.selected_polygons):
            # validation failed — discard the snapshot we just took
            self._undo_stack.pop() if self._undo_stack else None
        else:
            self.modified.emit()

    def weld_all_adjacent(self, threshold: float = 5.0) -> None:
        """Auto-weld all coincident boundary edges across different managers."""
        self.take_undo_snapshot()
        wr = self.polygon_manager.weld_registry
        tot = self.polygon_manager.polygon_count
        for i in range(tot):
            mi = self.polygon_manager.get_manager(i)
            for j in range(i + 1, tot):
                mj = self.polygon_manager.get_manager(j)
                for ei in mi.curves:
                    for ej in mj.curves:
                        self._try_auto_weld(ei, ej, wr, threshold)
        self.modified.emit()

    def _try_auto_weld(self, e0, e1, wr, threshold: float) -> None:
        """Weld two edges if their anchor pairs are within threshold."""
        p0, p1 = e0.points, e1.points
        if any(p is None for p in (p0[0], p0[3], p1[0], p1[3])):
            return
        dist_same = (math.hypot(p0[0].pos.x()-p1[0].pos.x(), p0[0].pos.y()-p1[0].pos.y()) +
                     math.hypot(p0[3].pos.x()-p1[3].pos.x(), p0[3].pos.y()-p1[3].pos.y()))
        dist_rev  = (math.hypot(p0[0].pos.x()-p1[3].pos.x(), p0[0].pos.y()-p1[3].pos.y()) +
                     math.hypot(p0[3].pos.x()-p1[0].pos.x(), p0[3].pos.y()-p1[0].pos.y()))
        if min(dist_same, dist_rev) > threshold * 2:
            return
        dx0 = p0[3].pos.x()-p0[0].pos.x(); dy0 = p0[3].pos.y()-p0[0].pos.y()
        dx1 = p1[3].pos.x()-p1[0].pos.x(); dy1 = p1[3].pos.y()-p1[0].pos.y()
        dot = dx0*dx1 + dy0*dy1
        reversed_ = (dot < 0) if abs(dist_same - dist_rev) < 1.0 else (dist_rev < dist_same)
        pa0, pa3 = p0[0], p0[3]
        pb0 = p1[3] if reversed_ else p1[0]
        pb3 = p1[0] if reversed_ else p1[3]
        if (pb0 in wr.get_linked(pa0) and pb3 in wr.get_linked(pa3)):
            return
        for pa, pb in ((pa0, pb0), (pa3, pb3)):
            mp = QPointF((pa.pos.x() + pb.pos.x()) / 2, (pa.pos.y() + pb.pos.y()) / 2)
            pa.pos = QPointF(mp); pa.set_orig_to_pos()
            pb.pos = QPointF(mp); pb.set_orig_to_pos()
            wr.register_weld(pa, pb)

    # ── auto-weld on drag ─────────────────────────────────────────────────────

    def set_auto_weld_enabled(self, enabled: bool) -> None:
        self._auto_weld_enabled = enabled
        if not enabled:
            self.clear_pending_weld()

    def clear_pending_weld(self) -> None:
        """Clear purple weld-preview highlights and pending pairs."""
        seen: set[int] = set()
        for e0, e1 in self._pending_weld_pairs:
            for e in (e0, e1):
                if id(e.manager) not in seen:
                    seen.add(id(e.manager))
                    e.manager.weldable_edge_indices.clear()
        self._pending_weld_pairs.clear()

    def _are_edges_weldable_for_pair(self, e0, e1) -> bool:
        """Drag-weld proximity check (tighter than manual weld):
        midpoints ≤60px, direction |dot|>0.85, endpoint pair ≤100px.
        Mirrors Java areEdgesWeldableForPair().
        """
        if e0.manager is e1.manager:
            return False
        if (e0.curve_index >= len(e0.manager.curves) or
                e1.curve_index >= len(e1.manager.curves)):
            return False
        p0 = e0.manager.curves[e0.curve_index].points
        p1 = e1.manager.curves[e1.curve_index].points
        if any(pt is None for pt in (p0[0], p0[3], p1[0], p1[3])):
            return False
        # Midpoint proximity ≤ 60px
        mid0x = (p0[0].pos.x() + p0[3].pos.x()) / 2
        mid0y = (p0[0].pos.y() + p0[3].pos.y()) / 2
        mid1x = (p1[0].pos.x() + p1[3].pos.x()) / 2
        mid1y = (p1[0].pos.y() + p1[3].pos.y()) / 2
        if math.hypot(mid0x - mid1x, mid0y - mid1y) > 60:
            return False
        # Direction parallelism: |dot| > 0.85
        dx0 = p0[3].pos.x() - p0[0].pos.x(); dy0 = p0[3].pos.y() - p0[0].pos.y()
        dx1 = p1[3].pos.x() - p1[0].pos.x(); dy1 = p1[3].pos.y() - p1[0].pos.y()
        len0 = math.hypot(dx0, dy0); len1 = math.hypot(dx1, dy1)
        if len0 < 1 or len1 < 1:
            return False
        if abs((dx0 * dx1 + dy0 * dy1) / (len0 * len1)) <= 0.85:
            return False
        # Endpoint pair ≤ 100px total
        dist_same = (math.hypot(p0[0].pos.x()-p1[0].pos.x(), p0[0].pos.y()-p1[0].pos.y()) +
                     math.hypot(p0[3].pos.x()-p1[3].pos.x(), p0[3].pos.y()-p1[3].pos.y()))
        dist_rev  = (math.hypot(p0[0].pos.x()-p1[3].pos.x(), p0[0].pos.y()-p1[3].pos.y()) +
                     math.hypot(p0[3].pos.x()-p1[0].pos.x(), p0[3].pos.y()-p1[0].pos.y()))
        return min(dist_same, dist_rev) <= 100

    def check_drag_weld(self) -> None:
        """During polygon drag: detect qualifying edge pairs and show purple highlight.
        Mirrors Java checkDragWeld().
        """
        self.clear_pending_weld()
        sel_set = set(id(m) for m in self.selected_polygons)
        tot = self.polygon_manager.polygon_count

        for sel_mgr in self.selected_polygons:
            for si in range(len(sel_mgr.curves)):
                for ni in range(tot):
                    n_mgr = self.polygon_manager.get_manager(ni)
                    if id(n_mgr) in sel_set:
                        continue
                    for nj in range(len(n_mgr.curves)):
                        e0 = SelectedEdge(sel_mgr, si)
                        e1 = SelectedEdge(n_mgr, nj)
                        if self._are_edges_weldable_for_pair(e0, e1):
                            self._pending_weld_pairs.append((e0, e1))

        # Apply purple highlight to every involved manager+edge
        highlights: dict[int, tuple] = {}  # id(mgr) → (mgr, set of indices)
        for e0, e1 in self._pending_weld_pairs:
            for e in (e0, e1):
                if id(e.manager) not in highlights:
                    highlights[id(e.manager)] = (e.manager, set())
                highlights[id(e.manager)][1].add(e.curve_index)
        for mgr, idxs in highlights.values():
            mgr.weldable_edge_indices = idxs

    def _snap_point_to_pos(self, pt: CubicPoint, pos: QPointF,
                           processed: set[int]) -> None:
        """BFS flood-fill: move pt and all weld-linked partners to pos.
        Mirrors Java snapPointToPos().
        """
        from collections import deque as _deque
        wr = self.polygon_manager.weld_registry
        queue = _deque([pt])
        while queue:
            p = queue.popleft()
            if id(p) in processed:
                continue
            processed.add(id(p))
            p.pos = QPointF(pos)
            p.set_orig_to_pos()
            for linked in wr.get_linked(p):
                queue.append(linked)

    def _execute_drag_weld(self, e0, e1) -> None:
        """Snap and register a single qualifying edge pair.
        Mirrors Java executeDragWeld().
        """
        wr = self.polygon_manager.weld_registry
        p0 = e0.manager.curves[e0.curve_index].points
        p1 = e1.manager.curves[e1.curve_index].points

        dx0 = p0[3].pos.x() - p0[0].pos.x(); dy0 = p0[3].pos.y() - p0[0].pos.y()
        dx1 = p1[3].pos.x() - p1[0].pos.x(); dy1 = p1[3].pos.y() - p1[0].pos.y()
        dot = dx0 * dx1 + dy0 * dy1
        dist_same = (math.hypot(p0[0].pos.x()-p1[0].pos.x(), p0[0].pos.y()-p1[0].pos.y()) +
                     math.hypot(p0[3].pos.x()-p1[3].pos.x(), p0[3].pos.y()-p1[3].pos.y()))
        dist_rev  = (math.hypot(p0[0].pos.x()-p1[3].pos.x(), p0[0].pos.y()-p1[3].pos.y()) +
                     math.hypot(p0[3].pos.x()-p1[0].pos.x(), p0[3].pos.y()-p1[0].pos.y()))
        reversed_ = (dot < 0) if abs(dist_same - dist_rev) < 1.0 else (dist_rev < dist_same)

        pa0, pa3   = p0[0], p0[3]
        pb0        = p1[3] if reversed_ else p1[0]
        pb3        = p1[0] if reversed_ else p1[3]
        pc0n, pc0f = p0[1], p0[2]
        pc1n       = p1[2] if reversed_ else p1[1]
        pc1f       = p1[1] if reversed_ else p1[2]

        m0  = QPointF((pa0.pos.x() + pb0.pos.x()) / 2, (pa0.pos.y() + pb0.pos.y()) / 2)
        m3  = QPointF((pa3.pos.x() + pb3.pos.x()) / 2, (pa3.pos.y() + pb3.pos.y()) / 2)
        cm0 = QPointF((pc0n.pos.x() + pc1n.pos.x()) / 2, (pc0n.pos.y() + pc1n.pos.y()) / 2)
        cm3 = QPointF((pc0f.pos.x() + pc1f.pos.x()) / 2, (pc0f.pos.y() + pc1f.pos.y()) / 2)

        processed: set[int] = set()
        self._snap_point_to_pos(pa0, m0, processed)
        self._snap_point_to_pos(pb0, m0, processed)
        self._snap_point_to_pos(pa3, m3, processed)
        self._snap_point_to_pos(pb3, m3, processed)
        self._snap_point_to_pos(pc0n, cm0, processed)
        self._snap_point_to_pos(pc1n, cm0, processed)
        self._snap_point_to_pos(pc0f, cm3, processed)
        self._snap_point_to_pos(pc1f, cm3, processed)

        wr.register_weld(pa0, pb0); wr.register_weld(pa3, pb3)
        wr.register_weld(pc0n, pc1n); wr.register_weld(pc0f, pc1f)
        e0.manager.weldable_edge_indices.discard(e0.curve_index)
        e1.manager.weldable_edge_indices.discard(e1.curve_index)

    def execute_pending_welds(self) -> None:
        """On mouse release: snap all pending weld pairs and register links.
        Mirrors Java mouseReleased() auto-weld block.
        """
        if not self._pending_weld_pairs:
            return
        self.take_undo_snapshot()
        for e0, e1 in self._pending_weld_pairs:
            self._execute_drag_weld(e0, e1)
        self._pending_weld_pairs.clear()
        self.modified.emit()

    # ── snap to grid ──────────────────────────────────────────────────────────

    def snap_to_grid(self, snap_control_points: bool = False) -> None:
        """
        Snap anchor points to the nearest 10-pixel grid.
        If snap_control_points is True, also reset control points to auto positions.
        When points are selected, only those anchors are affected; otherwise all
        anchors in the active layer are snapped.
        """
        self.take_undo_snapshot()
        wr = self.polygon_manager.weld_registry
        al = self.layer_manager.active_layer_id
        processed: set[int] = set()
        grid_step = GRIDWIDTH // 100  # 10px = fine grid cell (100×100 visible squares)

        # Build a set of selected anchor ids when there is an active selection.
        # Control points in selected_points are ignored — snap only targets anchors.
        selected_ids: set[int] | None = None
        if self.selected_points:
            selected_ids = {id(p) for p in self.selected_points}

        def nearest_grid(val: float, step: int) -> float:
            return round(val / step) * step

        for mgr in self.polygon_manager.committed_managers():
            if mgr.layer_id != al:
                continue
            for cv in mgr.curves:
                anchor_snapped = False
                for idx in (0, 3):
                    pt = cv.points[idx]
                    if pt is None or id(pt) in processed:
                        continue
                    # With a selection, skip anchors not in it
                    if selected_ids is not None and id(pt) not in selected_ids:
                        continue
                    processed.add(id(pt))
                    snapped = QPointF(nearest_grid(pt.pos.x(), grid_step),
                                      nearest_grid(pt.pos.y(), grid_step))
                    pt.pos = snapped
                    pt.set_orig_to_pos()
                    anchor_snapped = True
                    # Propagate to welded partners
                    for linked in wr.get_linked(pt):
                        if id(linked) not in processed:
                            processed.add(id(linked))
                            linked.pos = QPointF(snapped)
                            linked.set_orig_to_pos()
                if snap_control_points:
                    # Reset handles only if this curve had an anchor snapped
                    # (or if there is no selection — all curves qualify)
                    if anchor_snapped or selected_ids is None:
                        if cv.points[0] and cv.points[3]:
                            cv.auto_control_points()
        self.modified.emit()

    # ── layer API ─────────────────────────────────────────────────────────────

    def set_active_layer(self, layer_id: int) -> None:
        self.layer_manager.set_active_layer_id(layer_id)
        self.polygon_manager.sync_active_drawing_manager_layer()
        self.layer_changed.emit()

    # ── selection mode setters ────────────────────────────────────────────────

    def set_polygon_selection_mode(self, enabled: bool,
                                   sub: SelectionSubMode = SelectionSubMode.RELATIONAL
                                   ) -> None:
        self.polygon_selection_mode = enabled
        self.poly_sub_mode = sub
        if not enabled:
            for m in self.selected_polygons:
                m.clear_all_highlights()
            self.selected_polygons.clear()
            for o in self.selected_ovals:
                o.selected = False
            self.selected_ovals.clear()
        self._clear_scope_highlight()

    def set_open_curve_selection_mode(self, enabled: bool) -> None:
        self.open_curve_selection_mode = enabled
        if not enabled:
            for m in self.selected_polygons:
                m.clear_all_highlights()
            self.selected_polygons.clear()
        self._clear_scope_highlight()

    def set_edge_selection_mode(self, enabled: bool,
                                sub: SelectionSubMode = SelectionSubMode.RELATIONAL
                                ) -> None:
        self.edge_selection_mode = enabled
        self.edge_sub_mode = sub
        if not enabled:
            self.selected_edges.clear()
            self._update_edge_highlights()
        self._clear_scope_highlight()

    def set_point_selection_mode(self, enabled: bool,
                                 sub: SelectionSubMode = SelectionSubMode.RELATIONAL
                                 ) -> None:
        self.point_selection_mode = enabled
        self.point_sub_mode = sub
        if not enabled:
            self.selected_points.clear()
            self._update_point_highlights()
        self._clear_scope_highlight()

    def any_selection_mode(self) -> bool:
        return (self.polygon_selection_mode or self.edge_selection_mode
                or self.point_selection_mode or self.open_curve_selection_mode)

    # ── selection click handlers (called from MouseHandler) ───────────────────

    def handle_polygon_selection_click(self, pos: QPointF) -> None:
        active_id = self.layer_manager.active_layer_id
        # Reset deferred click-through state (mirrors Java handlePolygonSelectionClick)
        self._polygon_click_candidate = None
        self._polygon_mouse_moved = False

        # Ovals first (drawn on top)
        for oval in reversed(self.oval_list):
            if oval.layer_id != active_id:
                continue
            if not oval.contains(pos.x(), pos.y()):
                continue
            if not oval.selected:
                oval.selected = True
                self.selected_ovals.append(oval)
            return

        # Closed polygons — topmost unselected first
        committed = self.polygon_manager.committed_managers()
        topmost = beneath = None
        for mgr in reversed(committed):
            if mgr.layer_id != active_id or not mgr.is_closed:
                continue
            if not mgr.contains_point(pos):
                continue
            if topmost is None:
                topmost = mgr
            elif beneath is None:
                beneath = mgr
                break

        if topmost is None:
            # Click on empty space — deselect all
            for m in self.selected_polygons:
                m.clear_all_highlights()
            self.selected_polygons.clear()
            for o in self.selected_ovals:
                o.selected = False
            self.selected_ovals.clear()
            return

        if not topmost.selected:
            # Unselected polygon → add to current selection (additive)
            topmost.selected = True
            topmost.selected_relational = (self.poly_sub_mode == SelectionSubMode.RELATIONAL)
            self.selected_polygons.append(topmost)
        elif beneath is not None and not beneath.selected:
            # Already-selected topmost with unselected polygon beneath:
            # defer adding beneath until mouseReleased so that dragging takes priority.
            self._polygon_click_candidate = beneath
        # else: already selected, nothing beneath → do nothing; keep selection for drag

    def handle_open_curve_selection_click(self, pos: QPointF) -> None:
        active_id = self.layer_manager.active_layer_id
        hit = None
        for mgr in reversed(self.polygon_manager.committed_managers()):
            if mgr.is_closed or mgr.layer_id != active_id:
                continue
            if mgr.near_open_curve(pos, 8.0):
                hit = mgr
                break

        if hit is None:
            # Click on empty space → deselect all
            for m in self.selected_polygons:
                m.clear_all_highlights()
            self.selected_polygons.clear()
            return

        if not hit.selected:
            hit.selected = True
            hit.selected_relational = False
            self.selected_polygons.append(hit)
        # already selected → do nothing; keep intact for dragging

    def handle_edge_scope_or_select(self, pos: QPointF, cmd_down: bool) -> None:
        # Scoped manager first
        if self.scoped_manager is not None:
            hit = self._find_nearest_edge_in_manager(pos, self.scoped_manager)
            if hit is not None:
                already = any(e.matches(hit) for e in self.selected_edges)
                if not already:
                    self._toggle_edge_selection(hit, cmd_down)
                    self._update_edge_highlights()
                return

        hit = self._find_nearest_edge(pos)
        if hit is not None:
            if self.scoped_manager is not hit.manager:
                self._clear_scope_highlight()
                self.scoped_manager = hit.manager
                hit.manager.scoped = True
            already = any(e.matches(hit) for e in self.selected_edges)
            if not already:
                self._toggle_edge_selection(hit, cmd_down)
                self._update_edge_highlights()
            return

        self._clear_scope_highlight()
        self.selected_edges.clear()
        self._update_edge_highlights()

    def handle_point_scope_or_select(self, pos: QPointF, cmd_down: bool) -> None:
        active_id = self.layer_manager.active_layer_id

        # Priority 1: point hit in scoped manager
        if self.scoped_manager is not None:
            ci, pi = self.scoped_manager.check_for_intersect(pos)
            if ci >= 0:
                pt = self.scoped_manager.curves[ci].points[pi]
                self._toggle_point_selection(pt, cmd_down)
                self._update_point_highlights()
                return

        # Priority 2: point hit in any active-layer manager
        for mgr in self.polygon_manager.committed_managers():
            if mgr.layer_id != active_id:
                continue
            ci, pi = mgr.check_for_intersect(pos)
            if ci >= 0:
                self._clear_scope_highlight()
                self.scoped_manager = mgr
                mgr.scoped = True
                pt = mgr.curves[ci].points[pi]
                self._toggle_point_selection(pt, cmd_down)
                self._update_point_highlights()
                return

        # Priority 3: click inside a polygon → scope it for next click
        self._clear_scope_highlight()
        if not cmd_down:
            self.selected_points.clear()
        for mgr in self.polygon_manager.committed_managers():
            if mgr.layer_id != active_id:
                continue
            if mgr.contains_point(pos):
                self.scoped_manager = mgr
                mgr.scoped = True
                self._update_point_highlights()
                return

        self._update_point_highlights()

    def finalize_rubber_band_selection(self) -> None:
        if not self.rubber_band_start or not self.rubber_band_end:
            return
        x1 = min(self.rubber_band_start.x(), self.rubber_band_end.x())
        y1 = min(self.rubber_band_start.y(), self.rubber_band_end.y())
        x2 = max(self.rubber_band_start.x(), self.rubber_band_end.x())
        y2 = max(self.rubber_band_start.y(), self.rubber_band_end.y())
        rect = QRectF(x1, y1, x2 - x1, y2 - y1)

        if self.point_selection_mode:
            self._select_points_in_rect(rect)
            self._update_point_highlights()
        elif self.edge_selection_mode:
            self._select_edges_in_rect(rect)
            self._update_edge_highlights()
        elif self.polygon_selection_mode:
            self._select_polygons_in_rect(rect)
        elif self.open_curve_selection_mode:
            self._select_open_curves_in_rect(rect)

        self.push_selection_to_history()

    # ── rect selection helpers ────────────────────────────────────────────────

    def _select_points_in_rect(self, rect: QRectF) -> None:
        active_id = self.layer_manager.active_layer_id
        seen: set[int] = set()
        for mgr in self.polygon_manager.committed_managers():
            if mgr.layer_id != active_id:
                continue
            for cv in mgr.curves:
                for pt in cv.points:
                    if pt is None or id(pt) in seen:
                        continue
                    seen.add(id(pt))
                    if rect.contains(pt.pos) and pt not in self.selected_points:
                        self.selected_points.append(pt)

    def _select_edges_in_rect(self, rect: QRectF) -> None:
        active_id = self.layer_manager.active_layer_id
        for mgr in self.polygon_manager.committed_managers():
            if mgr.layer_id != active_id:
                continue
            for j, cv in enumerate(mgr.curves):
                pts = cv.points
                if pts[0] is None or pts[3] is None:
                    continue
                mx = (pts[0].pos.x() + pts[3].pos.x()) / 2.0
                my = (pts[0].pos.y() + pts[3].pos.y()) / 2.0
                if rect.contains(QPointF(mx, my)):
                    e = SelectedEdge(mgr, j)
                    if not any(ex.matches(e) for ex in self.selected_edges):
                        self.selected_edges.append(e)

    def _select_polygons_in_rect(self, rect: QRectF) -> None:
        active_id = self.layer_manager.active_layer_id
        for mgr in self.polygon_manager.committed_managers():
            if not mgr.is_closed or mgr.layer_id != active_id:
                continue
            c = mgr.get_average_xy()
            if rect.contains(c) and not mgr.selected:
                mgr.selected = True
                mgr.selected_relational = (self.poly_sub_mode == SelectionSubMode.RELATIONAL)
                self.selected_polygons.append(mgr)
        for oval in self.oval_list:
            if rect.contains(QPointF(oval.cx, oval.cy)) and not oval.selected:
                oval.selected = True
                self.selected_ovals.append(oval)

    def _select_open_curves_in_rect(self, rect: QRectF) -> None:
        active_id = self.layer_manager.active_layer_id
        for mgr in self.polygon_manager.committed_managers():
            if mgr.is_closed or mgr.layer_id != active_id:
                continue
            c = mgr.get_average_xy()
            if rect.contains(c) and not mgr.selected:
                mgr.selected = True
                self.selected_polygons.append(mgr)

    # ── edge hit-test helpers ─────────────────────────────────────────────────

    def _find_nearest_edge(self, pos: QPointF,
                           threshold: float = 15.0) -> SelectedEdge | None:
        active_id = self.layer_manager.active_layer_id
        best_dist = threshold
        best: SelectedEdge | None = None
        for mgr in self.polygon_manager.committed_managers():
            if mgr.layer_id != active_id:
                continue
            e = self._find_nearest_edge_in_manager(pos, mgr, best_dist)
            if e is not None:
                d = CubicCurveManager.distance_to_edge(pos, mgr.curves[e.curve_index])
                if d < best_dist:
                    best_dist = d
                    best = e
        return best

    def _find_nearest_edge_in_manager(self, pos: QPointF, mgr: CubicCurveManager,
                                      threshold: float = 15.0) -> SelectedEdge | None:
        best_dist = threshold
        best_idx  = -1
        for j, cv in enumerate(mgr.curves):
            d = CubicCurveManager.distance_to_edge(pos, cv)
            if d < best_dist:
                best_dist = d
                best_idx  = j
        return SelectedEdge(mgr, best_idx) if best_idx >= 0 else None

    # ── selection toggle helpers ──────────────────────────────────────────────

    def _toggle_point_selection(self, pt: CubicPoint, cmd_down: bool) -> None:
        if pt in self.selected_points:
            if cmd_down:
                self.selected_points.remove(pt)
        else:
            if not cmd_down:
                self.selected_points.clear()
            self.selected_points.append(pt)

    def _toggle_edge_selection(self, edge: SelectedEdge, cmd_down: bool) -> None:
        # Edge selection is always additive; click on selected edge to deselect it.
        # Click empty space (handled in handle_edge_scope_or_select) clears all.
        for i, e in enumerate(self.selected_edges):
            if e.matches(edge):
                self.selected_edges.pop(i)
                return
        self.selected_edges.append(edge)

    # ── highlight sync ────────────────────────────────────────────────────────

    def _update_point_highlights(self) -> None:
        for mgr in self.polygon_manager.all_managers():
            mgr.discrete_points.clear()
            mgr.relational_points.clear()
        if not self.selected_points:
            return
        for pt in self.selected_points:
            owner = self._find_manager_for_point(pt)
            if owner is None:
                continue
            if self.point_sub_mode == SelectionSubMode.RELATIONAL:
                owner.relational_points.add(pt)
            else:
                owner.discrete_points.add(pt)

    def _update_edge_highlights(self) -> None:
        for mgr in self.polygon_manager.committed_managers():
            mgr.discrete_edge_indices.clear()
            mgr.relational_edge_indices.clear()
            mgr.weldable_edge_indices.clear()
        weldable = self._are_edges_weldable()
        for edge in self.selected_edges:
            if weldable:
                edge.manager.weldable_edge_indices.add(edge.curve_index)
            elif self.edge_sub_mode == SelectionSubMode.RELATIONAL:
                edge.manager.relational_edge_indices.add(edge.curve_index)
            else:
                edge.manager.discrete_edge_indices.add(edge.curve_index)

    def _clear_scope_highlight(self) -> None:
        if self.scoped_manager is not None:
            self.scoped_manager.scoped = False
            self.scoped_manager = None

    def _find_manager_for_point(self, pt: CubicPoint) -> CubicCurveManager | None:
        for mgr in self.polygon_manager.all_managers():
            for cv in mgr.curves:
                if pt in cv.points:
                    return mgr
        return None

    # ── selection history ─────────────────────────────────────────────────────

    def deselect_all(self) -> None:
        self.selected_points.clear()
        self.selected_edges.clear()
        for m in self.selected_polygons:
            m.clear_all_highlights()
        self.selected_polygons.clear()
        for o in self.selected_ovals:
            o.selected = False
        self.selected_ovals.clear()
        self._polygon_click_candidate = None
        self._polygon_mouse_moved = False
        self._clear_scope_highlight()
        self._update_point_highlights()
        self._update_edge_highlights()

    def push_selection_to_history(self) -> None:
        if self._navigating_history:
            return
        if (not self.selected_points and not self.selected_edges
                and not self.selected_polygons and not self.selected_ovals):
            return
        current_layer = self.layer_manager.active_layer_id
        if current_layer != self._history_layer_id:
            self.clear_selection_history()
        # Truncate forward entries when a new selection is made mid-navigation
        if (0 <= self._sel_history_cursor
                < len(self._sel_history) - 1):
            tail = len(self._sel_history) - self._sel_history_cursor - 1
            for _ in range(tail):
                self._sel_history.pop()
        snap = SelectionSnapshot(
            points   = list(self.selected_points),
            edges    = list(self.selected_edges),
            polygons = list(self.selected_polygons),
            ovals    = list(self.selected_ovals),
        )
        # Skip if identical to the last entry
        if self._sel_history:
            last = self._sel_history[-1]
            if (set(id(p) for p in last.points) == set(id(p) for p in snap.points)
                    and set(id(p) for p in last.polygons) == set(id(p) for p in snap.polygons)
                    and len(last.edges) == len(snap.edges)
                    and set(id(o) for o in last.ovals) == set(id(o) for o in snap.ovals)):
                return
        self._sel_history.append(snap)
        self._sel_history_cursor = len(self._sel_history) - 1

    def navigate_selection_back(self) -> None:
        if self._sel_history_cursor <= 0:
            return
        self._sel_history_cursor -= 1
        self._restore_selection_snapshot(self._sel_history[self._sel_history_cursor])

    def navigate_selection_forward(self) -> None:
        if self._sel_history_cursor >= len(self._sel_history) - 1:
            return
        self._sel_history_cursor += 1
        self._restore_selection_snapshot(self._sel_history[self._sel_history_cursor])

    def clear_selection_history(self) -> None:
        self._sel_history.clear()
        self._sel_history_cursor = -1
        self._history_layer_id = self.layer_manager.active_layer_id

    def _restore_selection_snapshot(self, snap: SelectionSnapshot) -> None:
        self._navigating_history = True
        self.deselect_all()
        active_id = self.layer_manager.active_layer_id
        if self.polygon_selection_mode:
            for m in snap.polygons:
                if m.is_closed and m.layer_id == active_id:
                    m.selected = True
                    m.selected_relational = (self.poly_sub_mode == SelectionSubMode.RELATIONAL)
                    self.selected_polygons.append(m)
            for o in snap.ovals:
                if o.layer_id == active_id:
                    o.selected = True
                    self.selected_ovals.append(o)
        elif self.open_curve_selection_mode:
            for m in snap.polygons:
                if not m.is_closed and m.layer_id == active_id:
                    m.selected = True
                    self.selected_polygons.append(m)
        elif self.edge_selection_mode:
            self.selected_edges.extend(snap.edges)
            self._update_edge_highlights()
        elif self.point_selection_mode:
            self.selected_points.extend(snap.points)
            self._update_point_highlights()
        self._navigating_history = False

    # ── transform helpers (layer-aware targets) ───────────────────────────────

    def _managers_in_layer(self, layer_id: int) -> list[CubicCurveManager]:
        return [m for m in self.polygon_manager.committed_managers()
                if m.layer_id == layer_id]

    def _ovals_in_layer(self, layer_id: int) -> list:
        return [o for o in self.oval_list if o.layer_id == layer_id]

    # ── drag-translate (called from mouse_handler.drag) ───────────────────────

    def translate_selected_points_by_delta(self, dx: float, dy: float) -> None:
        """Cumulative per-frame delta; commits origPos each step (drag-move).
        In RELATIONAL point mode, weld-linked partners also move.
        """
        relational = (self.point_selection_mode
                      and self.point_sub_mode == SelectionSubMode.RELATIONAL)
        wr = self.polygon_manager.weld_registry if relational else None
        moved: set[int] = set()
        for pt in self.selected_points:
            if id(pt) in moved:
                continue
            moved.add(id(pt))
            pt.pos = QPointF(pt.pos.x() + dx, pt.pos.y() + dy)
            pt.set_orig_to_pos()
            if wr is not None:
                for linked in wr.get_linked(pt):
                    if id(linked) in moved:
                        continue
                    moved.add(id(linked))
                    linked.pos = QPointF(linked.pos.x() + dx, linked.pos.y() + dy)
                    linked.set_orig_to_pos()

    def translate_edges_by(self, dx: float, dy: float) -> None:
        """Move all 4 points of each selected edge + adjacent control points."""
        moved: set[int] = set()
        for edge in self.selected_edges:
            mgr = edge.manager
            if edge.curve_index >= len(mgr.curves):
                continue
            cv = mgr.curves[edge.curve_index]
            for pt in cv.points:
                if pt is None or id(pt) in moved:
                    continue
                moved.add(id(pt))
                pt.pos = QPointF(pt.pos.x() + dx, pt.pos.y() + dy)
                pt.set_orig_to_pos()
            # Propagate to adjacent control points for tangent continuity
            n = len(mgr.curves)
            if n > 1:
                prev_i = (edge.curve_index - 1) % n
                next_i = (edge.curve_index + 1) % n
                for adj_pt in (mgr.curves[prev_i].points[2],
                               mgr.curves[next_i].points[1]):
                    if adj_pt is not None and id(adj_pt) not in moved:
                        moved.add(id(adj_pt))
                        adj_pt.pos = QPointF(adj_pt.pos.x() + dx, adj_pt.pos.y() + dy)
                        adj_pt.set_orig_to_pos()

    def _build_ctrl_map(self) -> dict:
        """Map each anchor-point id → list of its immediately adjacent control
        points across all managers.

        When a weld-linked anchor is moved by a RELATIONAL transform, we also
        move its adjacent control points so bezier curve shapes deform smoothly
        instead of kinking at the moved anchor.  Only the immediate controls
        are moved; the far anchors of adjacent polygons remain fixed.
        """
        ctrl_map: dict[int, list] = {}
        for m in self.polygon_manager.committed_managers():
            for cv in m.curves:
                # Anchor at index 0 → its outgoing control is index 1
                if cv.points[0] is not None and cv.points[1] is not None:
                    ctrl_map.setdefault(id(cv.points[0]), []).append(cv.points[1])
                # Anchor at index 3 → its incoming control is index 2
                if cv.points[3] is not None and cv.points[2] is not None:
                    ctrl_map.setdefault(id(cv.points[3]), []).append(cv.points[2])
        return ctrl_map

    def translate_polygon_by(self, mgr: CubicCurveManager,
                             dx: float, dy: float, moved: set[int]) -> None:
        """Translate a single manager.  In RELATIONAL polygon mode, weld-linked
        anchors on adjacent polygons also move (BFS through the weld registry),
        and each moved anchor drags its immediately adjacent control points so
        bezier shapes deform gracefully rather than kinking.
        """
        relational = (self.polygon_selection_mode
                      and self.poly_sub_mode == SelectionSubMode.RELATIONAL)
        wr = self.polygon_manager.weld_registry if relational else None
        ctrl_map = self._build_ctrl_map() if wr is not None else {}

        for cv in mgr.curves:
            for pt in cv.points:
                if pt is None or id(pt) in moved:
                    continue
                # BFS: move this point, follow weld links, and pull each linked
                # anchor's adjacent control points along with it.
                queue = deque([pt])
                while queue:
                    cur = queue.popleft()
                    if id(cur) in moved:
                        continue
                    moved.add(id(cur))
                    cur.pos = QPointF(cur.pos.x() + dx, cur.pos.y() + dy)
                    cur.set_orig_to_pos()
                    if wr is not None:
                        for linked in wr.get_linked(cur):
                            if id(linked) not in moved:
                                queue.append(linked)
                                # Also drag the control points adjacent to
                                # this linked anchor so curves stay smooth.
                                for ctrl in ctrl_map.get(id(linked), []):
                                    if id(ctrl) not in moved:
                                        queue.append(ctrl)

    # ── slider-based scale ────────────────────────────────────────────────────

    def set_scale_target(self, target: int) -> None:
        """Set which point types are affected by the scale slider (SCALE_TARGET_*)."""
        self._scale_target = target

    def scale_xy(self, scale: float, axis: int = SCALE_XY) -> None:
        """
        scale: [-100, 100] → factor = 1 + scale/100
        axis: SCALE_XY / SCALE_X / SCALE_Y
        """
        if self._scale_rotate_snapshot_pending:
            self.take_undo_snapshot()
            self._scale_rotate_snapshot_pending = False
            # Freeze ovals at gesture start
            oval_targets = (self.selected_ovals if self.selected_ovals
                            else ([] if (self.polygon_selection_mode
                                         or self.open_curve_selection_mode)
                                  else self.oval_list))
            for o in oval_targets:
                o.freeze_orig()

        factor = 1.0 + scale / 100.0
        do_x = (axis != SCALE_Y)
        do_y = (axis != SCALE_X)

        if self.point_selection_mode:
            if self.selected_points:
                self._scale_selected_points(factor)
            return
        if self.edge_selection_mode:
            if self.selected_edges:
                self._scale_selected_edges(factor, do_x, do_y)
            return

        targets = (self.selected_polygons if self.selected_polygons
                   else ([] if (self.polygon_selection_mode
                                or self.open_curve_selection_mode)
                         else self.polygon_manager.committed_managers()))
        oval_targets = (self.selected_ovals if self.selected_ovals
                        else ([] if (self.polygon_selection_mode
                                     or self.open_curve_selection_mode)
                              else self.oval_list))

        # Shared pivot in RELATIONAL polygon mode
        relational = (self.polygon_selection_mode
                      and self.poly_sub_mode == SelectionSubMode.RELATIONAL
                      and bool(self.selected_polygons))
        shared_cx = shared_cy = 0.0
        if relational and targets:
            cnt = 0
            for m in targets:
                if m.curves:
                    c = m.get_average_xy_from_orig()
                    shared_cx += c.x(); shared_cy += c.y(); cnt += 1
            if cnt:
                shared_cx /= cnt; shared_cy /= cnt

        wr = self.polygon_manager.weld_registry if relational else None
        ctrl_map = self._build_ctrl_map() if wr is not None else {}
        processed: set[int] = set()
        for mgr in targets:
            if not mgr.curves:
                continue
            if relational:
                cx, cy = shared_cx, shared_cy
            else:
                c = mgr.get_average_xy_from_orig()
                cx, cy = c.x(), c.y()
            for cv in mgr.curves:
                for pt in cv.points:
                    if pt is None or id(pt) in processed:
                        continue
                    # BFS: scale this point, follow weld links, and also scale
                    # each linked anchor's adjacent control points.
                    queue = deque([pt])
                    while queue:
                        cur = queue.popleft()
                        if id(cur) in processed:
                            continue
                        processed.add(id(cur))
                        # Respect scale target: skip moving the wrong point type
                        # but still mark as processed so BFS weld-links work.
                        is_anchor  = (cur.type == PointType.ANCHOR)
                        skip = ((self._scale_target == SCALE_TARGET_ANCHORS  and not is_anchor) or
                                (self._scale_target == SCALE_TARGET_CONTROLS and     is_anchor))
                        if not skip:
                            ox = cur.orig_pos.x() - cx
                            oy = cur.orig_pos.y() - cy
                            nx = ox * factor + cx if do_x else cur.orig_pos.x()
                            ny = oy * factor + cy if do_y else cur.orig_pos.y()
                            cur.pos = QPointF(nx, ny)
                        else:
                            cur.pos = QPointF(cur.orig_pos)
                        if wr is not None:
                            for linked in wr.get_linked(cur):
                                if id(linked) not in processed:
                                    queue.append(linked)
                                    for ctrl in ctrl_map.get(id(linked), []):
                                        if id(ctrl) not in processed:
                                            queue.append(ctrl)

        # Ovals: scale around their shared centroid
        if oval_targets:
            ocx = ocy = 0.0; cnt = 0
            for o in oval_targets:
                ocx += o.orig_cx; ocy += o.orig_cy; cnt += 1
            if cnt:
                ocx /= cnt; ocy /= cnt
                for o in oval_targets:
                    o.scale_xy_from_orig(factor, ocx, ocy)

    # ── slider-based rotate ───────────────────────────────────────────────────

    def rotate(self, degrees: float, axis_mode: int = ROTATE_LOCAL) -> None:
        if self._scale_rotate_snapshot_pending:
            self.take_undo_snapshot()
            self._scale_rotate_snapshot_pending = False

        if self.point_selection_mode and self.selected_points:
            self._rotate_selected_points(degrees, axis_mode)
            return
        if self.edge_selection_mode and self.selected_edges:
            self._rotate_selected_edges(degrees, axis_mode)
            return

        targets = (self.selected_polygons if self.selected_polygons
                   else ([] if (self.polygon_selection_mode
                                or self.open_curve_selection_mode)
                         else self.polygon_manager.committed_managers()))
        oval_targets = (self.selected_ovals if self.selected_ovals
                        else ([] if (self.polygon_selection_mode
                                     or self.open_curve_selection_mode)
                              else self.oval_list))

        abs_centre = QPointF(EDGE_OFFSET + GRIDWIDTH / 2.0,
                             EDGE_OFFSET + GRIDHEIGHT / 2.0)

        rot_processed: set[int] = set()
        if axis_mode == ROTATE_COMMON and targets:
            cx = cy = 0.0; cnt = 0
            for m in targets:
                if m.curves:
                    c = m.get_average_xy_from_orig()
                    cx += c.x(); cy += c.y(); cnt += 1
            pivot = QPointF(cx / cnt, cy / cnt) if cnt else abs_centre
            for m in targets:
                self._rotate_manager(m, degrees, pivot, rot_processed)
        elif axis_mode == ROTATE_ABSOLUTE:
            for m in targets:
                self._rotate_manager(m, degrees, abs_centre, rot_processed)
        else:  # ROTATE_LOCAL
            for m in targets:
                self._rotate_manager(m, degrees, m.get_average_xy_from_orig(),
                                     rot_processed)

        # Rotate ovals
        if oval_targets:
            if axis_mode == ROTATE_ABSOLUTE:
                pivot = abs_centre
            else:
                cx = cy = 0.0; cnt = 0
                for o in oval_targets:
                    cx += o.cx; cy += o.cy; cnt += 1
                pivot = QPointF(cx / cnt, cy / cnt) if cnt else abs_centre
            for o in oval_targets:
                o.rotate(degrees, pivot.x(), pivot.y())

    def _rotate_manager(self, mgr: CubicCurveManager,
                        degrees: float, pivot: QPointF,
                        processed: set[int] | None = None) -> None:
        if processed is None:
            processed = set()
        relational = (self.polygon_selection_mode
                      and self.poly_sub_mode == SelectionSubMode.RELATIONAL)
        wr = self.polygon_manager.weld_registry if relational else None
        ctrl_map = self._build_ctrl_map() if wr is not None else {}
        rad = math.radians(degrees)
        cos_r = math.cos(rad); sin_r = math.sin(rad)
        for cv in mgr.curves:
            for pt in cv.points:
                if pt is None or id(pt) in processed:
                    continue
                queue = deque([pt])
                while queue:
                    cur = queue.popleft()
                    if id(cur) in processed:
                        continue
                    processed.add(id(cur))
                    ox = cur.orig_pos.x() - pivot.x()
                    oy = cur.orig_pos.y() - pivot.y()
                    cur.pos = QPointF(ox * cos_r - oy * sin_r + pivot.x(),
                                     ox * sin_r + oy * cos_r + pivot.y())
                    if wr is not None:
                        for linked in wr.get_linked(cur):
                            if id(linked) not in processed:
                                queue.append(linked)
                                for ctrl in ctrl_map.get(id(linked), []):
                                    if id(ctrl) not in processed:
                                        queue.append(ctrl)

    # ── point/edge scale/rotate helpers ──────────────────────────────────────

    def _scale_selected_points(self, factor: float) -> None:
        if not self.selected_points:
            return
        # Centroid is always the centre of all selected points, regardless of
        # target mode, so the pivot stays stable when switching target.
        cx = sum(p.orig_pos.x() for p in self.selected_points) / len(self.selected_points)
        cy = sum(p.orig_pos.y() for p in self.selected_points) / len(self.selected_points)
        for pt in self.selected_points:
            is_anchor = (pt.type == PointType.ANCHOR)
            skip = ((self._scale_target == SCALE_TARGET_ANCHORS  and not is_anchor) or
                    (self._scale_target == SCALE_TARGET_CONTROLS and     is_anchor))
            if skip:
                pt.pos = QPointF(pt.orig_pos)
            else:
                ox = pt.orig_pos.x() - cx; oy = pt.orig_pos.y() - cy
                pt.pos = QPointF(ox * factor + cx, oy * factor + cy)

    def _rotate_selected_points(self, degrees: float, axis_mode: int) -> None:
        abs_c = QPointF(EDGE_OFFSET + GRIDWIDTH / 2.0, EDGE_OFFSET + GRIDHEIGHT / 2.0)
        if axis_mode == ROTATE_ABSOLUTE:
            pivot = abs_c
        else:
            cx = sum(p.orig_pos.x() for p in self.selected_points) / len(self.selected_points)
            cy = sum(p.orig_pos.y() for p in self.selected_points) / len(self.selected_points)
            pivot = QPointF(cx, cy)
        rad = math.radians(degrees)
        cos_r = math.cos(rad); sin_r = math.sin(rad)
        for pt in self.selected_points:
            ox = pt.orig_pos.x() - pivot.x(); oy = pt.orig_pos.y() - pivot.y()
            pt.pos = QPointF(ox * cos_r - oy * sin_r + pivot.x(),
                             ox * sin_r + oy * cos_r + pivot.y())

    def _scale_selected_edges(self, factor: float,
                              do_x: bool = True, do_y: bool = True) -> None:
        cx = cy = 0.0; cnt = 0
        for edge in self.selected_edges:
            if edge.curve_index >= len(edge.manager.curves):
                continue
            pts = edge.manager.curves[edge.curve_index].points
            for i in (0, 3):
                if pts[i]:
                    cx += pts[i].orig_pos.x(); cy += pts[i].orig_pos.y(); cnt += 1
        if cnt == 0:
            return
        cx /= cnt; cy /= cnt
        processed: set[int] = set()
        for edge in self.selected_edges:
            if edge.curve_index >= len(edge.manager.curves):
                continue
            for pt in edge.manager.curves[edge.curve_index].points:
                if pt is None or id(pt) in processed:
                    continue
                processed.add(id(pt))
                is_anchor = (pt.type == PointType.ANCHOR)
                skip = ((self._scale_target == SCALE_TARGET_ANCHORS  and not is_anchor) or
                        (self._scale_target == SCALE_TARGET_CONTROLS and     is_anchor))
                if skip:
                    pt.pos = QPointF(pt.orig_pos)
                else:
                    ox = pt.orig_pos.x() - cx; oy = pt.orig_pos.y() - cy
                    nx = ox * factor + cx if do_x else pt.orig_pos.x()
                    ny = oy * factor + cy if do_y else pt.orig_pos.y()
                    pt.pos = QPointF(nx, ny)

    def _rotate_selected_edges(self, degrees: float, axis_mode: int) -> None:
        abs_c = QPointF(EDGE_OFFSET + GRIDWIDTH / 2.0, EDGE_OFFSET + GRIDHEIGHT / 2.0)
        if axis_mode == ROTATE_ABSOLUTE:
            pivot = abs_c
        else:
            cx = cy = 0.0; cnt = 0
            for edge in self.selected_edges:
                if edge.curve_index >= len(edge.manager.curves):
                    continue
                pts = edge.manager.curves[edge.curve_index].points
                for i in (0, 3):
                    if pts[i]:
                        cx += pts[i].orig_pos.x(); cy += pts[i].orig_pos.y(); cnt += 1
            pivot = QPointF(cx / cnt, cy / cnt) if cnt else abs_c
        rad = math.radians(degrees)
        cos_r = math.cos(rad); sin_r = math.sin(rad)
        processed: set[int] = set()
        for edge in self.selected_edges:
            if edge.curve_index >= len(edge.manager.curves):
                continue
            for pt in edge.manager.curves[edge.curve_index].points:
                if pt is None or id(pt) in processed:
                    continue
                processed.add(id(pt))
                ox = pt.orig_pos.x() - pivot.x(); oy = pt.orig_pos.y() - pivot.y()
                pt.pos = QPointF(ox * cos_r - oy * sin_r + pivot.x(),
                                 ox * sin_r + oy * cos_r + pivot.y())

    # ── commit origPos after slider release ───────────────────────────────────

    def set_orig_pos_of_all_points_to_pos(self) -> None:
        """Commit all modified positions as new originals. Call on slider release."""
        seen: set[int] = set()
        for mgr in self.polygon_manager.all_managers():
            for cv in mgr.curves:
                for pt in cv.points:
                    if pt is not None and id(pt) not in seen:
                        seen.add(id(pt))
                        pt.set_orig_to_pos()
        self._scale_rotate_snapshot_pending = True

    # ── flip ──────────────────────────────────────────────────────────────────

    def perform_flip(self, horizontal: bool) -> None:
        self.take_undo_snapshot()
        al = self.layer_manager.active_layer_id
        targets = (self.selected_polygons if self.selected_polygons
                   else self._managers_in_layer(al))
        oval_targets = (self.selected_ovals if self.selected_ovals
                        else self._ovals_in_layer(al))

        cx = cy = 0.0; cnt = 0
        for m in targets:
            if m.curves:
                c = m.get_average_xy()
                cx += c.x(); cy += c.y(); cnt += 1
        for o in oval_targets:
            cx += o.cx; cy += o.cy; cnt += 1
        if cnt == 0:
            return
        cx /= cnt; cy /= cnt

        processed: set[int] = set()
        for m in targets:
            for cv in m.curves:
                for pt in cv.points:
                    if pt is None or id(pt) in processed:
                        continue
                    processed.add(id(pt))
                    if horizontal:
                        pt.pos = QPointF(2.0 * cx - pt.pos.x(), pt.pos.y())
                    else:
                        pt.pos = QPointF(pt.pos.x(), 2.0 * cy - pt.pos.y())
                    pt.set_orig_to_pos()
        for o in oval_targets:
            if horizontal:
                o.flip_h(cx)
            else:
                o.flip_v(cy)
        self.modified.emit()

    # ── centre ────────────────────────────────────────────────────────────────

    def perform_centre(self) -> None:
        self.take_undo_snapshot()
        canvas_centre = QPointF(EDGE_OFFSET + GRIDWIDTH / 2.0,
                                EDGE_OFFSET + GRIDHEIGHT / 2.0)
        al = self.layer_manager.active_layer_id
        targets = (self.selected_polygons if self.selected_polygons
                   else self._managers_in_layer(al))
        oval_targets = (self.selected_ovals if self.selected_ovals
                        else self._ovals_in_layer(al))

        cx = cy = 0.0; cnt = 0
        for m in targets:
            if m.curves:
                c = m.get_average_xy()
                cx += c.x(); cy += c.y(); cnt += 1
        for o in oval_targets:
            cx += o.cx; cy += o.cy; cnt += 1
        if cnt == 0:
            return
        dx = canvas_centre.x() - cx / cnt
        dy = canvas_centre.y() - cy / cnt

        moved: set[int] = set()
        for m in targets:
            for cv in m.curves:
                for pt in cv.points:
                    if pt is None or id(pt) in moved:
                        continue
                    moved.add(id(pt))
                    pt.pos = QPointF(pt.pos.x() + dx, pt.pos.y() + dy)
                    pt.set_orig_to_pos()
        for o in oval_targets:
            o.translate(dx, dy)
        self.modified.emit()

    # ── zoom ──────────────────────────────────────────────────────────────────

    def zoom_in(self) -> None:
        self.take_undo_snapshot()
        self._apply_zoom(1.25)

    def zoom_out(self) -> None:
        self.take_undo_snapshot()
        self._apply_zoom(0.8)

    def _apply_zoom(self, factor: float) -> None:
        pivot = self._get_zoom_pivot()
        processed: set[int] = set()
        for mgr in self.polygon_manager.committed_managers():
            for cv in mgr.curves:
                for pt in cv.points:
                    if pt is None or id(pt) in processed:
                        continue
                    processed.add(id(pt))
                    ox = pt.pos.x() - pivot.x()
                    oy = pt.pos.y() - pivot.y()
                    pt.pos = QPointF(ox * factor + pivot.x(),
                                     oy * factor + pivot.y())
                    pt.set_orig_to_pos()
        for o in self.oval_list:
            o.scale_xy_from_orig(factor, pivot.x(), pivot.y())
            o.freeze_orig()
        self.modified.emit()

    def _get_zoom_pivot(self) -> QPointF:
        canvas_centre = QPointF(EDGE_OFFSET + GRIDWIDTH / 2.0,
                                EDGE_OFFSET + GRIDHEIGHT / 2.0)
        if self.selected_points:
            cx = sum(p.pos.x() for p in self.selected_points) / len(self.selected_points)
            cy = sum(p.pos.y() for p in self.selected_points) / len(self.selected_points)
            return QPointF(cx, cy)
        if self.selected_edges:
            cx = cy = 0.0; cnt = 0
            for e in self.selected_edges:
                if e.curve_index >= len(e.manager.curves):
                    continue
                pts = e.manager.curves[e.curve_index].points
                if pts[0] and pts[3]:
                    cx += (pts[0].pos.x() + pts[3].pos.x()) / 2.0
                    cy += (pts[0].pos.y() + pts[3].pos.y()) / 2.0
                    cnt += 1
            if cnt:
                return QPointF(cx / cnt, cy / cnt)
        if self.selected_polygons:
            cx = cy = 0.0; cnt = 0
            for m in self.selected_polygons:
                if m.curves:
                    c = m.get_average_xy()
                    cx += c.x(); cy += c.y(); cnt += 1
            if cnt:
                return QPointF(cx / cnt, cy / cnt)
        return canvas_centre

    # ── undo / redo ───────────────────────────────────────────────────────────

    def take_undo_snapshot(self) -> None:
        snap = GeometrySnapshot.capture(
            self.polygon_manager,
            self.oval_list,
            self.point_list,
            self.point_pressures,
            self.layer_manager.active_layer_id,
        )
        self._undo_stack.append(snap)
        # A new edit invalidates any forward redo history.
        self._redo_stack.clear()

    def undo(self) -> None:
        if not self._undo_stack:
            return
        # Save current state so Redo can return to it.
        self._redo_stack.append(GeometrySnapshot.capture(
            self.polygon_manager, self.oval_list,
            self.point_list, self.point_pressures,
            self.layer_manager.active_layer_id,
        ))
        self._apply_snapshot(self._undo_stack.pop())

    def redo(self) -> None:
        if not self._redo_stack:
            return
        # Save current state so Undo can return to it.
        self._undo_stack.append(GeometrySnapshot.capture(
            self.polygon_manager, self.oval_list,
            self.point_list, self.point_pressures,
            self.layer_manager.active_layer_id,
        ))
        self._apply_snapshot(self._redo_stack.pop())

    def _apply_snapshot(self, snap: GeometrySnapshot) -> None:
        """Shared restore logic for both undo() and redo()."""
        self.clear_selection_history()
        self.deselect_all()
        self._drag_snapshot_pending_reset()
        self.polygon_manager.restore_snapshot(snap.managers)
        for m in self.polygon_manager.committed_managers():
            m.clear_all_highlights()
        self.point_list = list(snap.points)
        self.point_pressures = list(snap.pressures)
        from model.oval_manager import OvalManager as _OM
        self.oval_list.clear()
        self.selected_ovals.clear()
        for os in snap.ovals:
            o = _OM(os.cx, os.cy, os.rx, os.ry)
            o.layer_id = os.layer_id
            self.oval_list.append(o)
        self._scale_rotate_snapshot_pending = True
        self.modified.emit()

    def _drag_snapshot_pending_reset(self) -> None:
        """Tell mouse handler to allow a fresh undo snapshot on next drag."""
        self._mouse_handler._drag_snapshot_taken = False

    # ── clipboard ─────────────────────────────────────────────────────────────

    def copy_selected(self) -> None:
        """Copy selected polygons or edges to the internal clipboard."""
        self._clipboard.clear()
        if self.edge_selection_mode and self.selected_edges:
            for edge in self.selected_edges:
                if edge.curve_index >= len(edge.manager.curves):
                    continue
                cv = edge.manager.curves[edge.curve_index]
                pts = [QPointF(p.pos) for p in cv.points if p is not None]
                if len(pts) == 4:
                    self._clipboard.append((pts, False))
        else:
            for mgr in self.selected_polygons:
                pts: list[QPointF] = []
                for cv in mgr.curves:
                    for pt in cv.points:
                        pts.append(QPointF(pt.pos) if pt is not None
                                   else QPointF(0, 0))
                if pts:
                    self._clipboard.append((pts, mgr.is_closed))

    def paste(self) -> None:
        if not self._clipboard:
            return
        self.take_undo_snapshot()
        # Centroid of all clipboard points
        cx = cy = 0.0; cnt = 0
        for pts, _ in self._clipboard:
            for p in pts:
                cx += p.x(); cy += p.y(); cnt += 1
        if cnt == 0:
            return
        cx /= cnt; cy /= cnt
        dx = self.current_mouse_pos.x() - cx
        dy = self.current_mouse_pos.y() - cy
        active_id = self.layer_manager.active_layer_id
        for pts, is_closed in self._clipboard:
            off = [QPointF(p.x() + dx, p.y() + dy) for p in pts]
            if is_closed:
                self.polygon_manager.add_closed_from_points(off, active_id)
            else:
                self.polygon_manager.add_open_from_points(off, active_id)
        self.modified.emit()

    # ── delete / cut ──────────────────────────────────────────────────────────

    def delete_selected(self) -> None:
        """Remove selected polygons and ovals from the canvas."""
        if not (self.selected_polygons or self.selected_ovals
                or self.selected_points):
            return
        self.take_undo_snapshot()
        # Remove selected polygons
        remove_ids = {id(m) for m in self.selected_polygons}
        self.polygon_manager._managers = [
            m for m in self.polygon_manager._managers
            if id(m) not in remove_ids
        ]
        # Ensure the drawing manager is still at the end
        if not self.polygon_manager._managers:
            from model.cubic_curve_manager import CubicCurveManager as _CCM
            dm = _CCM()
            dm.layer_id = self.layer_manager.active_layer_id
            self.polygon_manager._managers.append(dm)
        elif self.polygon_manager._managers[-1].add_points is False:
            # Last manager is committed — append fresh drawing manager
            from model.cubic_curve_manager import CubicCurveManager as _CCM
            dm = _CCM()
            dm.layer_id = self.layer_manager.active_layer_id
            self.polygon_manager._managers.append(dm)
        # Remove selected ovals
        remove_oval_ids = {id(o) for o in self.selected_ovals}
        self.oval_list = [o for o in self.oval_list
                          if id(o) not in remove_oval_ids]
        self.deselect_all()
        self.modified.emit()

    def cut_selected(self) -> None:
        """Copy then delete selected geometry."""
        self.copy_selected()
        self.delete_selected()

    # ── select all ────────────────────────────────────────────────────────────

    def select_all(self) -> None:
        active_id = self.layer_manager.active_layer_id
        if self.polygon_selection_mode:
            for mgr in self.polygon_manager.committed_managers():
                if mgr.is_closed and mgr.layer_id == active_id and not mgr.selected:
                    mgr.selected = True
                    mgr.selected_relational = (
                        self.poly_sub_mode == SelectionSubMode.RELATIONAL)
                    self.selected_polygons.append(mgr)
            for o in self.oval_list:
                if o.layer_id == active_id and not o.selected:
                    o.selected = True
                    self.selected_ovals.append(o)
        elif self.open_curve_selection_mode:
            for mgr in self.polygon_manager.committed_managers():
                if not mgr.is_closed and mgr.layer_id == active_id and not mgr.selected:
                    mgr.selected = True
                    self.selected_polygons.append(mgr)
        elif self.edge_selection_mode:
            for mgr in self.polygon_manager.committed_managers():
                if mgr.layer_id != active_id:
                    continue
                for j in range(len(mgr.curves)):
                    e = SelectedEdge(mgr, j)
                    if not any(ex.matches(e) for ex in self.selected_edges):
                        self.selected_edges.append(e)
            self._update_edge_highlights()
        elif self.point_selection_mode:
            seen: set[int] = set()
            for mgr in self.polygon_manager.committed_managers():
                if mgr.layer_id != active_id:
                    continue
                for cv in mgr.curves:
                    for pt in cv.points:
                        if pt is not None and id(pt) not in seen:
                            seen.add(id(pt))
                            if pt not in self.selected_points:
                                self.selected_points.append(pt)
            self._update_point_highlights()
        self.push_selection_to_history()

    # ── XML load ──────────────────────────────────────────────────────────────

    def load_polygon_set(self, managers_data: list[dict]) -> None:
        active_id = self.layer_manager.active_layer_id
        pm = PolygonManager(self.layer_manager)
        pm._managers.clear()
        for item in managers_data:
            mgr = CubicCurveManager()
            mgr.layer_id = active_id
            if item['is_closed']:
                mgr.set_all_points(item['points'])
                mgr.is_closed = True
            else:
                mgr.set_open_points(item['points'])
            pm._managers.append(mgr)
        drawing = CubicCurveManager()
        drawing.layer_id = active_id
        pm._managers.append(drawing)
        self.polygon_manager = pm
        self.oval_list.clear()
        self.selected_ovals.clear()
        self.point_list.clear()
        self.point_pressures.clear()
        self.deselect_all()
        self.modified.emit()

    def append_polygon_set_to_layer(self, managers_data: list[dict],
                                    layer_id: int) -> None:
        insert_idx = len(self.polygon_manager._managers) - 1
        for item in managers_data:
            mgr = CubicCurveManager()
            mgr.layer_id = layer_id
            if item['is_closed']:
                mgr.set_all_points(item['points'])
                mgr.is_closed = True
            else:
                mgr.set_open_points(item['points'])
            self.polygon_manager._managers.insert(insert_idx, mgr)
            insert_idx += 1

    def load_oval_set(self, ovals: list[OvalManager]) -> None:
        active_id = self.layer_manager.active_layer_id
        for o in ovals:
            o.layer_id = active_id
        self.oval_list = list(ovals)
        self.selected_ovals.clear()
        self.polygon_manager = PolygonManager(self.layer_manager)
        self.point_list.clear()
        self.point_pressures.clear()
        self.deselect_all()
        self.modified.emit()

    def load_point_set(self, points: list[QPointF], pressures: list[float]) -> None:
        self.point_list = list(points)
        self.point_pressures = list(pressures)
        self.polygon_manager = PolygonManager(self.layer_manager)
        self.oval_list.clear()
        self.selected_ovals.clear()
        self.selected_discrete_point_index = -1
        self.point_mode = True
        self.deselect_all()
        self.modified.emit()

    # ── getters for IO ────────────────────────────────────────────────────────

    @property
    def grid_width(self) -> int:
        return GRIDWIDTH

    @property
    def grid_height(self) -> int:
        return GRIDHEIGHT

    @property
    def edge_offset(self) -> int:
        return EDGE_OFFSET
