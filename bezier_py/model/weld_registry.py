"""
WeldRegistry — tracks cross-manager point identity for welded/coincident points.
Port of WeldRegistry.java.
"""
from __future__ import annotations


class WeldRegistry:
    """
    Bidirectional weld link registry.
    Maps CubicPoint → set[CubicPoint] for all welded partners.
    """

    def __init__(self) -> None:
        self._links: dict = {}  # dict[CubicPoint, set[CubicPoint]]

    def register_weld(self, a, b) -> None:
        """Mark a and b as welded to each other."""
        self._links.setdefault(a, set()).add(b)
        self._links.setdefault(b, set()).add(a)

    def get_linked(self, p) -> frozenset:
        """Return all points welded to p (empty frozenset if none)."""
        s = self._links.get(p)
        return frozenset(s) if s else frozenset()

    def unregister_point(self, p) -> None:
        """Remove p from the registry and clean up all reverse links."""
        linked = self._links.pop(p, None)
        if linked:
            for other in linked:
                s = self._links.get(other)
                if s:
                    s.discard(p)
                    if not s:
                        del self._links[other]

    def unregister_link(self, a, b) -> None:
        """Remove only the link between a and b, leaving other links intact."""
        sa = self._links.get(a)
        if sa:
            sa.discard(b)
            if not sa:
                del self._links[a]
        sb = self._links.get(b)
        if sb:
            sb.discard(a)
            if not sb:
                del self._links[b]

    def clear(self) -> None:
        self._links.clear()

    def entries(self):
        """Return items view of the link dict (for snapshot capture)."""
        return list(self._links.items())
