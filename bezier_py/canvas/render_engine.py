"""
RenderEngine — all QPainter drawing logic for the Bezier canvas.
Mirrors drawing methods from Java BezierDrawPanel and CubicCurveManager.
"""
from __future__ import annotations
import math

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import (
    QColor, QPainter, QPainterPath, QPen, QBrush,
)

from model.cubic_curve_manager import CubicCurveManager
from model.cubic_curve import CubicCurve
from model.cubic_point import CubicPoint, PointType
from model.oval_manager import OvalManager

# ── palette ──────────────────────────────────────────────────────────────────
COL_BACKGROUND  = QColor(255, 255, 255)   # white, matches Java
COL_GRID        = QColor(200, 200, 200)   # fine grid squares
COL_AXIS_ODD    = QColor(50, 150, 200)    # GridAxes odd (even-indexed) — blue
COL_AXIS_EVEN   = QColor(50, 200, 150)    # GridAxes even (odd-indexed) — teal
COL_STROKE      = QColor(0, 0, 0)
COL_HANDLE_LINE = QColor(0, 50, 230)
COL_ANCHOR      = QColor(0, 230, 50, 160)
COL_ANCHOR_SEL  = QColor(230, 250, 0, 220)
COL_CONTROL     = QColor(230, 50, 0, 80)
COL_CONTROL_SEL = QColor(230, 100, 0, 220)
COL_SEL_CLOSED  = QColor(0, 100, 255, 160)
COL_SEL_REL     = QColor(255, 140, 0, 160)
COL_IN_PROG     = QColor(80, 80, 80, 200)

ANCHOR_RADIUS       = 5.0
CONTROL_RADIUS      = 4.0
GRID_FINE_DIVISIONS = 100   # 100×100 squares, each 10 px — matches Java Grid(100,100,...)
GRID_AXES_DIVISIONS = 20    # 20 coarser coloured axes — matches Java GridAxes(..., 20, ...)


