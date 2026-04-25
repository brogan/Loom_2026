"""
Global configuration tab for the parameter editor.
Provides UI for editing global_config.xml settings.
Quality/Scale/Animating/DrawBgOnce have been moved to the Run tab.
"""
import os
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QTextEdit, QSpinBox, QCheckBox, QComboBox, QScrollArea, QLabel,
    QPushButton, QTabWidget, QRadioButton, QButtonGroup
)
from PySide6.QtCore import Signal, Qt
from models.global_config import GlobalConfig
from models.rendering import Color
from .widgets.color_picker import ColorPickerWidget


class GlobalTab(QWidget):
    """Tab widget for editing global project configuration."""

    modified = Signal()
    background_image_browse_requested = Signal()
    projects_dir_changed = Signal(str)
    engine_changed = Signal(str)   # emits "scala" or "swift"

    def __init__(self, parent=None):
        super().__init__(parent)
        self._config = GlobalConfig.default()
        self._updating = False
        self._background_image_path: str = ""
        self._projects_dir: str = os.path.expanduser("~/.loom_projects")

        self._setup_ui()

    def _setup_ui(self):
        """Set up the UI layout."""
        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)

        inner_tabs = QTabWidget()
        main_layout.addWidget(inner_tabs)

        # ── Project tab (default) ─────────────────────────────────────
        project_scroll = QScrollArea()
        project_scroll.setWidgetResizable(True)
        project_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        project_content = QWidget()
        project_scroll.setWidget(project_content)
        layout = QVBoxLayout(project_content)
        layout.setSpacing(16)
        inner_tabs.addTab(project_scroll, "Project")

        # ── 3D && Serial tab ──────────────────────────────────────────
        three_d_scroll = QScrollArea()
        three_d_scroll.setWidgetResizable(True)
        three_d_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        three_d_content = QWidget()
        three_d_scroll.setWidget(three_d_content)
        three_d_layout = QVBoxLayout(three_d_content)
        three_d_layout.setSpacing(16)
        inner_tabs.addTab(three_d_scroll, "3D && Serial")

        # Project Info Group
        project_group = QGroupBox("Project")
        project_layout = QFormLayout(project_group)

        self.name_edit = QLineEdit()
        self.name_edit.textChanged.connect(self._on_modified)
        project_layout.addRow("Name:", self.name_edit)

        self.note_edit = QTextEdit()
        self.note_edit.setFixedHeight(80)
        self.note_edit.setPlaceholderText("Project notes...")
        self.note_edit.textChanged.connect(self._on_modified)
        project_layout.addRow("Note:", self.note_edit)

        layout.addWidget(project_group)

        # Project Directory Group (app-level, not saved in project XML)
        projects_dir_group = QGroupBox("Project Directory")
        projects_dir_layout = QFormLayout(projects_dir_group)

        dir_row = QHBoxLayout()
        self._projects_dir_label = QLabel(self._projects_dir)
        self._projects_dir_label.setWordWrap(True)
        dir_row.addWidget(self._projects_dir_label, stretch=1)
        change_dir_btn = QPushButton("Change...")
        change_dir_btn.clicked.connect(self._on_change_projects_dir)
        dir_row.addWidget(change_dir_btn)
        projects_dir_layout.addRow("Directory:", dir_row)

        layout.addWidget(projects_dir_group)

        # Loom Engine Group
        engine_group = QGroupBox("Loom Engine")
        engine_layout = QHBoxLayout(engine_group)

        self._engine_btn_group = QButtonGroup(self)
        self._scala_radio = QRadioButton("Scala")
        self._swift_radio = QRadioButton("Swift")
        self._scala_radio.setChecked(True)
        self._engine_btn_group.addButton(self._scala_radio, 0)
        self._engine_btn_group.addButton(self._swift_radio, 1)
        engine_layout.addWidget(self._scala_radio)
        engine_layout.addWidget(self._swift_radio)
        engine_layout.addStretch()
        self._engine_btn_group.idToggled.connect(self._on_engine_toggled)

        layout.addWidget(engine_group)

        # Canvas Group
        canvas_group = QGroupBox("Canvas")
        canvas_layout = QFormLayout(canvas_group)

        size_layout = QHBoxLayout()
        self.width_spin = QSpinBox()
        self.width_spin.setRange(1, 16384)
        self.width_spin.valueChanged.connect(self._on_modified)
        size_layout.addWidget(QLabel("Width:"))
        size_layout.addWidget(self.width_spin)

        self.height_spin = QSpinBox()
        self.height_spin.setRange(1, 16384)
        self.height_spin.valueChanged.connect(self._on_modified)
        size_layout.addWidget(QLabel("Height:"))
        size_layout.addWidget(self.height_spin)
        size_layout.addStretch()

        canvas_layout.addRow("Dimensions:", size_layout)

        layout.addWidget(canvas_group)

        # Display Group
        display_group = QGroupBox("Display")
        display_layout = QFormLayout(display_group)

        self.fullscreen_check = QCheckBox()
        self.fullscreen_check.stateChanged.connect(self._on_modified)
        display_layout.addRow("Fullscreen:", self.fullscreen_check)

        # Colors
        self.border_color = ColorPickerWidget(show_alpha=True)
        self.border_color.colorChanged.connect(self._on_modified)
        display_layout.addRow("Border Color:", self.border_color)

        self.background_color = ColorPickerWidget(show_alpha=True)
        self.background_color.colorChanged.connect(self._on_modified)
        display_layout.addRow("Background Color:", self.background_color)

        self.overlay_color = ColorPickerWidget(show_alpha=True)
        self.overlay_color.colorChanged.connect(self._on_modified)
        display_layout.addRow("Overlay Color:", self.overlay_color)

        # Background image row
        bg_img_row = QHBoxLayout()
        self._bg_image_label = QLabel("None")
        self._bg_image_label.setStyleSheet("color: grey; font-style: italic;")
        bg_img_row.addWidget(self._bg_image_label, stretch=1)
        bg_img_browse_btn = QPushButton("Background Image...")
        bg_img_browse_btn.clicked.connect(self.background_image_browse_requested)
        bg_img_row.addWidget(bg_img_browse_btn)
        display_layout.addRow("Background Image:", bg_img_row)

        self._output_size_label = QLabel("")
        self._output_size_label.setStyleSheet("color: grey;")
        display_layout.addRow("Output size:", self._output_size_label)

        layout.addWidget(display_group)
        layout.addStretch()

        # 3D Settings Group  (lives in the "3D & Serial" tab)
        three_d_group = QGroupBox("3D Settings (not implemented)")
        three_d_form = QFormLayout(three_d_group)

        self.three_d_check = QCheckBox()
        self.three_d_check.stateChanged.connect(self._on_modified)
        three_d_form.addRow("Enable 3D:", self.three_d_check)

        self.camera_angle_spin = QSpinBox()
        self.camera_angle_spin.setRange(1, 180)
        self.camera_angle_spin.valueChanged.connect(self._on_modified)
        three_d_form.addRow("Camera View Angle:", self.camera_angle_spin)

        three_d_layout.addWidget(three_d_group)

        # Serial Group (Legacy)
        serial_group = QGroupBox("Serial Communication (Legacy)")
        serial_layout = QFormLayout(serial_group)

        self.serial_check = QCheckBox()
        self.serial_check.stateChanged.connect(self._on_modified)
        serial_layout.addRow("Enable Serial:", self.serial_check)

        self.port_edit = QLineEdit()
        self.port_edit.textChanged.connect(self._on_modified)
        serial_layout.addRow("Port:", self.port_edit)

        self.mode_combo = QComboBox()
        self.mode_combo.addItems(["bytes", "text"])
        self.mode_combo.currentTextChanged.connect(self._on_modified)
        serial_layout.addRow("Mode:", self.mode_combo)

        self.quantity_spin = QSpinBox()
        self.quantity_spin.setRange(1, 256)
        self.quantity_spin.valueChanged.connect(self._on_modified)
        serial_layout.addRow("Quantity:", self.quantity_spin)

        three_d_layout.addWidget(serial_group)
        three_d_layout.addStretch()

    def _on_engine_toggled(self, btn_id: int, checked: bool):
        if checked:
            engine = "swift" if btn_id == 1 else "scala"
            self.engine_changed.emit(engine)

    def _on_modified(self):
        """Handle any value change."""
        if self._updating:
            return
        self.modified.emit()

    def _on_change_projects_dir(self):
        from PySide6.QtWidgets import QFileDialog
        dir_path = QFileDialog.getExistingDirectory(
            self, "Select Projects Directory", self._projects_dir
        )
        if dir_path:
            self._projects_dir = dir_path
            self._projects_dir_label.setText(dir_path)
            self.projects_dir_changed.emit(dir_path)

    # --- Background image public API ---

    def set_background_image_path(self, path: str) -> None:
        self._background_image_path = path
        if path:
            self._bg_image_label.setText(os.path.basename(path))
            self._bg_image_label.setStyleSheet("color: black; font-style: normal;")
        else:
            self._bg_image_label.setText("None")
            self._bg_image_label.setStyleSheet("color: grey; font-style: italic;")
        self._on_modified()

    def update_output_size_hint(self, w: int, h: int) -> None:
        if w > 0 and h > 0:
            self._output_size_label.setText(f"{w} × {h} px")
        else:
            self._output_size_label.setText("")

    # --- Engine selection public API ---

    def get_selected_engine(self) -> str:
        """Return 'scala' or 'swift'."""
        return "swift" if self._swift_radio.isChecked() else "scala"

    def set_selected_engine(self, engine: str) -> None:
        """Set the engine radio button without emitting engine_changed."""
        self._engine_btn_group.blockSignals(True)
        if engine == "swift":
            self._swift_radio.setChecked(True)
        else:
            self._scala_radio.setChecked(True)
        self._engine_btn_group.blockSignals(False)

    # --- Projects dir public API ---

    def set_projects_dir(self, path: str) -> None:
        self._projects_dir = path
        self._projects_dir_label.setText(path)

    def get_projects_dir(self) -> str:
        return self._projects_dir

    # --- Config get/set ---

    def get_config(self) -> GlobalConfig:
        """Get the current configuration from the UI.
        Note: quality_multiple, scale_image, animating, draw_background_once
        are NOT read here — they live in RunTab. MainWindow patches them in
        via _get_full_global_config() before saving.
        """
        return GlobalConfig(
            name=self.name_edit.text(),
            note=self.note_edit.toPlainText(),
            width=self.width_spin.value(),
            height=self.height_spin.value(),
            # These 5 keep their dataclass defaults; MainWindow patches real values in
            quality_multiple=1,
            scale_image=False,
            animating=False,
            draw_background_once=True,
            subdividing=True,
            fullscreen=self.fullscreen_check.isChecked(),
            border_color=self.border_color.get_color(),
            background_color=self.background_color.get_color(),
            overlay_color=self.overlay_color.get_color(),
            background_image_path=self._background_image_path,
            three_d=self.three_d_check.isChecked(),
            camera_view_angle=self.camera_angle_spin.value(),
            serial=self.serial_check.isChecked(),
            port=self.port_edit.text(),
            mode=self.mode_combo.currentText(),
            quantity=self.quantity_spin.value()
        )

    def set_config(self, config: GlobalConfig) -> None:
        """Set the UI to display the given configuration."""
        self._updating = True
        try:
            self._config = config.copy()

            self.name_edit.setText(config.name)
            self.note_edit.setPlainText(config.note)
            self.width_spin.setValue(config.width)
            self.height_spin.setValue(config.height)
            # quality_multiple / scale_image / animating / draw_bg_once
            # are set on RunTab by MainWindow — not here
            self.fullscreen_check.setChecked(config.fullscreen)
            self.border_color.set_color(config.border_color)
            self.background_color.set_color(config.background_color)
            self.overlay_color.set_color(config.overlay_color)
            # Background image
            self._background_image_path = config.background_image_path
            if config.background_image_path:
                self._bg_image_label.setText(os.path.basename(config.background_image_path))
                self._bg_image_label.setStyleSheet("color: black; font-style: normal;")
            else:
                self._bg_image_label.setText("None")
                self._bg_image_label.setStyleSheet("color: grey; font-style: italic;")
            self.three_d_check.setChecked(config.three_d)
            self.camera_angle_spin.setValue(config.camera_view_angle)
            # subdividing is set on SubdivisionTab by MainWindow — not here
            self.serial_check.setChecked(config.serial)
            self.port_edit.setText(config.port)
            self.mode_combo.setCurrentText(config.mode)
            self.quantity_spin.setValue(config.quantity)
        finally:
            self._updating = False

    def create_default_config(self) -> GlobalConfig:
        """Create a default configuration."""
        return GlobalConfig.default()
