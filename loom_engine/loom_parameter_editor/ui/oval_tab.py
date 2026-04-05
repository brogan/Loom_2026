"""
Oval Set configuration tab for the parameter editor.
Provides UI for editing ovals.xml settings.
"""
import os
import re
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QComboBox, QTreeWidget, QTreeWidgetItem, QPushButton,
    QSplitter, QLabel, QMessageBox, QInputDialog, QSizePolicy
)
from PyQt6.QtCore import pyqtSignal, Qt, QProcess, QFileSystemWatcher
from PyQt6.QtGui import QColor, QFont, QBrush
from PyQt6.QtWidgets import QStyledItemDelegate
from models.oval_config import OvalSetDef, OvalSetLibrary, OvalSourceType
from models.polygon_config import FileSource
from models.shape_config import ShapeDef, ShapeSet, ShapeSourceType
from models.sprite_config import SpriteDef, SpriteSet
from models.subdivision_config import SubdivisionParams, SubdivisionParamsSet, SubdivisionType
from models.rendering import Renderer, RendererSet
from models.constants import RenderMode
from ui.polygon_tab import PolygonPreviewWidget, _COL_ORANGE, _COL_GREEN, _COL_SEL_GREEN, _FilenameDelegate

BEZIER_JAR = "/Users/broganbunt/Loom_2026/bezier/out/artifacts/Bezier_jar/Bezier.jar"
BEZIER_WORKING_DIR = "/Users/broganbunt/Loom_2026/bezier"