class RenderEngine:
    """Stateless helper — all methods take a QPainter + data."""

    # ── trace image ──────────────────────────────────────────────────────────

    @staticmethod
    def draw_trace_image(p: QPainter, layer) -> None:
        """
        Render the trace layer's image onto the canvas.

        The image is drawn centred at (layer.trace_x, layer.trace_y) and scaled
        uniformly by layer.trace_scale.  Opacity is set to layer.trace_alpha.
        This is always drawn at the user-configured alpha — it is NOT dimmed when
        another layer is active.
        """
        img = layer.trace_image
        if img is None or img.isNull():
            return
        iw = img.width()  * layer.trace_scale
        ih = img.height() * layer.trace_scale
        x  = layer.trace_x - iw * 0.5
        y  = layer.trace_y - ih * 0.5
        p.setOpacity(layer.trace_alpha)
        p.drawImage(QRectF(x, y, iw, ih), img)
        p.setOpacity(1.0)

    # ── background ───────────────────────────────────────────────────────────

    @staticmethod
    def draw_background(p: QPainter, w: int, h: int, edge_offset: int,
                        grid_w: int, grid_h: int,
                        show_grid: bool = True) -> None:
        # ── 1. White fill (Java: dBufferGraphics.setColor(WHITE); fillRect) ──
        p.fillRect(0, 0, w, h, COL_BACKGROUND)

        if not show_grid:
            return

        # ── 2. Fine grid: 100×100 cells, each 10 px ──────────────────────────
        # Disable AA so lines are crisp 1-pixel-wide (matches Java Grid rendering)
        p.setRenderHint(QPainter.RenderHint.Antialiasing, False)
        cell_x = grid_w / GRID_FINE_DIVISIONS
        cell_y = grid_h / GRID_FINE_DIVISIONS
        fine_pen = QPen(COL_GRID, 1.0)
        p.setPen(fine_pen)
        for i in range(GRID_FINE_DIVISIONS + 1):
            x = float(round(edge_offset + i * cell_x))
            y = float(round(edge_offset + i * cell_y))
            p.drawLine(QPointF(x, edge_offset), QPointF(x, edge_offset + grid_h))
            p.drawLine(QPointF(edge_offset, y), QPointF(edge_offset + grid_w, y))

        # ── 3. GridAxes: 20 divisions (50 px), alternating blue/teal ──────────
        axis_step_x = grid_w / GRID_AXES_DIVISIONS
        axis_step_y = grid_h / GRID_AXES_DIVISIONS
        for i in range(GRID_AXES_DIVISIONS + 1):
            col = COL_AXIS_EVEN if (i % 2 != 0) else COL_AXIS_ODD
            p.setPen(QPen(col, 1.0))
            vx = float(round(edge_offset + i * axis_step_x))
            hy = float(round(edge_offset + i * axis_step_y))
            p.drawLine(QPointF(vx, edge_offset), QPointF(vx, edge_offset + grid_h))
            p.drawLine(QPointF(edge_offset, hy), QPointF(edge_offset + grid_w, hy))

        # Re-enable AA for all subsequent geometry drawing
        p.setRenderHint(QPainter.RenderHint.Antialiasing, True)

    # ── committed manager ────────────────────────────────────────────────────

    @staticmethod
    def draw_manager(p: QPainter, mgr: CubicCurveManager,
                     show_handles: bool = True,
                     opacity: float = 1.0) -> None:
        """Draw a committed manager (closed or open curve)."""
        if not mgr.curves:
            return

        old_opacity = p.opacity()
        p.setOpacity(opacity)

        # Build path
        path = QPainterPath()
        first_pt = mgr.curves[0].points[0]
        if first_pt is None:
            p.setOpacity(old_opacity)
            return
        path.moveTo(first_pt.pos)
        for cv in mgr.curves:
            pts = cv.points
            if all(x is not None for x in pts):
                path.cubicTo(pts[1].pos, pts[2].pos, pts[3].pos)
        if mgr.is_closed:
            path.closeSubpath()

        # Stroke path — open curves with pressure data use per-segment width
        p.setBrush(Qt.BrushStyle.NoBrush)
        if not mgr.is_closed and mgr.anchor_pressures is not None:
            for i, cv in enumerate(mgr.curves):
                pts = cv.points
                if not all(x is not None for x in pts):
                    continue
                seg = QPainterPath()
                seg.moveTo(pts[0].pos)
                seg.cubicTo(pts[1].pos, pts[2].pos, pts[3].pos)
                p0 = mgr.get_anchor_pressure(i)
                p1 = mgr.get_anchor_pressure(i + 1)
                w = max(1.0, ((p0 + p1) * 0.5) * 8.0)
                seg_pen = QPen(COL_STROKE)
                seg_pen.setWidthF(w)
                p.setPen(seg_pen)
                p.drawPath(seg)
        else:
            pen = QPen(COL_STROKE)
            pen.setWidthF(2.0)
            p.setPen(pen)
            p.drawPath(path)

        # Selection overlay
        if mgr.selected:
            col = COL_SEL_REL if mgr.selected_relational else COL_SEL_CLOSED
            sel_pen = QPen(col)
            sel_pen.setWidthF(4.0)
            p.setPen(sel_pen)
            p.setBrush(Qt.BrushStyle.NoBrush)
            p.drawPath(path)

        # Scope indicator (yellow dashed outline)
        if mgr.scoped:
            dash_pen = QPen(QColor(255, 255, 100, 200))
            dash_pen.setWidthF(2.0)
            dash_pen.setDashPattern([8.0, 4.0])
            p.setPen(dash_pen)
            p.setBrush(Qt.BrushStyle.NoBrush)
            p.drawPath(path)

        # Handle lines + point ovals
        if show_handles:
            RenderEngine._draw_handles(p, mgr)

        p.setOpacity(old_opacity)

    @staticmethod
    def _draw_handles(p: QPainter, mgr: CubicCurveManager) -> None:
        """Draw control handle lines and anchor/control point ovals."""
        handle_pen = QPen(COL_HANDLE_LINE)
        handle_pen.setWidthF(1.0)

        for cv in mgr.curves:
            pts = cv.points
            if not all(x is not None for x in pts):
                continue
            a1, c1, c2, a2 = pts

            # Draw handle lines (anchor ↔ control)
            p.setPen(handle_pen)
            p.drawLine(a1.pos, c1.pos)
            p.drawLine(c2.pos, a2.pos)

            # Draw points
            RenderEngine._draw_point_oval(p, a1)
            RenderEngine._draw_point_oval(p, c1)
            RenderEngine._draw_point_oval(p, c2)
            RenderEngine._draw_point_oval(p, a2)

    @staticmethod
    def _draw_point_oval(p: QPainter, pt: CubicPoint) -> None:
        r = ANCHOR_RADIUS if pt.type == PointType.ANCHOR else CONTROL_RADIUS
        if pt.type == PointType.ANCHOR:
            fill = COL_ANCHOR_SEL if pt.selected else COL_ANCHOR
        else:
            fill = COL_CONTROL_SEL if pt.selected else COL_CONTROL
        rect = QRectF(pt.pos.x() - r, pt.pos.y() - r, r * 2, r * 2)
        p.setBrush(QBrush(fill))
        p.setPen(QPen(QColor(0, 0, 0, 80), 1.0))
        p.drawEllipse(rect)

    # ── in-progress (active drawing) manager ─────────────────────────────────

    @staticmethod
    def draw_in_progress(p: QPainter, mgr: CubicCurveManager,
                         mouse_pos: QPointF | None = None,
                         paused: bool = False) -> None:
        """Draw the active drawing manager (partially built curve).
        When paused=True the rubber-line is suppressed (Space-key pause).
        """
        if not mgr.add_points:
            return

        # Draw committed curves so far
        if mgr.curves:
            pen = QPen(COL_IN_PROG)
            pen.setWidthF(2.0)
            p.setPen(pen)
            p.setBrush(Qt.BrushStyle.NoBrush)

            path = QPainterPath()
            first = mgr.curves[0].points[0]
            if first:
                path.moveTo(first.pos)
                for cv in mgr.curves:
                    pts = cv.points
                    if all(x is not None for x in pts):
                        path.cubicTo(pts[1].pos, pts[2].pos, pts[3].pos)
            p.drawPath(path)

            # Draw handles for in-progress curves
            RenderEngine._draw_handles(p, mgr)

        # Draw rubber line from last placed anchor to mouse (unless paused)
        if not paused and mgr.add_points and mouse_pos is not None:
            rubber_pen = QPen(QColor(120, 120, 120, 150))
            rubber_pen.setWidthF(1.0)
            rubber_pen.setDashPattern([4.0, 4.0])
            p.setPen(rubber_pen)
            # Case A: first curve in progress (between click 1 and click 2)
            cur = mgr.current_curve
            if cur.points[0] is not None:
                RenderEngine._draw_point_oval(p, cur.points[0])
                p.drawLine(cur.points[0].pos, mouse_pos)
            # Case B: subsequent anchors (after click 2+)
            # current_curve is empty; rubber line from last committed anchor to mouse
            elif mgr.curves:
                last_pt = mgr.curves[-1].points[3]
                if last_pt is not None:
                    p.drawLine(last_pt.pos, mouse_pos)

    # ── edge highlights ──────────────────────────────────────────────────────

    @staticmethod
    def draw_edge_highlights(p: QPainter, mgr: CubicCurveManager) -> None:
        all_idx = (mgr.discrete_edge_indices | mgr.relational_edge_indices
                   | mgr.weldable_edge_indices)
        for idx in all_idx:
            if idx >= len(mgr.curves):
                continue
            cv = mgr.curves[idx]
            pts = cv.points
            if not all(x is not None for x in pts):
                continue
            if idx in mgr.weldable_edge_indices:
                col = QColor(220, 0, 255, 200)   # purple — weld preview
                width = 5.0
            elif idx in mgr.relational_edge_indices:
                col = QColor(255, 140, 0, 200)   # orange — relational selection
                width = 4.0
            else:
                col = QColor(0, 100, 255, 200)   # blue — discrete selection
                width = 4.0
            pen = QPen(col, width)
            p.setPen(pen)
            sub = QPainterPath()
            sub.moveTo(pts[0].pos)
            sub.cubicTo(pts[1].pos, pts[2].pos, pts[3].pos)
            p.drawPath(sub)

    # ── point highlights ─────────────────────────────────────────────────────

    @staticmethod
    def draw_point_highlights(p: QPainter, mgr: CubicCurveManager) -> None:
        for pt in mgr.discrete_points:
            RenderEngine._draw_highlight_oval(p, pt, relational=False)
        for pt in mgr.relational_points:
            RenderEngine._draw_highlight_oval(p, pt, relational=True)

    @staticmethod
    def _draw_highlight_oval(p: QPainter, pt: CubicPoint, relational: bool) -> None:
        pos = pt.pos
        if relational:
            col = (QColor(220, 50, 30) if pt.type == PointType.ANCHOR
                   else QColor(255, 220, 0))
        else:
            col = (QColor(100, 150, 255) if pt.type == PointType.ANCHOR
                   else QColor(255, 255, 255))
        p.setBrush(QBrush(col))
        p.setPen(QPen(QColor(0, 0, 0), 1.0))
        p.drawEllipse(QRectF(pos.x() - 6, pos.y() - 6, 12, 12))

    # ── mesh build overlay ───────────────────────────────────────────────────

    _MESH_ADD_R     = 10.0   # px — add to sequence when mouse enters this radius
    _MESH_PREVIEW_R = 18.0   # px — show hover ring when within this radius

    @staticmethod
    def draw_mesh_build_overlay(p: QPainter, seq: list, mouse_pos: QPointF,
                                point_list: list) -> None:
        """Draw mesh-build-mode overlay: connecting lines, numbered rings, hover preview.

        seq        — ordered list of QPointF (positions already in the sequence)
        mouse_pos  — current canvas mouse position
        point_list — all discrete point positions (list[QPointF])
        """
        ADD_R     = RenderEngine._MESH_ADD_R
        PREVIEW_R = RenderEngine._MESH_PREVIEW_R

        # Build a set of "already sequenced" positions for fast membership test
        seq_keys = {(round(s.x()), round(s.y())) for s in seq}

        # 1. Connecting lines between sequence points
        if len(seq) >= 2:
            pen = QPen(QColor(0, 200, 80, 220), 1.5)
            p.setPen(pen)
            p.setBrush(Qt.BrushStyle.NoBrush)
            for i in range(len(seq) - 1):
                p.drawLine(seq[i], seq[i + 1])

        # 2. Closing-edge ghost line when ≥3 points (last→first, dashed)
        if len(seq) >= 3:
            close_pen = QPen(QColor(0, 200, 80, 90), 1.0)
            close_pen.setStyle(Qt.PenStyle.DashLine)
            p.setPen(close_pen)
            p.drawLine(seq[-1], seq[0])

        # 3. Preview line from last sequence point (or origin) to mouse
        anchor = seq[-1] if seq else None
        if anchor is not None:
            dash_pen = QPen(QColor(0, 200, 80, 130), 1.0)
            dash_pen.setStyle(Qt.PenStyle.DashLine)
            p.setPen(dash_pen)
            p.drawLine(anchor, mouse_pos)

        # 4. Find nearest un-sequenced point for hover preview ring
        nearest_preview: QPointF | None = None
        nearest_add:     QPointF | None = None
        nearest_d_preview = PREVIEW_R
        nearest_d_add     = ADD_R
        for pt in point_list:
            key = (round(pt.x()), round(pt.y()))
            if key in seq_keys:
                continue
            d = math.hypot(pt.x() - mouse_pos.x(), pt.y() - mouse_pos.y())
            if d < nearest_d_preview:
                nearest_d_preview = d
                nearest_preview = pt
            if d < nearest_d_add:
                nearest_d_add = d
                nearest_add = pt

        # 4a. Outer hover ring (pale green) — point is "approaching"
        if nearest_preview is not None and nearest_add is None:
            p.setBrush(QBrush(QColor(0, 220, 100, 80)))
            p.setPen(QPen(QColor(0, 170, 60, 180), 1.5))
            R = 10.0
            p.drawEllipse(QRectF(nearest_preview.x() - R, nearest_preview.y() - R,
                                 2 * R, 2 * R))

        # 5. Numbered rings for each sequence point
        font = p.font()
        font.setPointSize(8)
        font.setBold(True)
        p.setFont(font)
        R = 9.0
        for i, sp in enumerate(seq):
            # Filled green circle
            p.setBrush(QBrush(QColor(0, 200, 80)))
            p.setPen(QPen(QColor(0, 0, 0, 200), 1.0))
            p.drawEllipse(QRectF(sp.x() - R, sp.y() - R, 2 * R, 2 * R))
            # Number centred in the ring
            p.setPen(QPen(QColor(0, 0, 0)))
            p.drawText(QRectF(sp.x() - R, sp.y() - R, 2 * R, 2 * R),
                       Qt.AlignmentFlag.AlignCenter, str(i + 1))

    # ── rubber-band ──────────────────────────────────────────────────────────

    @staticmethod
    def draw_knife_line(p: QPainter, start: QPointF, end: QPointF) -> None:
        """Render the knife tool cut preview: dashed red line + tick at start."""
        dx = end.x() - start.x()
        dy = end.y() - start.y()
        length = math.sqrt(dx * dx + dy * dy)
        if length < 1.0:
            return
        pen = QPen(QColor(220, 30, 30, 200), 1.5)
        pen.setDashPattern([6.0, 4.0])
        pen.setCapStyle(Qt.PenCapStyle.FlatCap)
        p.setPen(pen)
        p.setBrush(Qt.BrushStyle.NoBrush)
        p.drawLine(start, end)
        # Perpendicular tick at start
        px, py = -dy / length * 8, dx / length * 8
        tick_pen = QPen(QColor(220, 30, 30, 200), 1.5)
        p.setPen(tick_pen)
        p.drawLine(QPointF(start.x() - px, start.y() - py),
                   QPointF(start.x() + px, start.y() + py))
        # Dot markers
        r = 4.0
        p.drawEllipse(QRectF(start.x() - r, start.y() - r, r*2, r*2))
        p.drawEllipse(QRectF(end.x() - r,   end.y() - r,   r*2, r*2))

    @staticmethod
    def draw_freehand_preview(p: QPainter, pts: list,
                              pressures: list | None = None,
                              first_pt=None, snap_radius: float = 20.0) -> None:
        """Draw the freehand stroke in progress.
        If pressures are provided (tablet input), draws a variable-width ribbon.
        Otherwise draws a thin polyline. Highlights the start point in green
        when auto-close is imminent.
        """
        if len(pts) < 2:
            return

        has_pressure = (pressures is not None and len(pressures) >= 2
                        and any(pr < 0.99 for pr in pressures))

        if has_pressure:
            # Port of Java drawPressureRibbon — filled polygon ribbon
            import math as _math
            n = len(pts)
            max_half_w = 5.0   # px at pressure=1.0 (matches Java)
            lx = [0.0] * n; ly = [0.0] * n
            rx = [0.0] * n; ry = [0.0] * n
            for i in range(n):
                pr = pressures[i] if i < len(pressures) else 1.0
                w = max(0.5, pr * max_half_w)
                if i == 0:
                    ddx = pts[1].x() - pts[0].x(); ddy = pts[1].y() - pts[0].y()
                elif i == n - 1:
                    ddx = pts[n-1].x() - pts[n-2].x(); ddy = pts[n-1].y() - pts[n-2].y()
                else:
                    ddx1 = pts[i].x() - pts[i-1].x(); ddy1 = pts[i].y() - pts[i-1].y()
                    len1 = _math.sqrt(ddx1*ddx1 + ddy1*ddy1) or 1.0
                    ddx2 = pts[i+1].x() - pts[i].x(); ddy2 = pts[i+1].y() - pts[i].y()
                    len2 = _math.sqrt(ddx2*ddx2 + ddy2*ddy2) or 1.0
                    nx = (-ddy1/len1 + -ddy2/len2) * 0.5
                    ny = (ddx1/len1 + ddx2/len2) * 0.5
                    nlen = _math.sqrt(nx*nx + ny*ny) or 1.0
                    lx[i] = pts[i].x() + nx/nlen * w
                    ly[i] = pts[i].y() + ny/nlen * w
                    rx[i] = pts[i].x() - nx/nlen * w
                    ry[i] = pts[i].y() - ny/nlen * w
                    continue
                # endpoints (i==0 or i==n-1): single-segment normal
                dlen = _math.sqrt(ddx*ddx + ddy*ddy) or 1.0
                nx = -ddy / dlen; ny = ddx / dlen
                lx[i] = pts[i].x() + nx * w; ly[i] = pts[i].y() + ny * w
                rx[i] = pts[i].x() - nx * w; ry[i] = pts[i].y() - ny * w

            ribbon = QPainterPath()
            ribbon.moveTo(lx[0], ly[0])
            for i in range(1, n):
                ribbon.lineTo(lx[i], ly[i])
            for i in range(n - 1, -1, -1):
                ribbon.lineTo(rx[i], ry[i])
            ribbon.closeSubpath()
            p.setBrush(QBrush(QColor(80, 80, 200, 180)))
            p.setPen(Qt.PenStyle.NoPen)
            p.drawPath(ribbon)
        else:
            pen = QPen(QColor(80, 80, 200, 160), 1.0)
            p.setPen(pen)
            for i in range(1, len(pts)):
                p.drawLine(pts[i - 1], pts[i])

        if first_pt is not None:
            import math
            last = pts[-1]
            dist = math.hypot(last.x() - first_pt.x(), last.y() - first_pt.y())
            near = dist < snap_radius
            r = 8.0
            if near:
                # Green highlight: auto-close imminent
                p.setBrush(QBrush(QColor(50, 220, 50, 200)))
                p.setPen(QPen(QColor(0, 150, 0), 2.0))
            else:
                # Normal: white dot at start point
                p.setBrush(QBrush(QColor(255, 255, 255, 180)))
                p.setPen(QPen(QColor(80, 80, 200, 160), 1.5))
            p.drawEllipse(QRectF(first_pt.x() - r, first_pt.y() - r, r * 2, r * 2))

    @staticmethod
    def draw_rubber_band(p: QPainter, start: QPointF, end: QPointF) -> None:
        x0 = min(start.x(), end.x())
        y0 = min(start.y(), end.y())
        w  = abs(end.x() - start.x())
        h  = abs(end.y() - start.y())
        pen = QPen(QColor(100, 150, 255, 200))
        pen.setWidthF(1.0)
        pen.setDashPattern([4.0, 4.0])
        p.setPen(pen)
        p.setBrush(QBrush(QColor(100, 150, 255, 30)))
        p.drawRect(QRectF(x0, y0, w, h))

    # ── ovals ─────────────────────────────────────────────────────────────────

    @staticmethod
    def draw_ovals(p: QPainter, ovals: list[OvalManager]) -> None:
        """Draw all ovals. Selected ovals get a coloured 4px outline."""
        for oval in ovals:
            x = oval.cx - oval.rx
            y = oval.cy - oval.ry
            w = oval.rx * 2
            h = oval.ry * 2
            rect = QRectF(x, y, w, h)
            if oval.selected:
                pen = QPen(QColor(100, 150, 255), 4.0)   # blue selection
            else:
                pen = QPen(QColor(0, 0, 0), 1.5)
            p.setPen(pen)
            p.setBrush(Qt.BrushStyle.NoBrush)
            p.drawEllipse(rect)

    # ── discrete points ───────────────────────────────────────────────────────

    @staticmethod
    def draw_discrete_points(p: QPainter, points: list,
                              pressures: list[float],
                              selected_index: int) -> None:
        """Draw discrete (free-standing) points as purple filled circles.
        Radius scales with pressure (3–8 px). Selected point gets a yellow ring.
        """
        if not points:
            return
        for i, pt in enumerate(points):
            pr = pressures[i] if i < len(pressures) else 1.0
            r = max(3, int(pr * 8))
            px, py = pt.x(), pt.y()

            if i == selected_index:
                # Yellow selection ring
                ring_pen = QPen(QColor(255, 220, 0, 220), 2.0)
                p.setPen(ring_pen)
                p.setBrush(Qt.BrushStyle.NoBrush)
                p.drawEllipse(QRectF(px - r - 3, py - r - 3, (r + 3) * 2, (r + 3) * 2))

            # Purple body
            p.setBrush(QBrush(QColor(200, 0, 255, 220)))
            p.setPen(QPen(QColor(0, 0, 0, 80), 1.0))
            p.drawEllipse(QRectF(px - r, py - r, r * 2, r * 2))
