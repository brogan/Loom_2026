"""
PySide6 pixel editor for creating/editing greyscale brush images.
Brushes are small PNGs (typically 16x16 to 64x64) used as stamps
in the BRUSHED renderer mode.
"""
import os
import math
from typing import Optional
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QSlider,
    QSpinBox, QComboBox, QPushButton, QFileDialog, QGroupBox,
    QSizePolicy
)
from PySide6.QtCore import Qt, Signal, QPoint, QRect
from PySide6.QtGui import (
    QImage, QPainter, QColor, QPen, QPixmap, QMouseEvent
)


class BrushCanvas(QWidget):
    """Zoomable pixel grid for painting greyscale brush images."""

    modified = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._image: Optional[QImage] = None
        self._zoom = 8  # pixels per cell
        self._paint_value = 255  # greyscale value to paint with
        self._brush_size = 1  # 1, 3, or 5 pixel brush
        self._painting = False
        self.setMinimumSize(200, 200)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        self.new_image(32, 32)

    def new_image(self, width: int, height: int) -> None:
        """Create a new blank (black) image."""
        self._image = QImage(width, height, QImage.Format.Format_Grayscale8)
        self._image.fill(QColor(0, 0, 0))
        self.update()
        self.modified.emit()

    def load_image(self, path: str) -> bool:
        """Load an image from file."""
        img = QImage(path)
        if img.isNull():
            return False
        self._image = img.convertToFormat(QImage.Format.Format_Grayscale8)
        self.update()
        return True

    def save_image(self, path: str) -> bool:
        """Save image to file as PNG."""
        if self._image is None:
            return False
        return self._image.save(path, "PNG")

    def get_image(self) -> Optional[QImage]:
        return self._image

    def set_paint_value(self, value: int) -> None:
        self._paint_value = max(0, min(255, value))

    def set_brush_size(self, size: int) -> None:
        self._brush_size = size

    def set_zoom(self, zoom: int) -> None:
        self._zoom = max(2, min(32, zoom))
        self.update()

    def _pixel_at(self, pos: QPoint) -> Optional[QPoint]:
        """Convert widget position to image pixel coordinates."""
        if self._image is None:
            return None
        px = pos.x() // self._zoom
        py = pos.y() // self._zoom
        if 0 <= px < self._image.width() and 0 <= py < self._image.height():
            return QPoint(px, py)
        return None

    def _paint_at(self, pixel: QPoint) -> None:
        """Paint at the given pixel with current brush size."""
        if self._image is None:
            return
        half = self._brush_size // 2
        color = QColor(self._paint_value, self._paint_value, self._paint_value)
        for dy in range(-half, half + 1):
            for dx in range(-half, half + 1):
                px = pixel.x() + dx
                py = pixel.y() + dy
                if 0 <= px < self._image.width() and 0 <= py < self._image.height():
                    self._image.setPixelColor(px, py, color)
        self.update()

    def mousePressEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            self._painting = True
            pixel = self._pixel_at(event.pos())
            if pixel:
                self._paint_at(pixel)

    def mouseMoveEvent(self, event: QMouseEvent) -> None:
        if self._painting:
            pixel = self._pixel_at(event.pos())
            if pixel:
                self._paint_at(pixel)

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            self._painting = False
            self.modified.emit()

    def paintEvent(self, event) -> None:
        if self._image is None:
            return
        painter = QPainter(self)
        w = self._image.width()
        h = self._image.height()

        # Draw pixels
        for y in range(h):
            for x in range(w):
                grey = self._image.pixelColor(x, y).red()
                painter.fillRect(
                    x * self._zoom, y * self._zoom,
                    self._zoom, self._zoom,
                    QColor(grey, grey, grey)
                )

        # Draw grid
        painter.setPen(QPen(QColor(60, 60, 60), 1))
        for x in range(w + 1):
            painter.drawLine(x * self._zoom, 0, x * self._zoom, h * self._zoom)
        for y in range(h + 1):
            painter.drawLine(0, y * self._zoom, w * self._zoom, y * self._zoom)

        painter.end()

    def generate_circle(self, soft: bool = False) -> None:
        """Generate a circular brush preset."""
        if self._image is None:
            return
        w = self._image.width()
        h = self._image.height()
        cx = w / 2.0
        cy = h / 2.0
        radius = min(cx, cy) - 1

        for y in range(h):
            for x in range(w):
                dist = math.sqrt((x - cx + 0.5) ** 2 + (y - cy + 0.5) ** 2)
                if soft:
                    val = max(0, int(255 * (1.0 - dist / radius)))
                else:
                    val = 255 if dist <= radius else 0
                self._image.setPixelColor(x, y, QColor(val, val, val))

        self.update()
        self.modified.emit()

    def generate_scatter(self) -> None:
        """Generate a scattered dots preset."""
        import random
        if self._image is None:
            return
        w = self._image.width()
        h = self._image.height()
        self._image.fill(QColor(0, 0, 0))

        num_dots = max(3, (w * h) // 8)
        cx = w / 2.0
        cy = h / 2.0
        radius = min(cx, cy) - 1

        for _ in range(num_dots):
            x = random.randint(0, w - 1)
            y = random.randint(0, h - 1)
            dist = math.sqrt((x - cx + 0.5) ** 2 + (y - cy + 0.5) ** 2)
            if dist <= radius:
                val = random.randint(100, 255)
                self._image.setPixelColor(x, y, QColor(val, val, val))

        self.update()
        self.modified.emit()


class BrushEditorWidget(QWidget):
    """Legacy stub — brush_library.py now opens BrushEditorWindow directly."""

    brushSaved = Signal(str)

    def __init__(self, brushes_dir: str = "", parent=None):
        super().__init__(parent)
