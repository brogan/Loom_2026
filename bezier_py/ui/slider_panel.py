"""
SliderPanel — Scale and Rotate sliders with radio-button axis selectors.
Mirrors Java CubicCurvePanel's Transform section.
Sliders reset to 0 on mouse-release; origPos committed at that point.
"""
from __future__ import annotations

from PySide6.QtWidgets import (
    QWidget, QHBoxLayout, QVBoxLayout, QSlider, QLabel,
    QRadioButton, QButtonGroup, QFrame, QSizePolicy,
)
from PySide6.QtCore import Qt

from canvas.draw_panel import (
    ROTATE_LOCAL, ROTATE_COMMON, ROTATE_ABSOLUTE,
    SCALE_XY, SCALE_X, SCALE_Y,
)


class SliderPanel(QWidget):
    """
    Two sliders (Scale, Rotate) + radio-button axis groups.
    Mirrors Java CubicCurvePanel Transform panel.
    """

    def __init__(self, bezier_widget, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._bw = bezier_widget
        self._setup_ui()

    def _setup_ui(self) -> None:
        layout = QHBoxLayout(self)
        layout.setContentsMargins(6, 4, 6, 10)
        layout.setSpacing(0)

        # 280px spacer matches the LayerPanel width, aligning the divider with the
        # horizontal midpoint of the canvas drawn area.
        layout.addSpacing(280)

        scale_grp  = self._make_scale_group()
        rotate_grp = self._make_rotate_group()
        scale_grp.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        rotate_grp.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)

        layout.addWidget(scale_grp, stretch=1)
        layout.addSpacing(6)
        layout.addWidget(_vsep())
        layout.addSpacing(6)
        layout.addWidget(rotate_grp, stretch=1)

    def _make_scale_group(self) -> QFrame:
        grp = QFrame()
        grp.setFrameShape(QFrame.Shape.Box)
        grp.setFrameShadow(QFrame.Shadow.Raised)
        vbox = QVBoxLayout(grp)
        vbox.setContentsMargins(6, 4, 6, 6)
        vbox.setSpacing(4)

        lbl = QLabel("Scale")
        lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)

        self._scale_slider = _slider()
        self._scale_slider.valueChanged.connect(self._on_scale_changed)
        self._scale_slider.sliderReleased.connect(self._on_slider_released)

        # Radio buttons for axis
        self._scale_xy_rb = QRadioButton("XY")
        self._scale_x_rb  = QRadioButton("X")
        self._scale_y_rb  = QRadioButton("Y")
        self._scale_xy_rb.setChecked(True)

        self._scale_axis_group = QButtonGroup(self)
        self._scale_axis_group.addButton(self._scale_xy_rb, SCALE_XY)
        self._scale_axis_group.addButton(self._scale_x_rb,  SCALE_X)
        self._scale_axis_group.addButton(self._scale_y_rb,  SCALE_Y)
        self._scale_axis_group.idClicked.connect(lambda _: self._on_scale_changed())

        radio_row = QHBoxLayout()
        radio_row.setContentsMargins(0, 0, 0, 0)
        radio_row.setSpacing(6)
        radio_row.addWidget(self._scale_xy_rb)
        radio_row.addWidget(self._scale_x_rb)
        radio_row.addWidget(self._scale_y_rb)

        vbox.addWidget(lbl)
        vbox.addWidget(self._scale_slider)
        vbox.addLayout(radio_row)
        return grp

    def _make_rotate_group(self) -> QFrame:
        grp = QFrame()
        grp.setFrameShape(QFrame.Shape.Box)
        grp.setFrameShadow(QFrame.Shadow.Raised)
        vbox = QVBoxLayout(grp)
        vbox.setContentsMargins(6, 4, 6, 6)
        vbox.setSpacing(4)

        lbl = QLabel("Rotate")
        lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)

        self._rotate_slider = _slider()
        self._rotate_slider.valueChanged.connect(self._on_rotate_changed)
        self._rotate_slider.sliderReleased.connect(self._on_slider_released)

        # Radio buttons for pivot
        self._rot_local_rb    = QRadioButton("Local")
        self._rot_common_rb   = QRadioButton("Common")
        self._rot_absolute_rb = QRadioButton("Absolute")
        self._rot_local_rb.setChecked(True)

        self._rotate_axis_group = QButtonGroup(self)
        self._rotate_axis_group.addButton(self._rot_local_rb,    ROTATE_LOCAL)
        self._rotate_axis_group.addButton(self._rot_common_rb,   ROTATE_COMMON)
        self._rotate_axis_group.addButton(self._rot_absolute_rb, ROTATE_ABSOLUTE)

        radio_row = QHBoxLayout()
        radio_row.setContentsMargins(0, 0, 0, 0)
        radio_row.setSpacing(6)
        radio_row.addWidget(self._rot_local_rb)
        radio_row.addWidget(self._rot_common_rb)
        radio_row.addWidget(self._rot_absolute_rb)

        vbox.addWidget(lbl)
        vbox.addWidget(self._rotate_slider)
        vbox.addLayout(radio_row)
        return grp

    # ── signal handlers ───────────────────────────────────────────────────────

    def _on_scale_changed(self, _value=None) -> None:
        axis = self._scale_axis_group.checkedId()
        if axis < 0:
            axis = SCALE_XY
        self._bw.scale_xy(float(self._scale_slider.value()), axis)

    def _on_rotate_changed(self, value: int) -> None:
        axis = self._rotate_axis_group.checkedId()
        if axis < 0:
            axis = ROTATE_LOCAL
        degrees = value * 1.8  # [-100,100] → [-180°,180°]
        self._bw.rotate(degrees, axis)

    def _on_slider_released(self) -> None:
        """Commit all origPos, reset sliders to 0."""
        self._bw.set_orig_pos_of_all_points_to_pos()
        for sl in (self._scale_slider, self._rotate_slider):
            sl.blockSignals(True)
            sl.setValue(0)
            sl.blockSignals(False)


# ── helpers ───────────────────────────────────────────────────────────────────

def _slider() -> QSlider:
    sl = QSlider(Qt.Orientation.Horizontal)
    sl.setRange(-100, 100)
    sl.setValue(0)
    sl.setMinimumWidth(120)   # expands with group; no fixed width
    sl.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
    return sl


def _vsep() -> QFrame:
    line = QFrame()
    line.setFrameShape(QFrame.Shape.VLine)
    line.setFrameShadow(QFrame.Shadow.Sunken)
    return line
