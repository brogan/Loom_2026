"""
OvalManager — one axis-aligned ellipse in canvas pixel space.
Mirrors Java OvalManager.
Coordinates: canvas pixel space (0..1040), centre at (520,520).
"""
from __future__ import annotations
import math
import copy


class OvalManager:
    """
    cx, cy : centre in canvas pixel space
    rx, ry : radii in canvas pixel space
    orig*  : frozen values for slider-based scale gestures (like CubicPoint.orig_pos)
    """

    def __init__(self, cx: float, cy: float, rx: float, ry: float) -> None:
        self.cx = cx
        self.cy = cy
        self.rx = rx
        self.ry = ry
        self.orig_cx = cx
        self.orig_cy = cy
        self.orig_rx = rx
        self.orig_ry = ry
        self.layer_id: int = 0
        self.selected: bool = False

    # ── geometry ──────────────────────────────────────────────────────────────

    def contains(self, px: float, py: float) -> bool:
        """True if canvas-space point is inside this ellipse."""
        rx = max(self.rx, 1.0)
        ry = max(self.ry, 1.0)
        dx = (px - self.cx) / rx
        dy = (py - self.cy) / ry
        return dx * dx + dy * dy <= 1.0

    def translate(self, dx: float, dy: float) -> None:
        self.cx += dx
        self.cy += dy

    def freeze_orig(self) -> None:
        """Capture current values at gesture start (for slider-based scale)."""
        self.orig_cx = self.cx
        self.orig_cy = self.cy
        self.orig_rx = self.rx
        self.orig_ry = self.ry

    def scale_xy_from_orig(self, factor: float, pivot_x: float, pivot_y: float) -> None:
        self.cx = pivot_x + (self.orig_cx - pivot_x) * factor
        self.cy = pivot_y + (self.orig_cy - pivot_y) * factor
        self.rx = abs(self.orig_rx * factor)
        self.ry = abs(self.orig_ry * factor)

    def rotate(self, degrees: float, pivot_x: float, pivot_y: float) -> None:
        """Rotate centre around pivot. Radii unchanged (stays axis-aligned)."""
        rad = math.radians(degrees)
        dx = self.cx - pivot_x
        dy = self.cy - pivot_y
        self.cx = pivot_x + dx * math.cos(rad) - dy * math.sin(rad)
        self.cy = pivot_y + dx * math.sin(rad) + dy * math.cos(rad)

    def flip_h(self, center_x: float) -> None:
        self.cx = 2.0 * center_x - self.cx

    def flip_v(self, center_y: float) -> None:
        self.cy = 2.0 * center_y - self.cy

    def average_xy(self):
        from PySide6.QtCore import QPointF
        return QPointF(self.cx, self.cy)

    def copy(self) -> OvalManager:
        m = OvalManager(self.cx, self.cy, self.rx, self.ry)
        m.layer_id = self.layer_id
        m.selected = False
        return m
