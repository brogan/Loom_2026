"""
Spline Polygon Set configuration tab.
Shows only FILE-source polygon sets (spline/line polygons edited in Bezier).
"""
from __future__ import annotations
import os
import re
import shutil
import xml.etree.ElementTree as ET
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QSpinBox, QDoubleSpinBox, QComboBox, QTreeWidget,
    QTreeWidgetItem, QPushButton, QSplitter, QLabel,
    QMessageBox, QInputDialog, QFileDialog, QCheckBox, QSizePolicy
)
from PySide6.QtCore import Signal, Qt, QProcess, QFileSystemWatcher
from PySide6.QtGui import QBrush
from models.polygon_config import (
    PolygonSourceType, PolygonType,
    FileSource, PolygonSetDef, PolygonSetLibrary
)
from models.sprite_config import SpriteDef, SpriteSet, GeoSourceType
from models.subdivision_config import SubdivisionParams, SubdivisionParamsSet, SubdivisionType
from models.rendering import Renderer, RendererSet
from models.constants import RenderMode
from ui.polygon_tab import (
    PolygonPreviewWidget, _FilenameDelegate,
    _COL_ORANGE, _COL_GREEN, _COL_SEL_GREEN,
    BEZIER_PY, PYTHON, _BEZIER_RESOURCES
)

POLYGONS_LIBRARY_DIR = os.path.expanduser("~/.loom_projects/polygons_library")


