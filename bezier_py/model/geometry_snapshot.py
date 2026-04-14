"""
GeometrySnapshot — lightweight snapshot of all canvas geometry for undo.
Mirrors Java GeometrySnapshot (field-level copy, not object references).
"""
from __future__ import annotations
import copy
from dataclasses import dataclass, field
from PySide6.QtCore import QPointF


@dataclass
class OvalSnap:
    """Snapshot of one oval's parameters."""
    cx: float
    cy: float
    rx: float
    ry: float
    layer_id: int


@dataclass
class GeometrySnapshot:
    """
    Full canvas state: polygon managers (deep-copied), ovals (value copy),
    discrete points (value copy), and pressures.
    Max 20 on the undo stack (deque maxlen=20).
    """
    # Deep copy of all committed CubicCurveManagers (preserves shared-point identity
    # within each manager; cross-manager weld links are lost but that is Phase 7).
    managers: list   # list[CubicCurveManager]

    # Value copies of ovals (cx, cy, rx, ry, layer_id)
    ovals: list      # list[OvalSnap]

    # Value copies of discrete points and pressures
    points:    list  # list[QPointF]
    pressures: list  # list[float]

    @staticmethod
    def capture(polygon_manager, oval_list, point_list, point_pressures,
                active_layer_id: int) -> 'GeometrySnapshot':
        """Build a snapshot from current canvas state."""
        mgr_copy = copy.deepcopy(polygon_manager.committed_managers())
        # Ensure copied managers remember their layer assignment
        ovals_snap = [
            OvalSnap(o.cx, o.cy, o.rx, o.ry, o.layer_id)
            for o in oval_list
        ]
        pts_snap = [QPointF(p) for p in point_list]
        pres_snap = list(point_pressures)
        return GeometrySnapshot(
            managers=mgr_copy,
            ovals=ovals_snap,
            points=pts_snap,
            pressures=pres_snap,
        )
