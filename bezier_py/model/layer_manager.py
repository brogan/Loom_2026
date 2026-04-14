"""
LayerManager — owns the ordered list of layers.
Mirrors Java LayerManager.java.
"""
from __future__ import annotations
from model.layer import Layer


class LayerManager:

    def __init__(self) -> None:
        first = Layer("Layer 1")
        self._layers: list[Layer] = [first]
        self._active_layer_id: int = first.id

    # ── properties ────────────────────────────────────────────────────────────

    @property
    def layers(self) -> list[Layer]:
        return self._layers

    @property
    def active_layer_id(self) -> int:
        return self._active_layer_id

    def set_active_layer_id(self, id: int) -> None:
        self._active_layer_id = id

    def get_active_layer(self) -> Layer | None:
        return self.get_layer_by_id(self._active_layer_id)

    def get_layer_by_id(self, id: int) -> Layer | None:
        for l in self._layers:
            if l.id == id:
                return l
        return None

    def geometry_layers(self) -> list[Layer]:
        """All layers that are NOT the trace layer."""
        return [l for l in self._layers if not l.is_trace]

    def get_trace_layer(self) -> Layer | None:
        """Return the single trace layer, or None if none exists."""
        for l in self._layers:
            if l.is_trace:
                return l
        return None

    # ── CRUD ──────────────────────────────────────────────────────────────────

    def create_layer(self, name: str) -> Layer:
        l = Layer(name)
        self._layers.append(l)
        return l

    def create_trace_layer(self, image_path: str = "") -> Layer:
        """
        Create (or replace) the single trace layer.

        The trace layer is inserted at position 0 so it sits beneath all
        geometry layers in the display stack.  If a trace layer already exists
        its geometry is replaced; position, scale and alpha are reset to defaults.
        """
        # Remove any existing trace layer first
        existing = self.get_trace_layer()
        if existing is not None:
            self._layers = [l for l in self._layers if l.id != existing.id]

        trace = Layer("Trace", is_trace=True)
        trace.trace_image_path = image_path
        self._layers.insert(0, trace)
        return trace

    def delete_layer(self, id: int) -> bool:
        """
        Returns False if deleting would leave no geometry layers.
        Trace layers can always be deleted regardless of count.
        """
        layer = self.get_layer_by_id(id)
        if layer is None:
            return False
        if not layer.is_trace:
            # Must keep at least one geometry layer
            if len(self.geometry_layers()) <= 1:
                return False
        self._layers = [l for l in self._layers if l.id != id]
        if self._active_layer_id == id:
            # Switch to first geometry layer, or whatever remains
            geo = self.geometry_layers()
            if geo:
                self._active_layer_id = geo[0].id
            elif self._layers:
                self._active_layer_id = self._layers[0].id
        return True

    def rename_layer(self, id: int, name: str) -> None:
        l = self.get_layer_by_id(id)
        if l:
            l.name = name

    def duplicate_layer(self, id: int, polygon_manager) -> Layer | None:
        """
        Create a new layer named '<name> copy' and deep-copy all polygons
        belonging to the source layer into it.
        """
        src = self.get_layer_by_id(id)
        if src is None:
            return None
        dup = self.create_layer(src.name + " copy")
        to_copy = [m for m in polygon_manager.committed_managers()
                   if m.layer_id == id]
        for m in to_copy:
            copy_mgr = polygon_manager.add_duplicate_of(m, 0, 0)
            copy_mgr.layer_id = dup.id
        return dup

    # ── ordering ──────────────────────────────────────────────────────────────

    def move_layer_up(self, id: int) -> None:
        idx = self._index_of(id)
        if idx > 0:
            self._layers[idx - 1], self._layers[idx] = (
                self._layers[idx], self._layers[idx - 1])

    def move_layer_down(self, id: int) -> None:
        idx = self._index_of(id)
        if 0 <= idx < len(self._layers) - 1:
            self._layers[idx + 1], self._layers[idx] = (
                self._layers[idx], self._layers[idx + 1])

    # ── internal ──────────────────────────────────────────────────────────────

    def _index_of(self, id: int) -> int:
        for i, l in enumerate(self._layers):
            if l.id == id:
                return i
        return -1
