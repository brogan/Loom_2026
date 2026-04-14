"""
MouseHandler — handles mouse events for BezierWidget.
Covers: curve drawing, handle drag, oval selection/drag, discrete point add/drag,
        and all 4 selection modes with rubber-band marquee.
"""
from __future__ import annotations
import math
from PySide6.QtCore import QPointF, Qt
from PySide6.QtGui import QMouseEvent

from model.cubic_curve_manager import CubicCurveManager
from model.cubic_point import CubicPoint, PointType
from model.oval_manager import OvalManager
from canvas.selection_state import SelectionSubMode

HIT_RADIUS   = 8.0   # px for bezier handle hit
POINT_RADIUS = 15.0  # px for discrete point hit


class MouseHandler:

    def __init__(self, widget) -> None:
        self._w = widget  # BezierWidget reference

        # ── bezier handle drag state ──────────────────────────────────────────
        self._dragging: bool = False
        self._curve_point_selected: bool = False
        self._selected_curve_idx: int = -1
        self._selected_point_idx: int = -1
        self._selected_manager: CubicCurveManager | None = None

        # ── oval drag state ───────────────────────────────────────────────────
        self._dragging_oval: OvalManager | None = None
        self._oval_drag_start_cx: float = 0.0
        self._oval_drag_start_cy: float = 0.0

        # ── oval creation drag state (oval mode) ──────────────────────────────
        self._oval_mode_start: QPointF | None = None
        self._oval_mode_oval: OvalManager | None = None

        # ── discrete point drag state ─────────────────────────────────────────
        self._dragging_discrete_point: bool = False

        # ── selection-mode drag snapshot (one undo per drag gesture) ──────────
        self._drag_snapshot_taken: bool = False

    # ── public interface ──────────────────────────────────────────────────────

    def press(self, event: QMouseEvent) -> None:
        pos = self._w.scale_mouse(event)
        w = self._w

        # In mesh build mode clicks have no geometry effect — hover drives selection
        if w.mesh_build_mode:
            w.current_mouse_pos = pos
            return

        mods  = event.modifiers()
        shift = bool(mods & Qt.KeyboardModifier.ShiftModifier)
        # On macOS Qt maps Cmd → ControlModifier (mirrors Java mE.isMetaDown())
        cmd   = bool(mods & Qt.KeyboardModifier.ControlModifier)

        # ── Oval mode: click sets centre, drag sets radius ────────────────────
        if w.oval_mode:
            w.take_undo_snapshot()
            ov = OvalManager(pos.x(), pos.y(), 1.0, 1.0)
            ov.layer_id = w.layer_manager.active_layer_id
            ov.selected = True
            for o in w.selected_ovals:
                o.selected = False
            w.selected_ovals.clear()
            w.oval_list.append(ov)
            w.selected_ovals.append(ov)
            self._oval_mode_start = QPointF(pos)
            self._oval_mode_oval  = ov
            w.oval_drag_active = True
            w.current_mouse_pos = pos
            return

        # ── Freehand mode ─────────────────────────────────────────────────────
        if w.freehand_mode:
            w.take_undo_snapshot()
            w._freehand_raw.clear()
            w._freehand_pressures.clear()
            w._freehand_raw.append(QPointF(pos))
            w._freehand_pressures.append(w._current_pressure)
            w._freehand_first = QPointF(pos)
            w._freehand_active = True
            w.current_mouse_pos = pos
            return

        # ── Knife mode ────────────────────────────────────────────────────────
        if w.knife_mode:
            w._knife_start = QPointF(pos)
            w._knife_end   = QPointF(pos)
            w.current_mouse_pos = pos
            return

        # ── Extrude trigger: Shift+press in edge mode with edges selected ─────
        if shift and w.edge_selection_mode and w.selected_edges:
            w._extrude_on_drag = True
            w.current_mouse_pos = pos
            return

        # ── Point mode: click to place / select a discrete point ──────────────
        if w.point_mode:
            hit = self._find_discrete_point(pos)
            if hit >= 0:
                w.selected_discrete_point_index = hit
                self._dragging_discrete_point = True
            else:
                w.selected_discrete_point_index = -1
                self._dragging_discrete_point = False
                w.point_list.append(QPointF(pos))
                w.point_pressures.append(w._current_pressure)
            w.current_mouse_pos = pos
            return

        # ── Selection modes ───────────────────────────────────────────────────
        if w.any_selection_mode():
            if shift:
                # Shift+press → start rubber-band marquee
                w.rubber_banding    = True
                w.rubber_band_start = QPointF(pos)
                w.rubber_band_end   = QPointF(pos)
            else:
                # Dispatch to the active mode's click handler
                if w.open_curve_selection_mode:
                    w.handle_open_curve_selection_click(pos)
                elif w.edge_selection_mode:
                    w.handle_edge_scope_or_select(pos, cmd)
                elif w.polygon_selection_mode:
                    w.handle_polygon_selection_click(pos)
                elif w.point_selection_mode:
                    dp_hit = self._find_discrete_point(pos)
                    if dp_hit >= 0:
                        w.selected_discrete_point_index = dp_hit
                    else:
                        w.selected_discrete_point_index = -1
                        w.handle_point_scope_or_select(pos, cmd)
            w.current_mouse_pos = pos
            return

        # ── Oval hit test ─────────────────────────────────────────────────────
        hit_oval = self._find_oval_at(pos)
        if hit_oval is not None:
            # Deselect all ovals, select this one
            for o in w.selected_ovals:
                o.selected = False
            w.selected_ovals.clear()
            hit_oval.selected = True
            w.selected_ovals.append(hit_oval)
            # Prepare for drag
            self._dragging_oval = hit_oval
            self._oval_drag_start_cx = hit_oval.cx
            self._oval_drag_start_cy = hit_oval.cy
            w.current_mouse_pos = pos
            self._dragging = False
            return

        # Click on empty space clears oval selection
        if w.selected_ovals:
            for o in w.selected_ovals:
                o.selected = False
            w.selected_ovals.clear()
            self._dragging_oval = None

        # ── Bezier handle hit test ────────────────────────────────────────────
        if not self._try_select_handle(pos):
            # No handle hit → snapshot + add an anchor point to the active drawing manager
            w.take_undo_snapshot()
            w.polygon_manager.set_point(pos)

        w.current_mouse_pos = pos
        self._dragging = False

    def drag(self, event: QMouseEvent) -> None:
        pos = self._w.scale_mouse(event)
        w = self._w

        # ── Freehand sampling ─────────────────────────────────────────────────
        if w.freehand_mode and w._freehand_active:
            if w._freehand_raw:
                last = w._freehand_raw[-1]
                dx = pos.x() - last.x(); dy = pos.y() - last.y()
                if math.sqrt(dx*dx + dy*dy) >= w._FREEHAND_MIN_STEP:
                    w._freehand_raw.append(QPointF(pos))
                    w._freehand_pressures.append(w._current_pressure)
            w.current_mouse_pos = pos
            return

        # ── Knife drag ────────────────────────────────────────────────────────
        if w.knife_mode and w._knife_start is not None:
            w._knife_end = QPointF(pos)
            w.current_mouse_pos = pos
            return

        # ── Oval mode: resize oval by dragging ────────────────────────────────
        if w.oval_mode and self._oval_mode_oval is not None:
            drx = pos.x() - self._oval_mode_start.x()
            dry = pos.y() - self._oval_mode_start.y()
            r   = math.sqrt(drx * drx + dry * dry)
            if r < 1.0:
                r = 1.0
            self._oval_mode_oval.rx = r
            self._oval_mode_oval.ry = r
            w.current_mouse_pos = pos
            return

        # ── Extrude drag ──────────────────────────────────────────────────────
        if w._extrude_on_drag or w._extruding:
            if not w._extruding:
                if not self._drag_snapshot_taken:
                    w.take_undo_snapshot()
                    self._drag_snapshot_taken = True
                w.start_extrude()
            dx = pos.x() - w.current_mouse_pos.x()
            dy = pos.y() - w.current_mouse_pos.y()
            moved: set[int] = set()
            for live in w._extrude_live_edges:
                w.translate_polygon_by(live, dx, dy, moved)
            w.current_mouse_pos = pos
            return

        # ── Rubber-band drag ──────────────────────────────────────────────────
        if w.rubber_banding:
            w.rubber_band_end   = QPointF(pos)
            w.current_mouse_pos = pos
            return

        dx = pos.x() - w.current_mouse_pos.x()
        dy = pos.y() - w.current_mouse_pos.y()
        diff = QPointF(dx, dy)

        # ── Selection-mode drag-translate ─────────────────────────────────────
        if w.point_selection_mode and w.selected_points:
            if not self._drag_snapshot_taken:
                w.take_undo_snapshot()
                self._drag_snapshot_taken = True
            w.translate_selected_points_by_delta(dx, dy)
            w.current_mouse_pos = pos
            return

        if w.edge_selection_mode and w.selected_edges:
            if not self._drag_snapshot_taken:
                w.take_undo_snapshot()
                self._drag_snapshot_taken = True
            w.translate_edges_by(dx, dy)
            w.current_mouse_pos = pos
            return

        if ((w.polygon_selection_mode or w.open_curve_selection_mode)
                and (w.selected_polygons or w.selected_ovals)):
            if not self._drag_snapshot_taken:
                w.take_undo_snapshot()
                self._drag_snapshot_taken = True
            w._polygon_mouse_moved = True   # suppress deferred click-through
            moved: set[int] = set()
            for mgr in w.selected_polygons:
                w.translate_polygon_by(mgr, dx, dy, moved)
            for o in w.selected_ovals:
                o.translate(dx, dy)
            # Auto-weld proximity check during polygon drag
            if w._auto_weld_enabled and w.polygon_selection_mode and w.selected_polygons:
                w.check_drag_weld()
            w.current_mouse_pos = pos
            return

        # ── Discrete point drag ───────────────────────────────────────────────
        if w.point_mode and self._dragging_discrete_point:
            idx = w.selected_discrete_point_index
            if 0 <= idx < len(w.point_list):
                w.point_list[idx] = QPointF(pos)
            w.current_mouse_pos = pos
            return

        # ── Oval drag ─────────────────────────────────────────────────────────
        if self._dragging_oval is not None:
            if not self._dragging:
                self._oval_drag_start_cx = self._dragging_oval.cx
                self._oval_drag_start_cy = self._dragging_oval.cy
                self._dragging = True
            self._dragging_oval.cx += diff.x()
            self._dragging_oval.cy += diff.y()
            w.current_mouse_pos = pos
            return

        # ── Bezier handle drag ────────────────────────────────────────────────
        if not self._dragging:
            self._freeze_all_positions()
            self._dragging = True

        if self._curve_point_selected:
            self._drag_selected_point(pos, diff)

        w.current_mouse_pos = pos

    def release(self, event: QMouseEvent) -> None:
        w = self._w

        # ── Oval mode: finalise created oval ──────────────────────────────────
        if w.oval_mode and self._oval_mode_oval is not None:
            if self._oval_mode_oval.rx < 5.0:
                # No meaningful drag — use default radius
                self._oval_mode_oval.rx = 1000.0 / 6.0
                self._oval_mode_oval.ry = 1000.0 / 6.0
            self._oval_mode_start = None
            self._oval_mode_oval  = None
            w.oval_drag_active = False
            w.modified.emit()
            return

        # ── Freehand release → fit and commit ─────────────────────────────────
        if w.freehand_mode and w._freehand_active:
            w.finalize_freehand()
            return

        # ── Knife release → perform cut ───────────────────────────────────────
        if w.knife_mode and w._knife_start is not None:
            w.execute_knife_cut()
            return

        # ── Extrude release → finalize quad ──────────────────────────────────
        if w._extruding:
            w.finalize_extrude()
            w._extruding = False
            w._extrude_on_drag = False
            self._drag_snapshot_taken = False
            return

        w._extrude_on_drag = False

        # ── Rubber-band release → finalise selection ──────────────────────────
        if w.rubber_banding:
            w.rubber_banding = False
            w.finalize_rubber_band_selection()
            w.rubber_band_start = None
            w.rubber_band_end   = None
            return

        self._dragging = False
        self._dragging_discrete_point = False
        self._dragging_oval = None
        self._drag_snapshot_taken = False

        if self._curve_point_selected and self._selected_manager is not None:
            self._commit_all_orig_positions()

        # Execute auto-weld pairs accumulated during polygon drag
        if w.polygon_selection_mode and w._auto_weld_enabled:
            w.execute_pending_welds()
        # Always clear any residual purple weld-preview highlights
        w.clear_pending_weld()
        for mgr in w.polygon_manager.committed_managers():
            mgr.weldable_edge_indices.clear()

        # Deferred click-through: add the polygon that was underneath the selected one,
        # but only if the user didn't drag (mirrors Java polygonClickCandidate logic).
        if w.polygon_selection_mode and w._polygon_click_candidate is not None:
            if not w._polygon_mouse_moved:
                c = w._polygon_click_candidate
                c.selected = True
                c.selected_relational = (w.poly_sub_mode == SelectionSubMode.RELATIONAL)
                w.selected_polygons.append(c)
            w._polygon_click_candidate = None
        w._polygon_mouse_moved = False

        # Push single-click selections to history
        if w.any_selection_mode():
            w.push_selection_to_history()

    def move(self, event: QMouseEvent) -> None:
        pos = self._w.scale_mouse(event)
        self._w.current_mouse_pos = pos
        if self._w.mesh_build_mode:
            self._w._mesh_hover_update(pos)
            self._w.update()

    # ── internal helpers ──────────────────────────────────────────────────────

    def _find_oval_at(self, pos: QPointF) -> OvalManager | None:
        """Return topmost oval whose ellipse contains pos, or None."""
        for oval in reversed(self._w.oval_list):
            if oval.contains(pos.x(), pos.y()):
                return oval
        return None

    def _find_discrete_point(self, pos: QPointF) -> int:
        """Return index of first discrete point within POINT_RADIUS, else -1."""
        r2 = POINT_RADIUS * POINT_RADIUS
        for i, pt in enumerate(self._w.point_list):
            dx = pt.x() - pos.x()
            dy = pt.y() - pos.y()
            if dx * dx + dy * dy <= r2:
                return i
        return -1

    def _try_select_handle(self, pos: QPointF) -> bool:
        """Look for a bezier handle near pos. Returns True if found."""
        for mgr in self._w.polygon_manager.all_managers():
            ci, pi = mgr.check_for_intersect(pos, HIT_RADIUS)
            if ci >= 0:
                self._curve_point_selected = True
                self._selected_curve_idx = ci
                self._selected_point_idx = pi
                self._selected_manager = mgr
                return True
        self._curve_point_selected = False
        self._selected_manager = None
        return False

    def _drag_selected_point(self, pos: QPointF, diff: QPointF) -> None:
        if self._selected_manager is None:
            return
        mgr = self._selected_manager
        if self._selected_curve_idx >= len(mgr.curves):
            return
        cv = mgr.curves[self._selected_curve_idx]
        pt = cv.points[self._selected_point_idx]
        if pt is None:
            return

        if pt.type == PointType.ANCHOR:
            self._drag_anchor(mgr, self._selected_curve_idx,
                              self._selected_point_idx, pos, diff)
        else:
            pt.drag(pos)

    def _drag_anchor(self, mgr: CubicCurveManager, ci: int, pi: int,
                     pos: QPointF, diff: QPointF) -> None:
        cv = mgr.curves[ci]
        anchor = cv.points[pi]
        anchor.drag(pos)
        n = len(mgr.curves)

        if pi == 0:
            c1 = cv.points[1]
            if c1:
                c1.drag(QPointF(c1.current_pos.x() + diff.x(),
                                c1.current_pos.y() + diff.y()))
            prev_i = (ci - 1) if ci > 0 else (n - 1)
            if 0 <= prev_i < n and mgr.is_closed:
                prev_cv = mgr.curves[prev_i]
                prev_cv.points[3].drag(pos)
                c2p = prev_cv.points[2]
                if c2p:
                    c2p.drag(QPointF(c2p.current_pos.x() + diff.x(),
                                     c2p.current_pos.y() + diff.y()))
        else:
            c2 = cv.points[2]
            if c2:
                c2.drag(QPointF(c2.current_pos.x() + diff.x(),
                                c2.current_pos.y() + diff.y()))
            next_i = (ci + 1) if ci < n - 1 else 0
            if 0 <= next_i < n and mgr.is_closed:
                next_cv = mgr.curves[next_i]
                next_cv.points[0].drag(pos)
                c1n = next_cv.points[1]
                if c1n:
                    c1n.drag(QPointF(c1n.current_pos.x() + diff.x(),
                                     c1n.current_pos.y() + diff.y()))

    def _freeze_all_positions(self) -> None:
        for mgr in self._w.polygon_manager.all_managers():
            mgr.save_all_current_pos()

    def _commit_all_orig_positions(self) -> None:
        for mgr in self._w.polygon_manager.all_managers():
            for cv in mgr.curves:
                for pt in cv.points:
                    if pt is not None:
                        pt.set_orig_to_pos()
