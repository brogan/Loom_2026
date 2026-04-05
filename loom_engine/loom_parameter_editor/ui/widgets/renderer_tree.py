"""
Tree view widget for Library > Set > Renderer hierarchy.
"""
from typing import Optional, Tuple
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QTreeWidget, QTreeWidgetItem,
    QPushButton, QInputDialog, QMessageBox
)
from PySide6.QtCore import Signal, Qt
from models.rendering import RendererSetLibrary, RendererSet, Renderer


class RendererTreeWidget(QWidget):
    """A tree widget for navigating and managing the renderer hierarchy."""

    # Signal emitted when selection changes: (set_name, renderer_name)
    # renderer_name is None if a set is selected
    selectionChanged = Signal(str, object)

    # Signal emitted when library is modified
    libraryModified = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._library: Optional[RendererSetLibrary] = None
        self._updating = False
        self._checking = False

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        # Tree widget
        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["Sel", "Name", "Enabled", "PC", "SC", "FC"])
        self.tree.setColumnWidth(0, 35)
        self.tree.setColumnWidth(1, 150)
        self.tree.setColumnWidth(2, 50)
        self.tree.setColumnWidth(3, 35)
        self.tree.setColumnWidth(4, 35)
        self.tree.setColumnWidth(5, 35)
        header = self.tree.header()
        header.setToolTip("")
        self.tree.headerItem().setToolTip(3, "PC = Point Change")
        self.tree.headerItem().setToolTip(4, "SC = Stroke Change")
        self.tree.headerItem().setToolTip(5, "FC = Fill Change")
        self.tree.itemSelectionChanged.connect(self._on_selection_changed)
        self.tree.itemChanged.connect(self._on_item_check_changed)
        self.tree.setStyleSheet("QTreeWidget::indicator { width: 13px; height: 13px; }")
        layout.addWidget(self.tree)

        # Set buttons row 1: add/remove
        set_buttons = QHBoxLayout()
        self.add_set_btn = QPushButton("+ Set")
        self.add_set_btn.clicked.connect(self._add_set)
        self.remove_set_btn = QPushButton("- Set")
        self.remove_set_btn.clicked.connect(self._remove_set)
        set_buttons.addWidget(self.add_set_btn)
        set_buttons.addWidget(self.remove_set_btn)
        layout.addLayout(set_buttons)

        # Renderer buttons row 1: add/remove
        renderer_buttons = QHBoxLayout()
        self.add_renderer_btn = QPushButton("+ Renderer")
        self.add_renderer_btn.clicked.connect(self._add_renderer)
        self.remove_renderer_btn = QPushButton("- Renderer")
        self.remove_renderer_btn.clicked.connect(self._remove_renderer)
        renderer_buttons.addWidget(self.add_renderer_btn)
        renderer_buttons.addWidget(self.remove_renderer_btn)
        layout.addLayout(renderer_buttons)

        # Shared rename/duplicate buttons
        rename_dup_buttons = QHBoxLayout()
        self.rename_btn = QPushButton("Rename")
        self.rename_btn.clicked.connect(self._rename_selected)
        self.duplicate_btn = QPushButton("Duplicate")
        self.duplicate_btn.clicked.connect(self._duplicate_selected)
        rename_dup_buttons.addWidget(self.rename_btn)
        rename_dup_buttons.addWidget(self.duplicate_btn)
        layout.addLayout(rename_dup_buttons)

        # Reorder buttons
        reorder_buttons = QHBoxLayout()
        self.move_up_btn = QPushButton("\u25b2")
        self.move_up_btn.setFixedWidth(40)
        self.move_up_btn.clicked.connect(self._move_up)
        self.move_down_btn = QPushButton("\u25bc")
        self.move_down_btn.setFixedWidth(40)
        self.move_down_btn.clicked.connect(self._move_down)
        reorder_buttons.addWidget(self.move_up_btn)
        reorder_buttons.addWidget(self.move_down_btn)
        reorder_buttons.addStretch()
        layout.addLayout(reorder_buttons)

        # Delete Selected button
        del_sel_layout = QHBoxLayout()
        self.delete_selected_btn = QPushButton("Delete Selected")
        self.delete_selected_btn.clicked.connect(self._delete_selected)
        del_sel_layout.addWidget(self.delete_selected_btn)
        del_sel_layout.addStretch()
        layout.addLayout(del_sel_layout)

        self._update_buttons()

    def set_library(self, library: RendererSetLibrary) -> None:
        """Set the library to display."""
        self._library = library
        self._refresh_tree()

    def get_library(self) -> Optional[RendererSetLibrary]:
        return self._library

    def _refresh_tree(self) -> None:
        """Rebuild the tree from the library."""
        self._updating = True
        self.tree.clear()

        self._checking = True
        if self._library:
            for rs in self._library.renderer_sets:
                set_item = QTreeWidgetItem(["", rs.name, "", "", "", ""])
                set_item.setData(0, Qt.ItemDataRole.UserRole, ("set", rs.name))
                set_item.setFlags(set_item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
                set_item.setCheckState(0, Qt.CheckState.Unchecked)
                self.tree.addTopLevelItem(set_item)

                for r in rs.renderers:
                    renderer_item = QTreeWidgetItem(["", r.name, "", "", "", ""])
                    renderer_item.setData(0, Qt.ItemDataRole.UserRole, ("renderer", rs.name, r.name))
                    renderer_item.setFlags(renderer_item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
                    renderer_item.setCheckState(0, Qt.CheckState.Unchecked)
                    renderer_item.setCheckState(2, Qt.CheckState.Checked if r.enabled else Qt.CheckState.Unchecked)
                    sc_enabled = r.stroke_color_change.enabled or r.stroke_width_change.enabled
                    renderer_item.setCheckState(3, Qt.CheckState.Checked if r.point_size_change.enabled else Qt.CheckState.Unchecked)
                    renderer_item.setCheckState(4, Qt.CheckState.Checked if sc_enabled else Qt.CheckState.Unchecked)
                    renderer_item.setCheckState(5, Qt.CheckState.Checked if r.fill_color_change.enabled else Qt.CheckState.Unchecked)
                    set_item.addChild(renderer_item)

                set_item.setExpanded(True)
        self._checking = False

        self._updating = False
        self._update_buttons()

    def _on_selection_changed(self) -> None:
        if self._updating:
            return

        items = self.tree.selectedItems()
        if items:
            data = items[0].data(0, Qt.ItemDataRole.UserRole)
            if data[0] == "set":
                self.selectionChanged.emit(data[1], None)
            else:  # renderer
                self.selectionChanged.emit(data[1], data[2])

        self._update_buttons()

    def _update_buttons(self) -> None:
        """Enable/disable buttons based on selection."""
        has_library = self._library is not None
        items = self.tree.selectedItems()
        has_selection = len(items) > 0
        selected_type = self._get_selected_type()
        is_set_selected = selected_type == "set"
        is_renderer_selected = selected_type == "renderer"

        self.add_set_btn.setEnabled(has_library)
        self.remove_set_btn.setEnabled(has_selection and is_set_selected)
        self.add_renderer_btn.setEnabled(has_selection)
        self.remove_renderer_btn.setEnabled(has_selection and is_renderer_selected)
        self.rename_btn.setEnabled(has_selection)
        self.duplicate_btn.setEnabled(has_selection)
        self.move_up_btn.setEnabled(has_selection)
        self.move_down_btn.setEnabled(has_selection)

    def _get_selected_type(self) -> Optional[str]:
        items = self.tree.selectedItems()
        if items:
            data = items[0].data(0, Qt.ItemDataRole.UserRole)
            return data[0]
        return None

    def _get_selection(self) -> Tuple[Optional[str], Optional[str]]:
        """Get (set_name, renderer_name) for current selection."""
        items = self.tree.selectedItems()
        if items:
            data = items[0].data(0, Qt.ItemDataRole.UserRole)
            if data[0] == "set":
                return data[1], None
            else:
                return data[1], data[2]
        return None, None

    def _add_set(self) -> None:
        if not self._library:
            return

        name, ok = QInputDialog.getText(self, "Add Renderer Set", "Set name:")
        if ok and name:
            if self._library.get_renderer_set(name):
                QMessageBox.warning(self, "Error", f"A set named '{name}' already exists.")
                return

            new_set = RendererSet(name=name)
            self._library.add_renderer_set(new_set)
            self._refresh_tree()
            self.libraryModified.emit()

    def _remove_set(self) -> None:
        set_name, _ = self._get_selection()
        if not set_name or not self._library:
            return

        result = QMessageBox.question(
            self, "Remove Set",
            f"Remove renderer set '{set_name}' and all its renderers?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result == QMessageBox.StandardButton.Yes:
            self._library.remove_renderer_set(set_name)
            self._refresh_tree()
            self.libraryModified.emit()

    def _add_renderer(self) -> None:
        set_name, _ = self._get_selection()
        if not set_name or not self._library:
            return

        rs = self._library.get_renderer_set(set_name)
        if not rs:
            return

        name, ok = QInputDialog.getText(self, "Add Renderer", "Renderer name:")
        if ok and name:
            if rs.get_renderer(name):
                QMessageBox.warning(self, "Error", f"A renderer named '{name}' already exists in this set.")
                return

            new_renderer = Renderer(name=name)
            rs.add_renderer(new_renderer)
            self._refresh_tree()
            self.libraryModified.emit()

    def _remove_renderer(self) -> None:
        set_name, renderer_name = self._get_selection()
        if not set_name or not renderer_name or not self._library:
            return

        rs = self._library.get_renderer_set(set_name)
        if not rs:
            return

        result = QMessageBox.question(
            self, "Remove Renderer",
            f"Remove renderer '{renderer_name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result == QMessageBox.StandardButton.Yes:
            rs.remove_renderer(renderer_name)
            self._refresh_tree()
            self.libraryModified.emit()

    def _rename_selected(self) -> None:
        set_name, renderer_name = self._get_selection()
        if not set_name or not self._library:
            return
        rs = self._library.get_renderer_set(set_name)
        if not rs:
            return
        if renderer_name is None:
            # Rename the set
            new_name, ok = QInputDialog.getText(
                self, "Rename Renderer Set", "New name:", text=set_name
            )
            if ok and new_name and new_name != set_name:
                if self._library.get_renderer_set(new_name):
                    QMessageBox.warning(self, "Error", f"A set named '{new_name}' already exists.")
                    return
                rs.name = new_name
                self._refresh_tree()
                self.libraryModified.emit()
        else:
            # Rename the renderer
            renderer = rs.get_renderer(renderer_name)
            if not renderer:
                return
            new_name, ok = QInputDialog.getText(
                self, "Rename Renderer", "New name:", text=renderer_name
            )
            if ok and new_name and new_name != renderer_name:
                if rs.get_renderer(new_name):
                    QMessageBox.warning(self, "Error", f"A renderer named '{new_name}' already exists in this set.")
                    return
                if rs.preferred_renderer == renderer_name:
                    rs.preferred_renderer = new_name
                renderer.name = new_name
                self._refresh_tree()
                self.libraryModified.emit()

    def _duplicate_selected(self) -> None:
        set_name, renderer_name = self._get_selection()
        if not set_name or not self._library:
            return
        rs = self._library.get_renderer_set(set_name)
        if not rs:
            return
        if renderer_name is None:
            # Duplicate the set
            base_name = f"{set_name}_copy"
            new_name = base_name
            counter = 1
            while self._library.get_renderer_set(new_name):
                new_name = f"{base_name}_{counter}"
                counter += 1
            new_name, ok = QInputDialog.getText(
                self, "Duplicate Renderer Set", "Name for copy:", text=new_name
            )
            if ok and new_name:
                if self._library.get_renderer_set(new_name):
                    QMessageBox.warning(self, "Error", f"A set named '{new_name}' already exists.")
                    return
                new_set = rs.copy()
                new_set.name = new_name
                self._library.add_renderer_set(new_set)
                self._refresh_tree()
                self.libraryModified.emit()
        else:
            # Duplicate the renderer
            renderer = rs.get_renderer(renderer_name)
            if not renderer:
                return
            base_name = f"{renderer_name}_copy"
            new_name = base_name
            counter = 1
            while rs.get_renderer(new_name):
                new_name = f"{base_name}_{counter}"
                counter += 1
            new_name, ok = QInputDialog.getText(
                self, "Duplicate Renderer", "Name for copy:", text=new_name
            )
            if ok and new_name:
                if rs.get_renderer(new_name):
                    QMessageBox.warning(self, "Error", f"A renderer named '{new_name}' already exists in this set.")
                    return
                new_renderer = renderer.copy()
                new_renderer.name = new_name
                rs.add_renderer(new_renderer)
                self._refresh_tree()
                self.libraryModified.emit()

    def _move_up(self) -> None:
        self._move(-1)

    def _move_down(self) -> None:
        self._move(1)

    def _move(self, direction: int) -> None:
        if not self._library:
            return

        set_name, renderer_name = self._get_selection()
        if not set_name:
            return

        if renderer_name:
            # Moving a renderer within a set
            rs = self._library.get_renderer_set(set_name)
            if rs:
                idx = next((i for i, r in enumerate(rs.renderers) if r.name == renderer_name), -1)
                if idx >= 0:
                    new_idx = idx + direction
                    if 0 <= new_idx < len(rs.renderers):
                        rs.move_renderer(idx, new_idx)
                        self._refresh_tree()
                        self.libraryModified.emit()
        else:
            # Moving a set
            idx = next((i for i, rs in enumerate(self._library.renderer_sets) if rs.name == set_name), -1)
            if idx >= 0:
                new_idx = idx + direction
                if 0 <= new_idx < len(self._library.renderer_sets):
                    self._library.move_renderer_set(idx, new_idx)
                    self._refresh_tree()
                    self.libraryModified.emit()

    def _on_item_check_changed(self, item, column):
        """Handle checkbox toggle."""
        if self._checking:
            return
        if not self._library:
            return
        data = item.data(0, Qt.ItemDataRole.UserRole)
        if data is None or data[0] != "renderer":
            return
        set_name, renderer_name = data[1], data[2]
        rs = self._library.get_renderer_set(set_name)
        if rs is None:
            return
        r = rs.get_renderer(renderer_name)
        if r is None:
            return
        checked = item.checkState(column) == Qt.CheckState.Checked
        if column == 2:  # Enabled
            r.enabled = checked
            self.libraryModified.emit()
        elif column == 3:  # PC — Point Change
            r.point_size_change.enabled = checked
            self.libraryModified.emit()
        elif column == 4:  # SC — Stroke Change
            r.stroke_width_change.enabled = checked
            r.stroke_color_change.enabled = checked
            self.libraryModified.emit()
        elif column == 5:  # FC — Fill Change
            r.fill_color_change.enabled = checked
            self.libraryModified.emit()

    def _delete_selected(self) -> None:
        """Delete all checked renderer items."""
        if not self._library:
            return

        to_delete = []  # list of (set_name, renderer_name) tuples
        for i in range(self.tree.topLevelItemCount()):
            set_item = self.tree.topLevelItem(i)
            for j in range(set_item.childCount()):
                renderer_item = set_item.child(j)
                if renderer_item.checkState(0) == Qt.CheckState.Checked:
                    data = renderer_item.data(0, Qt.ItemDataRole.UserRole)
                    if data and data[0] == "renderer":
                        to_delete.append((data[1], data[2]))

        if not to_delete:
            QMessageBox.information(self, "No Selection", "No items are checked for deletion.")
            return

        result = QMessageBox.question(
            self, "Delete Selected",
            f"Delete {len(to_delete)} checked renderer(s)?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result == QMessageBox.StandardButton.Yes:
            for set_name, renderer_name in to_delete:
                rs = self._library.get_renderer_set(set_name)
                if rs:
                    rs.remove_renderer(renderer_name)
            self._refresh_tree()
            self.libraryModified.emit()

    def update_current_enabled_checkbox(self, enabled: bool) -> None:
        """Update the Enabled column checkbox for the currently selected renderer item."""
        self._checking = True
        items = self.tree.selectedItems()
        if items:
            data = items[0].data(0, Qt.ItemDataRole.UserRole)
            if data and data[0] == "renderer":
                items[0].setCheckState(
                    2, Qt.CheckState.Checked if enabled else Qt.CheckState.Unchecked
                )
        self._checking = False

    def select_renderer(self, set_name: str, renderer_name: Optional[str] = None) -> None:
        """Programmatically select a set or renderer."""
        for i in range(self.tree.topLevelItemCount()):
            set_item = self.tree.topLevelItem(i)
            data = set_item.data(0, Qt.ItemDataRole.UserRole)
            if data[1] == set_name:
                if renderer_name:
                    for j in range(set_item.childCount()):
                        renderer_item = set_item.child(j)
                        rdata = renderer_item.data(0, Qt.ItemDataRole.UserRole)
                        if rdata[2] == renderer_name:
                            self.tree.setCurrentItem(renderer_item)
                            return
                else:
                    self.tree.setCurrentItem(set_item)
                    return
