"""
Stencil file management widget — lists available stencil PNGs with thumbnails.
"""
import os
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton,
    QListWidget, QListWidgetItem, QFileDialog, QMessageBox,
)
from PyQt6.QtCore import Qt, pyqtSignal, QSize
from PyQt6.QtGui import QPixmap, QIcon


class StencilLibraryWidget(QWidget):
    """Grid/list of available stencils with thumbnails and management buttons."""

    stencilSelected = pyqtSignal(str)  # emits filename when a stencil is selected

    def __init__(self, parent=None):
        super().__init__(parent)
        self._stencils_dir = ""
        self._editor_window = None

        layout = QVBoxLayout(self)

        layout.addWidget(QLabel("Available Stencils:"))

        self.stencil_list = QListWidget()
        self.stencil_list.setIconSize(QSize(32, 32))
        self.stencil_list.setViewMode(QListWidget.ViewMode.ListMode)
        self.stencil_list.itemClicked.connect(self._on_item_clicked)
        layout.addWidget(self.stencil_list)

        # Buttons
        btn_row = QHBoxLayout()
        refresh_btn = QPushButton("Refresh")
        refresh_btn.clicked.connect(self.refresh)
        btn_row.addWidget(refresh_btn)

        import_btn = QPushButton("Import...")
        import_btn.clicked.connect(self._on_import)
        btn_row.addWidget(import_btn)

        create_btn = QPushButton("Create New...")
        create_btn.clicked.connect(self._on_create)
        btn_row.addWidget(create_btn)

        edit_btn = QPushButton("Edit...")
        edit_btn.clicked.connect(self._on_edit)
        btn_row.addWidget(edit_btn)

        delete_btn = QPushButton("Delete")
        delete_btn.clicked.connect(self._on_delete)
        btn_row.addWidget(delete_btn)

        btn_row.addStretch()
        layout.addLayout(btn_row)

    def set_stencils_dir(self, path: str) -> None:
        """Set the stencils directory and refresh the list."""
        self._stencils_dir = path
        self.refresh()

    def refresh(self) -> None:
        """Reload the stencil list from the directory."""
        self.stencil_list.clear()
        if not self._stencils_dir or not os.path.isdir(self._stencils_dir):
            return

        for filename in sorted(os.listdir(self._stencils_dir)):
            if filename.lower().endswith(".png"):
                filepath = os.path.join(self._stencils_dir, filename)
                item = QListWidgetItem(filename)
                # Load thumbnail
                pixmap = QPixmap(filepath)
                if not pixmap.isNull():
                    icon = QIcon(pixmap.scaled(
                        32, 32, Qt.AspectRatioMode.KeepAspectRatio,
                        Qt.TransformationMode.SmoothTransformation
                    ))
                    item.setIcon(icon)
                self.stencil_list.addItem(item)

    def get_stencil_names(self) -> list:
        """Return list of all stencil filenames."""
        names = []
        for i in range(self.stencil_list.count()):
            names.append(self.stencil_list.item(i).text())
        return names

    def _on_item_clicked(self, item: QListWidgetItem) -> None:
        self.stencilSelected.emit(item.text())

    def _on_import(self) -> None:
        """Import external PNG files into the stencils directory."""
        if not self._stencils_dir:
            QMessageBox.warning(self, "No Project", "Set a project directory first.")
            return

        os.makedirs(self._stencils_dir, exist_ok=True)
        paths, _ = QFileDialog.getOpenFileNames(
            self, "Import Stencil Images", "", "PNG Files (*.png)"
        )
        for path in paths:
            import shutil
            dest = os.path.join(self._stencils_dir, os.path.basename(path))
            if not os.path.exists(dest):
                shutil.copy2(path, dest)

        if paths:
            self.refresh()

    def _open_editor(self, initial_file=None):
        from .stencil_editor_window import StencilEditorWindow
        if self._editor_window and self._editor_window.isVisible():
            self._editor_window.raise_()
            self._editor_window.activateWindow()
            if initial_file:
                self._editor_window.open_file(initial_file)
            return
        self._editor_window = StencilEditorWindow(
            self._stencils_dir, initial_file=initial_file, parent=None)
        self._editor_window.stencilSaved.connect(lambda _: self.refresh())
        self._editor_window.show()

    def _on_create(self) -> None:
        """Open stencil editor window to create a new stencil."""
        if not self._stencils_dir:
            QMessageBox.warning(self, "No Project", "Set a project directory first.")
            return
        self._open_editor(initial_file=None)

    def _on_edit(self) -> None:
        """Open stencil editor window for the selected stencil."""
        current = self.stencil_list.currentItem()
        if not current or not self._stencils_dir:
            return
        filepath = os.path.join(self._stencils_dir, current.text())
        if not os.path.exists(filepath):
            return
        self._open_editor(initial_file=filepath)

    def _on_delete(self) -> None:
        """Delete the selected stencil file."""
        current = self.stencil_list.currentItem()
        if current is None:
            return
        if not self._stencils_dir:
            return

        filepath = os.path.join(self._stencils_dir, current.text())
        reply = QMessageBox.question(
            self, "Delete Stencil",
            f"Delete '{current.text()}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if reply == QMessageBox.StandardButton.Yes:
            if os.path.exists(filepath):
                os.remove(filepath)
                # Also remove sidecar if it exists
                meta = filepath + ".meta.json"
                if os.path.exists(meta):
                    os.remove(meta)
            self.refresh()
