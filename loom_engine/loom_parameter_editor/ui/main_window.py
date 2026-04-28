"""
Main application window with tabbed interface.
"""
import os
import shutil
from pathlib import Path
from typing import Optional
from PySide6.QtWidgets import (
    QMainWindow, QTabWidget, QMenuBar, QMenu, QFileDialog,
    QMessageBox, QLabel, QStatusBar, QDialog, QVBoxLayout,
    QHBoxLayout, QFormLayout, QLineEdit, QPushButton, QDialogButtonBox,
    QTableWidget, QTableWidgetItem, QHeaderView, QSizePolicy
)
import datetime
from PySide6.QtCore import Qt, QUrl, QTimer
from PySide6.QtGui import QAction, QKeySequence, QDesktopServices
from .rendering_tab import RenderingTab
from .global_tab import GlobalTab
from .geometry_tab import GeometryTab
from .subdivision_tab import SubdivisionTab
from .sprite_tab import SpriteTab
from .run_tab import RunTab
from models.project import Project
from models.rendering import RendererSetLibrary
from models.global_config import GlobalConfig
from models.polygon_config import PolygonSetLibrary
from models.subdivision_config import SubdivisionParamsSetCollection
from models.sprite_config import SpriteLibrary
from models.open_curve_config import OpenCurveSetLibrary
from models.point_config import PointSetLibrary
from models.oval_config import OvalSetLibrary
from file_io.project_io import ProjectIO
from file_io.rendering_io import RenderingIO
from file_io.global_config_io import GlobalConfigIO
from file_io.polygon_config_io import PolygonConfigIO
from file_io.subdivision_config_io import SubdivisionConfigIO
from file_io.sprite_config_io import SpriteConfigIO, auto_generate_shapes_xml, migrate_shapes_into_sprites
from file_io.open_curve_config_io import OpenCurveConfigIO
from file_io.point_config_io import PointConfigIO
from file_io.oval_config_io import OvalConfigIO
from app_settings import AppSettings


class OpenProjectDialog(QDialog):
    """Lists Loom projects found in the configured projects directory.

    Avoids the macOS hidden-directory problem: the projects directory
    (~/.loom_projects) starts with a dot, so the native file picker hides
    its contents.  This dialog reads the directory directly and presents
    found projects as a simple list.
    """

    def __init__(self, parent=None, projects_dir: str = ""):
        super().__init__(parent)
        self.setWindowTitle("Open Project")
        self.setMinimumSize(460, 360)

        self._selected_path: str = ""
        self._projects_dir = projects_dir or os.path.expanduser("~/.loom_projects")

        layout = QVBoxLayout(self)

        # Directory row
        dir_row = QHBoxLayout()
        dir_row.addWidget(QLabel("Projects folder:"))
        self._dir_label = QLabel()
        self._dir_label.setStyleSheet("color: #555; font-size: 11px;")
        self._dir_label.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
        dir_row.addWidget(self._dir_label, 1)
        browse_btn = QPushButton("Change…")
        browse_btn.setFixedWidth(80)
        browse_btn.clicked.connect(self._browse_dir)
        dir_row.addWidget(browse_btn)
        layout.addLayout(dir_row)

        # Project table
        self._table = QTableWidget()
        self._table.setColumnCount(4)
        self._table.setHorizontalHeaderLabels(["#", "Name", "Date", "Edited"])
        self._table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Fixed)
        self._table.setColumnWidth(0, 35)
        self._table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self._table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        self._table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        self._table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self._table.setSelectionMode(QTableWidget.SelectionMode.SingleSelection)
        self._table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self._table.setAlternatingRowColors(True)
        self._table.verticalHeader().setVisible(False)
        self._table.cellDoubleClicked.connect(lambda r, c: self._accept_selection())
        self._table.currentCellChanged.connect(self._on_cell_changed)
        layout.addWidget(self._table)

        # Buttons
        btn_row = QHBoxLayout()
        btn_row.addStretch()
        self._open_btn = QPushButton("Open")
        self._open_btn.setEnabled(False)
        self._open_btn.clicked.connect(self._accept_selection)
        cancel_btn = QPushButton("Cancel")
        cancel_btn.clicked.connect(self.reject)
        btn_row.addWidget(cancel_btn)
        btn_row.addWidget(self._open_btn)
        layout.addLayout(btn_row)

        self._populate(self._projects_dir)

    def _populate(self, directory: str) -> None:
        """Scan directory for project folders and fill the table."""
        self._projects_dir = directory
        self._dir_label.setText(directory)
        self._table.setRowCount(0)
        self._selected_path = ""
        self._open_btn.setEnabled(False)

        if not os.path.isdir(directory):
            return

        entries = []
        try:
            for name in sorted(os.listdir(directory)):
                proj_dir = os.path.join(directory, name)
                proj_xml = os.path.join(proj_dir, "project.xml")
                if os.path.isfile(proj_xml):
                    # Creation date: st_birthtime on macOS, fallback to st_ctime
                    try:
                        st = os.stat(proj_dir)
                        birth = getattr(st, "st_birthtime", st.st_ctime)
                        date_str = datetime.datetime.fromtimestamp(birth).strftime("%d/%m/%Y")
                    except OSError:
                        date_str = ""
                    # Last edited: project.xml mtime
                    try:
                        mtime = os.path.getmtime(proj_xml)
                        edited_str = datetime.datetime.fromtimestamp(mtime).strftime("%d/%m/%Y")
                    except OSError:
                        edited_str = ""
                    entries.append((name, proj_dir, date_str, edited_str))
        except OSError:
            pass

        for row_idx, (name, path, date_str, edited_str) in enumerate(entries):
            self._table.insertRow(row_idx)
            num_item = QTableWidgetItem(str(row_idx + 1))
            num_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            num_item.setData(Qt.ItemDataRole.UserRole, path)
            self._table.setItem(row_idx, 0, num_item)
            self._table.setItem(row_idx, 1, QTableWidgetItem(name))
            self._table.setItem(row_idx, 2, QTableWidgetItem(date_str))
            self._table.setItem(row_idx, 3, QTableWidgetItem(edited_str))

    def _on_cell_changed(self, current_row, current_col, previous_row, previous_col):
        item = self._table.item(current_row, 0) if current_row >= 0 else None
        path = item.data(Qt.ItemDataRole.UserRole) if item else None
        self._selected_path = path or ""
        self._open_btn.setEnabled(bool(self._selected_path))

    def _accept_selection(self):
        if self._selected_path:
            self.accept()

    def _browse_dir(self) -> None:
        """Let user navigate to a different projects directory.
        Uses DontUseNativeDialog to avoid the macOS hidden-folder problem."""
        chosen = QFileDialog.getExistingDirectory(
            self, "Select Projects Folder",
            self._projects_dir,
            QFileDialog.Option.ShowDirsOnly | QFileDialog.Option.DontUseNativeDialog
        )
        if chosen:
            self._populate(chosen)

    def selected_project_dir(self) -> str:
        """Return the selected project directory path, or empty string."""
        return self._selected_path