class OvalTab(QWidget):
    """Tab widget for editing oval set configuration."""

    modified = pyqtSignal()
    shapeLibraryChanged    = pyqtSignal()
    subdivisionChanged     = pyqtSignal()
    spriteLibraryChanged   = pyqtSignal()
    rendererLibraryChanged = pyqtSignal()
    newShapeCreated        = pyqtSignal(str, str)   # (set_name, shape_name)
    newSpriteCreated       = pyqtSignal(str, str)   # (set_name, sprite_name)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._library = OvalSetLibrary.default()
        self._current_set: OvalSetDef = None
        self._updating = False
        self._oval_sets_dir: str = ""
        self._bezier_process: QProcess = None
        self._pre_launch_files: set = set()
        self._shape_library = None
        self._sprite_library = None
        self._subdivision_collection = None
        self._renderer_library = None
        self._conv_shape_group = None
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

        left_layout.addWidget(QLabel("Oval Sets:"))

        self.set_list = QTreeWidget()
        self.set_list.setHeaderLabels(["Name"])
        self.set_list.setRootIsDecorated(False)
        self.set_list.currentItemChanged.connect(self._on_set_selected)
        left_layout.addWidget(self.set_list)

        btn_layout = QHBoxLayout()
        self.new_btn = QPushButton("New")
        self.new_btn.clicked.connect(self._new_oval_set)
        btn_layout.addWidget(self.new_btn)

        self.rename_btn = QPushButton("Rename")
        self.rename_btn.clicked.connect(self._rename_oval_set)
        btn_layout.addWidget(self.rename_btn)

        btn_layout2 = QHBoxLayout()
        self.dup_btn = QPushButton("Duplicate")
        self.dup_btn.clicked.connect(self._duplicate_oval_set)
        btn_layout2.addWidget(self.dup_btn)

        self.del_btn = QPushButton("Delete")
        self.del_btn.clicked.connect(self._delete_oval_set)
        btn_layout2.addWidget(self.del_btn)

        left_layout.addLayout(btn_layout)
        left_layout.addLayout(btn_layout2)
        left_layout.addStretch()
        splitter.addWidget(left_panel)

        # ── Right panel ───────────────────────────────────────────────────────
        right_panel = QWidget()
        right_layout = QVBoxLayout(right_panel)

        info_group = QGroupBox("Oval Set")
        form = QFormLayout(info_group)

        self.name_edit = QLineEdit()
        self.name_edit.setReadOnly(True)
        form.addRow("Name:", self.name_edit)

        self.folder_edit = QLineEdit()
        self.folder_edit.setText("ovalSets")
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
        right_layout.addWidget(preview_group)

        qs_label = QLabel("Quick Setup")
        qs_label.setStyleSheet("font-weight: bold; margin-top: 4px;")
        right_layout.addWidget(qs_label)
        right_layout.addWidget(self._create_convenience_panel())

        right_layout.addStretch()
        splitter.addWidget(right_panel)
        splitter.setSizes([220, 580])

    # ── Library access ────────────────────────────────────────────────────────

    def set_library(self, library: OvalSetLibrary) -> None:
        self._library = library
        self._refresh_list()

    def get_library(self) -> OvalSetLibrary:
        return self._library

    def set_oval_sets_directory(self, directory: str) -> None:
        self._oval_sets_dir = directory
        if self._fs_watcher.directories():
            self._fs_watcher.removePaths(self._fs_watcher.directories())
        if self._fs_watcher.files():
            self._fs_watcher.removePaths(self._fs_watcher.files())
        if directory and os.path.isdir(directory):
            self._fs_watcher.addPath(directory)
        self._refresh_file_list()
        self._auto_discover()

    def set_shape_library(self, library) -> None:
        self._shape_library = library
        self._refresh_convenience_combos()

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
        if not self._oval_sets_dir or not os.path.isdir(self._oval_sets_dir):
            return
        if self._library.oval_sets:
            return
        files = sorted(f for f in os.listdir(self._oval_sets_dir) if f.lower().endswith(".xml"))
        if not files:
            return
        for filename in files:
            name = os.path.splitext(filename)[0]
            os_def = OvalSetDef(name=name, file_source=FileSource(folder="ovalSets", filename=filename))
            self._library.add_oval_set(os_def)
        self._refresh_list()

    def create_default_library(self) -> OvalSetLibrary:
        return OvalSetLibrary.default()

    # ── List management ───────────────────────────────────────────────────────

    def _refresh_list(self):
        self._updating = True
        try:
            current_name = self._current_set.name if self._current_set else None
            self.set_list.clear()
            for os_def in self._library.oval_sets:
                item = QTreeWidgetItem([os_def.name])
                item.setData(0, Qt.ItemDataRole.UserRole, os_def)
                self.set_list.addTopLevelItem(item)
                if os_def.name == current_name:
                    self.set_list.setCurrentItem(item)
        finally:
            self._updating = False

    def _on_set_selected(self, current, previous):
        if current is None:
            self._current_set = None
            self._clear_editor()
            return
        os_def = current.data(0, Qt.ItemDataRole.UserRole)
        self._current_set = os_def
        self._load_set_to_editor(os_def)

    def _clear_editor(self):
        self._updating = True
        try:
            self.name_edit.clear()
            self.folder_edit.clear()
            self.filename_combo.setCurrentText("")
            self.preview_widget.clear()
        finally:
            self._updating = False

    def _load_set_to_editor(self, os_def: OvalSetDef):
        self._updating = True
        try:
            self.name_edit.setText(os_def.name)
            if os_def.file_source:
                self.folder_edit.setText(os_def.file_source.folder or "ovalSets")
                self._refresh_file_list()
                self.filename_combo.setCurrentText(os_def.file_source.filename or "")
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
            if self._oval_sets_dir and os.path.isdir(self._oval_sets_dir):
                files = sorted(
                    f for f in os.listdir(self._oval_sets_dir)
                    if f.lower().endswith(".xml")
                )
                for i, f in enumerate(files):
                    self.filename_combo.addItem(f)
                    self.filename_combo.setItemData(
                        i, QBrush(self._file_color(f)), Qt.ItemDataRole.ForegroundRole)
                if self._fs_watcher.files():
                    self._fs_watcher.removePaths(self._fs_watcher.files())
                for f in files:
                    self._fs_watcher.addPath(os.path.join(self._oval_sets_dir, f))
            if current:
                idx = self.filename_combo.findText(current)
                if idx >= 0:
                    self.filename_combo.setCurrentIndex(idx)
                else:
                    self.filename_combo.setCurrentText(current)
        finally:
            self._updating = False

    def _update_preview(self):
        if not self._oval_sets_dir:
            self.preview_widget.clear()
            return
        filename = self.filename_combo.currentText()
        if not filename:
            self.preview_widget.clear()
            return
        full_path = os.path.join(self._oval_sets_dir, filename)
        self.preview_widget.load_polygon_set(full_path)

    # ── CRUD ─────────────────────────────────────────────────────────────────

    def _new_oval_set(self):
        name, ok = QInputDialog.getText(self, "New Oval Set", "Name:")
        if not ok or not name.strip():
            return
        name = name.strip()
        if self._library.get_oval_set(name):
            QMessageBox.warning(self, "Duplicate Name", f"An oval set named '{name}' already exists.")
            return
        os_def = OvalSetDef(name=name, file_source=FileSource(folder="ovalSets"))
        self._library.add_oval_set(os_def)
        self._refresh_list()
        self.modified.emit()
        for i in range(self.set_list.topLevelItemCount()):
            item = self.set_list.topLevelItem(i)
            if item.data(0, Qt.ItemDataRole.UserRole).name == name:
                self.set_list.setCurrentItem(item)
                break

    def _rename_oval_set(self):
        if self._current_set is None:
            return
        old_name = self._current_set.name
        name, ok = QInputDialog.getText(self, "Rename", "New name:", text=old_name)
        if not ok or not name.strip() or name.strip() == old_name:
            return
        name = name.strip()
        if self._library.get_oval_set(name):
            QMessageBox.warning(self, "Duplicate Name", f"'{name}' already exists.")
            return
        self._current_set.name = name
        self._refresh_list()
        self.modified.emit()

    def _duplicate_oval_set(self):
        if self._current_set is None:
            return
        new_os = self._current_set.copy()
        new_os.name = self._current_set.name + "_copy"
        self._library.add_oval_set(new_os)
        self._refresh_list()
        self.modified.emit()

    def _delete_oval_set(self):
        if self._current_set is None:
            return
        result = QMessageBox.question(
            self, "Delete", f"Delete '{self._current_set.name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result != QMessageBox.StandardButton.Yes:
            return
        self._library.remove_oval_set(self._current_set.name)
        self._current_set = None
        self._refresh_list()
        self._clear_editor()
        self.modified.emit()

    # ── Bezier launch ─────────────────────────────────────────────────────────

    def _strip_xml_headers(self, filepath: str) -> None:
        """Remove XML declaration and DOCTYPE lines from an oval set file."""
        with open(filepath, 'r', encoding='latin-1') as f:
            lines = f.readlines()
        cleaned = [l for l in lines
                   if not l.strip().startswith('<?xml')
                   and not l.strip().startswith('<!DOCTYPE')]
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(cleaned)

    def _snapshot_files(self) -> set:
        """Return the set of filenames currently in the oval sets directory."""
        if not self._oval_sets_dir or not os.path.isdir(self._oval_sets_dir):
            return set()
        return set(os.listdir(self._oval_sets_dir))

    def _create_in_bezier(self) -> None:
        """Launch Bezier to create a new oval set."""
        if not self._oval_sets_dir:
            QMessageBox.warning(self, "No Project", "Please save the project first.")
            return
        os.makedirs(self._oval_sets_dir, exist_ok=True)
        if self._bezier_process is not None and \
                self._bezier_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.information(self, "Bezier Running", "Bezier is already running.")
            return

        self._pre_launch_files = self._snapshot_files()

        self._bezier_process = QProcess(self)
        self._bezier_process.setWorkingDirectory(BEZIER_WORKING_DIR)
        self._bezier_process.finished.connect(self._on_create_bezier_finished)
        self._bezier_process.start("java", [
            "-Xmx4G", "-jar", BEZIER_JAR,
            "--save-dir", self._oval_sets_dir
        ])

    def _on_create_bezier_finished(self, exit_code, exit_status) -> None:
        """Handle Bezier process finishing after create."""
        if not self._oval_sets_dir or not os.path.isdir(self._oval_sets_dir):
            return

        current_files = self._snapshot_files()
        new_files = current_files - self._pre_launch_files

        for fname in new_files:
            fpath = os.path.join(self._oval_sets_dir, fname)
            if os.path.isfile(fpath):
                self._strip_xml_headers(fpath)

        xml_files = sorted(f for f in new_files if f.endswith('.xml'))

        self._refresh_file_list()

        if len(xml_files) == 1:
            self.filename_combo.setCurrentText(xml_files[0])

        self.modified.emit()

    def _edit_in_bezier(self):
        if not self._oval_sets_dir:
            QMessageBox.warning(self, "No Project", "Please save the project first.")
            return
        filename = self.filename_combo.currentText()
        if not filename:
            QMessageBox.warning(self, "No File", "Select an oval set file first.")
            return
        full_path = os.path.join(self._oval_sets_dir, filename)

        if self._bezier_process is not None and \
                self._bezier_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.information(self, "Bezier Running", "Bezier is already running.")
            return

        self._bezier_process = QProcess(self)
        self._bezier_process.setWorkingDirectory(BEZIER_WORKING_DIR)
        self._bezier_process.finished.connect(self._on_edit_bezier_finished)
        self._bezier_process.start("java", [
            "-Xmx4G", "-jar", BEZIER_JAR,
            "--save-dir", self._oval_sets_dir,
            "--load", full_path
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
        if filename.lower().endswith('.layers.xml'):
            return _COL_ORANGE
        if re.search(r'_layer_\d+\.xml$', filename, re.IGNORECASE):
            return _COL_ORANGE
        return _COL_GREEN

    # ── Convenience panel ─────────────────────────────────────────────────

    def _create_convenience_panel(self) -> QWidget:
        container = QWidget()
        outer = QVBoxLayout(container)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(4)

        row1 = QHBoxLayout()
        row1.setSpacing(4)

        shape_group = QGroupBox("Shapes")
        self._conv_shape_group = shape_group
        sg_layout = QVBoxLayout(shape_group)
        sg_layout.setContentsMargins(4, 4, 4, 4)
        sg_layout.setSpacing(4)
        srow = QHBoxLayout()
        srow.addWidget(QLabel("Set:"))
        self.conv_shape_set_combo = QComboBox()
        self.conv_shape_set_combo.setMinimumWidth(80)
        self.conv_shape_set_combo.currentIndexChanged.connect(
            lambda: self._update_conv_combo_style(self.conv_shape_set_combo))
        srow.addWidget(self.conv_shape_set_combo, 1)
        add_shape_set_btn = QPushButton("+ Set")
        add_shape_set_btn.setMaximumWidth(48)
        add_shape_set_btn.clicked.connect(self._on_conv_add_shape_set)
        srow.addWidget(add_shape_set_btn)
        sg_layout.addLayout(srow)
        make_shape_btn = QPushButton("Make Shape")
        make_shape_btn.clicked.connect(self._on_conv_make_shape)
        sg_layout.addWidget(make_shape_btn)
        sg_layout.addStretch()
        row1.addWidget(shape_group)

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
        groups = (self._conv_shape_group, self._conv_sprite_group, self._conv_render_group)
        if any(g is None for g in groups):
            return
        root = self._convenience_root()
        if not root:
            for g in groups:
                g.setStyleSheet("")
            return
        shape_name = f"{root}_shape"

        expected_set_name = f"{root}_ovalSet"
        shape_done = bool(self._shape_library and any(
            ss.name == expected_set_name and any(s.name == shape_name for s in ss.shapes)
            for ss in getattr(self._shape_library, 'shape_sets', [])))

        sprite_done = bool(self._sprite_library and any(
            any(getattr(sp, 'shape_set_name', '') == expected_set_name
                and getattr(sp, 'shape_name', '') == shape_name
                for sp in ss.sprites)
            for ss in getattr(self._sprite_library, 'sprite_sets', [])))

        renderer_name = f"{root}_renderer"
        render_done = bool(self._renderer_library and any(
            any(r.name == renderer_name for r in rs.renderers)
            for rs in getattr(self._renderer_library, 'renderer_sets', [])))

        gs = self._CONV_GREEN_BORDER
        self._conv_shape_group.setStyleSheet(gs if shape_done else "")
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
        if combo.currentText():
            combo.setStyleSheet(f"QComboBox {{ color: {_COL_SEL_GREEN}; }}")
        else:
            combo.setStyleSheet("")

    def _refresh_convenience_combos(self) -> None:
        if not hasattr(self, 'conv_shape_set_combo'):
            return
        shape_sel = self.conv_shape_set_combo.currentText()
        sprite_sel = self.conv_sprite_set_combo.currentText()
        renderer_sel = self.conv_renderer_set_combo.currentText()
        self.conv_shape_set_combo.blockSignals(True)
        self.conv_sprite_set_combo.blockSignals(True)
        self.conv_renderer_set_combo.blockSignals(True)
        try:
            self.conv_shape_set_combo.clear()
            if self._shape_library:
                for s in self._shape_library.shape_sets:
                    self.conv_shape_set_combo.addItem(s.name)
            self.conv_sprite_set_combo.clear()
            if self._sprite_library:
                for s in self._sprite_library.sprite_sets:
                    self.conv_sprite_set_combo.addItem(s.name)
            self.conv_renderer_set_combo.clear()
            if self._renderer_library:
                for rs in self._renderer_library.renderer_sets:
                    self.conv_renderer_set_combo.addItem(rs.name)
        finally:
            self.conv_shape_set_combo.blockSignals(False)
            self.conv_sprite_set_combo.blockSignals(False)
            self.conv_renderer_set_combo.blockSignals(False)
        for combo, sel in [
            (self.conv_shape_set_combo, shape_sel),
            (self.conv_sprite_set_combo, sprite_sel),
            (self.conv_renderer_set_combo, renderer_sel),
        ]:
            if sel:
                idx = combo.findText(sel)
                if idx >= 0:
                    combo.setCurrentIndex(idx)
            self._update_conv_combo_style(combo)

    def _on_conv_add_shape_set(self) -> None:
        root = self._convenience_root()
        suggestion = f"{root}_ovalSet" if root else "ovalSet"
        name, ok = QInputDialog.getText(self, "Add Shape Set", "Name:", text=suggestion)
        if not ok or not name.strip():
            return
        name = name.strip()
        if self._shape_library is None:
            QMessageBox.warning(self, "No Shape Library", "Shape library not available.")
            return
        if any(s.name == name for s in self._shape_library.shape_sets):
            QMessageBox.warning(self, "Duplicate", f"Shape set '{name}' already exists.")
            return
        self._shape_library.add(ShapeSet(name=name))
        self._refresh_convenience_combos()
        idx = self.conv_shape_set_combo.findText(name)
        if idx >= 0:
            self.conv_shape_set_combo.setCurrentIndex(idx)
        self.shapeLibraryChanged.emit()
        self.modified.emit()

    def _on_conv_make_shape(self) -> None:
        root = self._convenience_root()
        if not root:
            QMessageBox.warning(self, "No File", "Select an oval file first.")
            return
        set_name = self.conv_shape_set_combo.currentText()
        if not set_name or self._shape_library is None:
            QMessageBox.warning(self, "No Shape Set", "Select or create a shape set first.")
            return
        shape_set = next((s for s in self._shape_library.shape_sets if s.name == set_name), None)
        if shape_set is None:
            return
        name = f"{root}_shape"
        if any(s.name == name for s in shape_set.shapes):
            QMessageBox.warning(self, "Duplicate", f"Shape '{name}' already exists in '{set_name}'.")
            return
        oval_set_name = ""
        if self._current_set:
            oval_set_name = self._current_set.name
        shape_set.add(ShapeDef(
            name=name,
            source_type=ShapeSourceType.OVAL_SET,
            oval_set_name=oval_set_name,
        ))
        self.newShapeCreated.emit(set_name, name)
        self.shapeLibraryChanged.emit()
        self.modified.emit()
        self._update_convenience_borders()

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
            QMessageBox.warning(self, "No File", "Select an oval file first.")
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
        shape_set_name = self.conv_shape_set_combo.currentText()
        shape_name = ""
        if shape_set_name and self._shape_library:
            ss = next((s for s in self._shape_library.shape_sets if s.name == shape_set_name), None)
            if ss and any(sh.name == f"{root}_shape" for sh in ss.shapes):
                shape_name = f"{root}_shape"
        sprite_set.add(SpriteDef(
            name=name,
            shape_set_name=shape_set_name,
            shape_name=shape_name,
            renderer_set_name="DefaultSet",
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
            QMessageBox.warning(self, "No File", "Select an oval file first.")
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
            self._current_set.file_source = FileSource(folder="ovalSets")
        self._current_set.file_source.folder = folder
        self._current_set.file_source.filename = filename
        current_item = self.set_list.currentItem()
        if current_item:
            current_item.setText(0, self._current_set.name)
