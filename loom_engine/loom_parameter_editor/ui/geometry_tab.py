"""
Geometry tab — hosts Spline Polygons, Regular Polygons, Curves, Points, Ovals,
and Bitmap Polygons as sub-tabs.
"""
from PySide6.QtWidgets import QWidget, QVBoxLayout, QTabWidget
from PySide6.QtCore import Signal
from .spline_polygon_tab import SplinePolygonTab
from .regular_polygon_tab import RegularPolygonTab
from .open_curve_tab import OpenCurveTab
from .point_tab import PointTab
from .oval_tab import OvalTab
from .bitmap_polygon_tab import BitmapPolygonTab
from models.polygon_config import PolygonSetLibrary


class GeometryTab(QWidget):
    modified = Signal()
    shapeLibraryChanged    = Signal()
    subdivisionChanged     = Signal()
    spriteLibraryChanged   = Signal()
    rendererLibraryChanged = Signal()
    newShapeCreated        = Signal(str, str)   # (set_name, shape_name)
    newSpriteCreated       = Signal(str, str)   # (set_name, sprite_name)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.sub_tabs = QTabWidget()

        # Shared polygon library — owned here, both polygon tabs reference it
        self._polygon_library = PolygonSetLibrary.default()

        self.spline_tab      = SplinePolygonTab()
        self.regular_tab     = RegularPolygonTab()
        self.open_curve_tab  = OpenCurveTab()
        self.point_tab       = PointTab()
        self.oval_tab        = OvalTab()
        self.bitmap_tab      = BitmapPolygonTab()

        # Wire shared library into both polygon tabs
        self.spline_tab.set_library(self._polygon_library)
        self.regular_tab.set_library(self._polygon_library)

        # Cross-refresh: when either polygon tab modifies the shared library,
        # the other tab's list needs to be refreshed
        self.spline_tab.modified.connect(self.regular_tab._refresh_list)
        self.regular_tab.modified.connect(self.spline_tab._refresh_list)

        # When bitmap tab creates a new file, refresh the Spline Polygons file list
        self.bitmap_tab.modified.connect(self.spline_tab._refresh_file_list)

        # Backward-compat alias used by main_window.py
        self.polygon_tab = self.spline_tab

        self.sub_tabs.addTab(self.spline_tab,     "Spline Polygons")
        self.sub_tabs.addTab(self.regular_tab,    "Regular Polygons")
        self.sub_tabs.addTab(self.open_curve_tab, "Curves")
        self.sub_tabs.addTab(self.point_tab,      "Points")
        self.sub_tabs.addTab(self.oval_tab,       "Ovals")
        self.sub_tabs.addTab(self.bitmap_tab,     "Bitmap Polygons")

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.sub_tabs)

        # Forward modified signals
        for tab in (self.spline_tab, self.regular_tab,
                    self.open_curve_tab, self.point_tab, self.oval_tab,
                    self.bitmap_tab):
            tab.modified.connect(self.modified)

        # Forward library-changed signals
        for tab in (self.spline_tab, self.regular_tab,
                    self.open_curve_tab, self.point_tab, self.oval_tab,
                    self.bitmap_tab):
            tab.shapeLibraryChanged.connect(self.shapeLibraryChanged)
            tab.subdivisionChanged.connect(self.subdivisionChanged)
            tab.spriteLibraryChanged.connect(self.spriteLibraryChanged)
            tab.rendererLibraryChanged.connect(self.rendererLibraryChanged)
            tab.newShapeCreated.connect(self.newShapeCreated)
            tab.newSpriteCreated.connect(self.newSpriteCreated)

    # ── Directory setters ─────────────────────────────────────────────────────

    def set_polygon_sets_directory(self, d):
        self.spline_tab.set_polygon_sets_directory(d)

    def set_regular_polygons_directory(self, d):
        self.regular_tab.set_regular_polygons_directory(d)

    def set_curve_sets_directory(self, d):
        self.open_curve_tab.set_curve_sets_directory(d)

    def set_point_sets_directory(self, d):
        self.point_tab.set_point_sets_directory(d)

    def set_oval_sets_directory(self, d):
        self.oval_tab.set_oval_sets_directory(d)

    def set_bitmap_polygon_dirs(self, polygon_sets_dir: str,
                                background_image_dir: str):
        self.bitmap_tab.set_polygon_sets_directory(polygon_sets_dir)
        self.bitmap_tab.set_background_image_dir(background_image_dir)

    # ── Library access — Polygons ─────────────────────────────────────────────

    def get_polygon_library(self):
        return self._polygon_library

    def set_polygon_library(self, lib):
        """Set the shared polygon library and push it into both polygon tabs."""
        self._polygon_library = lib
        self.spline_tab.set_library(lib)
        self.regular_tab.set_library(lib)

    def create_default_polygon_library(self):
        return PolygonSetLibrary.default()

    # ── Library access — Open Curves ──────────────────────────────────────────

    def get_open_curve_library(self):
        return self.open_curve_tab.get_library()

    def set_open_curve_library(self, lib):
        self.open_curve_tab.set_library(lib)

    def create_default_open_curve_library(self):
        return self.open_curve_tab.create_default_library()

    # ── Library access — Points ───────────────────────────────────────────────

    def get_point_library(self):
        return self.point_tab.get_library()

    def set_point_library(self, lib):
        self.point_tab.set_library(lib)

    def create_default_point_library(self):
        return self.point_tab.create_default_library()

    # ── Library access — Ovals ────────────────────────────────────────────────

    def get_oval_library(self):
        return self.oval_tab.get_library()

    def set_oval_library(self, lib):
        self.oval_tab.set_library(lib)

    def create_default_oval_library(self):
        return self.oval_tab.create_default_library()

    # ── Shape / Sprite cross-refs ─────────────────────────────────────────────

    def set_shape_library(self, lib):
        for tab in (self.spline_tab, self.regular_tab,
                    self.open_curve_tab, self.point_tab, self.oval_tab):
            if hasattr(tab, 'set_shape_library'):
                tab.set_shape_library(lib)

    def set_sprite_library(self, lib):
        for tab in (self.spline_tab, self.regular_tab,
                    self.open_curve_tab, self.point_tab, self.oval_tab):
            if hasattr(tab, 'set_sprite_library'):
                tab.set_sprite_library(lib)

    def set_subdivision_collection(self, coll):
        for tab in (self.spline_tab, self.regular_tab,
                    self.open_curve_tab, self.point_tab, self.oval_tab):
            if hasattr(tab, 'set_subdivision_collection'):
                tab.set_subdivision_collection(coll)

    def set_renderer_library(self, lib):
        for tab in (self.spline_tab, self.regular_tab,
                    self.open_curve_tab, self.point_tab, self.oval_tab):
            if hasattr(tab, 'set_renderer_library'):
                tab.set_renderer_library(lib)