class NewProjectDialog(QDialog):
    """Dialog for creating a new project with location and name."""

    def __init__(self, parent=None, default_location: str = ""):
        super().__init__(parent)
        self.setWindowTitle("New Project")
        self.setMinimumWidth(500)

        if not default_location:
            default_location = os.path.expanduser("~/.loom_projects")

        layout = QVBoxLayout(self)

        form = QFormLayout()

        # Project location
        loc_layout = QHBoxLayout()
        self.location_edit = QLineEdit()
        self.location_edit.setText(default_location)
        loc_layout.addWidget(self.location_edit)

        browse_btn = QPushButton("Browse...")
        browse_btn.clicked.connect(self._browse_location)
        loc_layout.addWidget(browse_btn)
        form.addRow("Location:", loc_layout)

        # Project name
        self.name_edit = QLineEdit()
        self.name_edit.setText("NewProject")
        self.name_edit.setPlaceholderText("Enter project name")
        form.addRow("Project Name:", self.name_edit)

        # Preview of full path
        self.preview_label = QLabel()
        self._update_preview()
        self.location_edit.textChanged.connect(self._update_preview)
        self.name_edit.textChanged.connect(self._update_preview)
        form.addRow("Full Path:", self.preview_label)

        layout.addLayout(form)

        # Buttons
        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._validate_and_accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _browse_location(self):
        """Browse for project location.
        Uses DontUseNativeDialog to avoid the macOS hidden-folder problem."""
        dir_path = QFileDialog.getExistingDirectory(
            self, "Select Projects Directory",
            self.location_edit.text(),
            QFileDialog.Option.ShowDirsOnly | QFileDialog.Option.DontUseNativeDialog
        )
        if dir_path:
            self.location_edit.setText(dir_path)

    def _update_preview(self):
        """Update the path preview."""
        location = self.location_edit.text()
        name = self.name_edit.text()
        if location and name:
            full_path = os.path.join(location, name)
            self.preview_label.setText(full_path)
        else:
            self.preview_label.setText("")

    def _validate_and_accept(self):
        """Validate inputs and accept."""
        name = self.name_edit.text().strip()
        if not name:
            QMessageBox.warning(self, "Invalid Name", "Project name cannot be empty.")
            return

        # Check for invalid characters
        invalid_chars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|']
        for char in invalid_chars:
            if char in name:
                QMessageBox.warning(self, "Invalid Name",
                    f"Project name cannot contain '{char}'")
                return

        location = self.location_edit.text().strip()
        if not location:
            QMessageBox.warning(self, "Invalid Location", "Location cannot be empty.")
            return

        full_path = os.path.join(location, name)
        if os.path.exists(full_path):
            result = QMessageBox.question(
                self, "Directory Exists",
                f"The directory '{full_path}' already exists.\n"
                "Do you want to create the project there anyway?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
            if result != QMessageBox.StandardButton.Yes:
                return

        self.accept()

    def get_project_path(self) -> str:
        """Get the full project path."""
        return os.path.join(self.location_edit.text(), self.name_edit.text())

    def get_project_name(self) -> str:
        """Get the project name."""
        return self.name_edit.text()


class MainWindow(QMainWindow):
    """Main application window."""

    def __init__(self):
        super().__init__()
        self._project: Optional[Project] = None
        self._project_path: Optional[str] = None
        self._project_dir: Optional[str] = None
        self._modified = False

        # Persistent app-level settings
        self._app_settings = AppSettings()

        self.setWindowTitle("Loom Parameter Editor")
        self.setMinimumSize(1200, 800)

        # Create tab widget
        self.tab_widget = QTabWidget()
        self.setCentralWidget(self.tab_widget)

        # Create tabs (ordered by workflow: define polygons → subdivide → compose shapes → place sprites → style)
        self.global_tab = GlobalTab()
        self.global_tab.modified.connect(self._on_modified)
        self.global_tab.background_image_browse_requested.connect(self._on_background_image_browse)
        self.global_tab.projects_dir_changed.connect(self._on_projects_dir_changed)
        self.tab_widget.addTab(self.global_tab, "Global")

        self.geometry_tab = GeometryTab()
        self.geometry_tab.modified.connect(self._on_modified)
        self.geometry_tab.modified.connect(self._on_geometry_modified)
        self.tab_widget.addTab(self.geometry_tab, "Geometry")
        # Aliases so all existing references in this file continue to work:
        self.polygon_tab    = self.geometry_tab.spline_tab
        self.open_curve_tab = self.geometry_tab.open_curve_tab
        self.point_tab      = self.geometry_tab.point_tab
        self.oval_tab       = self.geometry_tab.oval_tab

        self.subdivision_tab = SubdivisionTab()
        self.subdivision_tab.modified.connect(self._on_modified)
        self.subdivision_tab.polygon_baked.connect(self._on_polygon_baked)
        self.tab_widget.addTab(self.subdivision_tab, "Subdivision")

        self.sprite_tab = SpriteTab()
        self.sprite_tab.modified.connect(self._on_modified)
        self.sprite_tab.modified.connect(self._on_sprite_library_for_polygon_counts)
        self.tab_widget.addTab(self.sprite_tab, "Sprites")

        self.rendering_tab = RenderingTab()
        self.rendering_tab.modified.connect(self._on_modified)
        self.tab_widget.addTab(self.rendering_tab, "Rendering")

        # Wire geometry convenience-panel signals to refresh downstream tabs
        self.geometry_tab.subdivisionChanged.connect(self._on_geometry_subdivision_changed)
        self.geometry_tab.spriteLibraryChanged.connect(self._on_geometry_sprite_library_changed)
        self.geometry_tab.rendererLibraryChanged.connect(self._on_geometry_renderer_library_changed)
        self.geometry_tab.newSpriteCreated.connect(self._on_geometry_new_sprite_created)

        self.run_tab = RunTab(save_callback=self._save_project)
        self.tab_widget.addTab(self.run_tab, "Run")

        # Place the media process controls in the top-right corner of the tab
        # bar, level with the tab labels.
        self.tab_widget.setCornerWidget(
            self.run_tab.control_bar, Qt.Corner.TopRightCorner
        )

        # Initialise global tab with persisted projects directory and engine selection
        self.global_tab.set_projects_dir(self._app_settings.default_projects_dir)
        self.global_tab.set_selected_engine(self._app_settings.selected_engine)
        self.run_tab.set_engine(self._app_settings.selected_engine)
        self.subdivision_tab.set_engine(self._app_settings.selected_engine)
        if self._app_settings.loom_app_path:
            self.run_tab.set_loom_app_path(self._app_settings.loom_app_path)

        # Propagate engine changes from Global tab → Run tab and persist
        self.global_tab.engine_changed.connect(self._on_engine_changed)
        self.run_tab.loom_app_path_changed.connect(self._on_loom_app_path_changed)

        # Connect signals for output size hint (quality × canvas dims)
        self.run_tab._quality_spin.valueChanged.connect(self._update_output_hint)
        self.global_tab.width_spin.valueChanged.connect(self._update_output_hint)
        self.global_tab.height_spin.valueChanged.connect(self._update_output_hint)
        self.global_tab.width_spin.valueChanged.connect(self._update_preview_canvas_size)
        self.global_tab.height_spin.valueChanged.connect(self._update_preview_canvas_size)

        # Create menus
        self._create_menus()

        # Status bar
        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)
        self.project_label = QLabel("No project loaded")
        self.status_bar.addPermanentWidget(self.project_label)

        # Start with a new project (silent, no dialog)
        self._create_empty_project()

    def _create_menus(self) -> None:
        """Create application menus."""
        menubar = self.menuBar()

        # File menu
        file_menu = menubar.addMenu("File")

        new_action = QAction("New Project...", self)
        new_action.setShortcut(QKeySequence.StandardKey.New)
        new_action.triggered.connect(self._new_project)
        file_menu.addAction(new_action)

        open_action = QAction("Open Project...", self)
        open_action.setShortcut(QKeySequence.StandardKey.Open)
        open_action.triggered.connect(self._open_project)
        file_menu.addAction(open_action)

        self._recent_menu = file_menu.addMenu("Open Recent Project")
        self._rebuild_recent_menu()

        file_menu.addSeparator()

        save_action = QAction("Save All", self)
        save_action.setShortcut(QKeySequence.StandardKey.Save)
        save_action.triggered.connect(self._save_project)
        file_menu.addAction(save_action)

        save_as_action = QAction("Save Project As...", self)
        save_as_action.setShortcut(QKeySequence.StandardKey.SaveAs)
        save_as_action.triggered.connect(self._save_project_as)
        file_menu.addAction(save_as_action)

        file_menu.addSeparator()

        # Individual tab save submenu
        save_tab_menu = file_menu.addMenu("Save Tab")

        save_global_action = QAction("Save Global Config", self)
        save_global_action.triggered.connect(lambda: self._save_single_tab("global"))
        save_tab_menu.addAction(save_global_action)

        save_rendering_action = QAction("Save Rendering Config", self)
        save_rendering_action.triggered.connect(lambda: self._save_single_tab("rendering"))
        save_tab_menu.addAction(save_rendering_action)

        save_geometry_action = QAction("Save Geometry Config", self)
        save_geometry_action.triggered.connect(self._save_geometry_config)
        save_tab_menu.addAction(save_geometry_action)

        save_subdivision_action = QAction("Save Subdivision Config", self)
        save_subdivision_action.triggered.connect(lambda: self._save_single_tab("subdivision"))
        save_tab_menu.addAction(save_subdivision_action)

        save_sprites_action = QAction("Save Sprites Config", self)
        save_sprites_action.triggered.connect(lambda: self._save_single_tab("sprites"))
        save_tab_menu.addAction(save_sprites_action)

        file_menu.addSeparator()

        # Export/Import submenu
        export_menu = file_menu.addMenu("Export")

        export_rendering_action = QAction("Export Rendering XML...", self)
        export_rendering_action.triggered.connect(self._export_rendering)
        export_menu.addAction(export_rendering_action)

        export_polygons_action = QAction("Export Polygons XML...", self)
        export_polygons_action.triggered.connect(self._export_polygons)
        export_menu.addAction(export_polygons_action)

        export_subdivision_action = QAction("Export Subdivision XML...", self)
        export_subdivision_action.triggered.connect(self._export_subdivision)
        export_menu.addAction(export_subdivision_action)

        export_sprites_action = QAction("Export Sprites XML...", self)
        export_sprites_action.triggered.connect(self._export_sprites)
        export_menu.addAction(export_sprites_action)

        import_menu = file_menu.addMenu("Import")

        import_rendering_action = QAction("Import Rendering XML...", self)
        import_rendering_action.triggered.connect(self._import_rendering)
        import_menu.addAction(import_rendering_action)

        import_polygons_action = QAction("Import Polygons XML...", self)
        import_polygons_action.triggered.connect(self._import_polygons)
        import_menu.addAction(import_polygons_action)

        import_subdivision_action = QAction("Import Subdivision XML...", self)
        import_subdivision_action.triggered.connect(self._import_subdivision)
        import_menu.addAction(import_subdivision_action)

        import_sprites_action = QAction("Import Sprites XML...", self)
        import_sprites_action.triggered.connect(self._import_sprites)
        import_menu.addAction(import_sprites_action)

        file_menu.addSeparator()

        quit_action = QAction("Quit", self)
        quit_action.setShortcut(QKeySequence.StandardKey.Quit)
        quit_action.triggered.connect(self.close)
        file_menu.addAction(quit_action)

        # Edit menu
        edit_menu = menubar.addMenu("Edit")

        add_set_action = QAction("Add Renderer Set", self)
        add_set_action.triggered.connect(lambda: self.rendering_tab.tree_widget._add_set())
        edit_menu.addAction(add_set_action)

        add_renderer_action = QAction("Add Renderer", self)
        add_renderer_action.triggered.connect(lambda: self.rendering_tab.tree_widget._add_renderer())
        edit_menu.addAction(add_renderer_action)

        # Run menu (shortcuts for Loom control)
        run_menu = menubar.addMenu("Run")

        run_loom_action = QAction("Run Loom", self)
        run_loom_action.setShortcut(QKeySequence("Ctrl+L"))
        run_loom_action.triggered.connect(self.run_tab._on_run)
        run_menu.addAction(run_loom_action)

        reload_action = QAction("Reload", self)
        reload_action.setShortcut(QKeySequence("Ctrl+R"))
        reload_action.setShortcutContext(Qt.ShortcutContext.ApplicationShortcut)
        reload_action.triggered.connect(self.run_tab._on_reload)
        run_menu.addAction(reload_action)

        stop_loom_action = QAction("Stop Loom", self)
        stop_loom_action.setShortcut(QKeySequence("Ctrl+H"))
        stop_loom_action.triggered.connect(self.run_tab._on_stop)
        run_menu.addAction(stop_loom_action)

        # Help menu
        help_menu = menubar.addMenu("Help")

        user_guide_action = QAction("User Guide", self)
        user_guide_action.setShortcut(QKeySequence("F1"))
        user_guide_action.triggered.connect(self._show_user_guide)
        help_menu.addAction(user_guide_action)

        help_menu.addSeparator()

        about_action = QAction("About", self)
        about_action.triggered.connect(self._show_about)
        help_menu.addAction(about_action)

    def _create_project_directory_structure(self, project_dir: str) -> None:
        """Create the project directory structure."""
        # Main project directory
        os.makedirs(project_dir, exist_ok=True)

        # Configuration directory (for XML files)
        config_dir = os.path.join(project_dir, "configuration")
        os.makedirs(config_dir, exist_ok=True)

        # PolygonSets directory
        polygon_sets_dir = os.path.join(project_dir, "polygonSets")
        os.makedirs(polygon_sets_dir, exist_ok=True)

        # CurveSets directory
        curve_sets_dir = os.path.join(project_dir, "curveSets")
        os.makedirs(curve_sets_dir, exist_ok=True)

        # PointSets directory
        point_sets_dir = os.path.join(project_dir, "pointSets")
        os.makedirs(point_sets_dir, exist_ok=True)

        # Regular polygons directory (editor-only asset store)
        regular_polygons_dir = os.path.join(project_dir, "regularPolygons")
        os.makedirs(regular_polygons_dir, exist_ok=True)

        # Morph targets directory
        morph_targets_dir = os.path.join(project_dir, "morphTargets")
        os.makedirs(morph_targets_dir, exist_ok=True)

        # Brushes directory (for BRUSHED renderer mode)
        brushes_dir = os.path.join(project_dir, "brushes")
        os.makedirs(brushes_dir, exist_ok=True)

        # Background image directory
        bg_image_dir = os.path.join(project_dir, "background_image")
        os.makedirs(bg_image_dir, exist_ok=True)

        # Renders directory
        renders_dir = os.path.join(project_dir, "renders")
        os.makedirs(renders_dir, exist_ok=True)

        # Stills subdirectory
        stills_dir = os.path.join(renders_dir, "stills")
        os.makedirs(stills_dir, exist_ok=True)

        # Animations subdirectory
        animations_dir = os.path.join(renders_dir, "animations")
        os.makedirs(animations_dir, exist_ok=True)

        # Palettes directory
        palettes_dir = os.path.join(project_dir, "palettes")
        os.makedirs(palettes_dir, exist_ok=True)

    def _create_empty_project(self) -> None:
        """Create an empty project without dialog (for startup)."""
        self._project = ProjectIO.create_new("New Project")
        self._project_path = None
        self._project_dir = None
        self._modified = False

        # Create default configs for all tabs
        global_config = self.global_tab.create_default_config()
        global_config.name = "New Project"
        self.global_tab.set_config(global_config)
        self.run_tab.set_drawing_settings(
            global_config.quality_multiple,
            global_config.scale_image,
            global_config.animating,
            global_config.draw_background_once,
        )
        self.subdivision_tab.set_subdividing(global_config.subdividing)
        self.sprite_tab.set_canvas_size(global_config.width, global_config.height)

        library = self.rendering_tab.create_default_library()
        self.rendering_tab.set_library(library)

        polygon_library = self.geometry_tab.create_default_polygon_library()
        self.geometry_tab.set_polygon_library(polygon_library)

        subdivision_collection = self.subdivision_tab.create_default_collection()
        self.subdivision_tab.set_collection(subdivision_collection)

        sprite_library = self.sprite_tab.create_default_library()
        self.sprite_tab.set_library(sprite_library)

        open_curve_library = self.open_curve_tab.create_default_library()
        self.open_curve_tab.set_library(open_curve_library)

        point_library = self.point_tab.create_default_library()
        self.point_tab.set_library(point_library)

        oval_library = self.oval_tab.create_default_library()
        self.oval_tab.set_library(oval_library)

        self._update_title()
        self.project_label.setText("New Project (unsaved)")

    def _new_project(self) -> None:
        """Create a new project with dialog."""
        if not self._check_save():
            return

        dialog = NewProjectDialog(self, default_location=self._app_settings.default_projects_dir)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return

        project_dir = dialog.get_project_path()
        project_name = dialog.get_project_name()

        try:
            # Create directory structure
            self._create_project_directory_structure(project_dir)

            # Create project
            self._project = ProjectIO.create_new(project_name)
            self._project_dir = project_dir
            self._project_path = os.path.join(project_dir, "project.xml")

            # Set up file references with new structure
            self._project.add_file("global", "configuration/global_config.xml")
            self._project.add_file("rendering", "configuration/rendering.xml")
            self._project.add_file("polygons", "configuration/polygons.xml")
            self._project.add_file("subdivision", "configuration/subdivision.xml")
            self._project.add_file("shapes", "configuration/shapes.xml")
            self._project.add_file("sprites", "configuration/sprites.xml")
            self._project.add_file("curves", "configuration/curves.xml")
            self._project.add_file("points", "configuration/points.xml")
            self._project.add_file("ovals", "configuration/ovals.xml")

            self._modified = False

            # Create default configs
            global_config = self.global_tab.create_default_config()
            global_config.name = project_name
            self.global_tab.set_config(global_config)
            self.run_tab.set_drawing_settings(
                global_config.quality_multiple,
                global_config.scale_image,
                global_config.animating,
                global_config.draw_background_once,
            )
            self.subdivision_tab.set_subdividing(global_config.subdividing)
            self.sprite_tab.set_canvas_size(global_config.width, global_config.height)

            library = self.rendering_tab.create_default_library()
            self.rendering_tab.set_library(library)

            polygon_library = self.geometry_tab.create_default_polygon_library()
            self.geometry_tab.set_polygon_library(polygon_library)

            subdivision_collection = self.subdivision_tab.create_default_collection()
            self.subdivision_tab.set_collection(subdivision_collection)

            sprite_library = self.sprite_tab.create_default_library()
            self.sprite_tab.set_library(sprite_library)

            open_curve_library = self.open_curve_tab.create_default_library()
            self.open_curve_tab.set_library(open_curve_library)

            point_library = self.point_tab.create_default_library()
            self.point_tab.set_library(point_library)

            oval_library = self.oval_tab.create_default_library()
            self.oval_tab.set_library(oval_library)

            # Notify tabs of project directory for polygon file lookups
            self._notify_tabs_of_project_dir()

            # Save immediately
            self._do_save(self._project_path)

            self._update_title()
            self.project_label.setText(project_name)
            self.status_bar.showMessage(f"Created project at {project_dir}", 3000)
            self._app_settings.add_recent_project(project_dir)
            self._rebuild_recent_menu()

        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to create project:\n{e}")

    def _rebuild_recent_menu(self) -> None:
        """Repopulate the Open Recent Project submenu from app settings."""
        self._recent_menu.clear()
        recents = self._app_settings.recent_projects
        if not recents:
            no_action = QAction("(no recent projects)", self)
            no_action.setEnabled(False)
            self._recent_menu.addAction(no_action)
        else:
            for path in recents:
                name = os.path.basename(path)
                action = QAction(name, self)
                action.setToolTip(path)
                action.triggered.connect(lambda checked, p=path: self._open_recent_project(p))
                self._recent_menu.addAction(action)

    def _notify_tabs_of_project_dir(self) -> None:
        """Notify tabs of the current project directory for cross-references."""
        if self._project_dir:
            # Notify polygon tab of polygonSets directory
            polygon_sets_dir = os.path.join(self._project_dir, "polygonSets")
            if hasattr(self.polygon_tab, 'set_polygon_sets_directory'):
                self.polygon_tab.set_polygon_sets_directory(polygon_sets_dir)

            # Notify open curve tab of curveSets directory
            curve_sets_dir = os.path.join(self._project_dir, "curveSets")
            if hasattr(self, 'open_curve_tab') and hasattr(self.open_curve_tab, 'set_curve_sets_directory'):
                self.open_curve_tab.set_curve_sets_directory(curve_sets_dir)

            # Notify regular polygon tab of regularPolygons directory
            regular_polygons_dir = os.path.join(self._project_dir, "regularPolygons")
            self.geometry_tab.set_regular_polygons_directory(regular_polygons_dir)

            # Notify point tab of pointSets directory
            point_sets_dir = os.path.join(self._project_dir, "pointSets")
            if hasattr(self, 'point_tab') and hasattr(self.point_tab, 'set_point_sets_directory'):
                self.point_tab.set_point_sets_directory(point_sets_dir)

            # Notify oval tab of ovalSets directory
            oval_sets_dir = os.path.join(self._project_dir, "ovalSets")
            if hasattr(self, 'oval_tab') and hasattr(self.oval_tab, 'set_oval_sets_directory'):
                self.oval_tab.set_oval_sets_directory(oval_sets_dir)

            # Notify geometry tab of sprite library (for usage counts + Quick Setup)
            if hasattr(self.geometry_tab, 'set_sprite_library'):
                self.geometry_tab.set_sprite_library(self.sprite_tab.get_library())

            # Notify sprite tab of geometry libraries and rendering config for dropdowns
            if hasattr(self.sprite_tab, 'set_polygon_library'):
                self.sprite_tab.set_polygon_library(self.geometry_tab.get_polygon_library())
            if hasattr(self, 'open_curve_tab') and hasattr(self.sprite_tab, 'set_open_curve_library'):
                self.sprite_tab.set_open_curve_library(self.open_curve_tab.get_library())
            if hasattr(self, 'point_tab') and hasattr(self.sprite_tab, 'set_point_set_library'):
                self.sprite_tab.set_point_set_library(self.point_tab.get_library())
            if hasattr(self, 'oval_tab') and hasattr(self.sprite_tab, 'set_oval_set_library'):
                self.sprite_tab.set_oval_set_library(self.oval_tab.get_library())
            if hasattr(self.sprite_tab, 'set_subdivision_collection'):
                self.sprite_tab.set_subdivision_collection(self.subdivision_tab.get_collection())
            if hasattr(self.sprite_tab, 'set_renderer_library'):
                self.sprite_tab.set_renderer_library(self.rendering_tab.get_library())

            # Notify geometry tab of subdivision and renderer libraries for convenience panel
            if hasattr(self.geometry_tab, 'set_subdivision_collection'):
                self.geometry_tab.set_subdivision_collection(
                    self.subdivision_tab.get_collection())
            if hasattr(self.geometry_tab, 'set_renderer_library'):
                self.geometry_tab.set_renderer_library(self.rendering_tab.get_library())

            # Notify rendering tab of brushes directory
            if hasattr(self.rendering_tab, 'set_project_dir'):
                self.rendering_tab.set_project_dir(self._project_dir)

            # Notify sprite tab of project directory for morph targets
            if hasattr(self.sprite_tab, 'set_project_dir'):
                self.sprite_tab.set_project_dir(self._project_dir)

            # Notify subdivision tab of project directory for bake feature
            if hasattr(self.subdivision_tab, 'set_project_dir'):
                self.subdivision_tab.set_project_dir(self._project_dir)

            # Notify run tab of project directory
            self.run_tab.set_project_dir(self._project_dir)

            # Notify bitmap polygon tab of relevant directories
            if hasattr(self.geometry_tab, 'set_bitmap_polygon_dirs'):
                bg_image_dir = os.path.join(self._project_dir, "background_image")
                self.geometry_tab.set_bitmap_polygon_dirs(
                    polygon_sets_dir, bg_image_dir)

    def _open_project(self) -> None:
        """Open an existing project via the project-list dialog."""
        if not self._check_save():
            return

        dialog = OpenProjectDialog(self, projects_dir=self._app_settings.default_projects_dir)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return

        project_dir = dialog.selected_project_dir()
        if not project_dir:
            return

        file_path = os.path.join(project_dir, "project.xml")
        if not os.path.isfile(file_path):
            QMessageBox.warning(
                self, "Not a Loom Project",
                f"No project.xml found in:\n{project_dir}"
            )
            return

        self._load_project_dir(project_dir)

    def _open_recent_project(self, project_dir: str) -> None:
        """Open a project directly from the recent-projects list."""
        if not self._check_save():
            return

        if not os.path.isdir(project_dir):
            QMessageBox.warning(self, "Project Not Found",
                                f"Project directory no longer exists:\n{project_dir}")
            self._app_settings.recent_projects = [
                p for p in self._app_settings.recent_projects if p != project_dir
            ]
            self._app_settings.save()
            self._rebuild_recent_menu()
            return

        file_path = os.path.join(project_dir, "project.xml")
        if not os.path.isfile(file_path):
            QMessageBox.warning(self, "Not a Loom Project",
                                f"No project.xml found in:\n{project_dir}")
            return

        self._load_project_dir(project_dir)

    def _load_project_dir(self, project_dir: str) -> None:
        """Load a project from the given directory (must contain project.xml)."""
        file_path = os.path.join(project_dir, "project.xml")
        try:
            self._project = ProjectIO.load(file_path)
            self._project_path = file_path
            self._project_dir = project_dir

            # Load global configuration
            global_file = self._project.get_file("global")
            if global_file:
                global_path = os.path.join(project_dir, global_file.path)
                if os.path.exists(global_path):
                    global_config = GlobalConfigIO.load(global_path)
                    self.global_tab.set_config(global_config)
                else:
                    global_config = self.global_tab.create_default_config()
                    global_config.name = self._project.name
                    self.global_tab.set_config(global_config)
            else:
                global_config = self.global_tab.create_default_config()
                global_config.name = self._project.name
                self.global_tab.set_config(global_config)
            # Sync drawing settings to Run tab and subdivision toggle
            self.run_tab.set_drawing_settings(
                global_config.quality_multiple,
                global_config.scale_image,
                global_config.animating,
                global_config.draw_background_once,
            )
            self.subdivision_tab.set_subdividing(global_config.subdividing)
            self.sprite_tab.set_canvas_size(global_config.width, global_config.height)

            # Load rendering configuration
            rendering_file = self._project.get_file("rendering")
            if rendering_file:
                rendering_path = os.path.join(project_dir, rendering_file.path)
                if os.path.exists(rendering_path):
                    library = RenderingIO.load(rendering_path)
                    self.rendering_tab.set_library(library)
                else:
                    library = self.rendering_tab.create_default_library()
                    self.rendering_tab.set_library(library)
            else:
                library = self.rendering_tab.create_default_library()
                self.rendering_tab.set_library(library)

            # Load polygon configuration
            polygons_file = self._project.get_file("polygons")
            if polygons_file:
                polygons_path = os.path.join(project_dir, polygons_file.path)
                if os.path.exists(polygons_path):
                    polygon_library = PolygonConfigIO.load(polygons_path)
                    self.geometry_tab.set_polygon_library(polygon_library)
                else:
                    polygon_library = self.geometry_tab.create_default_polygon_library()
                    self.geometry_tab.set_polygon_library(polygon_library)
            else:
                polygon_library = self.geometry_tab.create_default_polygon_library()
                self.geometry_tab.set_polygon_library(polygon_library)

            # Load subdivision configuration
            subdivision_file = self._project.get_file("subdivision")
            if subdivision_file:
                subdivision_path = os.path.join(project_dir, subdivision_file.path)
                if os.path.exists(subdivision_path):
                    subdivision_collection = SubdivisionConfigIO.load(subdivision_path)
                    self.subdivision_tab.set_collection(subdivision_collection)
                else:
                    subdivision_collection = self.subdivision_tab.create_default_collection()
                    self.subdivision_tab.set_collection(subdivision_collection)
            else:
                subdivision_collection = self.subdivision_tab.create_default_collection()
                self.subdivision_tab.set_collection(subdivision_collection)

            # Load sprite configuration
            sprite_file = self._project.get_file("sprites")
            if sprite_file:
                sprite_path = os.path.join(project_dir, sprite_file.path)
                if os.path.exists(sprite_path):
                    sprite_library = SpriteConfigIO.load(sprite_path)
                    self.sprite_tab.set_library(sprite_library)
                else:
                    sprite_library = self.sprite_tab.create_default_library()
                    self.sprite_tab.set_library(sprite_library)
            else:
                sprite_library = self.sprite_tab.create_default_library()
                self.sprite_tab.set_library(sprite_library)

            # Backward-compat migration: copy shapes.xml geo fields into SpriteDef
            shapes_path = os.path.join(project_dir, "configuration", "shapes.xml")
            if not os.path.isfile(shapes_path):
                shapes_path = os.path.join(project_dir, "shapes.xml")
            if os.path.isfile(shapes_path):
                migrate_shapes_into_sprites(shapes_path, sprite_library)

            # Load open curve configuration
            curves_file = self._project.get_file("curves")
            if curves_file:
                curves_path = os.path.join(project_dir, curves_file.path)
                if os.path.exists(curves_path):
                    open_curve_library = OpenCurveConfigIO.load(curves_path)
                    self.open_curve_tab.set_library(open_curve_library)
                else:
                    open_curve_library = self.open_curve_tab.create_default_library()
                    self.open_curve_tab.set_library(open_curve_library)
            else:
                open_curve_library = self.open_curve_tab.create_default_library()
                self.open_curve_tab.set_library(open_curve_library)

            # Load point set configuration
            points_file = self._project.get_file("points")
            if points_file:
                points_path = os.path.join(project_dir, points_file.path)
                if os.path.exists(points_path):
                    point_library = PointConfigIO.load(points_path)
                    self.point_tab.set_library(point_library)
                else:
                    point_library = self.point_tab.create_default_library()
                    self.point_tab.set_library(point_library)
            else:
                point_library = self.point_tab.create_default_library()
                self.point_tab.set_library(point_library)

            # Load oval set configuration
            ovals_file = self._project.get_file("ovals")
            if ovals_file:
                ovals_path = os.path.join(project_dir, ovals_file.path)
                if os.path.exists(ovals_path):
                    oval_library = OvalConfigIO.load(ovals_path)
                    self.oval_tab.set_library(oval_library)
                else:
                    oval_library = self.oval_tab.create_default_library()
                    self.oval_tab.set_library(oval_library)
            else:
                oval_library = self.oval_tab.create_default_library()
                self.oval_tab.set_library(oval_library)

            # Notify tabs of project directory
            self._notify_tabs_of_project_dir()

            self._modified = False
            self._update_title()
            self.project_label.setText(self._project.name)
            self.status_bar.showMessage(f"Opened {file_path}", 3000)
            self._app_settings.add_recent_project(project_dir)
            self._rebuild_recent_menu()

        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to open project:\n{e}")

    def _save_project(self) -> bool:
        """Save the current project."""
        if not self._project_path:
            return self._save_project_as()

        return self._do_save(self._project_path)

    def _save_project_as(self) -> bool:
        """Save the project to a new location."""
        dialog = NewProjectDialog(self, default_location=self._app_settings.default_projects_dir)
        # Pre-fill with current project name from the Global tab (may have been edited)
        current_name = self._get_full_global_config().name
        if current_name and current_name != "Untitled":
            dialog.name_edit.setText(current_name)
        elif self._project:
            dialog.name_edit.setText(self._project.name)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return False

        project_dir = dialog.get_project_path()
        project_name = dialog.get_project_name()

        try:
            # Remember old project dir for copying polygonSets
            old_project_dir = self._project_dir

            # Create directory structure
            self._create_project_directory_structure(project_dir)

            # Copy polygonSets from old project to new project
            if old_project_dir:
                old_poly_dir = os.path.join(old_project_dir, "polygonSets")
                new_poly_dir = os.path.join(project_dir, "polygonSets")
                if os.path.isdir(old_poly_dir):
                    for filename in os.listdir(old_poly_dir):
                        src = os.path.join(old_poly_dir, filename)
                        if os.path.isfile(src):
                            shutil.copy2(src, os.path.join(new_poly_dir, filename))

                # Copy regularPolygons from old project to new project
                old_reg_dir = os.path.join(old_project_dir, "regularPolygons")
                new_reg_dir = os.path.join(project_dir, "regularPolygons")
                if os.path.isdir(old_reg_dir):
                    for filename in os.listdir(old_reg_dir):
                        src = os.path.join(old_reg_dir, filename)
                        if os.path.isfile(src):
                            shutil.copy2(src, os.path.join(new_reg_dir, filename))

                # Copy curveSets from old project to new project
                old_curve_dir = os.path.join(old_project_dir, "curveSets")
                new_curve_dir = os.path.join(project_dir, "curveSets")
                if os.path.isdir(old_curve_dir):
                    for filename in os.listdir(old_curve_dir):
                        src = os.path.join(old_curve_dir, filename)
                        if os.path.isfile(src):
                            shutil.copy2(src, os.path.join(new_curve_dir, filename))

                # Copy pointSets from old project to new project
                old_point_dir = os.path.join(old_project_dir, "pointSets")
                new_point_dir = os.path.join(project_dir, "pointSets")
                if os.path.isdir(old_point_dir):
                    for filename in os.listdir(old_point_dir):
                        src = os.path.join(old_point_dir, filename)
                        if os.path.isfile(src):
                            shutil.copy2(src, os.path.join(new_point_dir, filename))

            # Update project
            self._project_dir = project_dir
            self._project_path = os.path.join(project_dir, "project.xml")

            if self._project:
                self._project.name = project_name
                # Update file references to new structure
                self._project.files.clear()
                self._project.add_file("global", "configuration/global_config.xml")
                self._project.add_file("rendering", "configuration/rendering.xml")
                self._project.add_file("polygons", "configuration/polygons.xml")
                self._project.add_file("subdivision", "configuration/subdivision.xml")
                self._project.add_file("shapes", "configuration/shapes.xml")
                self._project.add_file("sprites", "configuration/sprites.xml")
                self._project.add_file("curves", "configuration/curves.xml")
                self._project.add_file("points", "configuration/points.xml")
                self._project.add_file("ovals", "configuration/ovals.xml")

            # Update global config name
            global_config = self._get_full_global_config()
            global_config.name = project_name
            self.global_tab.set_config(global_config)
            self.run_tab.set_drawing_settings(
                global_config.quality_multiple,
                global_config.scale_image,
                global_config.animating,
                global_config.draw_background_once,
            )
            self.subdivision_tab.set_subdividing(global_config.subdividing)
            self.sprite_tab.set_canvas_size(global_config.width, global_config.height)

            # Notify tabs
            self._notify_tabs_of_project_dir()

            return self._do_save(self._project_path)

        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to save project:\n{e}")
            return False

    def _get_full_global_config(self):
        """Merge global tab config with settings from run tab and subdivision tab."""
        config = self.global_tab.get_config()
        config.quality_multiple = self.run_tab.get_quality_multiple()
        config.scale_image = self.run_tab.get_scale_image()
        config.animating = self.run_tab.get_animating()
        config.draw_background_once = self.run_tab.get_draw_bg_once()
        config.subdividing = self.subdivision_tab.get_subdividing()
        return config

    def _save_single_tab(self, tab_name: str) -> bool:
        """Save a single tab's XML file."""
        if not self._project_path or not self._project_dir:
            QMessageBox.warning(self, "No Project",
                "Please save the project first before saving individual tabs.")
            return False

        try:
            project_dir = self._project_dir

            if tab_name == "global":
                global_file = self._project.get_file("global")
                if global_file:
                    global_path = os.path.join(project_dir, global_file.path)
                    os.makedirs(os.path.dirname(global_path), exist_ok=True)
                    GlobalConfigIO.save(self._get_full_global_config(), global_path)
                    self.status_bar.showMessage(f"Saved {global_path}", 3000)

            elif tab_name == "rendering":
                rendering_file = self._project.get_file("rendering")
                if rendering_file:
                    rendering_path = os.path.join(project_dir, rendering_file.path)
                    os.makedirs(os.path.dirname(rendering_path), exist_ok=True)
                    library = self.rendering_tab.get_library()
                    if library:
                        RenderingIO.save(library, rendering_path)
                        self.status_bar.showMessage(f"Saved {rendering_path}", 3000)

            elif tab_name == "polygons":
                polygons_file = self._project.get_file("polygons")
                if polygons_file:
                    polygons_path = os.path.join(project_dir, polygons_file.path)
                    os.makedirs(os.path.dirname(polygons_path), exist_ok=True)
                    polygon_library = self.geometry_tab.get_polygon_library()
                    if polygon_library:
                        PolygonConfigIO.save(polygon_library, polygons_path)
                        self.status_bar.showMessage(f"Saved {polygons_path}", 3000)

            elif tab_name == "subdivision":
                subdivision_file = self._project.get_file("subdivision")
                if subdivision_file:
                    subdivision_path = os.path.join(project_dir, subdivision_file.path)
                    os.makedirs(os.path.dirname(subdivision_path), exist_ok=True)
                    subdivision_collection = self.subdivision_tab.get_collection()
                    if subdivision_collection:
                        SubdivisionConfigIO.save(subdivision_collection, subdivision_path)
                        self.status_bar.showMessage(f"Saved {subdivision_path}", 3000)

            elif tab_name == "sprites":
                sprite_file = self._project.get_file("sprites")
                if sprite_file:
                    sprite_path = os.path.join(project_dir, sprite_file.path)
                    os.makedirs(os.path.dirname(sprite_path), exist_ok=True)
                    sprite_library = self.sprite_tab.get_library()
                    if sprite_library:
                        SpriteConfigIO.save(sprite_library, sprite_path)
                        self.status_bar.showMessage(f"Saved {sprite_path}", 3000)

            elif tab_name == "curves":
                curves_file = self._project.get_file("curves")
                if curves_file:
                    curves_path = os.path.join(project_dir, curves_file.path)
                    os.makedirs(os.path.dirname(curves_path), exist_ok=True)
                    open_curve_library = self.open_curve_tab.get_library()
                    if open_curve_library:
                        OpenCurveConfigIO.save(open_curve_library, curves_path)
                        self.status_bar.showMessage(f"Saved {curves_path}", 3000)

            elif tab_name == "points":
                points_file = self._project.get_file("points")
                if points_file:
                    points_path = os.path.join(project_dir, points_file.path)
                    os.makedirs(os.path.dirname(points_path), exist_ok=True)
                    point_library = self.point_tab.get_library()
                    if point_library:
                        PointConfigIO.save(point_library, points_path)
                        self.status_bar.showMessage(f"Saved {points_path}", 3000)

            elif tab_name == "ovals":
                ovals_file = self._project.get_file("ovals")
                if ovals_file:
                    ovals_path = os.path.join(project_dir, ovals_file.path)
                    os.makedirs(os.path.dirname(ovals_path), exist_ok=True)
                    oval_library = self.oval_tab.get_library()
                    if oval_library:
                        OvalConfigIO.save(oval_library, ovals_path)
                        self.status_bar.showMessage(f"Saved {ovals_path}", 3000)

            return True

        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to save {tab_name}:\n{e}")
            return False

    def _do_save(self, project_file: str) -> bool:
        """Perform the actual save operation."""
        try:
            project_dir = os.path.dirname(project_file)

            # Update project metadata
            if self._project:
                self._project.touch()

                # Ensure file references exist
                if not self._project.get_file("global"):
                    self._project.add_file("global", "configuration/global_config.xml")
                if not self._project.get_file("rendering"):
                    self._project.add_file("rendering", "configuration/rendering.xml")
                if not self._project.get_file("polygons"):
                    self._project.add_file("polygons", "configuration/polygons.xml")
                if not self._project.get_file("subdivision"):
                    self._project.add_file("subdivision", "configuration/subdivision.xml")
                if not self._project.get_file("shapes"):
                    self._project.add_file("shapes", "configuration/shapes.xml")
                if not self._project.get_file("sprites"):
                    self._project.add_file("sprites", "configuration/sprites.xml")
                if not self._project.get_file("curves"):
                    self._project.add_file("curves", "configuration/curves.xml")
                if not self._project.get_file("points"):
                    self._project.add_file("points", "configuration/points.xml")
                if not self._project.get_file("ovals"):
                    self._project.add_file("ovals", "configuration/ovals.xml")

                # Update project name from global config
                global_config = self._get_full_global_config()
                self._project.name = global_config.name

                # Save project manifest
                ProjectIO.save(self._project, project_file)

                # Save all configuration files
                self._save_single_tab("global")
                self._save_single_tab("rendering")
                self._save_single_tab("polygons")
                self._save_single_tab("subdivision")
                self._save_single_tab("sprites")
                # Auto-generate shapes.xml from sprite geo fields (Scala reads it unchanged)
                sprite_lib = self.sprite_tab.get_library()
                if sprite_lib and self._project.get_file("shapes"):
                    shapes_path = os.path.join(project_dir,
                                               self._project.get_file("shapes").path)
                    os.makedirs(os.path.dirname(shapes_path), exist_ok=True)
                    auto_generate_shapes_xml(sprite_lib, shapes_path)
                self._save_single_tab("curves")
                self._save_single_tab("points")
                self._save_single_tab("ovals")

            self._project_path = project_file
            self._project_dir = project_dir
            self._modified = False
            self._update_title()
            self.project_label.setText(self._project.name if self._project else "")
            self.status_bar.showMessage(f"Saved to {project_file}", 3000)
            self._app_settings.add_recent_project(project_dir)
            self._rebuild_recent_menu()
            return True

        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to save project:\n{e}")
            return False

    # Export methods
    def _export_rendering(self) -> None:
        """Export rendering configuration to a standalone XML file."""
        self._export_tab("Rendering", self.rendering_tab.get_library(), RenderingIO.save, "rendering.xml")

    def _export_polygons(self) -> None:
        """Export polygons configuration."""
        self._export_tab("Polygons", self.geometry_tab.get_polygon_library(), PolygonConfigIO.save, "polygons.xml")

    def _export_subdivision(self) -> None:
        """Export subdivision configuration."""
        self._export_tab("Subdivision", self.subdivision_tab.get_collection(), SubdivisionConfigIO.save, "subdivision.xml")

    def _export_sprites(self) -> None:
        """Export sprites configuration."""
        self._export_tab("Sprites", self.sprite_tab.get_library(), SpriteConfigIO.save, "sprites.xml")

    def _export_tab(self, name: str, data, save_func, default_name: str) -> None:
        """Generic export method."""
        file_path, _ = QFileDialog.getSaveFileName(
            self, f"Export {name} XML",
            default_name, "XML Files (*.xml);;All Files (*)"
        )
        if not file_path:
            return

        try:
            if data:
                save_func(data, file_path)
                self.status_bar.showMessage(f"Exported to {file_path}", 3000)
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to export:\n{e}")

    # Import methods
    def _import_rendering(self) -> None:
        """Import rendering configuration from an XML file."""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Import Rendering XML",
            "", "XML Files (*.xml);;All Files (*)"
        )
        if not file_path:
            return

        try:
            library = RenderingIO.load(file_path)
            self.rendering_tab.set_library(library)
            self._modified = True
            self._update_title()
            self.status_bar.showMessage(f"Imported from {file_path}", 3000)
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to import:\n{e}")

    def _import_polygons(self) -> None:
        """Import polygons configuration."""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Import Polygons XML",
            "", "XML Files (*.xml);;All Files (*)"
        )
        if not file_path:
            return

        try:
            library = PolygonConfigIO.load(file_path)
            self.geometry_tab.set_polygon_library(library)
            self._modified = True
            self._update_title()
            self.status_bar.showMessage(f"Imported from {file_path}", 3000)
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to import:\n{e}")

    def _import_subdivision(self) -> None:
        """Import subdivision configuration."""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Import Subdivision XML",
            "", "XML Files (*.xml);;All Files (*)"
        )
        if not file_path:
            return

        try:
            collection = SubdivisionConfigIO.load(file_path)
            self.subdivision_tab.set_collection(collection)
            self._modified = True
            self._update_title()
            self.status_bar.showMessage(f"Imported from {file_path}", 3000)
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to import:\n{e}")

    def _import_sprites(self) -> None:
        """Import sprites configuration."""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Import Sprites XML",
            "", "XML Files (*.xml);;All Files (*)"
        )
        if not file_path:
            return

        try:
            library = SpriteConfigIO.load(file_path)
            self.sprite_tab.set_library(library)
            self._modified = True
            self._update_title()
            self.status_bar.showMessage(f"Imported from {file_path}", 3000)
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to import:\n{e}")

    def _check_save(self) -> bool:
        """Check if there are unsaved changes and prompt to save."""
        if not self._modified:
            return True

        result = QMessageBox.question(
            self, "Unsaved Changes",
            "There are unsaved changes. Do you want to save?",
            QMessageBox.StandardButton.Save |
            QMessageBox.StandardButton.Discard |
            QMessageBox.StandardButton.Cancel
        )

        if result == QMessageBox.StandardButton.Save:
            return self._save_project()
        elif result == QMessageBox.StandardButton.Discard:
            return True
        else:
            return False

    def _on_modified(self) -> None:
        """Handle modification of project data."""
        self._modified = True
        self._update_title()

        # Update cross-references when tabs are modified
        self._notify_tabs_of_project_dir()

    def _on_polygon_baked(self) -> None:
        """Add baked polygon set to library and refresh the geometry tab."""
        if hasattr(self, 'geometry_tab'):
            self.geometry_tab.spline_tab._refresh_file_list()
            self.geometry_tab.spline_tab._reconcile_polygon_sets()

    def _on_geometry_modified(self) -> None:
        """Dispatch geometry sub-tab change notifications."""
        pass  # cross-references updated via _notify_tabs_of_project_dir in _on_modified

    def _on_geometry_subdivision_changed(self) -> None:
        if hasattr(self, 'subdivision_tab'):
            self.subdivision_tab._refresh_tree()

    def _on_geometry_sprite_library_changed(self) -> None:
        if hasattr(self, 'sprite_tab'):
            self.sprite_tab._refresh_tree()

    def _on_geometry_renderer_library_changed(self) -> None:
        if hasattr(self, 'rendering_tab') and hasattr(self.rendering_tab, 'tree_widget'):
            self.rendering_tab.tree_widget._refresh_tree()

    def _on_geometry_new_sprite_created(self, set_name: str, sprite_name: str) -> None:
        """After sprite_tab refreshes, select the newly created sprite."""
        if hasattr(self, 'sprite_tab'):
            QTimer.singleShot(0, lambda: self.sprite_tab._select_sprite(set_name, sprite_name))

    def _save_geometry_config(self) -> None:
        """Save all three geometry config files."""
        self._save_single_tab("polygons")
        self._save_single_tab("curves")
        self._save_single_tab("points")

    def _on_sprite_library_for_polygon_counts(self) -> None:
        """Refresh geometry sub-tab usage counts when the sprite library changes."""
        if hasattr(self, 'geometry_tab'):
            self.geometry_tab.set_sprite_library(self.sprite_tab.get_library())

    def _update_title(self) -> None:
        """Update window title based on project state."""
        title = "Loom Parameter Editor"
        if self._project:
            title = f"{self._project.name} - {title}"
        if self._modified:
            title = f"*{title}"
        self.setWindowTitle(title)

    def _show_user_guide(self) -> None:
        """Open the user guide in the default web browser."""
        # Get the path to the help file
        help_path = os.path.join(
            os.path.dirname(os.path.dirname(__file__)),
            "resources", "help.html"
        )

        if os.path.exists(help_path):
            # Open in default browser
            url = QUrl.fromLocalFile(help_path)
            QDesktopServices.openUrl(url)
        else:
            QMessageBox.warning(
                self, "Help Not Found",
                f"Could not find the user guide at:\n{help_path}"
            )

    def _show_about(self) -> None:
        """Show about dialog."""
        QMessageBox.about(
            self, "About Loom Parameter Editor",
            "Loom Parameter Editor\n\n"
            "A tool for configuring renderer parameters for the Loom Scala application.\n\n"
            "Creates XML configuration files that can be loaded by the Scala application."
        )

    def closeEvent(self, event) -> None:
        """Handle window close event."""
        if self._check_save():
            event.accept()
        else:
            event.ignore()

    def _update_output_hint(self) -> None:
        """Update the output size hint label in the global tab."""
        w = self.global_tab.width_spin.value() * self.run_tab.get_quality_multiple()
        h = self.global_tab.height_spin.value() * self.run_tab.get_quality_multiple()
        self.global_tab.update_output_size_hint(w, h)

    def _update_preview_canvas_size(self) -> None:
        self.sprite_tab.set_canvas_size(
            self.global_tab.width_spin.value(),
            self.global_tab.height_spin.value(),
        )

    def _on_background_image_browse(self) -> None:
        """Browse for a background image file."""
        quality = self.run_tab.get_quality_multiple()
        w = self.global_tab.width_spin.value() * quality
        h = self.global_tab.height_spin.value() * quality

        # Default dir: project's background_image subdir if available
        if self._project_dir:
            default_dir = os.path.join(self._project_dir, "background_image")
            if not os.path.isdir(default_dir):
                default_dir = self._project_dir
        else:
            default_dir = os.path.expanduser("~")

        file_path, _ = QFileDialog.getOpenFileName(
            self,
            f"Select Background Image — output size: {w}×{h} px",
            default_dir,
            "Images (*.png *.jpg *.jpeg)"
        )
        if file_path:
            self.global_tab.set_background_image_path(file_path)
            self._on_modified()

    def _on_projects_dir_changed(self, path: str) -> None:
        """Handle change in the default projects directory."""
        self._app_settings.default_projects_dir = path
        self._app_settings.save()

    def _on_engine_changed(self, engine: str) -> None:
        """Propagate engine selection to RunTab, SubdivisionTab and persist it."""
        self.run_tab.set_engine(engine)
        self.subdivision_tab.set_engine(engine)
        self._app_settings.selected_engine = engine
        self._app_settings.save()

    def _on_loom_app_path_changed(self, path: str) -> None:
        """Persist the LoomApp.app path from RunTab."""
        self._app_settings.loom_app_path = path
        self._app_settings.save()

    def get_project_dir(self) -> Optional[str]:
        """Get the current project directory."""
        return self._project_dir