class SplinePolygonTab(QWidget):
    """Tab for FILE-source polygon sets (spline / line polygons from Bezier)."""

    modified = Signal()
    shapeLibraryChanged    = Signal()
    subdivisionChanged     = Signal()
    spriteLibraryChanged   = Signal()
    rendererLibraryChanged = Signal()
    newShapeCreated        = Signal(str, str)
    newSpriteCreated       = Signal(str, str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._library: PolygonSetLibrary = PolygonSetLibrary.default()
        self._current_set: PolygonSetDef = None
        self._updating = False
        self._checking = False
        self._polygon_sets_dir: str = ""
        self._bezier_process: QProcess = None
        self._pre_launch_files: set = set()
        self._sprite_library = None
        self._subdivision_collection = None
        self._renderer_library = None
        self._pre_edit_topology = None
        self._edit_file_path: str = ""
        self._conv_sub_group = None
        self._conv_sprite_group = None
        self._conv_render_group = None

        self._fs_watcher = QFileSystemWatcher()
        self._fs_watcher.directoryChanged.connect(self._on_dir_changed)
        self._fs_watcher.fileChanged.connect(self._on_file_changed)

        self._setup_ui()
        self._refresh_list()

    # ── UI setup ──────────────────────────────────────────────────────────────

    def _setup_ui(self):
        main_layout = QHBoxLayout(self)
        splitter = QSplitter(Qt.Orientation.Horizontal)
        main_layout.addWidget(splitter)

        # ── Left panel ────────────────────────────────────────────────────────
        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)

        left_layout.addWidget(QLabel("Polygon Sets:"))

        self.set_list = QTreeWidget()
        self.set_list.setHeaderLabels(["Name", "Shapes", "Sprites"])
        self.set_list.setRootIsDecorated(False)
        self.set_list.setColumnWidth(0, 140)
        self.set_list.setColumnWidth(1, 50)
        self.set_list.setColumnWidth(2, 50)
        self.set_list.header().setStretchLastSection(False)
        self.set_list.currentItemChanged.connect(self._on_set_selected)
        left_layout.addWidget(self.set_list)

        btn_layout = QHBoxLayout()
        self.delete_btn = QPushButton("Delete")
        self.delete_btn.clicked.connect(self._delete_set)
        btn_layout.addWidget(self.delete_btn)

        self.dup_btn = QPushButton("Duplicate")
        self.dup_btn.clicked.connect(self._duplicate_set)
        btn_layout.addWidget(self.dup_btn)

        self.rename_btn = QPushButton("Rename")
        self.rename_btn.clicked.connect(self._rename_set)
        btn_layout.addWidget(self.rename_btn)

        left_layout.addLayout(btn_layout)
        splitter.addWidget(left_panel)

        # ── Right panel ───────────────────────────────────────────────────────
        right_panel = QWidget()
        right_layout = QVBoxLayout(right_panel)

        info_group = QGroupBox("Spline Polygon Set")
        form = QFormLayout(info_group)

        self.name_edit = QLineEdit()
        self.name_edit.setReadOnly(True)
        form.addRow("Name:", self.name_edit)

        self.folder_edit = QLineEdit()
        self.folder_edit.setText("polygonSets")
        self.folder_edit.textChanged.connect(self._on_modified)
        form.addRow("Folder:", self.folder_edit)

        self.filename_combo = QComboBox()
        self.filename_combo.setEditable(True)
        self.filename_combo.setItemDelegate(_FilenameDelegate(self.filename_combo))
        self.filename_combo.currentTextChanged.connect(self._on_modified)
        self.filename_combo.currentTextChanged.connect(self._update_preview)
        self.filename_combo.currentTextChanged.connect(lambda _: self._update_convenience_borders())
        form.addRow("Filename:", self.filename_combo)

        self.poly_type_combo = QComboBox()
        self.poly_type_combo.addItems(["SPLINE_POLYGON", "LINE_POLYGON"])
        self.poly_type_combo.currentTextChanged.connect(self._on_modified)
        form.addRow("Polygon Type:", self.poly_type_combo)

        self._include_open_curves_check = QCheckBox("Include open curves")
        self._include_open_curves_check.setChecked(True)
        self._include_open_curves_check.stateChanged.connect(self._on_include_open_changed)
        form.addRow("", self._include_open_curves_check)

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

        btn_row.addStretch()

        self.refresh_btn = QPushButton("Refresh Files")
        self.refresh_btn.clicked.connect(self._refresh_file_list)
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
        splitter.setSizes([250, 550])

    # ── Library access ────────────────────────────────────────────────────────

    def set_library(self, library: PolygonSetLibrary) -> None:
        self._library = library
        self._refresh_list()

    def get_library(self) -> PolygonSetLibrary:
        return self._library

    def create_default_library(self) -> PolygonSetLibrary:
        return PolygonSetLibrary.default()

    # ── Directory / cross-wiring ──────────────────────────────────────────────

    def set_polygon_sets_directory(self, directory: str) -> None:
        self._polygon_sets_dir = directory
        if self._fs_watcher.directories():
            self._fs_watcher.removePaths(self._fs_watcher.directories())
        if self._fs_watcher.files():
            self._fs_watcher.removePaths(self._fs_watcher.files())
        if directory and os.path.isdir(directory):
            self._fs_watcher.addPath(directory)
        self._refresh_file_list()
        self._reconcile_polygon_sets()

    def set_sprite_library(self, library) -> None:
        self._sprite_library = library
        self._refresh_list()
        self._refresh_convenience_combos()

    def set_subdivision_collection(self, coll) -> None:
        self._subdivision_collection = coll
        self._refresh_convenience_combos()

    def set_renderer_library(self, lib) -> None:
        self._renderer_library = lib
        self._refresh_convenience_combos()

    # ── List management ───────────────────────────────────────────────────────

    def _refresh_list(self):
        selected_name = None
        current = self.set_list.currentItem()
        if current:
            ps = current.data(0, Qt.ItemDataRole.UserRole)
            if ps:
                selected_name = ps.name

        self.set_list.clear()
        counts = self._compute_usage_counts()
        restore_item = None
        for ps in self._library.polygon_sets:
            if ps.source_type != PolygonSourceType.FILE:
                continue
            shape_count, sprite_count = counts.get(ps.name, (0, 0))
            item = QTreeWidgetItem([ps.name, str(shape_count), str(sprite_count)])
            item.setData(0, Qt.ItemDataRole.UserRole, ps)
            item.setTextAlignment(1, Qt.AlignmentFlag.AlignCenter)
            item.setTextAlignment(2, Qt.AlignmentFlag.AlignCenter)
            self.set_list.addTopLevelItem(item)
            if ps.name == selected_name:
                restore_item = item

        if restore_item:
            self.set_list.setCurrentItem(restore_item)
        elif self.set_list.topLevelItemCount() > 0:
            self.set_list.setCurrentItem(self.set_list.topLevelItem(0))

    def _on_set_selected(self, current, previous):
        if current is None:
            self._current_set = None
            self._clear_editor()
            return
        self._current_set = current.data(0, Qt.ItemDataRole.UserRole)
        self._load_set_to_editor(self._current_set)

    def _clear_editor(self):
        self._updating = True
        try:
            self.name_edit.clear()
            self.folder_edit.setText("polygonSets")
            self.filename_combo.setCurrentText("")
            self.poly_type_combo.setCurrentIndex(0)
            self._include_open_curves_check.setChecked(True)
            self.preview_widget.clear()
        finally:
            self._updating = False

    def _load_set_to_editor(self, ps: PolygonSetDef):
        self._updating = True
        try:
            self.name_edit.setText(ps.name)
            if ps.file_source:
                self.folder_edit.setText(ps.file_source.folder or "polygonSets")
                self._refresh_file_list()
                self.filename_combo.setCurrentText(ps.file_source.filename or "")
                self.poly_type_combo.setCurrentText(ps.file_source.polygon_type.value)
                self._include_open_curves_check.setChecked(
                    ps.file_source.filter_type == "all"
                )
            self._update_preview()
        finally:
            self._updating = False

    # ── CRUD ─────────────────────────────────────────────────────────────────

    def _delete_set(self) -> None:
        ps = self._current_set
        if ps is None:
            return
        fname = ps.file_source.filename if ps.file_source else None
        file_exists = bool(
            fname and self._polygon_sets_dir
            and os.path.isfile(os.path.join(self._polygon_sets_dir, fname))
        )
        msg = f"Remove '{ps.name}' from the library?"
        if file_exists:
            msg += f"\n\nAlso delete '{fname}' from disk?\n(Choose No to keep the file.)"
            btns = (QMessageBox.StandardButton.Yes |
                    QMessageBox.StandardButton.No |
                    QMessageBox.StandardButton.Cancel)
            result = QMessageBox.question(self, "Delete", msg, btns,
                                          QMessageBox.StandardButton.Cancel)
            if result == QMessageBox.StandardButton.Cancel:
                return
            if result == QMessageBox.StandardButton.Yes and fname:
                base = os.path.splitext(fname)[0]
                for fn in [fname, base + ".svg"]:
                    fpath = os.path.join(self._polygon_sets_dir, fn)
                    if os.path.isfile(fpath):
                        try:
                            os.remove(fpath)
                        except OSError as e:
                            QMessageBox.warning(self, "Delete Error", str(e))
        else:
            result = QMessageBox.question(
                self, "Delete", msg,
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
            if result != QMessageBox.StandardButton.Yes:
                return

        self._library.remove_polygon_set(ps.name)
        self._current_set = None
        self._refresh_list()
        self.modified.emit()

    def _duplicate_set(self) -> None:
        ps = self._current_set
        if ps is None:
            return
        new_ps = ps.copy()
        base = ps.name + "_copy"
        name, i = base, 2
        while any(p.name == name for p in self._library.polygon_sets):
            name = f"{base}{i}"; i += 1
        new_ps.name = name
        if new_ps.file_source:
            new_ps.file_source.filename = name + ".xml"
        self._library.add_polygon_set(new_ps)
        self._refresh_list()
        self.modified.emit()

    def _rename_set(self) -> None:
        if self._bezier_process and \
                self._bezier_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.warning(self, "Bezier Running",
                                "Close Bezier before renaming.")
            return
        ps = self._current_set
        if ps is None:
            return
        old_root = ps.file_source.filename if ps.file_source else ps.name
        # Strip .xml for display
        if old_root.lower().endswith('.xml'):
            old_root = old_root[:-4]
        new_root, ok = QInputDialog.getText(
            self, "Rename Polygon Set",
            f"New root name  (files '{old_root}.*' will be renamed):",
            text=old_root)
        if not ok or not new_root.strip():
            return
        new_root = new_root.strip()
        if any(p.name == new_root for p in self._library.polygon_sets if p is not ps):
            QMessageBox.warning(self, "Duplicate",
                f"A polygon set named '{new_root}' already exists.")
            return

        errors = []
        if self._polygon_sets_dir and os.path.isdir(self._polygon_sets_dir):
            for fn in os.listdir(self._polygon_sets_dir):
                stem, ext = os.path.splitext(fn)
                # Match: exact stem, or stem with _layer_N suffix, or .layers.xml
                if (stem == old_root
                        or fn == old_root + '.layers.xml'
                        or stem.startswith(old_root + '_')):
                    suffix = fn[len(old_root):]
                    new_fn = new_root + suffix
                    try:
                        os.rename(os.path.join(self._polygon_sets_dir, fn),
                                  os.path.join(self._polygon_sets_dir, new_fn))
                    except OSError as e:
                        errors.append(f"{fn}: {e}")

        if errors:
            QMessageBox.warning(self, "Rename Errors",
                "Some files could not be renamed:\n" + "\n".join(errors))

        ps.name = new_root
        if ps.file_source:
            ps.file_source.filename = new_root + ".xml"
        self._refresh_list()
        self._refresh_file_list()
        self.modified.emit()

    # ── File helpers ──────────────────────────────────────────────────────────

    def _refresh_file_list(self) -> None:
        _saved = self._updating   # preserve outer guard if called from _load_set_to_editor
        self._updating = True
        try:
            current_text = self.filename_combo.currentText()
            self.filename_combo.clear()

            if self._polygon_sets_dir and os.path.isdir(self._polygon_sets_dir):
                extensions = ('.xml', '.json', '.txt', '.poly')
                files = []
                try:
                    for f in os.listdir(self._polygon_sets_dir):
                        if os.path.isfile(os.path.join(self._polygon_sets_dir, f)):
                            if f.lower().endswith(extensions) or '.' not in f:
                                files.append(f)
                    files.sort()
                    for i, f in enumerate(files):
                        self.filename_combo.addItem(f)
                        self.filename_combo.setItemData(
                            i, QBrush(self._file_color(f)), Qt.ItemDataRole.ForegroundRole)
                except OSError:
                    pass
                if self._fs_watcher.files():
                    self._fs_watcher.removePaths(self._fs_watcher.files())
                for f in files:
                    self._fs_watcher.addPath(os.path.join(self._polygon_sets_dir, f))

            if current_text:
                index = self.filename_combo.findText(current_text)
                if index >= 0:
                    self.filename_combo.setCurrentIndex(index)
                else:
                    self.filename_combo.setCurrentText(current_text)
        finally:
            self._updating = _saved

    def _file_color(self, filename: str):
        if filename.lower().endswith('.layers.xml'):
            return _COL_ORANGE
        return _COL_GREEN

    def _update_preview(self) -> None:
        if not hasattr(self, 'preview_widget'):
            return
        fname = self.filename_combo.currentText() if hasattr(self, 'filename_combo') else ""
        if fname and self._polygon_sets_dir:
            fpath = os.path.join(self._polygon_sets_dir, fname)
            filter_open = not self._include_open_curves_check.isChecked()
            self.preview_widget.load_polygon_set(fpath, filter_open=filter_open)
        else:
            self.preview_widget.clear()

    # ── Reconcile ─────────────────────────────────────────────────────────────

    def _reconcile_polygon_sets(self) -> None:
        if not self._polygon_sets_dir or not os.path.isdir(self._polygon_sets_dir):
            return

        changed = False

        # Remove stale FILE entries
        stale_names = []
        for ps in self._library.polygon_sets:
            if (ps.source_type == PolygonSourceType.FILE
                    and ps.file_source and ps.file_source.filename):
                fpath = os.path.join(self._polygon_sets_dir, ps.file_source.filename)
                if not os.path.isfile(fpath):
                    stale_names.append(ps.name)
        for name in stale_names:
            self._library.remove_polygon_set(name)
        if stale_names:
            changed = True

        # Build referenced set
        referenced_files = set()
        for ps in self._library.polygon_sets:
            if ps.source_type == PolygonSourceType.FILE and ps.file_source:
                referenced_files.add(ps.file_source.filename)

        # Add new XML files
        try:
            all_files = sorted(os.listdir(self._polygon_sets_dir))
        except OSError:
            all_files = []

        for fname in all_files:
            if not fname.lower().endswith('.xml'):
                continue
            if fname in referenced_files:
                continue
            fpath = os.path.join(self._polygon_sets_dir, fname)
            if not os.path.isfile(fpath):
                continue
            name = self._parse_polygon_set_name(fpath)
            base_name = name
            counter = 1
            while self._library.get_polygon_set(name):
                name = f"{base_name}_{counter}"
                counter += 1
            self._library.add_polygon_set(PolygonSetDef(
                name=name,
                source_type=PolygonSourceType.FILE,
                file_source=FileSource(
                    folder="polygonSet",
                    filename=fname,
                    polygon_type=PolygonType.SPLINE_POLYGON
                )
            ))
            changed = True

        if changed:
            self._refresh_list()
            self.modified.emit()

    def _compute_usage_counts(self) -> dict:
        sprite_counts: dict[str, int] = {}
        if self._sprite_library is not None:
            for sprite_set in getattr(self._sprite_library, 'sprite_sets', []):
                for sprite in getattr(sprite_set, 'sprites', []):
                    name = getattr(sprite, 'geo_polygon_set_name', '')
                    if name:
                        sprite_counts[name] = sprite_counts.get(name, 0) + 1
        return {n: (0, sprite_counts[n]) for n in sprite_counts}

    # ── Change tracking ───────────────────────────────────────────────────────

    def _on_modified(self):
        if self._updating:
            return
        self._save_editor_to_set()
        self._update_preview()
        self.modified.emit()

    def _on_include_open_changed(self):
        if self._updating:
            return
        self._save_editor_to_set()
        self._update_preview()
        self.modified.emit()

    def _save_editor_to_set(self):
        if self._current_set is None:
            return
        filename = self.filename_combo.currentText()
        folder = self.folder_edit.text()
        if self._current_set.file_source is None:
            self._current_set.file_source = FileSource()
        self._current_set.file_source.folder = folder
        self._current_set.file_source.filename = filename
        try:
            self._current_set.file_source.polygon_type = PolygonType(
                self.poly_type_combo.currentText())
        except ValueError:
            self._current_set.file_source.polygon_type = PolygonType.SPLINE_POLYGON
        self._current_set.file_source.filter_type = (
            "all" if self._include_open_curves_check.isChecked() else "closed_only"
        )
        current_item = self.set_list.currentItem()
        if current_item:
            current_item.setText(0, self._current_set.name)

    # ── Watcher ───────────────────────────────────────────────────────────────

    def _on_dir_changed(self, path: str) -> None:
        self._refresh_file_list()
        self._refresh_list()

    def _on_file_changed(self, path: str) -> None:
        if os.path.exists(path):
            self._fs_watcher.addPath(path)
        self._refresh_file_list()
        self._refresh_list()

    # ── XML header helpers ────────────────────────────────────────────────────

    def _strip_xml_headers(self, filepath: str) -> None:
        with open(filepath, 'r', encoding='latin-1') as f:
            lines = f.readlines()
        cleaned = [l for l in lines
                   if not l.strip().startswith('<?xml')
                   and not l.strip().startswith('<!DOCTYPE')]
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(cleaned)

    def _add_xml_headers(self, filepath: str) -> None:
        xml_dir = os.path.dirname(filepath)
        dtd_dir = os.path.join(os.path.dirname(xml_dir), "dtd")
        dtd_dest = os.path.join(dtd_dir, "polygonSet.dtd")
        if not os.path.isfile(dtd_dest):
            dtd_source = os.path.join(_BEZIER_RESOURCES, "dtd", "polygonSet.dtd")
            if os.path.isfile(dtd_source):
                os.makedirs(dtd_dir, exist_ok=True)
                shutil.copy2(dtd_source, dtd_dest)
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        if content.lstrip().startswith('<?xml'):
            return
        header = ('<?xml version="1.0" encoding="ISO-8859-1"?>\n'
                  '<!DOCTYPE polygonSet SYSTEM "../dtd/polygonSet.dtd">\n')
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(header + content)

    def _add_xml_headers_layerset(self, filepath: str) -> None:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        if content.lstrip().startswith('<?xml'):
            return
        header = '<?xml version="1.0" encoding="ISO-8859-1"?>\n'
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(header + content)

    def _add_xml_headers_for_bundle_layers(self, layers_xml_path: str) -> None:
        base_dir = os.path.dirname(layers_xml_path)
        try:
            tree = ET.parse(layers_xml_path)
            for layer_elem in tree.getroot().findall('layer'):
                file_elem = layer_elem.find('file')
                if file_elem is not None and file_elem.text:
                    fpath = os.path.join(base_dir, file_elem.text.strip())
                    if os.path.isfile(fpath):
                        self._add_xml_headers_layerset(fpath)
        except Exception:
            pass

    def _parse_layers_manifest_name(self, filepath: str) -> str:
        try:
            tree = ET.parse(filepath)
            el = tree.getroot().find('overallName')
            return el.text.strip() if el is not None and el.text else ''
        except Exception:
            return ''

    def _parse_polygon_set_name(self, filepath: str) -> str:
        name = None
        try:
            tree = ET.parse(filepath, parser=ET.XMLParser(encoding='utf-8'))
            name_elem = tree.find('name')
            if name_elem is not None and name_elem.text:
                name = name_elem.text.strip()
        except Exception:
            pass
        if not name:
            name = os.path.splitext(os.path.basename(filepath))[0]
        if name.lower().endswith('.xml'):
            name = name[:-4]
        return name

    def _snapshot_polygon_files(self) -> set:
        if not self._polygon_sets_dir or not os.path.isdir(self._polygon_sets_dir):
            return set()
        return set(os.listdir(self._polygon_sets_dir))

    # ── Bezier integration ────────────────────────────────────────────────────

    def _count_topology(self, file_path: str):
        try:
            from lxml import etree
            tree = etree.parse(file_path)
            root = tree.getroot()
            polys = root.findall(".//polygon") + root.findall(".//openCurve")
            poly_count = len(polys)
            vert_count = sum(len(p.findall("point")) + len(p.findall("pt")) for p in polys)
            return (poly_count, vert_count)
        except Exception:
            return None

    def _sprites_with_morph_targets_for(self, filename: str):
        if self._sprite_library is None:
            return []
        affected = []
        for ss in self._sprite_library.sprite_sets:
            for sprite in ss.sprites:
                if sprite.params.morph_targets and sprite.shape_name == filename:
                    affected.append(f"{ss.name}/{sprite.name}")
        return affected

    def _auto_populate_fields(self, filename: str, filepath: str) -> None:
        name = self._parse_polygon_set_name(filepath)
        if self._current_set is None:
            new_set = PolygonSetDef(
                name=name,
                source_type=PolygonSourceType.FILE,
                file_source=FileSource(
                    folder="polygonSet",
                    filename=filename,
                    polygon_type=PolygonType.SPLINE_POLYGON
                )
            )
            self._library.add_polygon_set(new_set)
            self._refresh_list()
            last = self.set_list.topLevelItem(self.set_list.topLevelItemCount() - 1)
            if last:
                self.set_list.setCurrentItem(last)
        else:
            self._updating = True
            try:
                self._current_set.name = name
                self._current_set.source_type = PolygonSourceType.FILE
                if self._current_set.file_source is None:
                    self._current_set.file_source = FileSource()
                self._current_set.file_source.folder = "polygonSet"
                self._current_set.file_source.filename = filename
                self._current_set.file_source.polygon_type = PolygonType.SPLINE_POLYGON
                self._load_set_to_editor(self._current_set)
                current_item = self.set_list.currentItem()
                if current_item:
                    current_item.setText(0, self._current_set.name)
            finally:
                self._updating = False
        self._refresh_file_list()
        self.modified.emit()

    def _create_in_bezier(self) -> None:
        if not self._polygon_sets_dir or not os.path.isdir(self._polygon_sets_dir):
            QMessageBox.warning(self, "No Project", "Please save the project first.")
            return
        if self._bezier_process is not None and \
                self._bezier_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.information(self, "Bezier Running", "Bezier is already running.")
            return
        self._pre_launch_files = self._snapshot_polygon_files()
        self._bezier_process = QProcess(self)
        self._bezier_process.finished.connect(self._on_create_bezier_finished)
        self._bezier_process.start(PYTHON, [BEZIER_PY, "--save-dir", self._polygon_sets_dir])

    def _on_create_bezier_finished(self, exit_code, exit_status) -> None:
        if not self._polygon_sets_dir or not os.path.isdir(self._polygon_sets_dir):
            return
        current_files = self._snapshot_polygon_files()
        new_files = current_files - self._pre_launch_files

        for fname in new_files:
            fpath = os.path.join(self._polygon_sets_dir, fname)
            if os.path.isfile(fpath):
                self._strip_xml_headers(fpath)

        polygon_files = sorted(
            f for f in new_files
            if f.endswith('.xml') and not f.endswith('.layers.xml')
        )

        if len(polygon_files) == 1:
            fname = polygon_files[0]
            fpath = os.path.join(self._polygon_sets_dir, fname)
            self._auto_populate_fields(fname, fpath)
        elif len(polygon_files) > 1:
            for fname in polygon_files:
                fpath = os.path.join(self._polygon_sets_dir, fname)
                name = self._parse_polygon_set_name(fpath)
                new_set = PolygonSetDef(
                    name=name,
                    source_type=PolygonSourceType.FILE,
                    file_source=FileSource(
                        folder="polygonSet",
                        filename=fname,
                        polygon_type=PolygonType.SPLINE_POLYGON
                    )
                )
                self._library.add_polygon_set(new_set)

            manifest_files = [f for f in new_files if f.endswith('.layers.xml')]
            if manifest_files:
                manifest_fname = manifest_files[0]
                manifest_fpath = os.path.join(self._polygon_sets_dir, manifest_fname)
                overall_name = self._parse_layers_manifest_name(manifest_fpath)
                if not overall_name:
                    overall_name = manifest_fname.replace('.layers.xml', '')
                bundle_set = PolygonSetDef(
                    name=f"{overall_name} (bundle)",
                    source_type=PolygonSourceType.FILE,
                    file_source=FileSource(
                        folder="polygonSet",
                        filename=manifest_fname,
                        polygon_type=PolygonType.SPLINE_POLYGON
                    )
                )
                self._library.add_polygon_set(bundle_set)

            self._refresh_list()
            self._refresh_file_list()
            self.modified.emit()
        else:
            self._refresh_file_list()

    def _import(self) -> None:
        if not self._polygon_sets_dir or not os.path.isdir(self._polygon_sets_dir):
            QMessageBox.warning(self, "No Project", "Please save the project first.")
            return
        default_dir = os.path.expanduser("~/.loom_projects/")
        if not os.path.isdir(default_dir):
            default_dir = os.path.expanduser("~")
        filepath, _ = QFileDialog.getOpenFileName(
            self, "Import Polygon Set", default_dir, "XML Files (*.xml);;All Files (*)")
        if not filepath:
            return
        filename = os.path.basename(filepath)
        dest_path = os.path.join(self._polygon_sets_dir, filename)
        if os.path.exists(dest_path) and os.path.abspath(filepath) != os.path.abspath(dest_path):
            result = QMessageBox.question(
                self, "File Exists",
                f"'{filename}' already exists. Overwrite?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
            if result != QMessageBox.StandardButton.Yes:
                return
        try:
            shutil.copy2(filepath, dest_path)
            self._strip_xml_headers(dest_path)
            self._auto_populate_fields(filename, dest_path)
        except Exception as e:
            QMessageBox.critical(self, "Import Failed", f"Could not import '{filename}':\n{e}")

    def _edit_in_bezier(self) -> None:
        if not self._polygon_sets_dir or not os.path.isdir(self._polygon_sets_dir):
            QMessageBox.warning(self, "No Project", "Please save the project first.")
            return
        if self._current_set is None:
            QMessageBox.warning(self, "No Selection", "Please select a polygon set first.")
            return
        if self._current_set.source_type != PolygonSourceType.FILE:
            return
        if not self._current_set.file_source or not self._current_set.file_source.filename:
            QMessageBox.warning(self, "No Filename", "The selected polygon set has no filename.")
            return
        full_path = os.path.join(self._polygon_sets_dir, self._current_set.file_source.filename)
        if not os.path.isfile(full_path):
            QMessageBox.warning(self, "File Not Found", f"File not found:\n{full_path}")
            return
        if self._bezier_process is not None and \
                self._bezier_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.information(self, "Bezier Running", "Bezier is already running.")
            return

        self._edit_file_path = full_path
        self._pre_edit_topology = self._count_topology(full_path)
        filename = self._current_set.file_source.filename
        affected = self._sprites_with_morph_targets_for(filename)
        if affected:
            QMessageBox.warning(
                self, "Morph Target Warning",
                "This polygon set is used as the base shape for sprites with morph targets:\n"
                + "\n".join(f"  \u2022 {s}" for s in affected)
                + "\n\nEditing it may break the morph chains if polygon or vertex count changes."
            )

        if full_path.endswith('.layers.xml'):
            self._add_xml_headers_for_bundle_layers(full_path)
            self._add_xml_headers_layerset(full_path)
        else:
            self._add_xml_headers(full_path)

        self._bezier_process = QProcess(self)
        self._bezier_process.finished.connect(self._on_edit_bezier_finished)
        self._bezier_process.start(PYTHON, [
            BEZIER_PY, "--save-dir", self._polygon_sets_dir,
            "--load", full_path, "--polygon-select"
        ])

    def _on_edit_bezier_finished(self, exit_code, exit_status) -> None:
        if hasattr(self, '_edit_file_path') and os.path.isfile(self._edit_file_path):
            if self._edit_file_path.endswith('.layers.xml'):
                if self._polygon_sets_dir and os.path.isdir(self._polygon_sets_dir):
                    for fname in os.listdir(self._polygon_sets_dir):
                        if fname.endswith('.xml'):
                            fpath = os.path.join(self._polygon_sets_dir, fname)
                            if os.path.isfile(fpath):
                                self._strip_xml_headers(fpath)
            else:
                self._strip_xml_headers(self._edit_file_path)

        if self._edit_file_path and self._pre_edit_topology is not None:
            post_topo = self._count_topology(self._edit_file_path)
            if post_topo and post_topo != self._pre_edit_topology:
                filename = os.path.basename(self._edit_file_path)
                affected = self._sprites_with_morph_targets_for(filename)
                if affected:
                    QMessageBox.warning(
                        self, "Topology Changed",
                        f"The polygon/vertex count of '{filename}' changed:\n"
                        f"  Before: {self._pre_edit_topology[0]} polygons, "
                        f"{self._pre_edit_topology[1]} vertices\n"
                        f"  After:  {post_topo[0]} polygons, {post_topo[1]} vertices\n\n"
                        "The following sprites have morph targets that may now be broken:\n"
                        + "\n".join(f"  \u2022 {s}" for s in affected)
                    )
        self._pre_edit_topology = None
        self._edit_file_path = ""
        self._refresh_file_list()
        self._update_preview()

    # ── Convenience panel ─────────────────────────────────────────────────────

    def _create_convenience_panel(self) -> QWidget:
        container = QWidget()
        outer = QVBoxLayout(container)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(4)

        row1 = QHBoxLayout()
        row1.setSpacing(4)

        sub_group = QGroupBox("Subdivision")
        self._conv_sub_group = sub_group
        sub_layout = QVBoxLayout(sub_group)
        sub_layout.setContentsMargins(4, 4, 4, 4)
        make_sub_btn = QPushButton("Make Subdivision Set")
        make_sub_btn.clicked.connect(self._on_conv_make_subdivision_set)
        sub_layout.addWidget(make_sub_btn)
        sub_layout.addStretch()
        row1.addWidget(sub_group)

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
        self.conv_mode_combo.setCurrentIndex(2)
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
        groups = (self._conv_sub_group, self._conv_sprite_group, self._conv_render_group)
        if any(g is None for g in groups):
            return
        root = self._convenience_root()
        if not root:
            for g in groups:
                g.setStyleSheet("")
            return

        sub_done = bool(self._subdivision_collection and any(
            ps.name == f"{root}_Subdivide"
            for ps in getattr(self._subdivision_collection, 'params_sets', [])))

        geo_set_name = self._current_set.name if self._current_set else ""
        sprite_done = bool(self._sprite_library and geo_set_name and any(
            any(getattr(sp, 'geo_polygon_set_name', '') == geo_set_name
                for sp in ss.sprites)
            for ss in getattr(self._sprite_library, 'sprite_sets', [])))

        renderer_name = f"{root}_renderer"
        render_done = bool(self._renderer_library and any(
            any(r.name == renderer_name for r in rs.renderers)
            for rs in getattr(self._renderer_library, 'renderer_sets', [])))

        gs = self._CONV_GREEN_BORDER
        self._conv_sub_group.setStyleSheet(gs if sub_done else "")
        self._conv_sprite_group.setStyleSheet(gs if sprite_done else "")
        self._conv_render_group.setStyleSheet(gs if render_done else "")

    def _convenience_root(self) -> str:
        f = self.filename_combo.currentText() if hasattr(self, 'filename_combo') else ""
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
            QMessageBox.warning(self, "No File", "Select a polygon file first.")
            return
        if self._subdivision_collection is None:
            QMessageBox.warning(self, "No Subdivision Collection",
                                "Subdivision collection not available.")
            return
        set_name = f"{root}_Subdivide"
        if self._subdivision_collection.get_params_set(set_name):
            QMessageBox.warning(self, "Duplicate",
                                f"Subdivision set '{set_name}' already exists.")
            return
        ps = SubdivisionParamsSet(name=set_name)
        ps.add_params(SubdivisionParams(name="A",
                                        subdivision_type=SubdivisionType.QUAD,
                                        enabled=True))
        self._subdivision_collection.add_params_set(ps)
        self.subdivisionChanged.emit()
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
            QMessageBox.warning(self, "No File", "Select a polygon file first.")
            return
        set_name = self.conv_sprite_set_combo.currentText()
        if not set_name or self._sprite_library is None:
            QMessageBox.warning(self, "No Sprite Set",
                                "Select or create a sprite set first.")
            return
        sprite_set = next(
            (s for s in self._sprite_library.sprite_sets if s.name == set_name), None)
        if sprite_set is None:
            return
        count = len(sprite_set.sprites) + 1
        name = f"{set_name}_{count:03d}"
        while any(s.name == name for s in sprite_set.sprites):
            count += 1
            name = f"{set_name}_{count:03d}"
        geo_polygon_set_name = self._current_set.name if self._current_set else ""
        sub_set_name = ""
        if self._subdivision_collection:
            candidate = f"{root}_Subdivide"
            if self._subdivision_collection.get_params_set(candidate):
                sub_set_name = candidate
        renderer_set_name = self.conv_renderer_set_combo.currentText() or "DefaultSet"
        sprite_set.add(SpriteDef(
            name=name,
            geo_source_type=GeoSourceType.POLYGON_SET,
            geo_polygon_set_name=geo_polygon_set_name,
            geo_subdivision_params_set_name=sub_set_name,
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
            QMessageBox.warning(self, "No Renderer Library",
                                "Renderer library not available.")
            return
        if any(rs.name == name for rs in self._renderer_library.renderer_sets):
            QMessageBox.warning(self, "Duplicate",
                                f"Renderer set '{name}' already exists.")
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
            QMessageBox.warning(self, "No File", "Select a polygon file first.")
            return
        rs_name = self.conv_renderer_set_combo.currentText()
        if not rs_name or self._renderer_library is None:
            QMessageBox.warning(self, "No Renderer Set",
                                "Select or create a renderer set first.")
            return
        rs = next(
            (r for r in self._renderer_library.renderer_sets if r.name == rs_name), None)
        if rs is None:
            return
        name = f"{root}_renderer"
        if any(r.name == name for r in rs.renderers):
            QMessageBox.warning(self, "Duplicate",
                f"Renderer '{name}' already exists in '{rs_name}'.")
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
