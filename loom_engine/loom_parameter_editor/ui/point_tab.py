"""
Point Set configuration tab for the parameter editor.
Provides UI for editing points.xml settings.
"""
import os
import re
import shutil
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QComboBox, QTreeWidget, QTreeWidgetItem, QPushButton,
    QSplitter, QLabel, QMessageBox, QInputDialog, QSizePolicy, QFileDialog
)
from PySide6.QtCore import Signal, Qt, QProcess, QFileSystemWatcher
from PySide6.QtGui import QColor, QFont, QBrush
from PySide6.QtWidgets import QStyledItemDelegate
from models.point_config import PointSetDef, PointSetLibrary, PointSourceType
from models.polygon_config import FileSource
from models.sprite_config import SpriteDef, SpriteSet, GeoSourceType
from models.subdivision_config import SubdivisionParams, SubdivisionParamsSet, SubdivisionType
from models.rendering import Renderer, RendererSet
from models.constants import RenderMode
from ui.polygon_tab import PolygonPreviewWidget, _COL_ORANGE, _COL_GREEN, _COL_SEL_GREEN, _FilenameDelegate

BEZIER_PY = "/Users/broganbunt/Loom_2026/bezier_py/main.py"
PYTHON    = "/Users/broganbunt/Loom_2026/loom_engine/loom_parameter_editor/.venv/bin/python"


