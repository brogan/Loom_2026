"""
Bezier Python — main entry point.
CLI: python main.py --save-dir <dir> [--load <file>] [--name <name>]
     [--point-select] [--polygon-select] [--open-curve-select]
     [--point-mode] [--oval-mode] [--freehand-mode]
"""
import sys
import os
import argparse

# Ensure bezier_py/ is on the path when launched as a script
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PySide6.QtWidgets import QApplication
from ui.bezier_app import BezierApp


def main() -> None:
    parser = argparse.ArgumentParser(description="Bezier Python curve editor")
    parser.add_argument("--save-dir", required=True, help="Directory to write output XML files")
    parser.add_argument("--load", default=None, dest="load_path", help="XML file to load on startup")
    parser.add_argument("--name", default=None, help="Initial shape name")
    parser.add_argument("--point-select",      action="store_true", dest="point_select",
                        help="Start in point-selection mode (selects bezier handles)")
    parser.add_argument("--polygon-select",    action="store_true", dest="polygon_select",
                        help="Start in polygon-selection mode")
    parser.add_argument("--open-curve-select", action="store_true", dest="open_curve_select",
                        help="Start in open-curve-selection mode")
    parser.add_argument("--point-mode",        action="store_true", dest="point_mode",
                        help="Start in discrete point-placement mode")
    parser.add_argument("--oval-mode",         action="store_true", dest="oval_mode",
                        help="Start in oval creation mode")
    parser.add_argument("--freehand-mode",     action="store_true", dest="freehand_mode",
                        help="Start in freehand draw mode")
    args = parser.parse_args()

    app = QApplication(sys.argv)
    app.setApplicationName("Bezier")

    window = BezierApp(
        save_dir=os.path.expanduser(args.save_dir),
        load_path=args.load_path,
        name=args.name,
        point_select=args.point_select,
        polygon_select=args.polygon_select,
        open_curve_select=args.open_curve_select,
        point_mode=args.point_mode,
        oval_mode=args.oval_mode,
        freehand_mode=args.freehand_mode,
    )
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
