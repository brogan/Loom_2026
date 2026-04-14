"""
Layer — a named, visible/hidden drawing layer.
Mirrors Java Layer.java.
"""
from __future__ import annotations


class Layer:
    _next_id: int = 1

    def __init__(self, name: str, is_trace: bool = False) -> None:
        self.id: int = Layer._next_id
        Layer._next_id += 1
        self.name: str = name
        self.visible: bool = True

        # ── Trace layer properties (populated only when is_trace=True) ────────
        self.is_trace: bool = is_trace
        self.trace_image_path: str = ""   # absolute or relative path for persistence
        self.trace_image = None            # QImage loaded at runtime (not persisted)
        self.trace_x: float = 520.0       # image centre X in canvas coords
        self.trace_y: float = 520.0       # image centre Y in canvas coords
        self.trace_scale: float = 1.0     # uniform scale factor
        self.trace_alpha: float = 1.0     # opacity 0.0–1.0
