"""
BezierApp — freestanding QMainWindow wrapping BezierWidget.
Mirrors Java CubicCurveFrame + CubicCurvePanel.
"""
from __future__ import annotations
import os
from xml.etree import ElementTree as ET
import re

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QSizePolicy, QMessageBox,
)

from canvas.draw_panel import BezierWidget
from ui.toolbar_panel import ToolbarPanel
from ui.name_panel import NamePanel
from ui.layer_panel import LayerPanel
from ui.slider_panel import SliderPanel
from bezier_io.polygon_set_xml import write_polygon_set, read_polygon_set
from bezier_io.open_curve_set_xml import read_open_curve_set, write_open_curve_set
from bezier_io.oval_set_xml import write_oval_set, read_oval_set
from bezier_io.point_set_xml import write_point_set, read_point_set
from bezier_io.layer_set_xml import (write_layer_set, read_layer_set,
                                      peek_overall_name, read_trace_layer_info)
from bezier_io.svg_exporter import save as svg_save, save_managers as svg_save_managers
from bezier_io.svg_importer import import_svg


class BezierApp(QMainWindow):
    """
    Standalone window.  CLI: python main.py --save-dir <dir> [--load <f>] [--name <n>]
    """

    def __init__(self,
                 save_dir: str,
                 load_path: str | None = None,
                 name: str | None = None,
                 point_select: bool = False,
                 polygon_select: bool = False,
                 open_curve_select: bool = False,
                 point_mode: bool = False,
                 oval_mode: bool = False,
                 freehand_mode: bool = False,
                 parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._save_dir = save_dir

        os.makedirs(save_dir, exist_ok=True)

        if name:
            initial_name = name
        elif load_path:
            base = os.path.basename(load_path)
            initial_name = (base.replace('.layers.xml', '')
                              .replace('.xml', ''))
        else:
            initial_name = "shape"

        self._setup_ui(initial_name)
        self._setup_menus()
        self._resize_to_screen()

        if load_path and os.path.isfile(load_path):
            self._load_file(load_path)

        # Apply initial mode after loading, then always sync toolbar
        if point_select:
            self._bezier.set_point_selection_mode(True)
        elif polygon_select:
            self._bezier.set_polygon_selection_mode(True)
        elif open_curve_select:
            self._bezier.set_open_curve_selection_mode(True)
        elif point_mode:
            self._bezier.set_point_mode(True)
        elif oval_mode:
            self._bezier.set_oval_mode(True)
        elif freehand_mode:
            self._bezier.set_freehand_mode(True)
        # Always sync toolbar so the correct button is highlighted on startup
        self._bezier.mode_changed.emit()

    # ── UI ────────────────────────────────────────────────────────────────────

    def _setup_ui(self, initial_name: str) -> None:
        self.setWindowTitle("Bezier")
        central = QWidget()
        self.setCentralWidget(central)
        vbox = QVBoxLayout(central)
        vbox.setContentsMargins(0, 0, 0, 0)
        vbox.setSpacing(0)

        self._name_panel = NamePanel(self._save_dir, initial_name)
        self._name_panel.save_requested.connect(self._on_save)
        self._name_panel.load_requested.connect(self._load_file)
        vbox.addWidget(self._name_panel)

        self._bezier = BezierWidget(self)
        self._toolbar = ToolbarPanel(self._bezier)
        vbox.addWidget(self._toolbar)

        # ── canvas row: LayerPanel (left) + BezierWidget (expanding) ──────────
        self._layer_panel = LayerPanel(self._bezier)
        self._bezier.layer_changed.connect(self._layer_panel.refresh_table)

        canvas_row = QHBoxLayout()
        canvas_row.setContentsMargins(0, 0, 0, 0)
        canvas_row.setSpacing(0)
        canvas_row.addWidget(self._layer_panel)
        canvas_row.addWidget(self._bezier)

        self._bezier.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding
        )
        vbox.addLayout(canvas_row)

        # ── transform panel — below canvas (mirrors Java layout) ──────────────
        self._slider_panel = SliderPanel(self._bezier)
        vbox.addWidget(self._slider_panel)

    def _setup_menus(self) -> None:
        mb = self.menuBar()

        file_menu = mb.addMenu("File")
        file_menu.addAction("Save Polygon Set",   self._save_polygon_set,   "Ctrl+S")
        file_menu.addAction("Save Oval Set",      self._save_oval_set)
        file_menu.addAction("Save Point Set",     self._save_point_set)
        file_menu.addSeparator()
        file_menu.addAction("Export SVG",         self._export_svg)
        file_menu.addAction("Import SVG…",        self._import_svg)
        file_menu.addSeparator()
        file_menu.addAction("Load Reference Image…", self._load_reference_image)
        file_menu.addAction("Toggle Reference Image", self._bezier.toggle_reference_image)
        file_menu.addSeparator()
        file_menu.addAction("Load Trace Image…",  self._load_trace_image)
        file_menu.addSeparator()
        file_menu.addAction("Quit", self.close, "Ctrl+Q")

        help_menu = mb.addMenu("Help")
        help_menu.addAction("Bezier Draw Help", self._open_help, "F1")

        edit_menu = mb.addMenu("Edit")
        edit_menu.addAction("Undo",              self._bezier.undo,            "Ctrl+Z")
        edit_menu.addAction("Redo",              self._bezier.redo,            "Ctrl+Y")
        edit_menu.addSeparator()
        edit_menu.addAction("Select All",        self._bezier.select_all,      "Ctrl+A")
        edit_menu.addAction("Deselect All",      self._bezier.deselect_all,    "Ctrl+D")
        edit_menu.addSeparator()
        edit_menu.addAction("Copy",              self._bezier.copy_selected,   "Ctrl+C")
        edit_menu.addAction("Paste",             self._bezier.paste,           "Ctrl+V")
        edit_menu.addAction("Cut",               self._bezier.cut_selected,    "Ctrl+X")
        edit_menu.addAction("Delete",            self._bezier.delete_selected, "Backspace")
        edit_menu.addSeparator()
        edit_menu.addAction("Weld All Adjacent", self._bezier.weld_all_adjacent)
        edit_menu.addSeparator()
        edit_menu.addAction("Clear Grid",        self._bezier.clear_grid)
        edit_menu.addAction("Finish Curve",      self._bezier.finish_curve,    "Ctrl+F")
        edit_menu.addAction("Finish Open Curve", self._bezier.finish_open_curve)
        edit_menu.addAction("Create Oval",       self._bezier.create_oval)

    def _open_help(self) -> None:
        """Open the Bezier Draw help file in the default browser."""
        import webbrowser
        help_path = os.path.join(os.path.dirname(os.path.dirname(__file__)),
                                 'resources', 'help.html')
        webbrowser.open(f'file://{help_path}')

    def _resize_to_screen(self) -> None:
        from PySide6.QtGui import QGuiApplication
        screen = QGuiApplication.primaryScreen()
        if screen:
            avail = screen.availableGeometry()
            side = min(avail.width(), avail.height()) - 100
            self.resize(side, side)

    # ── save ──────────────────────────────────────────────────────────────────

    # Loom project subdirectories that are NOT for polygon data.
    # When the app is launched with --save-dir pointing at one of these,
    # polygon/layer-set saves should be redirected to the polygonSets/ sibling.
    _NON_POLYGON_SUBDIRS = frozenset({'pointSets', 'curveSets', 'ovalSets',
                                      'regularPolygons'})

    def _polygon_save_dir(self, save_dir: str) -> str:
        """Redirect to polygonSets/ when save_dir is a non-polygon Loom subdir."""
        base = os.path.basename(os.path.normpath(save_dir))
        if base in self._NON_POLYGON_SUBDIRS:
            return os.path.join(os.path.dirname(os.path.normpath(save_dir)),
                                'polygonSets')
        return save_dir

    def _on_save(self, name: str | None = None, save_dir: str | None = None) -> None:
        """Default save: dispatch by content type."""
        bw = self._bezier
        committed = bw.polygon_manager.committed_managers()
        if bw.oval_list and not committed:
            self._save_oval_set(name, save_dir)
        elif bw.point_list and not committed:
            self._save_point_set(name, save_dir)
        elif committed and all(not m.is_closed for m in committed):
            # All managers are open curves → openCurveSet
            self._save_open_curve_set(name, save_dir)
        else:
            self._save_polygon_set(name, save_dir)

    def _save_polygon_set(self, name: str | None = None,
                          save_dir: str | None = None) -> None:
        name = name or self._name_panel.name
        save_dir = save_dir or self._save_dir
        # Redirect to polygonSets/ when launched from a non-polygon Loom subdir
        poly_dir = self._polygon_save_dir(save_dir)
        os.makedirs(poly_dir, exist_ok=True)
        lm = self._bezier.layer_manager
        pm = self._bezier.polygon_manager

        if len(lm.layers) > 1:
            # Multi-layer: save per-layer files + manifest
            try:
                write_layer_set(poly_dir, name, lm, pm)
            except Exception as e:
                QMessageBox.critical(self, "Save Error", str(e))
                return
        else:
            # Single layer: plain polygonSet XML
            path = os.path.join(poly_dir, f"{name}.xml")
            try:
                write_polygon_set(path, name, pm)
            except Exception as e:
                QMessageBox.critical(self, "Save Error", str(e))
                return

        # Auto-export SVG to project-level svg/ directory (sibling of polygonSets/)
        try:
            project_root = os.path.dirname(os.path.normpath(poly_dir))
            svg_dir = os.path.join(project_root, "svg")
            svg_save(pm, svg_dir, name)
        except Exception:
            pass  # SVG export failure is non-fatal

    def _save_oval_set(self, name: str | None = None,
                       save_dir: str | None = None) -> None:
        name = name or self._name_panel.name
        save_dir = save_dir or self._save_dir
        os.makedirs(save_dir, exist_ok=True)
        path = os.path.join(save_dir, f"{name}.xml")
        try:
            write_oval_set(path, name, self._bezier.oval_list)
        except Exception as e:
            QMessageBox.critical(self, "Save Error", str(e))

    def _save_point_set(self, name: str | None = None,
                        save_dir: str | None = None) -> None:
        name = name or self._name_panel.name
        save_dir = save_dir or self._save_dir
        os.makedirs(save_dir, exist_ok=True)
        path = os.path.join(save_dir, f"{name}.xml")
        try:
            write_point_set(path, name, self._bezier.point_list,
                            self._bezier.point_pressures)
        except Exception as e:
            QMessageBox.critical(self, "Save Error", str(e))

    def _save_open_curve_set(self, name: str | None = None,
                             save_dir: str | None = None) -> None:
        name = name or self._name_panel.name
        save_dir = save_dir or self._save_dir
        os.makedirs(save_dir, exist_ok=True)
        path = os.path.join(save_dir, f"{name}.xml")
        try:
            write_open_curve_set(path, name, self._bezier.polygon_manager)
        except Exception as e:
            QMessageBox.critical(self, "Save Error", str(e))

    def _export_svg(self) -> None:
        """Explicitly export the current geometry as SVG (no XML save)."""
        name = self._name_panel.name
        svg_dir = os.path.join(os.path.dirname(self._save_dir), "svg")
        try:
            svg_save(self._bezier.polygon_manager, svg_dir, name)
            QMessageBox.information(self, "SVG Exported",
                                    f"Saved to {os.path.join(svg_dir, name + '.svg')}")
        except Exception as e:
            QMessageBox.critical(self, "SVG Export Error", str(e))

    def _import_svg(self) -> None:
        """Open an SVG file and import all <path> elements as closed polygons."""
        from PySide6.QtWidgets import QFileDialog
        path, _ = QFileDialog.getOpenFileName(
            self, "Import SVG", self._save_dir, "SVG Files (*.svg)"
        )
        if not path:
            return
        self._bezier.take_undo_snapshot()
        active_id = self._bezier.layer_manager.active_layer_id
        n = import_svg(path, self._bezier.polygon_manager, active_id)
        if n == 0:
            QMessageBox.warning(self, "SVG Import", "No recognisable paths found in the SVG.")
        else:
            self._bezier.modified.emit()

    def _load_reference_image(self) -> None:
        """Open a dialog to select a reference image for the canvas overlay."""
        from PySide6.QtWidgets import QFileDialog
        path, _ = QFileDialog.getOpenFileName(
            self, "Load Reference Image", "",
            "Images (*.png *.jpg *.jpeg *.bmp *.gif *.tiff *.webp)"
        )
        if not path:
            return
        if not self._bezier.load_reference_image(path):
            QMessageBox.warning(self, "Reference Image",
                                "Could not load the selected image.")

    def _load_trace_image(self) -> None:
        """
        Open a dialog, load the chosen image as the Trace layer.

        • Creates tracing_images/ alongside the project root if it does not exist.
        • Calls BezierWidget.load_trace_image() which creates / replaces the
          single trace layer and makes it the active layer.
        • Refreshes the layer panel so the Trace row appears immediately.
        """
        from PySide6.QtWidgets import QFileDialog
        # Default the dialog to the project's tracing_images/ folder
        project_root = os.path.dirname(self._save_dir)
        tracing_dir  = os.path.join(project_root, "tracing_images")
        os.makedirs(tracing_dir, exist_ok=True)

        start = tracing_dir if os.path.isdir(tracing_dir) else ""
        path, _ = QFileDialog.getOpenFileName(
            self, "Load Trace Image", start,
            "Images (*.png *.jpg *.jpeg *.bmp *.gif *.tiff *.tif *.webp)"
        )
        if not path:
            return
        if not self._bezier.load_trace_image(path):
            QMessageBox.warning(self, "Trace Image",
                                "Could not load the selected image.")
            return
        # Sync the layer panel's internal LayerManager reference and refresh
        self._layer_panel._lm = self._bezier.layer_manager
        self._layer_panel.refresh_table()

    # ── load — dispatches by root element ─────────────────────────────────────

    def _load_file(self, file_path: str) -> None:
        root_tag = self._peek_root_tag(file_path)
        try:
            if root_tag == 'layerSet':
                self._load_layer_set(file_path)
                return
            elif root_tag in ('polygonSet', 'openCurveSet'):
                data = read_polygon_set(file_path)
                self._bezier.load_polygon_set(data)
            elif root_tag == 'ovalSet':
                ovals = read_oval_set(file_path)
                self._bezier.load_oval_set(ovals)
            elif root_tag == 'pointSet':
                pts, pressures = read_point_set(file_path)
                self._bezier.load_point_set(pts, pressures)
            else:
                QMessageBox.warning(self, "Load",
                                    f"Unknown root element <{root_tag}>")
                return

            base = os.path.basename(file_path)
            name = base.replace('.layers.xml', '').replace('.xml', '')
            self._name_panel.name = name
        except Exception as e:
            QMessageBox.critical(self, "Load Error", str(e))

    def _load_layer_set(self, manifest_path: str) -> None:
        """Load a .layers.xml manifest: reset layers, load per-layer XMLs."""
        bw = self._bezier
        lm = bw.layer_manager

        try:
            layer_infos = read_layer_set(manifest_path)
            overall_name = peek_overall_name(manifest_path)
        except Exception as e:
            QMessageBox.critical(self, "Load Error", str(e))
            return

        dir_path = os.path.dirname(manifest_path)

        # Reset geometry and layer structure
        from model.layer import Layer
        Layer._next_id = 1          # reset counter for clean IDs on reload
        from model.layer_manager import LayerManager
        bw.layer_manager = LayerManager()
        lm = bw.layer_manager
        from model.polygon_manager import PolygonManager
        bw.polygon_manager = PolygonManager(lm)
        bw.oval_list.clear()
        bw.selected_ovals.clear()
        bw.point_list.clear()
        bw.point_pressures.clear()

        first_layer = True
        for info in layer_infos:
            if first_layer:
                layer = lm.get_active_layer()
                lm.rename_layer(layer.id, info['name'])
                first_layer = False
            else:
                layer = lm.create_layer(info['name'])
            layer.visible = info['visible']
            lm.set_active_layer_id(layer.id)
            bw.polygon_manager.sync_active_drawing_manager_layer()

            layer_file = os.path.join(dir_path, info['file'])
            if os.path.isfile(layer_file):
                try:
                    data = read_polygon_set(layer_file)
                    bw.append_polygon_set_to_layer(data, layer.id)
                except Exception as e:
                    print(f"LayerSet load: failed to load '{info['file']}': {e}")

        # Activate the first geometry layer
        geo = lm.geometry_layers()
        if geo:
            lm.set_active_layer_id(geo[0].id)
            bw.polygon_manager.sync_active_drawing_manager_layer()

        # Restore trace layer if one was saved in the manifest
        trace_info = read_trace_layer_info(manifest_path)
        if trace_info:
            img_path = trace_info.get('image_path', '')
            # Resolve relative paths from the manifest directory
            if img_path and not os.path.isabs(img_path):
                img_path = os.path.normpath(
                    os.path.join(dir_path, img_path))
            if img_path and os.path.isfile(img_path):
                bw.load_trace_image(img_path)
                trace = lm.get_trace_layer()
                if trace is not None:
                    trace.visible    = trace_info.get('visible', True)
                    trace.trace_x    = trace_info.get('x', 520.0)
                    trace.trace_y    = trace_info.get('y', 520.0)
                    trace.trace_scale = trace_info.get('scale', 1.0)
                    trace.trace_alpha = trace_info.get('alpha', 1.0)
            # Switch active layer back to the first geometry layer after loading
            if geo:
                lm.set_active_layer_id(geo[0].id)
                bw.polygon_manager.sync_active_drawing_manager_layer()

        if overall_name:
            self._name_panel.name = overall_name
        else:
            base = os.path.basename(manifest_path)
            self._name_panel.name = base.replace('.layers.xml', '')

        self._layer_panel._lm = lm
        self._layer_panel.refresh_table()
        bw.modified.emit()

    @staticmethod
    def _peek_root_tag(file_path: str) -> str:
        """Read just enough of the file to determine the root element tag."""
        try:
            with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
                head = f.read(512)
            head = re.sub(r'<\?xml[^?]*\?>', '', head)
            head = re.sub(r'<!DOCTYPE[^>]*>', '', head)
            m = re.search(r'<(\w+)', head)
            return m.group(1) if m else 'polygonSet'
        except Exception:
            return 'polygonSet'

    # ── window close → auto-save ──────────────────────────────────────────────

    def closeEvent(self, event) -> None:
        bw = self._bezier
        has_content = (bw.polygon_manager.polygon_count > 0
                       or bw.oval_list
                       or bw.point_list)
        if has_content:
            self._on_save()
        super().closeEvent(event)
