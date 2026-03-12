"""
Brush file management widget — lists available brush PNGs with thumbnails.
"""
import os
from typing import Optional
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton,
    QListWidget, QListWidgetItem, QFileDialog, QMessageBox,
    QDialog, QSizePolicy
)
from PyQt6.QtCore import Qt, pyqtSignal, QSize
from PyQt6.QtGui import QPixmap, QIcon, QImage
from .brush_editor import BrushEditorWidget


class BrushLibraryWidget(QWidget):
    """Grid/list of available brushes with thumbnails and management buttons."""

    brushSelected = pyqtSignal(str)  # emits filename when a brush is selected

    def __init__(self, parent=None):
        super().__init__(parent)
        self._brushes_dir = ""

        layout = QVBoxLayout(self)

        layout.addWidget(QLabel("Available Brushes:"))

        self.brush_list = QListWidget()
        self.brush_list.setIconSize(QSize(32, 32))
        self.brush_list.setViewMode(QListWidget.ViewMode.ListMode)
        self.brush_list.itemClicked.connect(self._on_item_clicked)
        layout.addWidget(self.brush_list)

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

    def set_brushes_dir(self, path: str) -> None:
        """Set the brushes directory and refresh the list."""
        self._brushes_dir = path
        self.refresh()

    def refresh(self) -> None:
        """Reload the brush list from the directory."""
        self.brush_list.clear()
        if not self._brushes_dir or not os.path.isdir(self._brushes_dir):
            return

        for filename in sorted(os.listdir(self._brushes_dir)):
            if filename.lower().endswith(".png"):
                filepath = os.path.join(self._brushes_dir, filename)
                item = QListWidgetItem(filename)
                # Load thumbnail
                pixmap = QPixmap(filepath)
                if not pixmap.isNull():
                    icon = QIcon(pixmap.scaled(
                        32, 32, Qt.AspectRatioMode.KeepAspectRatio,
                        Qt.TransformationMode.SmoothTransformation
                    ))
                    item.setIcon(icon)
                self.brush_list.addItem(item)

    def get_brush_names(self) -> list:
        """Return list of all brush filenames."""
        names = []
        for i in range(self.brush_list.count()):
            names.append(self.brush_list.item(i).text())
        return names

    def _on_item_clicked(self, item: QListWidgetItem) -> None:
        self.brushSelected.emit(item.text())

    def _on_import(self) -> None:
        """Import external PNG files into the brushes directory."""
        if not self._brushes_dir:
            QMessageBox.warning(self, "No Project", "Set a project directory first.")
            return

        os.makedirs(self._brushes_dir, exist_ok=True)
        paths, _ = QFileDialog.getOpenFileNames(
            self, "Import Brush Images", "", "PNG Files (*.png)"
        )
        for path in paths:
            import shutil
            dest = os.path.join(self._brushes_dir, os.path.basename(path))
            if not os.path.exists(dest):
                shutil.copy2(path, dest)

        if paths:
            self.refresh()

    def _on_create(self) -> None:
        """Open brush editor dialog to create a new brush."""
        if not self._brushes_dir:
            QMessageBox.warning(self, "No Project", "Set a project directory first.")
            return

        dialog = QDialog(self)
        dialog.setWindowTitle("Create Brush")
        dialog.setMinimumSize(500, 600)
        dlg_layout = QVBoxLayout(dialog)

        editor = BrushEditorWidget(self._brushes_dir)
        editor.brushSaved.connect(lambda name: (self.refresh(), dialog.accept()))
        dlg_layout.addWidget(editor)

        dialog.exec()

    def _on_edit(self) -> None:
        """Open brush editor for the selected brush."""
        current = self.brush_list.currentItem()
        if current is None:
            return
        if not self._brushes_dir:
            return

        filepath = os.path.join(self._brushes_dir, current.text())
        if not os.path.exists(filepath):
            return

        dialog = QDialog(self)
        dialog.setWindowTitle(f"Edit Brush: {current.text()}")
        dialog.setMinimumSize(500, 600)
        dlg_layout = QVBoxLayout(dialog)

        editor = BrushEditorWidget(self._brushes_dir)
        editor.canvas.load_image(filepath)
        editor.brushSaved.connect(lambda name: (self.refresh(), dialog.accept()))
        dlg_layout.addWidget(editor)

        dialog.exec()

    def _on_delete(self) -> None:
        """Delete the selected brush file."""
        current = self.brush_list.currentItem()
        if current is None:
            return
        if not self._brushes_dir:
            return

        filepath = os.path.join(self._brushes_dir, current.text())
        reply = QMessageBox.question(
            self, "Delete Brush",
            f"Delete '{current.text()}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if reply == QMessageBox.StandardButton.Yes:
            if os.path.exists(filepath):
                os.remove(filepath)
            self.refresh()
