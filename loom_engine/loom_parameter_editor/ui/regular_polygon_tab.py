"""
Regular Polygon Set configuration tab.
Shows only REGULAR-source polygon sets (mathematically defined, no Bezier file).
"""
from __future__ import annotations
import os
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QComboBox, QTreeWidget,
    QTreeWidgetItem, QPushButton, QSplitter, QLabel,
    QMessageBox, QInputDialog, QSizePolicy
)
from PySide6.QtCore import Signal, Qt
from models.polygon_config import (
    PolygonSourceType, RegularPolygonParams, PolygonSetDef, PolygonSetLibrary
)
from models.sprite_config import SpriteDef, SpriteSet, GeoSourceType
from models.subdivision_config import SubdivisionParams, SubdivisionParamsSet, SubdivisionType
from models.rendering import Renderer, RendererSet
from models.constants import RenderMode
from file_io.regular_polygon_io import RegularPolygonIO
from ui.regular_polygon_dialog import RegularPolygonDialog
from ui.polygon_tab import PolygonPreviewWidget, _COL_SEL_GREEN


class RegularPolygonTab(QWidget):
    """Tab for REGULAR-source polygon sets (mathematically defined polygons)."""

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
        self._regular_polygons_dir: str = ""
        self._sprite_library = None
        self._subdivision_collection = None
        self._renderer_library = None
        self._conv_sub_group = None
        self._conv_sprite_group = None
        self._conv_render_group = None

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

        left_layout.addWidget(QLabel("Regular Polygon Sets:"))

        self.set_list = QTreeWidget()
        self.set_list.setHeaderLabels(["Name"])
        self.set_list.setRootIsDecorated(False)
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

        group = QGroupBox("Regular Polygon Set")
        form = QFormLayout(group)

        self.name_edit = QLineEdit()
        self.name_edit.setReadOnly(True)
        form.addRow("Name:", self.name_edit)

        act_row = QHBoxLayout()
        self.create_btn = QPushButton("Create")
        self.create_btn.clicked.connect(self._create)
        act_row.addWidget(self.create_btn)

        self.edit_btn = QPushButton("Edit in Dialog…")
        self.edit_btn.clicked.connect(self._edit)
        act_row.addWidget(self.edit_btn)
        act_row.addStretch()
        form.addRow("", act_row)

        right_layout.addWidget(group)

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

    def set_regular_polygons_directory(self, directory: str) -> None:
        self._regular_polygons_dir = directory

    def set_sprite_library(self, library) -> None:
        self._sprite_library = library
        self._refresh_convenience_combos()

    def set_subdivision_collection(self, coll) -> None:
        self._subdivision_collection = coll
        self._refresh_convenience_combos()

    def set_renderer_library(self, lib) -> None:
        self._renderer_library = lib
        self._refresh_convenience_combos()

    # ── List management ───────────────────────────────────────────────────────

    def _refresh_list(self):
        current_name = self._current_set.name if self._current_set else None
        self.set_list.clear()
        restore_item = None
        for ps in self._library.polygon_sets:
            if ps.source_type != PolygonSourceType.REGULAR:
                continue
            item = QTreeWidgetItem([ps.name])
            item.setData(0, Qt.ItemDataRole.UserRole, ps)
            self.set_list.addTopLevelItem(item)
            if ps.name == current_name:
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
            self.preview_widget.clear()
        finally:
            self._updating = False

    def _load_set_to_editor(self, ps: PolygonSetDef):
        self._updating = True
        try:
            self.name_edit.setText(ps.name)
            if ps.regular_params:
                self.preview_widget.load_regular_polygon(ps.regular_params)
            else:
                self.preview_widget.clear()
        finally:
            self._updating = False

    # ── CRUD ─────────────────────────────────────────────────────────────────

    def _delete_set(self) -> None:
        ps = self._current_set
        if ps is None:
            return
        result = QMessageBox.question(
            self, "Delete", f"Delete '{ps.name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result != QMessageBox.StandardButton.Yes:
            return
        self._library.remove_polygon_set(ps.name)
        self._current_set = None
        self._refresh_list()
        self._clear_editor()
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
        self._library.add_polygon_set(new_ps)
        self._refresh_list()
        self.modified.emit()

    def _rename_set(self) -> None:
        ps = self._current_set
        if ps is None:
            return
        new_name, ok = QInputDialog.getText(
            self, "Rename", "New name:", text=ps.name)
        if not ok or not new_name.strip():
            return
        new_name = new_name.strip()
        if any(p.name == new_name for p in self._library.polygon_sets if p is not ps):
            QMessageBox.warning(self, "Duplicate",
                f"A set named '{new_name}' already exists.")
            return
        ps.name = new_name
        self._refresh_list()
        self.modified.emit()

    # ── Create / Edit ─────────────────────────────────────────────────────────

    def _create(self) -> None:
        if not self._regular_polygons_dir:
            QMessageBox.warning(self, "No Project", "Please save the project first.")
            return
        dialog = RegularPolygonDialog(self)
        if dialog.exec() != RegularPolygonDialog.DialogCode.Accepted:
            return
        name, params = dialog.get_result()
        if not name:
            QMessageBox.warning(self, "No Name", "Name cannot be empty.")
            return
        if self._library.get_polygon_set(name):
            QMessageBox.warning(self, "Duplicate Name",
                f"A polygon set named '{name}' already exists.")
            return
        os.makedirs(self._regular_polygons_dir, exist_ok=True)
        filepath = os.path.join(self._regular_polygons_dir, f"{name}.xml")
        RegularPolygonIO.save(name, params, filepath)
        new_set = PolygonSetDef(
            name=name,
            source_type=PolygonSourceType.REGULAR,
            regular_params=params
        )
        self._library.add_polygon_set(new_set)
        self._refresh_list()
        last = self.set_list.topLevelItem(self.set_list.topLevelItemCount() - 1)
        if last:
            self.set_list.setCurrentItem(last)
        self.modified.emit()

    def _edit(self) -> None:
        if self._current_set is None or \
                self._current_set.source_type != PolygonSourceType.REGULAR:
            return
        if self._current_set.regular_params is None:
            return
        dialog = RegularPolygonDialog(
            self, self._current_set.name, self._current_set.regular_params)
        if dialog.exec() != RegularPolygonDialog.DialogCode.Accepted:
            return
        name, params = dialog.get_result()
        if not name:
            return
        self._current_set.name = name
        self._current_set.regular_params = params
        self._load_set_to_editor(self._current_set)
        current_item = self.set_list.currentItem()
        if current_item:
            current_item.setText(0, name)
        if self._regular_polygons_dir:
            os.makedirs(self._regular_polygons_dir, exist_ok=True)
            filepath = os.path.join(self._regular_polygons_dir, f"{name}.xml")
            RegularPolygonIO.save(name, params, filepath)
        self.modified.emit()

    # ── Change tracking ───────────────────────────────────────────────────────

    def _on_modified(self):
        if self._updating:
            return
        self.modified.emit()

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
        root = self._current_set.name if self._current_set else ""
        if not root:
            for g in groups:
                g.setStyleSheet("")
            return

        sub_done = bool(self._subdivision_collection and any(
            ps.name == f"{root}_Subdivide"
            for ps in getattr(self._subdivision_collection, 'params_sets', [])))

        geo_set_name = root
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
        root = self._current_set.name if self._current_set else ""
        if not root:
            QMessageBox.warning(self, "No Selection", "Select a polygon set first.")
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
        root = self._current_set.name if self._current_set else ""
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
        if self._current_set is None:
            QMessageBox.warning(self, "No Selection", "Select a polygon set first.")
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
        geo_regular_sides = (self._current_set.regular_params.total_points
                             if self._current_set.regular_params else 4)
        renderer_set_name = self.conv_renderer_set_combo.currentText() or "DefaultSet"
        sprite_set.add(SpriteDef(
            name=name,
            geo_source_type=GeoSourceType.REGULAR_POLYGON,
            geo_regular_polygon_sides=geo_regular_sides,
            renderer_set_name=renderer_set_name,
        ))
        self.newSpriteCreated.emit(set_name, name)
        self.spriteLibraryChanged.emit()
        self.modified.emit()
        self._update_convenience_borders()

    def _on_conv_add_renderer_set(self) -> None:
        root = self._current_set.name if self._current_set else ""
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
        root = self._current_set.name if self._current_set else ""
        if not root:
            QMessageBox.warning(self, "No Selection", "Select a polygon set first.")
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
        self.rendererLibraryChanged.emit()
        self.modified.emit()
        self._update_convenience_borders()
