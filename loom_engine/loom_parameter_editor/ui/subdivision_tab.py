"""
Subdivision configuration tab for the parameter editor.
Provides UI for editing subdivision.xml settings.
"""
import os
import re
import shlex
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QSpinBox, QDoubleSpinBox, QComboBox, QCheckBox,
    QTreeWidget, QTreeWidgetItem, QPushButton, QSplitter, QLabel,
    QScrollArea, QMessageBox, QInputDialog, QDialog, QDialogButtonBox,
    QTabWidget
)
from typing import Optional
from PyQt6.QtCore import pyqtSignal, Qt, QProcess, QProcessEnvironment
from models.subdivision_config import (
    SubdivisionType, VisibilityRule, Vector2D, Range, RangeXY, Transform2D,
    SubdivisionParams, SubdivisionParamsSet, SubdivisionParamsSetCollection
)
from models.transform_config import (
    Range as TRange, ExteriorAnchorsConfig, CentralAnchorsConfig,
    AnchorsLinkedToCentreConfig, OuterControlPointsConfig,
    InnerControlPointsConfig, TransformSetConfig
)


class SubdivisionTab(QWidget):
    """Tab widget for editing subdivision configuration."""

    modified = pyqtSignal()
    subdividing_changed = pyqtSignal(bool)
    polygon_baked = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._collection = SubdivisionParamsSetCollection.default()
        self._current_set: SubdivisionParamsSet = None
        self._current_params: SubdivisionParams = None
        self._updating = False
        self._checking = False
        self._project_dir: str = ""
        self._bake_process = None

        self._setup_ui()
        self._refresh_tree()

    def _setup_ui(self):
        """Set up the UI layout."""
        main_layout = QHBoxLayout(self)

        # Create splitter
        splitter = QSplitter(Qt.Orientation.Horizontal)
        main_layout.addWidget(splitter)

        # Left panel - tree view
        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)

        left_layout.addWidget(QLabel("Subdivision Parameters:"))

        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["Sel", "Name", "Type", "Inset", "PTW", "PTP"])
        self.tree.setColumnWidth(0, 35)
        self.tree.setColumnWidth(1, 150)
        self.tree.setColumnWidth(2, 50)
        self.tree.setColumnWidth(3, 40)
        self.tree.setColumnWidth(4, 40)
        self.tree.setColumnWidth(5, 40)
        self.tree.itemClicked.connect(self._on_item_clicked)
        self.tree.itemChanged.connect(self._on_item_check_changed)
        self.tree.setStyleSheet("QTreeWidget::indicator { width: 13px; height: 13px; }")
        left_layout.addWidget(self.tree)

        # Buttons for sets
        set_btn_layout = QHBoxLayout()
        self.add_set_btn = QPushButton("+ Set")
        self.add_set_btn.clicked.connect(self._add_set)
        set_btn_layout.addWidget(self.add_set_btn)

        self.remove_set_btn = QPushButton("- Set")
        self.remove_set_btn.clicked.connect(self._remove_set)
        set_btn_layout.addWidget(self.remove_set_btn)
        left_layout.addLayout(set_btn_layout)

        # Buttons for params
        params_btn_layout = QHBoxLayout()
        self.add_params_btn = QPushButton("+ Params")
        self.add_params_btn.clicked.connect(self._add_params)
        params_btn_layout.addWidget(self.add_params_btn)

        self.remove_params_btn = QPushButton("- Params")
        self.remove_params_btn.clicked.connect(self._remove_params)
        params_btn_layout.addWidget(self.remove_params_btn)
        left_layout.addLayout(params_btn_layout)

        # Shared rename/duplicate buttons
        rename_dup_layout = QHBoxLayout()
        self.rename_btn = QPushButton("Rename")
        self.rename_btn.clicked.connect(self._rename_selected)
        self.duplicate_btn = QPushButton("Duplicate")
        self.duplicate_btn.clicked.connect(self._duplicate_selected)
        rename_dup_layout.addWidget(self.rename_btn)
        rename_dup_layout.addWidget(self.duplicate_btn)
        left_layout.addLayout(rename_dup_layout)

        # Reorder buttons
        reorder_layout = QHBoxLayout()
        self.move_up_btn = QPushButton("\u25b2")
        self.move_up_btn.setFixedWidth(40)
        self.move_up_btn.clicked.connect(self._move_up)
        self.move_down_btn = QPushButton("\u25bc")
        self.move_down_btn.setFixedWidth(40)
        self.move_down_btn.clicked.connect(self._move_down)
        reorder_layout.addWidget(self.move_up_btn)
        reorder_layout.addWidget(self.move_down_btn)
        self.bake_btn = QPushButton("Bake\u2026")
        self.bake_btn.setToolTip("Run subdivision and save result as a polygon set")
        self.bake_btn.clicked.connect(self._on_bake)
        reorder_layout.addWidget(self.bake_btn)
        reorder_layout.addStretch()
        left_layout.addLayout(reorder_layout)

        # Delete Selected button
        del_sel_layout = QHBoxLayout()
        self.delete_selected_btn = QPushButton("Delete Selected")
        self.delete_selected_btn.clicked.connect(self._delete_selected)
        del_sel_layout.addWidget(self.delete_selected_btn)
        del_sel_layout.addStretch()
        left_layout.addLayout(del_sel_layout)

        splitter.addWidget(left_panel)

        # Right panel - property editor
        right_panel = QWidget()
        right_layout = QVBoxLayout(right_panel)

        # Enable Subdivision toggle — sits above the scroll area (global setting from global_config.xml)
        enable_row = QHBoxLayout()
        enable_row.addStretch()
        enable_row.addWidget(QLabel("Enable Subdivision:"))
        self.subdividing_check = QCheckBox()
        self.subdividing_check.setChecked(True)
        self.subdividing_check.setToolTip("Master on/off switch for subdivision (globalConfig.subdividing)")
        self.subdividing_check.stateChanged.connect(self._on_subdividing_changed)
        enable_row.addWidget(self.subdividing_check)
        right_layout.addLayout(enable_row)

        # Inner tabs for the four parameter groups
        inner_tabs = QTabWidget()
        right_layout.addWidget(inner_tabs)

        def _make_tab(label: str) -> QVBoxLayout:
            sc = QScrollArea()
            sc.setWidgetResizable(True)
            sc.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
            cw = QWidget()
            lo = QVBoxLayout(cw)
            sc.setWidget(cw)
            inner_tabs.addTab(sc, label)
            return lo

        general_layout = _make_tab("General")
        inset_layout   = _make_tab("Inset Transform")
        ptw_layout     = _make_tab("Polygons Transform Whole")
        ptp_layout     = _make_tab("Polygons Transform Points")

        # Name
        name_group = QGroupBox("Subdivision Parameters")
        name_form = QFormLayout(name_group)

        self.name_edit = QLineEdit()
        self.name_edit.textChanged.connect(self._on_name_changed)
        name_form.addRow("Name:", self.name_edit)

        self.enabled_check = QCheckBox()
        self.enabled_check.setChecked(True)
        self.enabled_check.stateChanged.connect(self._on_modified)
        name_form.addRow("Enabled:", self.enabled_check)

        general_layout.addWidget(name_group)

        # Core settings
        core_group = QGroupBox("Core Settings")
        core_form = QFormLayout(core_group)

        self.subdiv_type_combo = QComboBox()
        for st in SubdivisionType:
            self.subdiv_type_combo.addItem(st.name, st)
        self.subdiv_type_combo.currentIndexChanged.connect(self._on_modified)
        core_form.addRow("Subdivision Type:", self.subdiv_type_combo)

        self.visibility_combo = QComboBox()
        for vr in VisibilityRule:
            self.visibility_combo.addItem(vr.name, vr)
        self.visibility_combo.currentIndexChanged.connect(self._on_modified)
        core_form.addRow("Visibility Rule:", self.visibility_combo)

        self.continuous_check = QCheckBox()
        self.continuous_check.stateChanged.connect(self._on_modified)
        core_form.addRow("Continuous:", self.continuous_check)

        general_layout.addWidget(core_group)

        # Line ratios
        ratio_group = QGroupBox("Line Ratios")
        ratio_form = QFormLayout(ratio_group)

        line_layout = QHBoxLayout()
        self.line_ratio_x = QDoubleSpinBox()
        self.line_ratio_x.setRange(0.0, 100.0)
        self.line_ratio_x.setDecimals(1)
        self.line_ratio_x.setSingleStep(1.0)
        self.line_ratio_x.setSuffix("%")
        self.line_ratio_x.valueChanged.connect(self._on_modified)
        line_layout.addWidget(QLabel("X:"))
        line_layout.addWidget(self.line_ratio_x)

        self.line_ratio_y = QDoubleSpinBox()
        self.line_ratio_y.setRange(0.0, 100.0)
        self.line_ratio_y.setDecimals(1)
        self.line_ratio_y.setSingleStep(1.0)
        self.line_ratio_y.setSuffix("%")
        self.line_ratio_y.valueChanged.connect(self._on_modified)
        line_layout.addWidget(QLabel("Y:"))
        line_layout.addWidget(self.line_ratio_y)
        ratio_form.addRow("Line Ratios:", line_layout)

        cp_layout = QHBoxLayout()
        self.cp_ratio_x = QDoubleSpinBox()
        self.cp_ratio_x.setRange(0.0, 100.0)
        self.cp_ratio_x.setDecimals(1)
        self.cp_ratio_x.setSingleStep(1.0)
        self.cp_ratio_x.setSuffix("%")
        self.cp_ratio_x.valueChanged.connect(self._on_modified)
        cp_layout.addWidget(QLabel("X:"))
        cp_layout.addWidget(self.cp_ratio_x)

        self.cp_ratio_y = QDoubleSpinBox()
        self.cp_ratio_y.setRange(0.0, 100.0)
        self.cp_ratio_y.setDecimals(1)
        self.cp_ratio_y.setSingleStep(1.0)
        self.cp_ratio_y.setSuffix("%")
        self.cp_ratio_y.valueChanged.connect(self._on_modified)
        cp_layout.addWidget(QLabel("Y:"))
        cp_layout.addWidget(self.cp_ratio_y)
        ratio_form.addRow("Control Point Ratios:", cp_layout)

        general_layout.addWidget(ratio_group)

        # Randomization
        random_group = QGroupBox("Randomization")
        random_form = QFormLayout(random_group)

        self.ran_middle_check = QCheckBox()
        self.ran_middle_check.stateChanged.connect(self._on_modified)
        random_form.addRow("Random Middle:", self.ran_middle_check)

        self.ran_div_spin = QDoubleSpinBox()
        self.ran_div_spin.setRange(1.0, 1000.0)
        self.ran_div_spin.setDecimals(1)
        self.ran_div_spin.valueChanged.connect(self._on_modified)
        random_form.addRow("Random Divisor:", self.ran_div_spin)

        general_layout.addWidget(random_group)

        # Inset Transform (for echo)
        inset_group = QGroupBox("Inset Transform (Echo)")
        inset_group.setToolTip(
            "Inset transform only applies to ECHO-type subdivision modes:\n"
            "ECHO, ECHO_ABS_CENTER, QUAD_BORD_ECHO, QUAD_BORD_DOUBLE_ECHO,\n"
            "TRI_BORD_B_ECHO, TRI_BORD_C_ECHO.\n"
            "It controls how the inner 'echo' polygon is scaled/translated/rotated\n"
            "relative to the outer polygon."
        )
        inset_form = QFormLayout(inset_group)

        # Translation
        trans_layout = QHBoxLayout()
        self.inset_trans_x = QDoubleSpinBox()
        self.inset_trans_x.setRange(-100.0, 100.0)
        self.inset_trans_x.setDecimals(3)
        self.inset_trans_x.setSingleStep(0.1)
        self.inset_trans_x.valueChanged.connect(self._on_modified)
        trans_layout.addWidget(QLabel("X:"))
        trans_layout.addWidget(self.inset_trans_x)

        self.inset_trans_y = QDoubleSpinBox()
        self.inset_trans_y.setRange(-100.0, 100.0)
        self.inset_trans_y.setDecimals(3)
        self.inset_trans_y.setSingleStep(0.1)
        self.inset_trans_y.valueChanged.connect(self._on_modified)
        trans_layout.addWidget(QLabel("Y:"))
        trans_layout.addWidget(self.inset_trans_y)
        inset_form.addRow("Translation:", trans_layout)

        # Scale (displayed as percentage)
        scale_layout = QHBoxLayout()
        self.inset_scale_x = QDoubleSpinBox()
        self.inset_scale_x.setRange(0.0, 200.0)
        self.inset_scale_x.setDecimals(1)
        self.inset_scale_x.setSingleStep(1.0)
        self.inset_scale_x.setSuffix("%")
        self.inset_scale_x.valueChanged.connect(self._on_modified)
        scale_layout.addWidget(QLabel("X:"))
        scale_layout.addWidget(self.inset_scale_x)

        self.inset_scale_y = QDoubleSpinBox()
        self.inset_scale_y.setRange(0.0, 200.0)
        self.inset_scale_y.setDecimals(1)
        self.inset_scale_y.setSingleStep(1.0)
        self.inset_scale_y.setSuffix("%")
        self.inset_scale_y.valueChanged.connect(self._on_modified)
        scale_layout.addWidget(QLabel("Y:"))
        scale_layout.addWidget(self.inset_scale_y)
        inset_form.addRow("Scale:", scale_layout)

        # Rotation
        self.inset_rotation = QDoubleSpinBox()
        self.inset_rotation.setRange(-360.0, 360.0)
        self.inset_rotation.setDecimals(1)
        self.inset_rotation.setSingleStep(1.0)
        self.inset_rotation.valueChanged.connect(self._on_modified)
        inset_form.addRow("Rotation:", self.inset_rotation)

        inset_layout.addWidget(inset_group)

        # Master transforms switch (gates both polygon and point transforms)
        transforms_master_group = QGroupBox("Transforms")
        transforms_master_form = QFormLayout(transforms_master_group)
        self.polys_transform_check = QCheckBox()
        self.polys_transform_check.setToolTip(
            "Master switch — enables/disables Polygon Transform Whole and Polygon Transform Points.\n"
            "Does NOT affect the Inset Transform (Echo), which has its own enable checkbox.\n"
            "In Scala: if polysTransform is false, neither polygon nor point transforms run."
        )
        self.polys_transform_check.stateChanged.connect(self._on_modified)
        transforms_master_form.addRow("Enable Polygon && Point Transforms:", self.polys_transform_check)

        # Polygon transforms
        transform_group = QGroupBox("Polygon Transforms")
        transform_form = QFormLayout(transform_group)

        self.ptw_probability_spin = QDoubleSpinBox()
        self.ptw_probability_spin.setRange(0.0, 100.0)
        self.ptw_probability_spin.setDecimals(1)
        self.ptw_probability_spin.valueChanged.connect(self._on_modified)
        transform_form.addRow("Probability %:", self.ptw_probability_spin)

        self.ptw_random_trans_check = QCheckBox()
        self.ptw_random_trans_check.stateChanged.connect(self._on_modified)
        transform_form.addRow("Random Translation:", self.ptw_random_trans_check)

        self.ptw_random_scale_check = QCheckBox()
        self.ptw_random_scale_check.stateChanged.connect(self._on_modified)
        transform_form.addRow("Random Scale:", self.ptw_random_scale_check)

        self.ptw_random_rot_check = QCheckBox()
        self.ptw_random_rot_check.stateChanged.connect(self._on_modified)
        transform_form.addRow("Random Rotation:", self.ptw_random_rot_check)

        self.ptw_common_centre_check = QCheckBox()
        self.ptw_common_centre_check.stateChanged.connect(self._on_modified)
        transform_form.addRow("Common Centre:", self.ptw_common_centre_check)

        # Base transform (pTW_transform)
        transform_form.addRow(QLabel("--- Base Transform ---"))

        ptw_trans_layout = QHBoxLayout()
        self.ptw_trans_x = QDoubleSpinBox()
        self.ptw_trans_x.setRange(-10.0, 10.0)
        self.ptw_trans_x.setDecimals(3)
        self.ptw_trans_x.setSingleStep(0.01)
        self.ptw_trans_x.valueChanged.connect(self._on_modified)
        ptw_trans_layout.addWidget(QLabel("X:"))
        ptw_trans_layout.addWidget(self.ptw_trans_x)
        self.ptw_trans_y = QDoubleSpinBox()
        self.ptw_trans_y.setRange(-10.0, 10.0)
        self.ptw_trans_y.setDecimals(3)
        self.ptw_trans_y.setSingleStep(0.01)
        self.ptw_trans_y.valueChanged.connect(self._on_modified)
        ptw_trans_layout.addWidget(QLabel("Y:"))
        ptw_trans_layout.addWidget(self.ptw_trans_y)
        transform_form.addRow("Translation:", ptw_trans_layout)

        ptw_scale_layout = QHBoxLayout()
        self.ptw_scale_x = QDoubleSpinBox()
        self.ptw_scale_x.setRange(-10.0, 10.0)
        self.ptw_scale_x.setDecimals(3)
        self.ptw_scale_x.setSingleStep(0.1)
        self.ptw_scale_x.valueChanged.connect(self._on_modified)
        ptw_scale_layout.addWidget(QLabel("X:"))
        ptw_scale_layout.addWidget(self.ptw_scale_x)
        self.ptw_scale_y = QDoubleSpinBox()
        self.ptw_scale_y.setRange(-10.0, 10.0)
        self.ptw_scale_y.setDecimals(3)
        self.ptw_scale_y.setSingleStep(0.1)
        self.ptw_scale_y.valueChanged.connect(self._on_modified)
        ptw_scale_layout.addWidget(QLabel("Y:"))
        ptw_scale_layout.addWidget(self.ptw_scale_y)
        transform_form.addRow("Scale:", ptw_scale_layout)

        self.ptw_rotation = QDoubleSpinBox()
        self.ptw_rotation.setRange(-360.0, 360.0)
        self.ptw_rotation.setDecimals(1)
        self.ptw_rotation.setSingleStep(1.0)
        self.ptw_rotation.valueChanged.connect(self._on_modified)
        transform_form.addRow("Rotation:", self.ptw_rotation)

        # Random centre divisor
        self.ptw_random_centre_divisor = QDoubleSpinBox()
        self.ptw_random_centre_divisor.setRange(1.0, 1000.0)
        self.ptw_random_centre_divisor.setDecimals(1)
        self.ptw_random_centre_divisor.setSingleStep(1.0)
        self.ptw_random_centre_divisor.setToolTip("Controls per-polygon centre randomness when Common Centre is enabled")
        self.ptw_random_centre_divisor.valueChanged.connect(self._on_modified)
        transform_form.addRow("Random Centre Divisor:", self.ptw_random_centre_divisor)

        # Random translation range
        transform_form.addRow(QLabel("--- Random Ranges ---"))

        ptw_rt_x_layout = QHBoxLayout()
        self.ptw_rt_x_min = QDoubleSpinBox()
        self.ptw_rt_x_min.setRange(-10.0, 10.0)
        self.ptw_rt_x_min.setDecimals(3)
        self.ptw_rt_x_min.setSingleStep(0.01)
        self.ptw_rt_x_min.valueChanged.connect(self._on_modified)
        ptw_rt_x_layout.addWidget(QLabel("Min:"))
        ptw_rt_x_layout.addWidget(self.ptw_rt_x_min)
        self.ptw_rt_x_max = QDoubleSpinBox()
        self.ptw_rt_x_max.setRange(-10.0, 10.0)
        self.ptw_rt_x_max.setDecimals(3)
        self.ptw_rt_x_max.setSingleStep(0.01)
        self.ptw_rt_x_max.valueChanged.connect(self._on_modified)
        ptw_rt_x_layout.addWidget(QLabel("Max:"))
        ptw_rt_x_layout.addWidget(self.ptw_rt_x_max)
        transform_form.addRow("Rand. Trans. X:", ptw_rt_x_layout)

        ptw_rt_y_layout = QHBoxLayout()
        self.ptw_rt_y_min = QDoubleSpinBox()
        self.ptw_rt_y_min.setRange(-10.0, 10.0)
        self.ptw_rt_y_min.setDecimals(3)
        self.ptw_rt_y_min.setSingleStep(0.01)
        self.ptw_rt_y_min.valueChanged.connect(self._on_modified)
        ptw_rt_y_layout.addWidget(QLabel("Min:"))
        ptw_rt_y_layout.addWidget(self.ptw_rt_y_min)
        self.ptw_rt_y_max = QDoubleSpinBox()
        self.ptw_rt_y_max.setRange(-10.0, 10.0)
        self.ptw_rt_y_max.setDecimals(3)
        self.ptw_rt_y_max.setSingleStep(0.01)
        self.ptw_rt_y_max.valueChanged.connect(self._on_modified)
        ptw_rt_y_layout.addWidget(QLabel("Max:"))
        ptw_rt_y_layout.addWidget(self.ptw_rt_y_max)
        transform_form.addRow("Rand. Trans. Y:", ptw_rt_y_layout)

        # Random scale range
        ptw_rs_x_layout = QHBoxLayout()
        self.ptw_rs_x_min = QDoubleSpinBox()
        self.ptw_rs_x_min.setRange(0.0, 10.0)
        self.ptw_rs_x_min.setDecimals(3)
        self.ptw_rs_x_min.setSingleStep(0.1)
        self.ptw_rs_x_min.valueChanged.connect(self._on_modified)
        ptw_rs_x_layout.addWidget(QLabel("Min:"))
        ptw_rs_x_layout.addWidget(self.ptw_rs_x_min)
        self.ptw_rs_x_max = QDoubleSpinBox()
        self.ptw_rs_x_max.setRange(0.0, 10.0)
        self.ptw_rs_x_max.setDecimals(3)
        self.ptw_rs_x_max.setSingleStep(0.1)
        self.ptw_rs_x_max.valueChanged.connect(self._on_modified)
        ptw_rs_x_layout.addWidget(QLabel("Max:"))
        ptw_rs_x_layout.addWidget(self.ptw_rs_x_max)
        transform_form.addRow("Rand. Scale X:", ptw_rs_x_layout)

        ptw_rs_y_layout = QHBoxLayout()
        self.ptw_rs_y_min = QDoubleSpinBox()
        self.ptw_rs_y_min.setRange(0.0, 10.0)
        self.ptw_rs_y_min.setDecimals(3)
        self.ptw_rs_y_min.setSingleStep(0.1)
        self.ptw_rs_y_min.valueChanged.connect(self._on_modified)
        ptw_rs_y_layout.addWidget(QLabel("Min:"))
        ptw_rs_y_layout.addWidget(self.ptw_rs_y_min)
        self.ptw_rs_y_max = QDoubleSpinBox()
        self.ptw_rs_y_max.setRange(0.0, 10.0)
        self.ptw_rs_y_max.setDecimals(3)
        self.ptw_rs_y_max.setSingleStep(0.1)
        self.ptw_rs_y_max.valueChanged.connect(self._on_modified)
        ptw_rs_y_layout.addWidget(QLabel("Max:"))
        ptw_rs_y_layout.addWidget(self.ptw_rs_y_max)
        transform_form.addRow("Rand. Scale Y:", ptw_rs_y_layout)

        # Random rotation range
        ptw_rr_layout = QHBoxLayout()
        self.ptw_rr_min = QDoubleSpinBox()
        self.ptw_rr_min.setRange(-360.0, 360.0)
        self.ptw_rr_min.setDecimals(1)
        self.ptw_rr_min.setSingleStep(1.0)
        self.ptw_rr_min.valueChanged.connect(self._on_modified)
        ptw_rr_layout.addWidget(QLabel("Min:"))
        ptw_rr_layout.addWidget(self.ptw_rr_min)
        self.ptw_rr_max = QDoubleSpinBox()
        self.ptw_rr_max.setRange(-360.0, 360.0)
        self.ptw_rr_max.setDecimals(1)
        self.ptw_rr_max.setSingleStep(1.0)
        self.ptw_rr_max.valueChanged.connect(self._on_modified)
        ptw_rr_layout.addWidget(QLabel("Max:"))
        ptw_rr_layout.addWidget(self.ptw_rr_max)
        transform_form.addRow("Rand. Rotation:", ptw_rr_layout)

        ptw_layout.addWidget(transform_group)

        # Point transforms group
        point_transform_group = QGroupBox("Point Transforms")
        point_transform_form = QFormLayout(point_transform_group)

        self.ptp_probability_spin = QDoubleSpinBox()
        self.ptp_probability_spin.setRange(0.0, 100.0)
        self.ptp_probability_spin.setDecimals(1)
        self.ptp_probability_spin.valueChanged.connect(self._on_modified)
        point_transform_form.addRow("Point Transform Probability %:", self.ptp_probability_spin)

        self.transform_status_label = QLabel("No transforms enabled")
        point_transform_form.addRow("Status:", self.transform_status_label)

        self.edit_transforms_btn = QPushButton("Edit Transforms...")
        self.edit_transforms_btn.clicked.connect(self._edit_transforms)
        point_transform_form.addRow("", self.edit_transforms_btn)

        ptp_layout.addWidget(point_transform_group)

        general_layout.addWidget(transforms_master_group)
        general_layout.addStretch()
        inset_layout.addStretch()
        ptw_layout.addStretch()
        ptp_layout.addStretch()

        splitter.addWidget(right_panel)
        splitter.setSizes([250, 550])

        # Initially disable editor
        self._set_editor_enabled(False)
        self._update_buttons()

    def _on_subdividing_changed(self):
        """Handle the global Enable Subdivision toggle."""
        if not self._updating:
            self.subdividing_changed.emit(self.subdividing_check.isChecked())
            self.modified.emit()

    def get_subdividing(self) -> bool:
        return self.subdividing_check.isChecked()

    def set_subdividing(self, value: bool) -> None:
        self._updating = True
        self.subdividing_check.setChecked(value)
        self._updating = False

    def _set_editor_enabled(self, enabled: bool):
        """Enable or disable the editor widgets."""
        self.name_edit.setEnabled(enabled)
        self.enabled_check.setEnabled(enabled)
        self.subdiv_type_combo.setEnabled(enabled)
        self.visibility_combo.setEnabled(enabled)
        self.continuous_check.setEnabled(enabled)
        self.line_ratio_x.setEnabled(enabled)
        self.line_ratio_y.setEnabled(enabled)
        self.cp_ratio_x.setEnabled(enabled)
        self.cp_ratio_y.setEnabled(enabled)
        self.ran_middle_check.setEnabled(enabled)
        self.ran_div_spin.setEnabled(enabled)
        self.inset_trans_x.setEnabled(enabled)
        self.inset_trans_y.setEnabled(enabled)
        self.inset_scale_x.setEnabled(enabled)
        self.inset_scale_y.setEnabled(enabled)
        self.inset_rotation.setEnabled(enabled)
        self.polys_transform_check.setEnabled(enabled)
        self.ptw_probability_spin.setEnabled(enabled)
        self.ptw_random_trans_check.setEnabled(enabled)
        self.ptw_random_scale_check.setEnabled(enabled)
        self.ptw_random_rot_check.setEnabled(enabled)
        self.ptw_common_centre_check.setEnabled(enabled)
        self.ptw_trans_x.setEnabled(enabled)
        self.ptw_trans_y.setEnabled(enabled)
        self.ptw_scale_x.setEnabled(enabled)
        self.ptw_scale_y.setEnabled(enabled)
        self.ptw_rotation.setEnabled(enabled)
        self.ptw_random_centre_divisor.setEnabled(enabled)
        self.ptw_rt_x_min.setEnabled(enabled)
        self.ptw_rt_x_max.setEnabled(enabled)
        self.ptw_rt_y_min.setEnabled(enabled)
        self.ptw_rt_y_max.setEnabled(enabled)
        self.ptw_rs_x_min.setEnabled(enabled)
        self.ptw_rs_x_max.setEnabled(enabled)
        self.ptw_rs_y_min.setEnabled(enabled)
        self.ptw_rs_y_max.setEnabled(enabled)
        self.ptw_rr_min.setEnabled(enabled)
        self.ptw_rr_max.setEnabled(enabled)
        self.ptp_probability_spin.setEnabled(enabled)
        self.edit_transforms_btn.setEnabled(enabled)

    _SUBDIV_TYPE_ABBREV = {
        "QUAD": "Q", "QUAD_BORD": "QB", "QUAD_BORD_ECHO": "QBE",
        "QUAD_BORD_DOUBLE": "QBD", "QUAD_BORD_DOUBLE_ECHO": "QBDE",
        "TRI": "T", "TRI_BORD_A": "TBA", "TRI_BORD_A_ECHO": "TBAE",
        "TRI_BORD_B": "TBB", "TRI_BORD_B_ECHO": "TBBE",
        "TRI_STAR": "TS", "TRI_BORD_C": "TBC", "TRI_BORD_C_ECHO": "TBCE",
        "SPLIT_VERT": "SV", "SPLIT_HORIZ": "SH", "SPLIT_DIAG": "SD",
        "ECHO": "E", "ECHO_ABS_CENTER": "EAC", "TRI_STAR_FILL": "TSF",
    }

    def _inset_supported(self, subdiv_type) -> bool:
        """Return True if the given SubdivisionType supports inset transform."""
        name = subdiv_type.name
        return "ECHO" in name or name in ("TRI_STAR", "TRI_STAR_FILL")

    def _refresh_tree(self):
        """Refresh the tree view."""
        self._checking = True
        self.tree.clear()
        for params_set in self._collection.params_sets:
            set_item = QTreeWidgetItem(["", params_set.name, "", "", "", ""])
            set_item.setData(0, Qt.ItemDataRole.UserRole, ("set", params_set))
            set_item.setFlags(set_item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
            set_item.setCheckState(0, Qt.CheckState.Unchecked)
            self.tree.addTopLevelItem(set_item)

            for params in params_set.params_list:
                abbrev = self._SUBDIV_TYPE_ABBREV.get(
                    params.subdivision_type.name, params.subdivision_type.name
                )
                it = params.inset_transform
                inset_active = not (
                    it.translation.x == 0.0 and it.translation.y == 0.0 and
                    it.scale.x == 1.0 and it.scale.y == 1.0 and
                    it.rotation.x == 0.0
                )
                params_item = QTreeWidgetItem(["", params.name, abbrev, "", "", ""])
                params_item.setData(0, Qt.ItemDataRole.UserRole, ("params", params, params_set))
                flags = params_item.flags() | Qt.ItemFlag.ItemIsUserCheckable
                params_item.setFlags(flags)
                params_item.setCheckState(0, Qt.CheckState.Unchecked)
                # Inset checkbox — only active for echo/tri-star types
                inset_ok = self._inset_supported(params.subdivision_type)
                if inset_ok:
                    params_item.setCheckState(3, Qt.CheckState.Checked if inset_active else Qt.CheckState.Unchecked)
                else:
                    params_item.setCheckState(3, Qt.CheckState.Unchecked)
                params_item.setCheckState(4, Qt.CheckState.Checked if params.polys_transform_whole else Qt.CheckState.Unchecked)
                params_item.setCheckState(5, Qt.CheckState.Checked if params.polys_transform_points else Qt.CheckState.Unchecked)
                set_item.addChild(params_item)

            set_item.setExpanded(True)
        self._checking = False

    def _on_item_clicked(self, item, column):
        """Handle tree item click."""
        data = item.data(0, Qt.ItemDataRole.UserRole)
        if data is None:
            return

        if data[0] == "set":
            self._current_set = data[1]
            self._current_params = None
            self._set_editor_enabled(False)
        elif data[0] == "params":
            self._current_params = data[1]
            self._current_set = data[2]
            self._load_params_to_ui(self._current_params)
            self._set_editor_enabled(True)

        self._update_buttons()

    def _load_params_to_ui(self, params: SubdivisionParams):
        """Load parameters into the UI."""
        self._updating = True
        try:
            self.name_edit.setText(params.name)
            self.enabled_check.setChecked(params.enabled)

            # Find and set subdivision type
            index = self.subdiv_type_combo.findData(params.subdivision_type)
            if index >= 0:
                self.subdiv_type_combo.setCurrentIndex(index)

            # Find and set visibility rule
            index = self.visibility_combo.findData(params.visibility_rule)
            if index >= 0:
                self.visibility_combo.setCurrentIndex(index)

            self.continuous_check.setChecked(params.continuous)
            self.line_ratio_x.setValue(params.line_ratios.x * 100.0)
            self.line_ratio_y.setValue(params.line_ratios.y * 100.0)
            self.cp_ratio_x.setValue(params.control_point_ratios.x * 100.0)
            self.cp_ratio_y.setValue(params.control_point_ratios.y * 100.0)
            self.ran_middle_check.setChecked(params.ran_middle)
            self.ran_div_spin.setValue(params.ran_div)

            # Inset transform
            it = params.inset_transform
            self.inset_trans_x.setValue(it.translation.x)
            self.inset_trans_y.setValue(it.translation.y)
            self.inset_scale_x.setValue(it.scale.x * 100.0)
            self.inset_scale_y.setValue(it.scale.y * 100.0)
            self.inset_rotation.setValue(it.rotation.x)
            self.polys_transform_check.setChecked(params.polys_transform)
            self.ptw_probability_spin.setValue(params.ptw_probability)
            self.ptw_random_trans_check.setChecked(params.ptw_random_translation)
            self.ptw_random_scale_check.setChecked(params.ptw_random_scale)
            self.ptw_random_rot_check.setChecked(params.ptw_random_rotation)
            self.ptw_common_centre_check.setChecked(params.ptw_common_centre)
            # Base transform values
            self.ptw_trans_x.setValue(params.ptw_transform.translation.x)
            self.ptw_trans_y.setValue(params.ptw_transform.translation.y)
            self.ptw_scale_x.setValue(params.ptw_transform.scale.x)
            self.ptw_scale_y.setValue(params.ptw_transform.scale.y)
            self.ptw_rotation.setValue(params.ptw_transform.rotation.x)
            self.ptw_random_centre_divisor.setValue(params.ptw_random_centre_divisor)
            # Random translation range
            self.ptw_rt_x_min.setValue(params.ptw_random_translation_range.x.min_val)
            self.ptw_rt_x_max.setValue(params.ptw_random_translation_range.x.max_val)
            self.ptw_rt_y_min.setValue(params.ptw_random_translation_range.y.min_val)
            self.ptw_rt_y_max.setValue(params.ptw_random_translation_range.y.max_val)
            # Random scale range
            self.ptw_rs_x_min.setValue(params.ptw_random_scale_range.x.min_val)
            self.ptw_rs_x_max.setValue(params.ptw_random_scale_range.x.max_val)
            self.ptw_rs_y_min.setValue(params.ptw_random_scale_range.y.min_val)
            self.ptw_rs_y_max.setValue(params.ptw_random_scale_range.y.max_val)
            # Random rotation range
            self.ptw_rr_min.setValue(params.ptw_random_rotation_range.min_val)
            self.ptw_rr_max.setValue(params.ptw_random_rotation_range.max_val)
            self.ptp_probability_spin.setValue(params.ptp_probability)
            self._update_transform_status(params.transform_set)
        finally:
            self._updating = False

    def _save_ui_to_params(self):
        """Save UI values back to current params."""
        if self._current_params is None:
            return

        self._current_params.name = self.name_edit.text()
        self._current_params.enabled = self.enabled_check.isChecked()
        self._current_params.subdivision_type = self.subdiv_type_combo.currentData()
        self._current_params.visibility_rule = self.visibility_combo.currentData()
        self._current_params.continuous = self.continuous_check.isChecked()
        self._current_params.line_ratios = Vector2D(
            self.line_ratio_x.value() / 100.0,
            self.line_ratio_y.value() / 100.0
        )
        self._current_params.control_point_ratios = Vector2D(
            self.cp_ratio_x.value() / 100.0,
            self.cp_ratio_y.value() / 100.0
        )
        self._current_params.ran_middle = self.ran_middle_check.isChecked()
        self._current_params.ran_div = self.ran_div_spin.value()

        # Inset transform — always save from fields (tree checkbox controls clear/set)
        self._current_params.inset_transform.translation = Vector2D(
            self.inset_trans_x.value(), self.inset_trans_y.value()
        )
        self._current_params.inset_transform.scale = Vector2D(
            self.inset_scale_x.value() / 100.0,
            self.inset_scale_y.value() / 100.0
        )
        self._current_params.inset_transform.rotation = Vector2D(
            self.inset_rotation.value(), 0.0
        )
        self._current_params.polys_transform = self.polys_transform_check.isChecked()
        self._current_params.ptw_probability = self.ptw_probability_spin.value()
        self._current_params.ptw_random_translation = self.ptw_random_trans_check.isChecked()
        self._current_params.ptw_random_scale = self.ptw_random_scale_check.isChecked()
        self._current_params.ptw_random_rotation = self.ptw_random_rot_check.isChecked()
        self._current_params.ptw_common_centre = self.ptw_common_centre_check.isChecked()
        # Base transform values
        self._current_params.ptw_transform.translation = Vector2D(
            self.ptw_trans_x.value(), self.ptw_trans_y.value()
        )
        self._current_params.ptw_transform.scale = Vector2D(
            self.ptw_scale_x.value(), self.ptw_scale_y.value()
        )
        self._current_params.ptw_transform.rotation = Vector2D(
            self.ptw_rotation.value(), 0.0
        )
        self._current_params.ptw_random_centre_divisor = self.ptw_random_centre_divisor.value()
        # Random translation range
        self._current_params.ptw_random_translation_range = RangeXY(
            Range(self.ptw_rt_x_min.value(), self.ptw_rt_x_max.value()),
            Range(self.ptw_rt_y_min.value(), self.ptw_rt_y_max.value())
        )
        # Random scale range
        self._current_params.ptw_random_scale_range = RangeXY(
            Range(self.ptw_rs_x_min.value(), self.ptw_rs_x_max.value()),
            Range(self.ptw_rs_y_min.value(), self.ptw_rs_y_max.value())
        )
        # Random rotation range
        self._current_params.ptw_random_rotation_range = Range(
            self.ptw_rr_min.value(), self.ptw_rr_max.value()
        )
        self._current_params.ptp_probability = self.ptp_probability_spin.value()

        # Update tree item text
        current_item = self.tree.currentItem()
        if current_item:
            current_item.setText(1, self._current_params.name)

    def _on_name_changed(self):
        """Handle name change."""
        if self._updating:
            return
        self._save_ui_to_params()
        self.modified.emit()

    def _on_modified(self):
        """Handle any value change."""
        if self._updating:
            return
        self._save_ui_to_params()
        self.modified.emit()

    def _add_set(self):
        """Add a new params set."""
        name, ok = QInputDialog.getText(self, "Add Params Set", "Name:")
        if ok and name:
            if self._collection.get_params_set(name):
                QMessageBox.warning(self, "Duplicate Name", f"A params set named '{name}' already exists.")
                return

            new_set = SubdivisionParamsSet(name=name)
            self._collection.add_params_set(new_set)
            self._refresh_tree()
            self.modified.emit()

    def _remove_set(self):
        """Remove the selected params set."""
        if self._current_set is None:
            return

        result = QMessageBox.question(
            self, "Remove Params Set",
            f"Remove params set '{self._current_set.name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result == QMessageBox.StandardButton.Yes:
            self._collection.remove_params_set(self._current_set.name)
            self._current_set = None
            self._current_params = None
            self._set_editor_enabled(False)
            self._refresh_tree()
            self.modified.emit()

    def _next_param_name(self) -> str:
        """Return the next unused alphabetical name (A, B, …, Z, AA, AB, …)."""
        existing = {p.name for p in self._current_set.params_list} if self._current_set else set()
        for i in range(26):
            name = chr(ord('A') + i)
            if name not in existing:
                return name
        for i in range(26):
            for j in range(26):
                name = chr(ord('A') + i) + chr(ord('A') + j)
                if name not in existing:
                    return name
        return "New"

    def _add_params(self):
        """Add new params to the current set."""
        if self._current_set is None:
            QMessageBox.warning(self, "No Set Selected", "Please select a params set first.")
            return

        name, ok = QInputDialog.getText(self, "Add Params", "Name:", text=self._next_param_name())
        if ok and name:
            if self._current_set.get_params(name):
                QMessageBox.warning(self, "Duplicate Name", f"Params named '{name}' already exists in this set.")
                return

            new_params = SubdivisionParams(name=name)
            self._current_set.add_params(new_params)
            self._refresh_tree()
            self.modified.emit()

    def _remove_params(self):
        """Remove the selected params."""
        if self._current_params is None or self._current_set is None:
            return

        result = QMessageBox.question(
            self, "Remove Params",
            f"Remove params '{self._current_params.name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result == QMessageBox.StandardButton.Yes:
            self._current_set.remove_params(self._current_params.name)
            self._current_params = None
            self._set_editor_enabled(False)
            self._refresh_tree()
            self.modified.emit()

    def _get_selected_type(self) -> Optional[str]:
        """Return 'set' or 'params' based on current tree selection."""
        item = self.tree.currentItem()
        if item:
            data = item.data(0, Qt.ItemDataRole.UserRole)
            if data:
                return data[0]
        return None

    def _update_buttons(self):
        """Enable/disable buttons based on current selection."""
        selected_type = self._get_selected_type()
        is_set = selected_type == "set"
        is_params = selected_type == "params"
        has_selection = selected_type is not None

        self.rename_btn.setEnabled(has_selection)
        self.duplicate_btn.setEnabled(has_selection)
        self.move_up_btn.setEnabled(has_selection)
        self.move_down_btn.setEnabled(has_selection)

    def _next_copy_name(self, base: str, exists_fn) -> str:
        """Return base_001, base_002, … — whichever is the first not taken."""
        counter = 1
        while True:
            candidate = f"{base}_{counter:03d}"
            if not exists_fn(candidate):
                return candidate
            counter += 1

    def _rename_selected(self):
        """Rename the selected params set or individual params."""
        if self._current_set is None:
            return
        if self._current_params is None:
            # Rename the set
            new_name, ok = QInputDialog.getText(
                self, "Rename Params Set", "New name:", text=self._current_set.name
            )
            if ok and new_name and new_name != self._current_set.name:
                if self._collection.get_params_set(new_name):
                    QMessageBox.warning(self, "Duplicate Name", f"A params set named '{new_name}' already exists.")
                    return
                self._current_set.name = new_name
                self._refresh_tree()
                self.modified.emit()
        else:
            # Rename the individual params
            new_name, ok = QInputDialog.getText(
                self, "Rename Params", "New name:", text=self._current_params.name
            )
            if ok and new_name and new_name != self._current_params.name:
                if self._current_set.get_params(new_name):
                    QMessageBox.warning(self, "Duplicate Name", f"Params named '{new_name}' already exists in this set.")
                    return
                self._current_params.name = new_name
                self._refresh_tree()
                self.modified.emit()

    def _duplicate_selected(self):
        """Duplicate the selected params set or individual params."""
        if self._current_set is None:
            return
        if self._current_params is None:
            # Duplicate the set
            new_name = self._next_copy_name(
                self._current_set.name,
                lambda n: self._collection.get_params_set(n) is not None
            )
            new_name, ok = QInputDialog.getText(
                self, "Duplicate Params Set", "Name for copy:", text=new_name
            )
            if ok and new_name:
                if self._collection.get_params_set(new_name):
                    QMessageBox.warning(self, "Duplicate Name", f"A params set named '{new_name}' already exists.")
                    return
                new_set = self._current_set.copy()
                new_set.name = new_name
                self._collection.add_params_set(new_set)
                self._refresh_tree()
                self.modified.emit()
        else:
            # Duplicate the individual params
            new_name = self._next_copy_name(
                self._current_params.name,
                lambda n: self._current_set.get_params(n) is not None
            )
            new_name, ok = QInputDialog.getText(
                self, "Duplicate Params", "Name for copy:", text=new_name
            )
            if ok and new_name:
                if self._current_set.get_params(new_name):
                    QMessageBox.warning(self, "Duplicate Name", f"Params named '{new_name}' already exists in this set.")
                    return
                new_params = self._current_params.copy()
                new_params.name = new_name
                self._current_set.add_params(new_params)
                self._refresh_tree()
                self.modified.emit()

    def _move_up(self):
        """Move selected item up."""
        self._move(-1)

    def _move_down(self):
        """Move selected item down."""
        self._move(1)

    def _move(self, direction: int):
        """Move selected set or params in the given direction."""
        selected_type = self._get_selected_type()
        if selected_type is None:
            return

        if selected_type == "params" and self._current_params and self._current_set:
            idx = next((i for i, p in enumerate(self._current_set.params_list) if p is self._current_params), -1)
            if idx >= 0:
                new_idx = idx + direction
                if 0 <= new_idx < len(self._current_set.params_list):
                    self._current_set.move_params(idx, new_idx)
                    self._refresh_tree()
                    self.modified.emit()
        elif selected_type == "set" and self._current_set:
            idx = next((i for i, ps in enumerate(self._collection.params_sets) if ps is self._current_set), -1)
            if idx >= 0:
                new_idx = idx + direction
                if 0 <= new_idx < len(self._collection.params_sets):
                    self._collection.move_params_set(idx, new_idx)
                    self._refresh_tree()
                    self.modified.emit()

    def _on_item_check_changed(self, item, column):
        """Handle checkbox toggle."""
        if self._checking:
            return
        data = item.data(0, Qt.ItemDataRole.UserRole)
        if data is None or data[0] != "params":
            return
        params = data[1]
        checked = item.checkState(column) == Qt.CheckState.Checked
        if column == 3:  # Inset
            if checked:
                # Only allowed for echo/tri-star types; revert if not supported
                if not self._inset_supported(params.subdivision_type):
                    self._checking = True
                    item.setCheckState(3, Qt.CheckState.Unchecked)
                    self._checking = False
                    return
                # Leave existing transform values — panel fields control them
            else:
                # Reset inset transform to identity
                params.inset_transform.translation = Vector2D(0.0, 0.0)
                params.inset_transform.scale = Vector2D(1.0, 1.0)
                params.inset_transform.rotation = Vector2D(0.0, 0.0)
                # Also reset panel fields if this is the current params
                if params is self._current_params:
                    self._updating = True
                    self.inset_trans_x.setValue(0.0)
                    self.inset_trans_y.setValue(0.0)
                    self.inset_scale_x.setValue(100.0)
                    self.inset_scale_y.setValue(100.0)
                    self.inset_rotation.setValue(0.0)
                    self._updating = False
            self.modified.emit()
        elif column == 4:  # PTW
            params.polys_transform_whole = checked
            self.modified.emit()
        elif column == 5:  # PTP
            params.polys_transform_points = checked
            self.modified.emit()

    def _delete_selected(self):
        """Delete all checked params items."""
        to_delete = []  # list of (params_set, params) tuples
        for i in range(self.tree.topLevelItemCount()):
            set_item = self.tree.topLevelItem(i)
            for j in range(set_item.childCount()):
                params_item = set_item.child(j)
                if params_item.checkState(0) == Qt.CheckState.Checked:
                    data = params_item.data(0, Qt.ItemDataRole.UserRole)
                    if data and data[0] == "params":
                        to_delete.append((data[2], data[1]))  # (params_set, params)

        if not to_delete:
            QMessageBox.information(self, "No Selection", "No items are checked for deletion.")
            return

        result = QMessageBox.question(
            self, "Delete Selected",
            f"Delete {len(to_delete)} checked subdivision params?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result == QMessageBox.StandardButton.Yes:
            for params_set, params in to_delete:
                params_set.remove_params(params.name)
            self._current_params = None
            self._set_editor_enabled(False)
            self._refresh_tree()
            self.modified.emit()

    def get_collection(self) -> SubdivisionParamsSetCollection:
        """Get the current collection."""
        return self._collection

    def set_collection(self, collection: SubdivisionParamsSetCollection) -> None:
        """Set the collection to display."""
        self._collection = collection
        self._current_set = None
        self._current_params = None
        self._set_editor_enabled(False)
        self._refresh_tree()

    def create_default_collection(self) -> SubdivisionParamsSetCollection:
        """Create a default collection."""
        return SubdivisionParamsSetCollection.default()

    def _update_transform_status(self, ts: TransformSetConfig):
        """Update the transform status label."""
        enabled = []
        if ts.exterior_anchors.enabled:
            enabled.append("ExteriorAnchors")
        if ts.central_anchors.enabled:
            enabled.append("CentralAnchors")
        if ts.anchors_linked.enabled:
            enabled.append("AnchorsLinked")
        if ts.outer_control_points.enabled:
            enabled.append("OuterCPs")
        if ts.inner_control_points.enabled:
            enabled.append("InnerCPs")
        if enabled:
            self.transform_status_label.setText(", ".join(enabled))
        else:
            self.transform_status_label.setText("No transforms enabled")

    def _edit_transforms(self):
        """Open the transform editing dialog."""
        if self._current_params is None:
            return

        dialog = TransformSetDialog(self._current_params.transform_set, self)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            self._current_params.transform_set = dialog.get_transform_set()
            self._update_transform_status(self._current_params.transform_set)
            self.modified.emit()

    # --- Bake subdivision ---

    def set_project_dir(self, d: str) -> None:
        """Called by MainWindow when a project is loaded."""
        self._project_dir = d

    def _on_bake(self) -> None:
        """Open the bake dialog and start a bake if confirmed."""
        if not self._project_dir:
            QMessageBox.warning(self, "No Project", "No project is open.")
            return
        poly_dir = os.path.join(self._project_dir, "polygonSets")
        if not os.path.isdir(poly_dir):
            QMessageBox.warning(self, "No polygonSets", f"polygonSets directory not found:\n{poly_dir}")
            return
        subdiv_xml = os.path.join(self._project_dir, "configuration", "subdivision.xml")
        if not os.path.isfile(subdiv_xml):
            QMessageBox.warning(self, "No subdivision.xml", f"Subdivision config not found:\n{subdiv_xml}")
            return

        dialog = BakeSubdivisionDialog(poly_dir, self._collection, self)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return

        input_path = dialog.selected_polygon_set()
        set_name = dialog.selected_set_name()
        stem = dialog.output_name()

        if not stem:
            QMessageBox.warning(self, "No Output Name", "Please enter an output file name.")
            return

        output_path = os.path.join(poly_dir, stem + ".xml")
        if os.path.exists(output_path):
            res = QMessageBox.question(
                self, "Overwrite?",
                f"'{stem}.xml' already exists. Overwrite?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
            if res != QMessageBox.StandardButton.Yes:
                return

        self._run_bake(input_path, subdiv_xml, set_name, output_path)

    def _run_bake(self, input_path: str, subdiv_xml: str, set_name: str, output_path: str) -> None:
        """Launch sbt bake-subdivision as a QProcess."""
        LOOM_ENGINE_PATH = "/Users/broganbunt/Loom_2026/loom_engine"
        shell_cmd = (
            f'sbt "run --bake-subdivision '
            f'{shlex.quote(input_path)} '
            f'{shlex.quote(subdiv_xml)} '
            f'{shlex.quote(set_name)} '
            f'{shlex.quote(output_path)}"'
        )

        self._bake_process = QProcess(self)
        self._bake_process.setWorkingDirectory(LOOM_ENGINE_PATH)
        env = QProcessEnvironment.systemEnvironment()
        self._bake_process.setProcessEnvironment(env)
        self._bake_process.finished.connect(
            lambda code, _status: self._on_bake_finished(code, output_path)
        )
        self._bake_process.errorOccurred.connect(self._on_bake_error)

        self.bake_btn.setEnabled(False)
        self.bake_btn.setText("Baking\u2026")
        self._bake_process.start("/bin/zsh", ["-l", "-c", shell_cmd])

    def _on_bake_finished(self, exit_code: int, output_path: str) -> None:
        """Handle bake process completion."""
        self.bake_btn.setEnabled(True)
        self.bake_btn.setText("Bake\u2026")
        self._bake_process = None

        if exit_code == 0 and os.path.isfile(output_path):
            self.polygon_baked.emit()
            QMessageBox.information(
                self, "Bake Complete",
                f"Subdivision baked to:\n{output_path}"
            )
        else:
            QMessageBox.warning(
                self, "Bake Failed",
                f"Bake process exited with code {exit_code}.\n"
                f"Check the terminal for details."
            )

    def _on_bake_error(self, error) -> None:
        """Handle bake process error."""
        self.bake_btn.setEnabled(True)
        self.bake_btn.setText("Bake\u2026")
        self._bake_process = None
        error_msgs = {
            QProcess.ProcessError.FailedToStart: "Failed to start sbt",
            QProcess.ProcessError.Crashed: "Process crashed",
            QProcess.ProcessError.Timedout: "Timed out",
            QProcess.ProcessError.WriteError: "Write error",
            QProcess.ProcessError.ReadError: "Read error",
        }
        msg = error_msgs.get(error, f"Unknown error ({error})")
        QMessageBox.critical(self, "Bake Error", f"Process error: {msg}")


class TransformSetDialog(QDialog):
    """Dialog for editing the 5 transform types."""

    def __init__(self, transform_set: TransformSetConfig, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Edit Point Transforms")
        self.setMinimumSize(600, 500)
        self._ts = transform_set.copy()
        self._setup_ui()

    def _setup_ui(self):
        layout = QVBoxLayout(self)

        tabs = QTabWidget()

        # ExteriorAnchors tab
        ea_widget = QWidget()
        ea_scroll = QScrollArea()
        ea_scroll.setWidgetResizable(True)
        ea_inner = QWidget()
        ea_form = QFormLayout(ea_inner)
        self._build_exterior_anchors_ui(ea_form)
        ea_scroll.setWidget(ea_inner)
        ea_layout = QVBoxLayout(ea_widget)
        ea_layout.addWidget(ea_scroll)
        tabs.addTab(ea_widget, "Exterior Anchors")

        # CentralAnchors tab
        ca_widget = QWidget()
        ca_scroll = QScrollArea()
        ca_scroll.setWidgetResizable(True)
        ca_inner = QWidget()
        ca_form = QFormLayout(ca_inner)
        self._build_central_anchors_ui(ca_form)
        ca_scroll.setWidget(ca_inner)
        ca_layout = QVBoxLayout(ca_widget)
        ca_layout.addWidget(ca_scroll)
        tabs.addTab(ca_widget, "Central Anchors")

        # AnchorsLinkedToCentre tab
        al_widget = QWidget()
        al_scroll = QScrollArea()
        al_scroll.setWidgetResizable(True)
        al_inner = QWidget()
        al_form = QFormLayout(al_inner)
        self._build_anchors_linked_ui(al_form)
        al_scroll.setWidget(al_inner)
        al_layout = QVBoxLayout(al_widget)
        al_layout.addWidget(al_scroll)
        tabs.addTab(al_widget, "Anchors Linked")

        # OuterControlPoints tab
        ocp_widget = QWidget()
        ocp_scroll = QScrollArea()
        ocp_scroll.setWidgetResizable(True)
        ocp_inner = QWidget()
        ocp_form = QFormLayout(ocp_inner)
        self._build_outer_control_points_ui(ocp_form)
        ocp_scroll.setWidget(ocp_inner)
        ocp_layout = QVBoxLayout(ocp_widget)
        ocp_layout.addWidget(ocp_scroll)
        tabs.addTab(ocp_widget, "Outer CPs")

        # InnerControlPoints tab
        icp_widget = QWidget()
        icp_scroll = QScrollArea()
        icp_scroll.setWidgetResizable(True)
        icp_inner = QWidget()
        icp_form = QFormLayout(icp_inner)
        self._build_inner_control_points_ui(icp_form)
        icp_scroll.setWidget(icp_inner)
        icp_layout = QVBoxLayout(icp_widget)
        icp_layout.addWidget(icp_scroll)
        tabs.addTab(icp_widget, "Inner CPs")

        layout.addWidget(tabs)

        # Dialog buttons
        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._save_and_accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _make_double_spin(self, value: float, min_val: float = -100.0, max_val: float = 100.0,
                          decimals: int = 3, step: float = 0.1) -> QDoubleSpinBox:
        spin = QDoubleSpinBox()
        spin.setRange(min_val, max_val)
        spin.setDecimals(decimals)
        spin.setSingleStep(step)
        spin.setValue(value)
        return spin

    def _make_range_row(self, form: QFormLayout, label: str, r: TRange,
                        min_val: float = -100.0, max_val: float = 100.0) -> tuple:
        layout = QHBoxLayout()
        min_spin = self._make_double_spin(r.min, min_val, max_val)
        max_spin = self._make_double_spin(r.max, min_val, max_val)
        layout.addWidget(QLabel("Min:"))
        layout.addWidget(min_spin)
        layout.addWidget(QLabel("Max:"))
        layout.addWidget(max_spin)
        form.addRow(label, layout)
        return min_spin, max_spin

    # --- Exterior Anchors ---

    def _build_exterior_anchors_ui(self, form: QFormLayout):
        ea = self._ts.exterior_anchors

        self.ea_enabled = QCheckBox()
        self.ea_enabled.setChecked(ea.enabled)
        form.addRow("Enabled:", self.ea_enabled)

        self.ea_probability = self._make_double_spin(ea.probability, 0, 100, 1, 1)
        form.addRow("Probability %:", self.ea_probability)

        self.ea_spike_factor = self._make_double_spin(ea.spike_factor, -10, 10)
        form.addRow("Spike Factor:", self.ea_spike_factor)

        self.ea_which_spike = QComboBox()
        for opt in ["ALL", "CORNERS", "MIDDLES"]:
            self.ea_which_spike.addItem(opt)
        self.ea_which_spike.setCurrentText(ea.which_spike)
        form.addRow("Which Spike:", self.ea_which_spike)

        self.ea_spike_type = QComboBox()
        for opt in ["SYMMETRICAL", "RIGHT", "LEFT", "RANDOM"]:
            self.ea_spike_type.addItem(opt)
        self.ea_spike_type.setCurrentText(ea.spike_type)
        form.addRow("Spike Type:", self.ea_spike_type)

        self.ea_spike_axis = QComboBox()
        for opt in ["XY", "X", "Y"]:
            self.ea_spike_axis.addItem(opt)
        self.ea_spike_axis.setCurrentText(ea.spike_axis)
        form.addRow("Spike Axis:", self.ea_spike_axis)

        self.ea_random_spike = QCheckBox()
        self.ea_random_spike.setChecked(ea.random_spike)
        form.addRow("Random Spike:", self.ea_random_spike)

        self.ea_rsf_min, self.ea_rsf_max = self._make_range_row(form, "Random Spike Factor:", ea.random_spike_factor)

        self.ea_cps_follow = QCheckBox()
        self.ea_cps_follow.setChecked(ea.cps_follow)
        form.addRow("CPs Follow:", self.ea_cps_follow)

        self.ea_cps_follow_mult = self._make_double_spin(ea.cps_follow_multiplier, -100, 100)
        form.addRow("CPs Follow Multiplier:", self.ea_cps_follow_mult)

        self.ea_random_cps_follow = QCheckBox()
        self.ea_random_cps_follow.setChecked(ea.random_cps_follow)
        form.addRow("Random CPs Follow:", self.ea_random_cps_follow)

        self.ea_rcf_min, self.ea_rcf_max = self._make_range_row(form, "Random CPs Follow Range:", ea.random_cps_follow_range)

        self.ea_cps_squeeze = QCheckBox()
        self.ea_cps_squeeze.setChecked(ea.cps_squeeze)
        form.addRow("CPs Squeeze:", self.ea_cps_squeeze)

        self.ea_cps_squeeze_factor = self._make_double_spin(ea.cps_squeeze_factor, -10, 10)
        form.addRow("CPs Squeeze Factor:", self.ea_cps_squeeze_factor)

        self.ea_random_cps_squeeze = QCheckBox()
        self.ea_random_cps_squeeze.setChecked(ea.random_cps_squeeze)
        form.addRow("Random CPs Squeeze:", self.ea_random_cps_squeeze)

        self.ea_rcs_min, self.ea_rcs_max = self._make_range_row(form, "Random CPs Squeeze Range:", ea.random_cps_squeeze_range)

    # --- Central Anchors ---

    def _build_central_anchors_ui(self, form: QFormLayout):
        ca = self._ts.central_anchors

        self.ca_enabled = QCheckBox()
        self.ca_enabled.setChecked(ca.enabled)
        form.addRow("Enabled:", self.ca_enabled)

        self.ca_probability = self._make_double_spin(ca.probability, 0, 100, 1, 1)
        form.addRow("Probability %:", self.ca_probability)

        self.ca_tear_factor = self._make_double_spin(ca.tear_factor, -10, 10)
        form.addRow("Tear Factor:", self.ca_tear_factor)

        self.ca_tear_axis = QComboBox()
        for opt in ["XY", "X", "Y", "RANDOM"]:
            self.ca_tear_axis.addItem(opt)
        self.ca_tear_axis.setCurrentText(ca.tear_axis)
        form.addRow("Tear Axis:", self.ca_tear_axis)

        self.ca_tear_direction = QComboBox()
        for opt in ["DIAGONAL", "LEFT", "RIGHT", "RANDOM"]:
            self.ca_tear_direction.addItem(opt)
        self.ca_tear_direction.setCurrentText(ca.tear_direction)
        form.addRow("Tear Direction:", self.ca_tear_direction)

        self.ca_random_tear = QCheckBox()
        self.ca_random_tear.setChecked(ca.random_tear)
        form.addRow("Random Tear:", self.ca_random_tear)

        self.ca_rtf_min, self.ca_rtf_max = self._make_range_row(form, "Random Tear Factor:", ca.random_tear_factor)

        self.ca_cps_follow = QCheckBox()
        self.ca_cps_follow.setChecked(ca.cps_follow)
        form.addRow("CPs Follow:", self.ca_cps_follow)

        self.ca_cps_follow_mult = self._make_double_spin(ca.cps_follow_multiplier, -100, 100)
        form.addRow("CPs Follow Multiplier:", self.ca_cps_follow_mult)

        self.ca_random_cps_follow = QCheckBox()
        self.ca_random_cps_follow.setChecked(ca.random_cps_follow)
        form.addRow("Random CPs Follow:", self.ca_random_cps_follow)

        self.ca_rcf_min, self.ca_rcf_max = self._make_range_row(form, "Random CPs Follow Range:", ca.random_cps_follow_range)

        self.ca_all_points_follow = QCheckBox()
        self.ca_all_points_follow.setChecked(ca.all_points_follow)
        form.addRow("All Points Follow:", self.ca_all_points_follow)

        self.ca_inverted_follow = QCheckBox()
        self.ca_inverted_follow.setChecked(ca.inverted_follow)
        form.addRow("Inverted Follow:", self.ca_inverted_follow)

    # --- Anchors Linked To Centre ---

    def _build_anchors_linked_ui(self, form: QFormLayout):
        al = self._ts.anchors_linked

        self.al_enabled = QCheckBox()
        self.al_enabled.setChecked(al.enabled)
        form.addRow("Enabled:", self.al_enabled)

        self.al_probability = self._make_double_spin(al.probability, 0, 100, 1, 1)
        form.addRow("Probability %:", self.al_probability)

        self.al_tear_factor = self._make_double_spin(al.tear_factor, -10, 10)
        form.addRow("Tear Factor:", self.al_tear_factor)

        self.al_tear_type = QComboBox()
        for opt in ["TOWARDS_OUTSIDE_CORNER", "TOWARDS_OPPOSITE_CORNER", "TOWARDS_CENTRE", "RANDOM"]:
            self.al_tear_type.addItem(opt)
        self.al_tear_type.setCurrentText(al.tear_type)
        form.addRow("Tear Type:", self.al_tear_type)

        self.al_random_tear = QCheckBox()
        self.al_random_tear.setChecked(al.random_tear)
        form.addRow("Random Tear:", self.al_random_tear)

        self.al_rtf_min, self.al_rtf_max = self._make_range_row(form, "Random Tear Factor:", al.random_tear_factor)

        self.al_cps_follow = QCheckBox()
        self.al_cps_follow.setChecked(al.cps_follow)
        form.addRow("CPs Follow:", self.al_cps_follow)

        self.al_cps_follow_mult = self._make_double_spin(al.cps_follow_multiplier, -100, 100)
        form.addRow("CPs Follow Multiplier:", self.al_cps_follow_mult)

        self.al_random_cps_follow = QCheckBox()
        self.al_random_cps_follow.setChecked(al.random_cps_follow)
        form.addRow("Random CPs Follow:", self.al_random_cps_follow)

        self.al_rcf_min, self.al_rcf_max = self._make_range_row(form, "Random CPs Follow Range:", al.random_cps_follow_range)

    # --- Outer Control Points ---

    def _build_outer_control_points_ui(self, form: QFormLayout):
        ocp = self._ts.outer_control_points

        self.ocp_enabled = QCheckBox()
        self.ocp_enabled.setChecked(ocp.enabled)
        form.addRow("Enabled:", self.ocp_enabled)

        self.ocp_probability = self._make_double_spin(ocp.probability, 0, 100, 1, 1)
        form.addRow("Probability %:", self.ocp_probability)

        self.ocp_line_ratio_x = self._make_double_spin(ocp.line_ratio_x, 0, 1)
        form.addRow("Line Ratio X:", self.ocp_line_ratio_x)

        self.ocp_line_ratio_y = self._make_double_spin(ocp.line_ratio_y, 0, 1)
        form.addRow("Line Ratio Y:", self.ocp_line_ratio_y)

        self.ocp_random_line_ratio = QCheckBox()
        self.ocp_random_line_ratio.setChecked(ocp.random_line_ratio)
        form.addRow("Random Line Ratio:", self.ocp_random_line_ratio)

        self.ocp_rlri_min, self.ocp_rlri_max = self._make_range_row(form, "Random Inner Ratio:", ocp.random_line_ratio_inner, 0, 1)
        self.ocp_rlro_min, self.ocp_rlro_max = self._make_range_row(form, "Random Outer Ratio:", ocp.random_line_ratio_outer, 0, 1)

        self.ocp_curve_mode = QComboBox()
        for opt in ["PERPENDICULAR", "FROM_CENTRE"]:
            self.ocp_curve_mode.addItem(opt)
        self.ocp_curve_mode.setCurrentText(ocp.curve_mode)
        form.addRow("Curve Mode:", self.ocp_curve_mode)

        self.ocp_curve_type = QComboBox()
        for opt in ["PUFF", "PINCH", "PUFF_PINCH_PUFF_PINCH", "PUFF_PINCH_PINCH_PUFF",
                     "PINCH_PUFF_PUFF_PINCH", "PINCH_PUFF_PINCH_PUFF"]:
            self.ocp_curve_type.addItem(opt)
        self.ocp_curve_type.setCurrentText(ocp.curve_type)
        form.addRow("Curve Type:", self.ocp_curve_type)

        self.ocp_curve_mult_min = self._make_double_spin(ocp.curve_multiplier_min, -100, 100)
        form.addRow("Curve Multiplier Min:", self.ocp_curve_mult_min)

        self.ocp_curve_mult_max = self._make_double_spin(ocp.curve_multiplier_max, -100, 100)
        form.addRow("Curve Multiplier Max:", self.ocp_curve_mult_max)

        self.ocp_random_multiplier = QCheckBox()
        self.ocp_random_multiplier.setChecked(ocp.random_multiplier)
        form.addRow("Random Multiplier:", self.ocp_random_multiplier)

        self.ocp_rcm_min, self.ocp_rcm_max = self._make_range_row(form, "Random Curve Multiplier:", ocp.random_curve_multiplier)

        self.ocp_cfc_ratio_x = self._make_double_spin(ocp.curve_from_centre_ratio_x, -10, 10)
        form.addRow("From Centre Ratio X:", self.ocp_cfc_ratio_x)

        self.ocp_cfc_ratio_y = self._make_double_spin(ocp.curve_from_centre_ratio_y, -10, 10)
        form.addRow("From Centre Ratio Y:", self.ocp_cfc_ratio_y)

        self.ocp_random_from_centre = QCheckBox()
        self.ocp_random_from_centre.setChecked(ocp.random_from_centre)
        form.addRow("Random From Centre:", self.ocp_random_from_centre)

        self.ocp_rfca_min, self.ocp_rfca_max = self._make_range_row(form, "Random From Centre A:", ocp.random_from_centre_a)
        self.ocp_rfcb_min, self.ocp_rfcb_max = self._make_range_row(form, "Random From Centre B:", ocp.random_from_centre_b)

    # --- Inner Control Points ---

    def _build_inner_control_points_ui(self, form: QFormLayout):
        icp = self._ts.inner_control_points

        self.icp_enabled = QCheckBox()
        self.icp_enabled.setChecked(icp.enabled)
        form.addRow("Enabled:", self.icp_enabled)

        self.icp_probability = self._make_double_spin(icp.probability, 0, 100, 1, 1)
        form.addRow("Probability %:", self.icp_probability)

        self.icp_refer_to_outer = QComboBox()
        for opt in ["NONE", "FOLLOW", "EXAGGERATE", "COUNTER"]:
            self.icp_refer_to_outer.addItem(opt)
        self.icp_refer_to_outer.setCurrentText(icp.refer_to_outer)
        form.addRow("Refer To Outer:", self.icp_refer_to_outer)

        self.icp_inner_mult_x = self._make_double_spin(icp.inner_multiplier_x, -100, 100)
        form.addRow("Inner Multiplier X:", self.icp_inner_mult_x)

        self.icp_inner_mult_y = self._make_double_spin(icp.inner_multiplier_y, -100, 100)
        form.addRow("Inner Multiplier Y:", self.icp_inner_mult_y)

        self.icp_outer_mult_x = self._make_double_spin(icp.outer_multiplier_x, -100, 100)
        form.addRow("Outer Multiplier X:", self.icp_outer_mult_x)

        self.icp_outer_mult_y = self._make_double_spin(icp.outer_multiplier_y, -100, 100)
        form.addRow("Outer Multiplier Y:", self.icp_outer_mult_y)

        self.icp_inner_ratio = self._make_double_spin(icp.inner_ratio, -10, 10)
        form.addRow("Inner Ratio:", self.icp_inner_ratio)

        self.icp_outer_ratio = self._make_double_spin(icp.outer_ratio, -10, 10)
        form.addRow("Outer Ratio:", self.icp_outer_ratio)

        self.icp_random_ratio = QCheckBox()
        self.icp_random_ratio.setChecked(icp.random_ratio)
        form.addRow("Random Ratio:", self.icp_random_ratio)

        self.icp_rir_min, self.icp_rir_max = self._make_range_row(form, "Random Inner Ratio:", icp.random_inner_ratio)
        self.icp_ror_min, self.icp_ror_max = self._make_range_row(form, "Random Outer Ratio:", icp.random_outer_ratio)

        self.icp_common_line = QComboBox()
        for opt in ["EVEN", "ODD", "RANDOM", "NONE"]:
            self.icp_common_line.addItem(opt)
        self.icp_common_line.setCurrentText(icp.common_line)
        form.addRow("Common Line:", self.icp_common_line)

    def _save_and_accept(self):
        """Save UI values to transform set and accept."""
        # Exterior Anchors
        ea = self._ts.exterior_anchors
        ea.enabled = self.ea_enabled.isChecked()
        ea.probability = self.ea_probability.value()
        ea.spike_factor = self.ea_spike_factor.value()
        ea.which_spike = self.ea_which_spike.currentText()
        ea.spike_type = self.ea_spike_type.currentText()
        ea.spike_axis = self.ea_spike_axis.currentText()
        ea.random_spike = self.ea_random_spike.isChecked()
        ea.random_spike_factor = TRange(self.ea_rsf_min.value(), self.ea_rsf_max.value())
        ea.cps_follow = self.ea_cps_follow.isChecked()
        ea.cps_follow_multiplier = self.ea_cps_follow_mult.value()
        ea.random_cps_follow = self.ea_random_cps_follow.isChecked()
        ea.random_cps_follow_range = TRange(self.ea_rcf_min.value(), self.ea_rcf_max.value())
        ea.cps_squeeze = self.ea_cps_squeeze.isChecked()
        ea.cps_squeeze_factor = self.ea_cps_squeeze_factor.value()
        ea.random_cps_squeeze = self.ea_random_cps_squeeze.isChecked()
        ea.random_cps_squeeze_range = TRange(self.ea_rcs_min.value(), self.ea_rcs_max.value())

        # Central Anchors
        ca = self._ts.central_anchors
        ca.enabled = self.ca_enabled.isChecked()
        ca.probability = self.ca_probability.value()
        ca.tear_factor = self.ca_tear_factor.value()
        ca.tear_axis = self.ca_tear_axis.currentText()
        ca.tear_direction = self.ca_tear_direction.currentText()
        ca.random_tear = self.ca_random_tear.isChecked()
        ca.random_tear_factor = TRange(self.ca_rtf_min.value(), self.ca_rtf_max.value())
        ca.cps_follow = self.ca_cps_follow.isChecked()
        ca.cps_follow_multiplier = self.ca_cps_follow_mult.value()
        ca.random_cps_follow = self.ca_random_cps_follow.isChecked()
        ca.random_cps_follow_range = TRange(self.ca_rcf_min.value(), self.ca_rcf_max.value())
        ca.all_points_follow = self.ca_all_points_follow.isChecked()
        ca.inverted_follow = self.ca_inverted_follow.isChecked()

        # Anchors Linked
        al = self._ts.anchors_linked
        al.enabled = self.al_enabled.isChecked()
        al.probability = self.al_probability.value()
        al.tear_factor = self.al_tear_factor.value()
        al.tear_type = self.al_tear_type.currentText()
        al.random_tear = self.al_random_tear.isChecked()
        al.random_tear_factor = TRange(self.al_rtf_min.value(), self.al_rtf_max.value())
        al.cps_follow = self.al_cps_follow.isChecked()
        al.cps_follow_multiplier = self.al_cps_follow_mult.value()
        al.random_cps_follow = self.al_random_cps_follow.isChecked()
        al.random_cps_follow_range = TRange(self.al_rcf_min.value(), self.al_rcf_max.value())

        # Outer Control Points
        ocp = self._ts.outer_control_points
        ocp.enabled = self.ocp_enabled.isChecked()
        ocp.probability = self.ocp_probability.value()
        ocp.line_ratio_x = self.ocp_line_ratio_x.value()
        ocp.line_ratio_y = self.ocp_line_ratio_y.value()
        ocp.random_line_ratio = self.ocp_random_line_ratio.isChecked()
        ocp.random_line_ratio_inner = TRange(self.ocp_rlri_min.value(), self.ocp_rlri_max.value())
        ocp.random_line_ratio_outer = TRange(self.ocp_rlro_min.value(), self.ocp_rlro_max.value())
        ocp.curve_mode = self.ocp_curve_mode.currentText()
        ocp.curve_type = self.ocp_curve_type.currentText()
        ocp.curve_multiplier_min = self.ocp_curve_mult_min.value()
        ocp.curve_multiplier_max = self.ocp_curve_mult_max.value()
        ocp.random_multiplier = self.ocp_random_multiplier.isChecked()
        ocp.random_curve_multiplier = TRange(self.ocp_rcm_min.value(), self.ocp_rcm_max.value())
        ocp.curve_from_centre_ratio_x = self.ocp_cfc_ratio_x.value()
        ocp.curve_from_centre_ratio_y = self.ocp_cfc_ratio_y.value()
        ocp.random_from_centre = self.ocp_random_from_centre.isChecked()
        ocp.random_from_centre_a = TRange(self.ocp_rfca_min.value(), self.ocp_rfca_max.value())
        ocp.random_from_centre_b = TRange(self.ocp_rfcb_min.value(), self.ocp_rfcb_max.value())

        # Inner Control Points
        icp = self._ts.inner_control_points
        icp.enabled = self.icp_enabled.isChecked()
        icp.probability = self.icp_probability.value()
        icp.refer_to_outer = self.icp_refer_to_outer.currentText()
        icp.inner_multiplier_x = self.icp_inner_mult_x.value()
        icp.inner_multiplier_y = self.icp_inner_mult_y.value()
        icp.outer_multiplier_x = self.icp_outer_mult_x.value()
        icp.outer_multiplier_y = self.icp_outer_mult_y.value()
        icp.inner_ratio = self.icp_inner_ratio.value()
        icp.outer_ratio = self.icp_outer_ratio.value()
        icp.random_ratio = self.icp_random_ratio.isChecked()
        icp.random_inner_ratio = TRange(self.icp_rir_min.value(), self.icp_rir_max.value())
        icp.random_outer_ratio = TRange(self.icp_ror_min.value(), self.icp_ror_max.value())
        icp.common_line = self.icp_common_line.currentText()

        self.accept()

    def get_transform_set(self) -> TransformSetConfig:
        """Return the edited transform set."""
        return self._ts


class BakeSubdivisionDialog(QDialog):
    """Dialog for configuring a subdivision bake operation."""

    def __init__(self, poly_dir: str, collection: SubdivisionParamsSetCollection, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Bake Subdivision")
        self.setMinimumWidth(440)
        self._poly_dir = poly_dir
        self._collection = collection
        self._setup_ui()

    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        form = QFormLayout()

        # Source polygon set combo — all .xml in polygonSets/, excluding *_SD*.xml
        self._source_combo = QComboBox()
        xml_files = sorted(
            f for f in os.listdir(self._poly_dir)
            if f.endswith(".xml")
            and not f.endswith(".layers.xml")
            and "_SD" not in f
        )
        for fname in xml_files:
            self._source_combo.addItem(fname, os.path.join(self._poly_dir, fname))
        self._source_combo.currentIndexChanged.connect(self._on_source_changed)
        form.addRow("Source polygon set:", self._source_combo)

        # Subdivision set combo
        self._set_combo = QComboBox()
        for ps in self._collection.params_sets:
            self._set_combo.addItem(ps.name)
        self._set_combo.currentIndexChanged.connect(self._on_set_changed)
        form.addRow("Subdivision set:", self._set_combo)

        # Output name
        self._output_edit = QLineEdit()
        form.addRow("Output name:", self._output_edit)

        # Warning label for many passes
        self._warning_label = QLabel()
        self._warning_label.setStyleSheet("color: orange;")
        self._warning_label.setWordWrap(True)
        self._warning_label.hide()
        form.addRow("", self._warning_label)

        layout.addLayout(form)

        # OK / Cancel
        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

        # Populate initial values
        self._on_source_changed(0)
        self._on_set_changed(0)

    def _on_source_changed(self, _index: int) -> None:
        """Auto-fill output name from source stem."""
        fname = self._source_combo.currentText()
        if not fname:
            return
        # Strip .layers.xml or .xml suffix
        stem = re.sub(r"\.layers\.xml$", "", fname)
        stem = re.sub(r"\.xml$", "", stem)
        # Strip _layer_N suffix
        stem = re.sub(r"_layer_\d+$", "", stem)
        self._output_edit.setText(stem + "_SD")

    def _on_set_changed(self, _index: int) -> None:
        """Show warning if selected set has more than 3 passes."""
        set_name = self._set_combo.currentText()
        ps = self._collection.get_params_set(set_name)
        if ps is None:
            self._warning_label.hide()
            return
        n = len(ps.params_list)
        if n > 3:
            self._warning_label.setText(
                f"\u26a0 {n} passes \u2014 output \u2248 input \u00d7 4^{n} polygons."
            )
            self._warning_label.show()
        else:
            self._warning_label.hide()

    def selected_polygon_set(self) -> str:
        """Return the full path of the selected source polygon set."""
        return self._source_combo.currentData() or ""

    def selected_set_name(self) -> str:
        """Return the name of the selected subdivision set."""
        return self._set_combo.currentText()

    def output_name(self) -> str:
        """Return the output stem (without .xml extension)."""
        return self._output_edit.text().strip()
