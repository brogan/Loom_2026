#!/usr/bin/env python3
"""
Loom Parameter Editor - Main entry point.

A PySide6 application for configuring renderer parameters for the Loom Scala application.
Creates XML configuration files that can be loaded by the Scala application.
"""
import sys
import os

# Add the package directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import error_logger
error_logger.install()

from PySide6.QtWidgets import QApplication
from PySide6.QtCore import Qt
from ui.main_window import MainWindow


def main():
    # Enable high DPI scaling
    QApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )

    app = QApplication(sys.argv)
    app.setApplicationName("Loom Parameter Editor")
    app.setOrganizationName("Loom")

    # Set application style
    app.setStyle("Fusion")

    window = MainWindow()
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
