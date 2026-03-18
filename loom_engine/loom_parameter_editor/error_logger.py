"""
Persistent error logger for the Loom Parameter Editor.

Installs a sys.excepthook that:
  1. Writes a timestamped traceback to  logs/errors.log  (rotates at 1 MB)
  2. Also mirrors the traceback to stderr (so /tmp/loom_editor.log still works)

Call install() once at startup, before creating the QApplication.
"""
import sys
import os
import traceback
import logging
from logging.handlers import RotatingFileHandler
from datetime import datetime
from typing import Optional

_LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
_LOG_FILE = os.path.join(_LOG_DIR, "errors.log")

_logger: Optional[logging.Logger] = None


def _get_logger() -> logging.Logger:
    global _logger
    if _logger is not None:
        return _logger

    os.makedirs(_LOG_DIR, exist_ok=True)

    _logger = logging.getLogger("loom.errors")
    _logger.setLevel(logging.DEBUG)

    # Rotating file: max 1 MB, keep 3 backups
    fh = RotatingFileHandler(_LOG_FILE, maxBytes=1_000_000, backupCount=3,
                              encoding="utf-8")
    fh.setFormatter(logging.Formatter("%(asctime)s  %(message)s",
                                       datefmt="%Y-%m-%d %H:%M:%S"))
    _logger.addHandler(fh)

    # Also mirror to stderr
    sh = logging.StreamHandler(sys.stderr)
    sh.setFormatter(logging.Formatter("%(message)s"))
    _logger.addHandler(sh)

    return _logger


def log_exception(exc_type, exc_value, exc_tb):
    """Write a formatted exception to the log file + stderr."""
    lines = traceback.format_exception(exc_type, exc_value, exc_tb)
    text = "".join(lines).rstrip()
    _get_logger().error("\n--- Unhandled exception ---\n%s\n---", text)


def log(msg: str, *args):
    """Write an informational message to the log."""
    _get_logger().info(msg, *args)


def install():
    """
    Install the global exception hook and log a startup marker.
    Call once at the top of main(), before any other imports that
    could trigger PyQt6 widget construction.
    """
    original_hook = sys.excepthook

    def _hook(exc_type, exc_value, exc_tb):
        log_exception(exc_type, exc_value, exc_tb)
        original_hook(exc_type, exc_value, exc_tb)

    sys.excepthook = _hook
    _get_logger().info("=" * 60)
    _get_logger().info("Loom Parameter Editor started  (%s)", datetime.now().isoformat(timespec="seconds"))
    _get_logger().info("Log file: %s", _LOG_FILE)