class PointTab(QWidget):
    """Tab widget for editing discrete point set configuration."""

    modified = Signal()
    shapeLibraryChanged    = Signal()
    subdivisionChanged     = Signal()
    spriteLibraryChanged   = Signal()
    rendererLibraryChanged = Signal()
    newShapeCreated        = Signal(str, str)   # (set_name, shape_name)
    newSpriteCreated       = Signal(str, str)   # (set_name, sprite_name)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._library = PointSetLibrary.default()
        self._current_set: PointSetDef = None
        self._updating = False
        self._point_sets_dir: str = ""
        self._bezier_process: QProcess = None
        self._pre_launch_files: set = set()
        self._sprite_library = None
        self._subdivision_collection = None
        self._renderer_library = None
        self._conv_sprite_group = None
        self._conv_render_group = None

        self._fs_watcher = QFileSystemWatcher()
        self._fs_watcher.directoryChanged.connect(self._on_dir_changed)
        self._fs_watcher.fileChanged.connect(self._on_file_changed)

        self._setup_ui()
        self._refresh_list()

    def _setup_ui(self):
        main_layout = QHBoxLayout(self)
        splitter = QSplitter(Qt.Orientation.Horizontal)
        main_layout.addWidget(splitter)

        # ── Left panel ────────────────────────────────────────────────────────
        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)

        left_layout.addWidget(QLabel("Point Sets:"))

        self.set_list = QTreeWidget()
        self.set_list.setHeaderLabels(["Name"])
        self.set_list.setRootIsDecorated(False)
        self.set_list.currentItemChanged.connect(self._on_set_selected)
        left_layout.addWidget(self.set_list)

        btn_layout = QHBoxLayout()
        self.del_btn = QPushButton("Delete")
        self.del_btn.clicked.connect(self._delete_point_set)
        btn_layout.addWidget(self.del_btn)

        self.dup_btn = QPushButton("Duplicate")
        self.dup_btn.clicked.connect(self._duplicate_point_set)
        btn_layout.addWidget(self.dup_btn)

        self.rename_btn = QPushButton("Rename")
        self.rename_btn.clicked.connect(self._rename_point_set)
        btn_layout.addWidget(self.rename_btn)

        left_layout.addLayout(btn_layout)
        splitter.addWidget(left_panel)

        # ── Right panel ───────────────────────────────────────────────────────
        right_panel = QWidget()
        right_layout = QVBoxLayout(right_panel)

        info_group = QGroupBox("Point Set")
        form = QFormLayout(info_group)

        self.name_edit = QLineEdit()
        self.name_edit.setReadOnly(True)
        form.addRow("Name:", self.name_edit)

        self.folder_edit = QLineEdit()
        self.folder_edit.setText("pointSets")
        self.folder_edit.textChanged.connect(self._on_modified)
        form.addRow("Folder:", self.folder_edit)

        self.filename_combo = QComboBox()
        self.filename_combo.setEditable(True)
        self.filename_combo.setItemDelegate(_FilenameDelegate(self.filename_combo))
        self.filename_combo.currentTextChanged.connect(self._on_modified)
        self.filename_combo.currentTextChanged.connect(self._update_preview)
        self.filename_combo.currentTextChanged.connect(lambda _: self._update_convenience_borders())
        form.addRow("Filename:", self.filename_combo)

        btn_row = QHBoxLayout()
        self.create_btn = QPushButton("Create in Bezier")
        self.create_btn.clicked.connect(self._create_in_bezier)
        btn_row.addWidget(self.create_btn)

        self.import_btn = QPushButton("Import")
        self.import_btn.clicked.connect(self._import)
        btn_row.addWidget(self.import_btn)

        self.edit_btn = QPushButton("Edit in Bezier")
        self.edit_btn.clicked.connect(self._edit_in_bezier)
        btn_row.addWidget(self.edit_btn)

        self.refresh_btn = QPushButton("Refresh Files")
        self.refresh_btn.clicked.connect(self._refresh_file_list)
        btn_row.addStretch()
        btn_row.addWidget(self.refresh_btn)
        form.addRow("", btn_row)

        right_layout.addWidget(info_group)

        preview_group = QGroupBox("Preview")
        preview_layout = QVBoxLayout(preview_group)
        preview_layout.setContentsMargins(4, 4, 4, 4)
        self.preview_widget = PolygonPreviewWidget()
        preview_layout.addWidget(self.preview_widget)
        right_layout.addWidget(preview_group, 1)

        qs_label = QLabel("Quick Setup")
        qs_label.setStyleSheet("font-weight: bold; margin-top: 4px;")
        right_layout.addWidget(qs_label)
        right_layout.addWidget(self._create_convenience_panel())

        splitter.addWidget(right_panel)
        splitter.setSizes([220, 580])

    # ── Library access ────────────────────────────────────────────────────────

    def set_library(self, library: PointSetLibrary) -> None:
        self._library = library
        self._refresh_list()

    def get_library(self) -> PointSetLibrary:
        return self._library

    def set_point_sets_directory(self, directory: str) -> None:
        self._point_sets_dir = directory
        if self._fs_watcher.directories():
            self._fs_watcher.removePaths(self._fs_watcher.directories())
        if self._fs_watcher.files():
            self._fs_watcher.removePaths(self._fs_watcher.files())
        if directory and os.path.isdir(directory):
            self._fs_watcher.addPath(directory)
        self._refresh_file_list()
        self._auto_discover()

    def set_sprite_library(self, library) -> None:
        self._sprite_library = library
        self._refresh_convenience_combos()

    def set_subdivision_collection(self, coll) -> None:
        self._subdivision_collection = coll
        self._refresh_convenience_combos()

    def set_renderer_library(self, lib) -> None:
        self._renderer_library = lib
        self._refresh_convenience_combos()

    def _auto_discover(self) -> None:
        """Populate library from filesystem if it currently has no entries."""
        if not self._point_sets_dir or not os.path.isdir(self._point_sets_dir):
            return
        if self._library.point_sets:
            return
        files = sorted(f for f in os.listdir(self._point_sets_dir) if f.lower().endswith(".xml"))
        if not files:
            return
        for filename in files:
            name = os.path.splitext(filename)[0]
            ps = PointSetDef(name=name, file_source=FileSource(folder="pointSets", filename=filename))
            self._library.add_point_set(ps)
        self._refresh_list()

    def create_default_library(self) -> PointSetLibrary:
        return PointSetLibrary.default()

    # ── List management ───────────────────────────────────────────────────────

    def _refresh_list(self):
        self._updating = True
        try:
            current_name = self._current_set.name if self._current_set else None
            self.set_list.clear()
            for ps in self._library.point_sets:
                item = QTreeWidgetItem([ps.name])
                item.setData(0, Qt.ItemDataRole.UserRole, ps)
                self.set_list.addTopLevelItem(item)
                if ps.name == current_name:
                    self.set_list.setCurrentItem(item)
        finally:
            self._updating = False

    def _on_set_selected(self, current, previous):
        if current is None:
            self._current_set = None
            self._clear_editor()
            return
        ps = current.data(0, Qt.ItemDataRole.UserRole)
        self._current_set = ps
        self._load_set_to_editor(ps)

    def _clear_editor(self):
        self._updating = True
        try:
            self.name_edit.clear()
            self.folder_edit.clear()
            self.filename_combo.setCurrentText("")
            self.preview_widget.clear()
        finally:
            self._updating = False

    def _load_set_to_editor(self, ps: PointSetDef):
        self._updating = True
        try:
            self.name_edit.setText(ps.name)
            if ps.file_source:
                self.folder_edit.setText(ps.file_source.folder or "pointSets")
                self._refresh_file_list()
                self.filename_combo.setCurrentText(ps.file_source.filename or "")
            self._update_preview()
        finally:
            self._updating = False

    # ── File list helpers ─────────────────────────────────────────────────────

    def _refresh_file_list(self):
        self._updating = True
        try:
            current = self.filename_combo.currentText()
            self.filename_combo.clear()
            files = []
            if self._point_sets_dir and os.path.isdir(self._point_sets_dir):
                files = sorted(
                    f for f in os.listdir(self._point_sets_dir)
                    if f.lower().endswith(".xml")
                )
                for i, f in enumerate(files):
                    self.filename_combo.addItem(f)
                    self.filename_combo.setItemData(
                        i, QBrush(self._file_color(f)), Qt.ItemDataRole.ForegroundRole)
                if self._fs_watcher.files():
                    self._fs_watcher.removePaths(self._fs_watcher.files())
                for f in files:
                    self._fs_watcher.addPath(os.path.join(self._point_sets_dir, f))
            if current:
                idx = self.filename_combo.findText(current)
                if idx >= 0:
                    self.filename_combo.setCurrentIndex(idx)
                else:
                    self.filename_combo.setCurrentText(current)
        finally:
            self._updating = False

    def _update_preview(self):
        if not self._point_sets_dir:
            self.preview_widget.clear()
            return
        filename = self.filename_combo.currentText()
        if not filename:
            self.preview_widget.clear()
            return
        full_path = os.path.join(self._point_sets_dir, filename)
        self.preview_widget.load_polygon_set(full_path)

    # ── CRUD ─────────────────────────────────────────────────────────────────

    def _rename_point_set(self):
        if self._bezier_process is not None and \
                self._bezier_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.warning(self, "Bezier Running", "Close Bezier before renaming.")
            return
        if self._current_set is None:
            return
        cs = self._current_set
        old_root = cs.file_source.filename if (cs.file_source and cs.file_source.filename) else cs.name
        if old_root.lower().endswith('.xml'):
            old_root = old_root[:-4]
        new_root, ok = QInputDialog.getText(
            self, "Rename Point Set",
            f"New root name  ('{old_root}.xml' will be renamed):",
            text=old_root)
        if not ok or not new_root.strip():
            return
        new_root = new_root.strip()
        if new_root == old_root:
            return
        if any(p.name == new_root for p in self._library.point_sets if p is not cs):
            QMessageBox.warning(self, "Duplicate",
                f"A point set named '{new_root}' already exists.")
            return
        old_fn = old_root + '.xml'
        new_fn = new_root + '.xml'
        if self._point_sets_dir and os.path.isfile(
                os.path.join(self._point_sets_dir, old_fn)):
            try:
                os.rename(os.path.join(self._point_sets_dir, old_fn),
                          os.path.join(self._point_sets_dir, new_fn))
            except OSError as e:
                QMessageBox.critical(self, "Rename Error", str(e))
                return
        cs.name = new_root
        if cs.file_source:
            cs.file_source.filename = new_fn
        self._refresh_list()
        self._refresh_file_list()
        self.modified.emit()

    def _import(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "Import Point Set", self._point_sets_dir or "", "XML Files (*.xml)")
        if not path:
            return
        if not self._point_sets_dir:
            QMessageBox.warning(self, "No Project", "Please save the project first.")
            return
        os.makedirs(self._point_sets_dir, exist_ok=True)
        dst = os.path.join(self._point_sets_dir, os.path.basename(path))
        if os.path.abspath(path) == os.path.abspath(dst):
            return
        if os.path.exists(dst):
            if QMessageBox.question(
                    self, "Overwrite?",
                    f"'{os.path.basename(path)}' already exists. Overwrite?",
                    QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
                    ) != QMessageBox.StandardButton.Yes:
                return
        try:
            shutil.copy2(path, dst)
        except Exception as e:
            QMessageBox.critical(self, "Import Error", str(e))
            return
        self._strip_xml_headers(dst)
        self._refresh_file_list()
        self.filename_combo.setCurrentText(os.path.basename(path))
        self.modified.emit()

    def _duplicate_point_set(self):
        if self._current_set is None:
            return
        new_ps = self._current_set.copy()
        new_ps.name = self._current_set.name + "_copy"
        self._library.add_point_set(new_ps)
        self._refresh_list()
        self.modified.emit()

    def _delete_point_set(self):
        if self._current_set is None:
            return
        result = QMessageBox.question(
            self, "Delete", f"Delete '{self._current_set.name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result != QMessageBox.StandardButton.Yes:
            return
        self._library.remove_point_set(self._current_set.name)
        self._current_set = None
        self._refresh_list()
        self._clear_editor()
        self.modified.emit()

    # ── Bezier launch ─────────────────────────────────────────────────────────

    def _strip_xml_headers(self, filepath: str) -> None:
        """Remove XML declaration and DOCTYPE lines from a point set file."""
        with open(filepath, 'r', encoding='latin-1') as f:
            lines = f.readlines()
        cleaned = [l for l in lines
                   if not l.strip().startswith('<?xml')
                   and not l.strip().startswith('<!DOCTYPE')]
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(cleaned)

    def _snapshot_files(self) -> set:
        """Return the set of filenames currently in the point sets directory."""
        if not self._point_sets_dir or not os.path.isdir(self._point_sets_dir):
            return set()
        return set(os.listdir(self._point_sets_dir))

    def _create_in_bezier(self) -> None:
        """Launch Bezier to create a new point set."""
        if not self._point_sets_dir or not os.path.isdir(self._point_sets_dir):
            QMessageBox.warning(self, "No Project", "Please save the project first.")
            return
        if self._bezier_process is not None and \
                self._bezier_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.information(self, "Bezier Running", "Bezier is already running.")
            return

        self._pre_launch_files = self._snapshot_files()

        self._bezier_process = QProcess(self)
        self._bezier_process.finished.connect(self._on_create_bezier_finished)
        self._bezier_process.start(PYTHON, [
            BEZIER_PY,
            "--save-dir", self._point_sets_dir,
            "--point-mode"
        ])

    def _on_create_bezier_finished(self, exit_code, exit_status) -> None:
        """Handle Bezier process finishing after create."""
        if not self._point_sets_dir or not os.path.isdir(self._point_sets_dir):
            return

        current_files = self._snapshot_files()
        new_files = current_files - self._pre_launch_files

        for fname in new_files:
            fpath = os.path.join(self._point_sets_dir, fname)
            if os.path.isfile(fpath):
                self._strip_xml_headers(fpath)

        xml_files = sorted(f for f in new_files if f.endswith('.xml'))

        self._refresh_file_list()

        if len(xml_files) == 1:
            self.filename_combo.setCurrentText(xml_files[0])

        self.modified.emit()

    def _edit_in_bezier(self):
        if not self._point_sets_dir:
            QMessageBox.warning(self, "No Project", "Please save the project first.")
            return
        filename = self.filename_combo.currentText()
        if not filename:
            QMessageBox.warning(self, "No File", "Select a point set file first.")
            return
        full_path = os.path.join(self._point_sets_dir, filename)

        if self._bezier_process is not None and \
                self._bezier_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.information(self, "Bezier Running", "Bezier is already running.")
            return

        self._bezier_process = QProcess(self)
        self._bezier_process.finished.connect(self._on_edit_bezier_finished)
        self._bezier_process.start(PYTHON, [
            BEZIER_PY,
            "--save-dir", self._point_sets_dir,
            "--load", full_path,
            "--point-select"
        ])

    def _on_edit_bezier_finished(self, exit_code, exit_status):
        self._refresh_file_list()
        self._update_preview()

    # ── Auto-refresh (QFileSystemWatcher) ─────────────────────────────────

    def _on_dir_changed(self, path: str) -> None:
        self._refresh_file_list()
        self._refresh_list()

    def _on_file_changed(self, path: str) -> None:
        if os.path.exists(path):
            self._fs_watcher.addPath(path)
        self._refresh_file_list()
        self._refresh_list()

    # ── File colour helper ─────────────────────────────────────────────────

    def _file_color(self, filename: str) -> QColor:
        """Return display colour for a file in the point combo.

        Point rules:
          *.layers.xml          → orange
          *_layer_N.xml         → orange (polygon-format layer file, not pointSet)
          other *.xml           → green  (pointSet file, Loom-usable)
        """
        if filename.lower().endswith('.layers.xml'):
            return _COL_ORANGE
        if re.search(r'_layer_\d+\.xml$', filename, re.IGNORECASE):
            return _COL_ORANGE
        return _COL_GREEN

    # ── Convenience panel ─────────────────────────────────────────────────

    def _create_convenience_panel(self) -> QWidget:
        """Build the sequential workflow panel (horizontal layout).

        Row 1: Sprites
        Row 2: Rendering
        """
        container = QWidget()
        outer = QVBoxLayout(container)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(4)

        # ── Row 1: Sprites ─────────────────────────────────────────────────
        row1 = QHBoxLayout()
        row1.setSpacing(4)

        # Sprites group
        sprite_group = QGroupBox("Sprites")
        self._conv_sprite_group = sprite_group
        sprite_layout = QVBoxLayout(sprite_group)
        sprite_layout.setContentsMargins(4, 4, 4, 4)
        sprite_layout.setSpacing(4)
        sprow = QHBoxLayout()
        sprow.addWidget(QLabel("Set:"))
        self.conv_sprite_set_combo = QComboBox()
        self.conv_sprite_set_combo.setMinimumWidth(80)
        self.conv_sprite_set_combo.currentIndexChanged.connect(
            lambda: self._update_conv_combo_style(self.conv_sprite_set_combo))
        sprow.addWidget(self.conv_sprite_set_combo, 1)
        add_sprite_set_btn = QPushButton("+ Set")
        add_sprite_set_btn.setMaximumWidth(48)
        add_sprite_set_btn.clicked.connect(self._on_conv_add_sprite_set)
        sprow.addWidget(add_sprite_set_btn)
        sprite_layout.addLayout(sprow)
        make_sprite_btn = QPushButton("Make Sprite")
        make_sprite_btn.clicked.connect(self._on_conv_make_sprite)
        sprite_layout.addWidget(make_sprite_btn)
        sprite_layout.addStretch()
        row1.addWidget(sprite_group)

        outer.addLayout(row1)

        # ── Row 2: Rendering ───────────────────────────────────────────────
        render_group = QGroupBox("Rendering")
        self._conv_render_group = render_group
        rlay = QHBoxLayout(render_group)
        rlay.setContentsMargins(4, 4, 4, 4)
        rlay.setSpacing(6)
        rlay.addWidget(QLabel("Set:"))
        self.conv_renderer_set_combo = QComboBox()
        self.conv_renderer_set_combo.setMinimumWidth(80)
        self.conv_renderer_set_combo.currentIndexChanged.connect(
            lambda: self._update_conv_combo_style(self.conv_renderer_set_combo))
        rlay.addWidget(self.conv_renderer_set_combo, 1)
        add_renderer_set_btn = QPushButton("+ Set")
        add_renderer_set_btn.setMaximumWidth(48)
        add_renderer_set_btn.clicked.connect(self._on_conv_add_renderer_set)
        rlay.addWidget(add_renderer_set_btn)
        rlay.addWidget(QLabel("Mode:"))
        self.conv_mode_combo = QComboBox()
        for mode in RenderMode:
            self.conv_mode_combo.addItem(mode.name, mode)
        self.conv_mode_combo.setCurrentIndex(2)  # FILLED
        rlay.addWidget(self.conv_mode_combo)
        make_renderer_btn = QPushButton("Make Renderer")
        make_renderer_btn.clicked.connect(self._on_conv_make_renderer)
        rlay.addWidget(make_renderer_btn)
        outer.addWidget(render_group)

        return container

    _CONV_GREEN_BORDER = (
        "QGroupBox { border: 2px solid #1A6B1A; border-radius: 4px; "
        "margin-top: 6px; padding-top: 4px; } "
        "QGroupBox::title { subcontrol-origin: margin; padding: 0 3px; }"
    )

    def _update_convenience_borders(self) -> None:
        """Apply green border to convenience groups whose workflow step is done."""
        groups = (self._conv_sprite_group, self._conv_render_group)
        if any(g is None for g in groups):
            return
        root = self._convenience_root()
        if not root:
            for g in groups:
                g.setStyleSheet("")
            return

        geo_set_name = self._current_set.name if self._current_set else ""
        sprite_done = bool(self._sprite_library and geo_set_name and any(
            any(getattr(sp, 'geo_point_set_name', '') == geo_set_name
                for sp in ss.sprites)
            for ss in getattr(self._sprite_library, 'sprite_sets', [])))

        renderer_name = f"{root}_renderer"
        render_done = bool(self._renderer_library and any(
            any(r.name == renderer_name for r in rs.renderers)
            for rs in getattr(self._renderer_library, 'renderer_sets', [])))

        gs = self._CONV_GREEN_BORDER
        self._conv_sprite_group.setStyleSheet(gs if sprite_done else "")
        self._conv_render_group.setStyleSheet(gs if render_done else "")

    def _convenience_root(self) -> str:
        f = self.filename_combo.currentText()
        if not f:
            return ""
        stem = f
        for ext in ('.layers.xml', '.xml'):
            if stem.lower().endswith(ext):
                stem = stem[:-len(ext)]
                break
        return re.sub(r'_layer_\d+$', '', stem, flags=re.IGNORECASE)

    def _update_conv_combo_style(self, combo: QComboBox) -> None:
        """Show green text when a set is selected, default otherwise."""
        if combo.currentText():
            combo.setStyleSheet(f"QComboBox {{ color: {_COL_SEL_GREEN}; }}")
        else:
            combo.setStyleSheet("")

    def _refresh_convenience_combos(self) -> None:
        if not hasattr(self, 'conv_sprite_set_combo'):
            return
        sprite_sel = self.conv_sprite_set_combo.currentText()
        renderer_sel = self.conv_renderer_set_combo.currentText()
        self.conv_sprite_set_combo.blockSignals(True)
        self.conv_renderer_set_combo.blockSignals(True)
        try:
            self.conv_sprite_set_combo.clear()
            if self._sprite_library:
                for s in self._sprite_library.sprite_sets:
                    self.conv_sprite_set_combo.addItem(s.name)
            self.conv_renderer_set_combo.clear()
            if self._renderer_library:
                for rs in self._renderer_library.renderer_sets:
                    self.conv_renderer_set_combo.addItem(rs.name)
        finally:
            self.conv_sprite_set_combo.blockSignals(False)
            self.conv_renderer_set_combo.blockSignals(False)
        for combo, sel in [
            (self.conv_sprite_set_combo, sprite_sel),
            (self.conv_renderer_set_combo, renderer_sel),
        ]:
            if sel:
                idx = combo.findText(sel)
                if idx >= 0:
                    combo.setCurrentIndex(idx)
            self._update_conv_combo_style(combo)

    def _on_conv_make_subdivision_set(self) -> None:
        root = self._convenience_root()
        if not root:
            QMessageBox.warning(self, "No File", "Select a point file first.")
            return
        if self._subdivision_collection is None:
            QMessageBox.warning(self, "No Subdivision Collection", "Subdivision collection not available.")
            return
        set_name = f"{root}_Subdivide"
        if self._subdivision_collection.get_params_set(set_name):
            QMessageBox.warning(self, "Duplicate", f"Subdivision set '{set_name}' already exists.")
            return
        ps = SubdivisionParamsSet(name=set_name)
        ps.add_params(SubdivisionParams(name="A", subdivision_type=SubdivisionType.QUAD, enabled=True))
        self._subdivision_collection.add_params_set(ps)
        self.subdivisionChanged.emit()
        self.modified.emit()

    def _on_conv_add_sprite_set(self) -> None:
        root = self._convenience_root()
        suggestion = f"{root}_sprite" if root else "sprite"
        name, ok = QInputDialog.getText(self, "Add Sprite Set", "Name:", text=suggestion)
        if not ok or not name.strip():
            return
        name = name.strip()
        if self._sprite_library is None:
            QMessageBox.warning(self, "No Sprite Library", "Sprite library not available.")
            return
        if any(s.name == name for s in self._sprite_library.sprite_sets):
            QMessageBox.warning(self, "Duplicate", f"Sprite set '{name}' already exists.")
            return
        self._sprite_library.add(SpriteSet(name=name))
        self._refresh_convenience_combos()
        idx = self.conv_sprite_set_combo.findText(name)
        if idx >= 0:
            self.conv_sprite_set_combo.setCurrentIndex(idx)
        self.spriteLibraryChanged.emit()
        self.modified.emit()

    def _on_conv_make_sprite(self) -> None:
        root = self._convenience_root()
        if not root:
            QMessageBox.warning(self, "No File", "Select a point file first.")
            return
        set_name = self.conv_sprite_set_combo.currentText()
        if not set_name or self._sprite_library is None:
            QMessageBox.warning(self, "No Sprite Set", "Select or create a sprite set first.")
            return
        sprite_set = next((s for s in self._sprite_library.sprite_sets if s.name == set_name), None)
        if sprite_set is None:
            return
        count = len(sprite_set.sprites) + 1
        name = f"{set_name}_{count:03d}"
        while any(s.name == name for s in sprite_set.sprites):
            count += 1
            name = f"{set_name}_{count:03d}"
        geo_set_name = self._current_set.name if self._current_set else ""
        renderer_set_name = self.conv_renderer_set_combo.currentText() or "DefaultSet"
        sprite_set.add(SpriteDef(
            name=name,
            geo_source_type=GeoSourceType.POINT_SET,
            geo_point_set_name=geo_set_name,
            renderer_set_name=renderer_set_name,
        ))
        self.newSpriteCreated.emit(set_name, name)
        self.spriteLibraryChanged.emit()
        self.modified.emit()
        self._update_convenience_borders()

    def _on_conv_add_renderer_set(self) -> None:
        root = self._convenience_root()
        suggestion = f"{root}_renderSet" if root else "renderSet"
        name, ok = QInputDialog.getText(self, "Add Renderer Set", "Name:", text=suggestion)
        if not ok or not name.strip():
            return
        name = name.strip()
        if self._renderer_library is None:
            QMessageBox.warning(self, "No Renderer Library", "Renderer library not available.")
            return
        if any(rs.name == name for rs in self._renderer_library.renderer_sets):
            QMessageBox.warning(self, "Duplicate", f"Renderer set '{name}' already exists.")
            return
        self._renderer_library.add_renderer_set(RendererSet(name=name))
        self._refresh_convenience_combos()
        idx = self.conv_renderer_set_combo.findText(name)
        if idx >= 0:
            self.conv_renderer_set_combo.setCurrentIndex(idx)
        self.rendererLibraryChanged.emit()
        self.modified.emit()

    def _on_conv_make_renderer(self) -> None:
        root = self._convenience_root()
        if not root:
            QMessageBox.warning(self, "No File", "Select a point file first.")
            return
        rs_name = self.conv_renderer_set_combo.currentText()
        if not rs_name or self._renderer_library is None:
            QMessageBox.warning(self, "No Renderer Set", "Select or create a renderer set first.")
            return
        rs = next((r for r in self._renderer_library.renderer_sets if r.name == rs_name), None)
        if rs is None:
            return
        name = f"{root}_renderer"
        if any(r.name == name for r in rs.renderers):
            QMessageBox.warning(self, "Duplicate", f"Renderer '{name}' already exists in '{rs_name}'.")
            return
        mode = self.conv_mode_combo.currentData()
        rs.add_renderer(Renderer(name=name, mode=mode))
        shape_name = f"{root}_shape"
        if self._sprite_library:
            updated = False
            for sprite_set in self._sprite_library.sprite_sets:
                for sprite in sprite_set.sprites:
                    if getattr(sprite, 'shape_name', '') == shape_name:
                        sprite.renderer_set_name = rs_name
                        updated = True
            if updated:
                self.spriteLibraryChanged.emit()
        self.rendererLibraryChanged.emit()
        self.modified.emit()
        self._update_convenience_borders()

    # ── Change tracking ───────────────────────────────────────────────────────

    def _on_modified(self):
        if self._updating:
            return
        self._save_editor_to_set()
        self.modified.emit()

    def _save_editor_to_set(self):
        if self._current_set is None:
            return
        filename = self.filename_combo.currentText()
        folder = self.folder_edit.text()
        if self._current_set.file_source is None:
            self._current_set.file_source = FileSource(folder="pointSets")
        self._current_set.file_source.folder = folder
        self._current_set.file_source.filename = filename
        current_item = self.set_list.currentItem()
        if current_item:
            current_item.setText(0, self._current_set.name)
