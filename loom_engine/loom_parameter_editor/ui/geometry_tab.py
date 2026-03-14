"""
Geometry tab — hosts Polygons, Curves, and Points as sub-tabs.
"""
from PyQt6.QtWidgets import QWidget, QVBoxLayout, QTabWidget
from PyQt6.QtCore import pyqtSignal
from .polygon_tab import PolygonTab
from .open_curve_tab import OpenCurveTab
from .point_tab import PointTab


class GeometryTab(QWidget):
    modified = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.sub_tabs = QTabWidget()

        self.polygon_tab    = PolygonTab()
        self.open_curve_tab = OpenCurveTab()
        self.point_tab      = PointTab()

        self.sub_tabs.addTab(self.polygon_tab,    "Polygons")
        self.sub_tabs.addTab(self.open_curve_tab, "Curves")
        self.sub_tabs.addTab(self.point_tab,      "Points")

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.sub_tabs)

        self.polygon_tab.modified.connect(self.modified)
        self.open_curve_tab.modified.connect(self.modified)
        self.point_tab.modified.connect(self.modified)

    # ── Directory setters ─────────────────────────────────────────────────────

    def set_polygon_sets_directory(self, d):
        self.polygon_tab.set_polygon_sets_directory(d)

    def set_regular_polygons_directory(self, d):
        self.polygon_tab.set_regular_polygons_directory(d)

    def set_curve_sets_directory(self, d):
        self.open_curve_tab.set_curve_sets_directory(d)

    def set_point_sets_directory(self, d):
        self.point_tab.set_point_sets_directory(d)

    # ── Library access — Polygons ─────────────────────────────────────────────

    def get_polygon_library(self):
        return self.polygon_tab.get_library()

    def set_polygon_library(self, lib):
        self.polygon_tab.set_library(lib)

    def create_default_polygon_library(self):
        return self.polygon_tab.create_default_library()

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

    # ── Shape / Sprite cross-refs (used by main_window for polygon counts) ────

    def set_shape_library(self, lib):
        self.polygon_tab.set_shape_library(lib)

    def set_sprite_library(self, lib):
        self.polygon_tab.set_sprite_library(lib)
