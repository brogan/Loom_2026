"""
Open Curve Set configuration tab for the parameter editor.
Provides UI for editing curves.xml settings.
"""
import os
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QComboBox, QTreeWidget, QTreeWidgetItem, QPushButton,
    QSplitter, QLabel, QMessageBox, QInputDialog, QSizePolicy
)
from PyQt6.QtCore import pyqtSignal, Qt, QProcess
from models.open_curve_config import OpenCurveDef, OpenCurveSetLibrary, OpenCurveSourceType
from models.polygon_config import FileSource
from ui.polygon_tab import PolygonPreviewWidget

BEZIER_JAR = "/Users/broganbunt/Loom_2026/bezier/out/artifacts/Bezier_jar/Bezier.jar"
BEZIER_WORKING_DIR = "/Users/broganbunt/Loom_2026/bezier"


class OpenCurveTab(QWidget):
    """Tab widget for editing open curve set configuration."""

    modified = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._library = OpenCurveSetLibrary.default()
        self._current_set: OpenCurveDef = None
        self._updating = False
        self._curve_sets_dir: str = ""
        self._bezier_process: QProcess = None
        self._sprite_library = None
        self._pre_edit_topology = None  # snapshot before Bezier launch
        self._edit_file_path: str = ""

        self._setup_ui()
        self._refresh_list()

    def _setup_ui(self):
        main_layout = QHBoxLayout(self)
        splitter = QSplitter(Qt.Orientation.Horizontal)
        main_layout.addWidget(splitter)

        # ── Left panel ────────────────────────────────────────────────────────
        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)

        left_layout.addWidget(QLabel("Open Curve Sets:"))

        self.set_list = QTreeWidget()
        self.set_list.setHeaderLabels(["Name"])
        self.set_list.setRootIsDecorated(False)
        self.set_list.currentItemChanged.connect(self._on_set_selected)
        left_layout.addWidget(self.set_list)

        btn_layout = QHBoxLayout()
        self.new_btn = QPushButton("New")
        self.new_btn.clicked.connect(self._new_curve_set)
        btn_layout.addWidget(self.new_btn)

        self.rename_btn = QPushButton("Rename")
        self.rename_btn.clicked.connect(self._rename_curve_set)
        btn_layout.addWidget(self.rename_btn)

        btn_layout2 = QHBoxLayout()
        self.dup_btn = QPushButton("Duplicate")
        self.dup_btn.clicked.connect(self._duplicate_curve_set)
        btn_layout2.addWidget(self.dup_btn)

        self.del_btn = QPushButton("Delete")
        self.del_btn.clicked.connect(self._delete_curve_set)
        btn_layout2.addWidget(self.del_btn)

        left_layout.addLayout(btn_layout)
        left_layout.addLayout(btn_layout2)
        left_layout.addStretch()
        splitter.addWidget(left_panel)

        # ── Right panel ───────────────────────────────────────────────────────
        right_panel = QWidget()
        right_layout = QVBoxLayout(right_panel)

        info_group = QGroupBox("Open Curve Set")
        form = QFormLayout(info_group)

        self.name_edit = QLineEdit()
        self.name_edit.setReadOnly(True)
        form.addRow("Name:", self.name_edit)

        self.folder_edit = QLineEdit()
        self.folder_edit.setText("curveSets")
        self.folder_edit.textChanged.connect(self._on_modified)
        form.addRow("Folder:", self.folder_edit)

        self.filename_combo = QComboBox()
        self.filename_combo.setEditable(True)
        self.filename_combo.currentTextChanged.connect(self._on_modified)
        self.filename_combo.currentTextChanged.connect(self._update_preview)
        form.addRow("Filename:", self.filename_combo)

        btn_row = QHBoxLayout()
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

        right_layout.addStretch()
        splitter.addWidget(right_panel)
        splitter.setSizes([220, 580])

    # ── Library access ────────────────────────────────────────────────────────

    def set_library(self, library: OpenCurveSetLibrary) -> None:
        self._library = library
        self._refresh_list()

    def get_library(self) -> OpenCurveSetLibrary:
        return self._library

    def set_curve_sets_directory(self, directory: str) -> None:
        self._curve_sets_dir = directory
        self._refresh_file_list()
        self._auto_discover()

    def _auto_discover(self) -> None:
        """Populate library from filesystem if it currently has no entries."""
        if not self._curve_sets_dir or not os.path.isdir(self._curve_sets_dir):
            return
        if self._library.curve_sets:
            return
        files = sorted(f for f in os.listdir(self._curve_sets_dir) if f.lower().endswith(".xml"))
        if not files:
            return
        for filename in files:
            name = os.path.splitext(filename)[0]
            cs = OpenCurveDef(name=name, file_source=FileSource(folder="curveSets", filename=filename))
            self._library.add_curve_set(cs)
        self._refresh_list()

    def create_default_library(self) -> OpenCurveSetLibrary:
        return OpenCurveSetLibrary.default()

    # ── List management ───────────────────────────────────────────────────────

    def _refresh_list(self):
        self._updating = True
        try:
            current_name = self._current_set.name if self._current_set else None
            self.set_list.clear()
            for cs in self._library.curve_sets:
                item = QTreeWidgetItem([cs.name])
                item.setData(0, Qt.ItemDataRole.UserRole, cs)
                self.set_list.addTopLevelItem(item)
                if cs.name == current_name:
                    self.set_list.setCurrentItem(item)
        finally:
            self._updating = False

    def _on_set_selected(self, current, previous):
        if current is None:
            self._current_set = None
            self._clear_editor()
            return
        cs = current.data(0, Qt.ItemDataRole.UserRole)
        self._current_set = cs
        self._load_set_to_editor(cs)

    def _clear_editor(self):
        self._updating = True
        try:
            self.name_edit.clear()
            self.folder_edit.clear()
            self.filename_combo.setCurrentText("")
            self.preview_widget.clear()
        finally:
            self._updating = False

    def _load_set_to_editor(self, cs: OpenCurveDef):
        self._updating = True
        try:
            self.name_edit.setText(cs.name)
            if cs.file_source:
                self.folder_edit.setText(cs.file_source.folder or "curveSets")
                self._refresh_file_list()
                self.filename_combo.setCurrentText(cs.file_source.filename or "")
            self._update_preview()
        finally:
            self._updating = False

    # ── File list helpers ─────────────────────────────────────────────────────

    def _refresh_file_list(self):
        self._updating = True
        try:
            current = self.filename_combo.currentText()
            self.filename_combo.clear()
            if self._curve_sets_dir and os.path.isdir(self._curve_sets_dir):
                files = sorted(
                    f for f in os.listdir(self._curve_sets_dir)
                    if f.lower().endswith(".xml")
                )
                self.filename_combo.addItems(files)
            if current:
                idx = self.filename_combo.findText(current)
                if idx >= 0:
                    self.filename_combo.setCurrentIndex(idx)
                else:
                    self.filename_combo.setCurrentText(current)
        finally:
            self._updating = False

    def _update_preview(self):
        if not self._curve_sets_dir:
            self.preview_widget.clear()
            return
        filename = self.filename_combo.currentText()
        if not filename:
            self.preview_widget.clear()
            return
        full_path = os.path.join(self._curve_sets_dir, filename)
        self.preview_widget.load_polygon_set(full_path)

    # ── CRUD ─────────────────────────────────────────────────────────────────

    def _new_curve_set(self):
        name, ok = QInputDialog.getText(self, "New Open Curve Set", "Name:")
        if not ok or not name.strip():
            return
        name = name.strip()
        if self._library.get_curve_set(name):
            QMessageBox.warning(self, "Duplicate Name", f"A curve set named '{name}' already exists.")
            return
        cs = OpenCurveDef(name=name, file_source=FileSource(folder="curveSets"))
        self._library.add_curve_set(cs)
        self._refresh_list()
        self.modified.emit()
        # Select newly created
        for i in range(self.set_list.topLevelItemCount()):
            item = self.set_list.topLevelItem(i)
            if item.data(0, Qt.ItemDataRole.UserRole).name == name:
                self.set_list.setCurrentItem(item)
                break

    def _rename_curve_set(self):
        if self._current_set is None:
            return
        old_name = self._current_set.name
        name, ok = QInputDialog.getText(self, "Rename", "New name:", text=old_name)
        if not ok or not name.strip() or name.strip() == old_name:
            return
        name = name.strip()
        if self._library.get_curve_set(name):
            QMessageBox.warning(self, "Duplicate Name", f"'{name}' already exists.")
            return
        self._current_set.name = name
        self._refresh_list()
        self.modified.emit()

    def _duplicate_curve_set(self):
        if self._current_set is None:
            return
        base = self._current_set.name + "_copy"
        new_cs = self._current_set.copy()
        new_cs.name = base
        self._library.add_curve_set(new_cs)
        self._refresh_list()
        self.modified.emit()

    def _delete_curve_set(self):
        if self._current_set is None:
            return
        result = QMessageBox.question(
            self, "Delete", f"Delete '{self._current_set.name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result != QMessageBox.StandardButton.Yes:
            return
        self._library.remove_curve_set(self._current_set.name)
        self._current_set = None
        self._refresh_list()
        self._clear_editor()
        self.modified.emit()

    # ── Topology helpers ──────────────────────────────────────────────────────

    def _count_topology(self, file_path: str):
        """Return (poly_count, total_vertex_count) for a curve XML, or None on error."""
        try:
            from lxml import etree
            tree = etree.parse(file_path)
            root = tree.getroot()
            curves = root.findall(".//openCurve") + root.findall(".//polygon")
            poly_count = len(curves)
            vert_count = sum(len(c.findall("point")) + len(c.findall("pt")) for c in curves)
            return (poly_count, vert_count)
        except Exception:
            return None

    def _sprites_with_morph_targets_for(self, filename: str):
        """Return list of sprite names that use filename as base and have morph targets."""
        if self._sprite_library is None:
            return []
        affected = []
        for ss in self._sprite_library.sprite_sets:
            for sprite in ss.sprites:
                if sprite.params.morph_targets and sprite.shape_name == filename:
                    affected.append(f"{ss.name}/{sprite.name}")
        return affected

    # ── Bezier launch ─────────────────────────────────────────────────────────

    def _edit_in_bezier(self):
        if not self._curve_sets_dir:
            QMessageBox.warning(self, "No Project", "Please save the project first.")
            return
        filename = self.filename_combo.currentText()
        if not filename:
            QMessageBox.warning(self, "No File", "Select a curve set file first.")
            return
        full_path = os.path.join(self._curve_sets_dir, filename)

        if self._bezier_process is not None and \
                self._bezier_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.information(self, "Bezier Running", "Bezier is already running.")
            return

        self._edit_file_path = full_path
        self._pre_edit_topology = self._count_topology(full_path)

        # Warn if any sprites have morph targets referencing this base shape
        affected = self._sprites_with_morph_targets_for(filename)
        if affected:
            QMessageBox.warning(
                self, "Morph Target Warning",
                "This curve set is used as the base shape for sprites with morph targets:\n"
                + "\n".join(f"  • {s}" for s in affected)
                + "\n\nEditing it may break the morph chains if curve or vertex count changes."
            )

        self._bezier_process = QProcess(self)
        self._bezier_process.setWorkingDirectory(BEZIER_WORKING_DIR)
        self._bezier_process.finished.connect(self._on_edit_bezier_finished)
        self._bezier_process.start("java", [
            "-Xmx4G", "-jar", BEZIER_JAR,
            "--save-dir", self._curve_sets_dir,
            "--load", full_path
        ])

    def _on_edit_bezier_finished(self, exit_code, exit_status):
        self._refresh_file_list()
        self._update_preview()

        # Post-edit topology check
        if self._edit_file_path and self._pre_edit_topology is not None:
            post_topo = self._count_topology(self._edit_file_path)
            if post_topo and post_topo != self._pre_edit_topology:
                filename = os.path.basename(self._edit_file_path)
                affected = self._sprites_with_morph_targets_for(filename)
                if affected:
                    QMessageBox.warning(
                        self, "Topology Changed",
                        f"The curve/vertex count of '{filename}' changed:\n"
                        f"  Before: {self._pre_edit_topology[0]} curves, {self._pre_edit_topology[1]} vertices\n"
                        f"  After:  {post_topo[0]} curves, {post_topo[1]} vertices\n\n"
                        "The following sprites have morph targets that may now be broken:\n"
                        + "\n".join(f"  • {s}" for s in affected)
                    )
        self._pre_edit_topology = None
        self._edit_file_path = ""

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
            self._current_set.file_source = FileSource(folder="curveSets")
        self._current_set.file_source.folder = folder
        self._current_set.file_source.filename = filename
        # Sync name label in list
        current_item = self.set_list.currentItem()
        if current_item:
            current_item.setText(0, self._current_set.name)
