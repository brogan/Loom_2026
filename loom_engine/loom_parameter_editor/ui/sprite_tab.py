"""
Sprite configuration tab for the parameter editor.
Provides UI for editing sprites.xml settings.
"""
import os
import re
import shutil
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QDoubleSpinBox, QSpinBox, QComboBox, QTreeWidget, QCheckBox,
    QTreeWidgetItem, QPushButton, QSplitter, QLabel, QListWidget,
    QMessageBox, QInputDialog, QScrollArea, QTableWidget, QTableWidgetItem,
    QHeaderView, QStyledItemDelegate, QDialog, QDialogButtonBox, QRadioButton,
    QButtonGroup, QTabWidget, QFileDialog
)
from PyQt6.QtCore import pyqtSignal, Qt
from PyQt6.QtCore import QProcess
from models.sprite_config import (
    SpriteDef, SpriteParams, SpriteSet, SpriteLibrary, Keyframe, MorphTargetRef,
    EASING_TYPES, LOOP_MODES
)
from ui.sprite_preview_widget import SpritePreviewWidget

ANIMATOR_TYPES = ["random", "keyframe", "jitter_morph", "keyframe_morph"]

BEZIER_JAR = "/Users/broganbunt/Loom_2026/bezier/out/artifacts/Bezier_jar/Bezier.jar"
BEZIER_WORKING_DIR = "/Users/broganbunt/Loom_2026/bezier"


class SpriteTab(QWidget):
    """Tab widget for editing sprite configuration."""

    modified = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._library = SpriteLibrary()
        self._current_set: SpriteSet = None
        self._current_sprite: SpriteDef = None
        self._updating = False
        self._checking = False
        self._shape_library = None  # Reference to shape library for dropdowns
        self._renderer_library = None  # Reference to renderer library for dropdowns
        self._project_dir = None  # Project directory for morph target file ops
        self._bezier_process = None  # QProcess for Bezier editor
        self._edit_morph_path = None          # Path of morph target being edited in Bezier
        self._edit_morph_bezier_saved = None  # Actual path where Bezier saves the file
        self._edit_morph_bezier_name = None   # Clean base name passed to Bezier (for cleanup)

        self._setup_ui()
        self._refresh_tree()

    def _setup_ui(self):
        """Set up the UI layout."""
        main_layout = QHBoxLayout(self)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        main_layout.addWidget(splitter)

        # Left panel - sprite tree
        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)

        left_layout.addWidget(QLabel("Sprite Library:"))

        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["Sel", "Name", "Enabled", "Anim"])
        self.tree.setColumnWidth(0, 35)
        self.tree.setColumnWidth(1, 180)
        self.tree.setColumnWidth(2, 50)
        self.tree.setColumnWidth(3, 40)
        self.tree.currentItemChanged.connect(self._on_item_selected)
        self.tree.itemChanged.connect(self._on_item_check_changed)
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

        # Buttons for sprites
        sprite_btn_layout = QHBoxLayout()
        self.add_sprite_btn = QPushButton("+ Sprite")
        self.add_sprite_btn.clicked.connect(self._add_sprite)
        sprite_btn_layout.addWidget(self.add_sprite_btn)

        self.remove_sprite_btn = QPushButton("- Sprite")
        self.remove_sprite_btn.clicked.connect(self._remove_sprite)
        sprite_btn_layout.addWidget(self.remove_sprite_btn)

        self.duplicate_btn = QPushButton("Duplicate")
        self.duplicate_btn.clicked.connect(self._duplicate_sprite)
        sprite_btn_layout.addWidget(self.duplicate_btn)
        left_layout.addLayout(sprite_btn_layout)

        # Delete Selected button
        del_sel_layout = QHBoxLayout()
        self.delete_selected_btn = QPushButton("Delete Selected")
        self.delete_selected_btn.clicked.connect(self._delete_selected)
        del_sel_layout.addWidget(self.delete_selected_btn)
        del_sel_layout.addStretch()
        left_layout.addLayout(del_sel_layout)

        splitter.addWidget(left_panel)

        # Right panel with inner tabs: General | Animation
        right_panel = QWidget()
        right_outer_layout = QVBoxLayout(right_panel)
        right_outer_layout.setContentsMargins(0, 0, 0, 0)

        inner_tabs = QTabWidget()
        right_outer_layout.addWidget(inner_tabs)

        # General tab
        gen_scroll = QScrollArea()
        gen_scroll.setWidgetResizable(True)
        gen_content = QWidget()
        gen_layout = QVBoxLayout(gen_content)
        gen_scroll.setWidget(gen_content)
        inner_tabs.addTab(gen_scroll, "General")

        # Animation tab
        anim_scroll = QScrollArea()
        anim_scroll.setWidgetResizable(True)
        anim_content = QWidget()
        anim_layout = QVBoxLayout(anim_content)
        anim_scroll.setWidget(anim_content)
        inner_tabs.addTab(anim_scroll, "Animation")

        # Preview tab
        self._inner_tabs = inner_tabs
        self.preview_widget = SpritePreviewWidget()
        inner_tabs.addTab(self.preview_widget, "Preview")
        self.preview_widget.transform_changed.connect(self._on_preview_transform_changed)
        self.preview_widget.kf_transform_changed.connect(self._on_preview_kf_transform_changed)

        # right_layout aliases the General tab layout for the groups below
        right_layout = gen_layout

        # Sprite identity
        identity_group = QGroupBox("Sprite")
        identity_layout = QFormLayout(identity_group)

        self.name_edit = QLineEdit()
        self.name_edit.textChanged.connect(self._on_name_changed)
        identity_layout.addRow("Name:", self.name_edit)

        right_layout.addWidget(identity_group)

        # References
        ref_group = QGroupBox("References")
        ref_layout = QFormLayout(ref_group)

        # Shape Set dropdown
        self.shape_set_combo = QComboBox()
        self.shape_set_combo.setEditable(True)
        self.shape_set_combo.setPlaceholderText("Shape set name from shapes.xml")
        self.shape_set_combo.currentTextChanged.connect(self._on_shape_set_changed)
        ref_layout.addRow("Shape Set:", self.shape_set_combo)

        # Shape Name dropdown (updates based on selected shape set)
        self.shape_name_combo = QComboBox()
        self.shape_name_combo.setEditable(True)
        self.shape_name_combo.setPlaceholderText("Shape name from shapes.xml")
        self.shape_name_combo.currentTextChanged.connect(self._on_modified)
        ref_layout.addRow("Shape Name:", self.shape_name_combo)

        # Renderer Set dropdown
        self.renderer_set_combo = QComboBox()
        self.renderer_set_combo.setEditable(True)
        self.renderer_set_combo.setPlaceholderText("RendererSet name from rendering.xml")
        self.renderer_set_combo.currentTextChanged.connect(self._on_modified)
        ref_layout.addRow("Renderer Set:", self.renderer_set_combo)

        # Refresh button for dropdowns
        refresh_layout = QHBoxLayout()
        self.refresh_refs_btn = QPushButton("Refresh Lists")
        self.refresh_refs_btn.clicked.connect(self._refresh_all_dropdowns)
        refresh_layout.addStretch()
        refresh_layout.addWidget(self.refresh_refs_btn)
        ref_layout.addRow("", refresh_layout)

        # Hidden animator combo — kept for backward compat, synced from animator_type_combo
        self.animator_combo = QComboBox()
        self.animator_combo.addItems(ANIMATOR_TYPES)
        self.animator_combo.setVisible(False)

        right_layout.addWidget(ref_group)

        # Position & Size
        pos_group = QGroupBox("Position && Size")
        pos_layout = QFormLayout(pos_group)

        # Location
        loc_layout = QHBoxLayout()
        self.loc_x_spin = QDoubleSpinBox()
        self.loc_x_spin.setRange(-200.0, 200.0)
        self.loc_x_spin.setDecimals(1)
        self.loc_x_spin.valueChanged.connect(self._on_modified)
        loc_layout.addWidget(QLabel("X:"))
        loc_layout.addWidget(self.loc_x_spin)

        self.loc_y_spin = QDoubleSpinBox()
        self.loc_y_spin.setRange(-200.0, 200.0)
        self.loc_y_spin.setDecimals(1)
        self.loc_y_spin.valueChanged.connect(self._on_modified)
        loc_layout.addWidget(QLabel("Y:"))
        loc_layout.addWidget(self.loc_y_spin)
        pos_layout.addRow("Location (%):", loc_layout)

        # Size
        size_layout = QHBoxLayout()
        self.size_x_spin = QDoubleSpinBox()
        self.size_x_spin.setRange(0.001, 10.0)
        self.size_x_spin.setDecimals(3)
        self.size_x_spin.setSingleStep(0.1)
        self.size_x_spin.setValue(1.0)
        self.size_x_spin.valueChanged.connect(self._on_modified)
        size_layout.addWidget(QLabel("X:"))
        size_layout.addWidget(self.size_x_spin)

        self.size_y_spin = QDoubleSpinBox()
        self.size_y_spin.setRange(0.001, 10.0)
        self.size_y_spin.setDecimals(3)
        self.size_y_spin.setSingleStep(0.1)
        self.size_y_spin.setValue(1.0)
        self.size_y_spin.valueChanged.connect(self._on_modified)
        size_layout.addWidget(QLabel("Y:"))
        size_layout.addWidget(self.size_y_spin)
        pos_layout.addRow("Size Factor:", size_layout)

        # Rotation
        self.start_rot_spin = QDoubleSpinBox()
        self.start_rot_spin.setRange(-360.0, 360.0)
        self.start_rot_spin.setDecimals(1)
        self.start_rot_spin.valueChanged.connect(self._on_modified)
        pos_layout.addRow("Start Rotation:", self.start_rot_spin)

        # Rotation offset
        rot_off_layout = QHBoxLayout()
        self.rot_off_x_spin = QDoubleSpinBox()
        self.rot_off_x_spin.setRange(-10.0, 10.0)
        self.rot_off_x_spin.setDecimals(3)
        self.rot_off_x_spin.valueChanged.connect(self._on_modified)
        rot_off_layout.addWidget(QLabel("X:"))
        rot_off_layout.addWidget(self.rot_off_x_spin)

        self.rot_off_y_spin = QDoubleSpinBox()
        self.rot_off_y_spin.setRange(-10.0, 10.0)
        self.rot_off_y_spin.setDecimals(3)
        self.rot_off_y_spin.valueChanged.connect(self._on_modified)
        rot_off_layout.addWidget(QLabel("Y:"))
        rot_off_layout.addWidget(self.rot_off_y_spin)
        pos_layout.addRow("Rotation Offset:", rot_off_layout)

        right_layout.addWidget(pos_group)

        # Animation
        anim_group = QGroupBox("Animation")
        anim_outer_layout = QVBoxLayout(anim_group)

        # Animator type selector
        type_layout = QHBoxLayout()
        type_layout.addWidget(QLabel("Mode:"))
        self.animator_type_combo = QComboBox()
        self.animator_type_combo.addItems(ANIMATOR_TYPES)
        self.animator_type_combo.setToolTip(
            "random: per-frame jitter using base factors + random ranges\n"
            "keyframe: interpolate between defined keyframes with easing\n"
            "jitter_morph: per-frame random morph between base and target shape\n"
            "keyframe_morph: keyframe animation with morph target interpolation"
        )
        self.animator_type_combo.currentTextChanged.connect(self._on_animator_type_changed)
        type_layout.addWidget(self.animator_type_combo)
        type_layout.addStretch()
        anim_outer_layout.addLayout(type_layout)

        # Total draws (shared between both modes)
        td_layout = QHBoxLayout()
        td_layout.addWidget(QLabel("Total Draws:"))
        self.total_draws_spin = QSpinBox()
        self.total_draws_spin.setRange(0, 100000)
        self.total_draws_spin.setValue(0)
        self.total_draws_spin.setSpecialValueText("Infinite")
        self.total_draws_spin.setToolTip(
            "Number of draw cycles before stopping.\n"
            "0 = infinite (draw forever)."
        )
        self.total_draws_spin.valueChanged.connect(self._on_modified)
        td_layout.addWidget(self.total_draws_spin)
        td_layout.addStretch()
        anim_outer_layout.addLayout(td_layout)

        # === Random jitter panel ===
        self.random_panel = QWidget()
        random_layout = QFormLayout(self.random_panel)
        random_layout.setContentsMargins(0, 0, 0, 0)

        # Jitter mode checkbox
        self.jitter_check = QCheckBox()
        self.jitter_check.setToolTip(
            "Jitter mode: each frame oscillates around the home position.\n"
            "Off: transforms accumulate (random walk / drift).\n"
            "On: previous frame's transform is undone before applying a new random offset."
        )
        self.jitter_check.stateChanged.connect(self._on_modified)
        random_layout.addRow("Jitter:", self.jitter_check)

        # Scale factor
        scale_layout = QHBoxLayout()
        self.scale_x_spin = QDoubleSpinBox()
        self.scale_x_spin.setRange(0.001, 10.0)
        self.scale_x_spin.setDecimals(3)
        self.scale_x_spin.setSingleStep(0.01)
        self.scale_x_spin.setValue(1.0)
        self.scale_x_spin.valueChanged.connect(self._on_modified)
        self.scale_x_spin.setToolTip("Base scale multiplier. Combined with ScaleRange for random jitter each frame.")
        scale_layout.addWidget(QLabel("X:"))
        scale_layout.addWidget(self.scale_x_spin)

        self.scale_y_spin = QDoubleSpinBox()
        self.scale_y_spin.setRange(0.001, 10.0)
        self.scale_y_spin.setDecimals(3)
        self.scale_y_spin.setSingleStep(0.01)
        self.scale_y_spin.setValue(1.0)
        self.scale_y_spin.valueChanged.connect(self._on_modified)
        self.scale_y_spin.setToolTip("Base scale multiplier. Combined with ScaleRange for random jitter each frame.")
        scale_layout.addWidget(QLabel("Y:"))
        scale_layout.addWidget(self.scale_y_spin)
        random_layout.addRow("Scale Factor:", scale_layout)

        # Rotation factor
        self.rot_factor_spin = QDoubleSpinBox()
        self.rot_factor_spin.setRange(-360.0, 360.0)
        self.rot_factor_spin.setDecimals(2)
        self.rot_factor_spin.setToolTip("Base rotation value. Combined with RotationRange for random jitter each frame.")
        self.rot_factor_spin.valueChanged.connect(self._on_modified)
        random_layout.addRow("Rotation Factor:", self.rot_factor_spin)

        # Speed factor
        speed_layout = QHBoxLayout()
        self.speed_x_spin = QDoubleSpinBox()
        self.speed_x_spin.setRange(-100.0, 100.0)
        self.speed_x_spin.setDecimals(3)
        self.speed_x_spin.setToolTip("Base translation speed. Combined with TranslationRange for random jitter each frame.")
        self.speed_x_spin.valueChanged.connect(self._on_modified)
        speed_layout.addWidget(QLabel("X:"))
        speed_layout.addWidget(self.speed_x_spin)

        self.speed_y_spin = QDoubleSpinBox()
        self.speed_y_spin.setRange(-100.0, 100.0)
        self.speed_y_spin.setDecimals(3)
        self.speed_y_spin.setToolTip("Base translation speed. Combined with TranslationRange for random jitter each frame.")
        self.speed_y_spin.valueChanged.connect(self._on_modified)
        speed_layout.addWidget(QLabel("Y:"))
        speed_layout.addWidget(self.speed_y_spin)
        random_layout.addRow("Speed Factor:", speed_layout)

        # --- Random Ranges ---
        random_layout.addRow(QLabel("--- Random Ranges ---"))

        # Scale Range
        sr_x_layout = QHBoxLayout()
        sr_x_layout.addWidget(QLabel("Min:"))
        self.scale_range_x_min_spin = QDoubleSpinBox()
        self.scale_range_x_min_spin.setRange(-10.0, 10.0)
        self.scale_range_x_min_spin.setDecimals(4)
        self.scale_range_x_min_spin.setSingleStep(0.001)
        self.scale_range_x_min_spin.valueChanged.connect(self._on_modified)
        sr_x_layout.addWidget(self.scale_range_x_min_spin)
        sr_x_layout.addWidget(QLabel("Max:"))
        self.scale_range_x_max_spin = QDoubleSpinBox()
        self.scale_range_x_max_spin.setRange(-10.0, 10.0)
        self.scale_range_x_max_spin.setDecimals(4)
        self.scale_range_x_max_spin.setSingleStep(0.001)
        self.scale_range_x_max_spin.valueChanged.connect(self._on_modified)
        sr_x_layout.addWidget(self.scale_range_x_max_spin)
        random_layout.addRow("Scale Range X:", sr_x_layout)

        sr_y_layout = QHBoxLayout()
        sr_y_layout.addWidget(QLabel("Min:"))
        self.scale_range_y_min_spin = QDoubleSpinBox()
        self.scale_range_y_min_spin.setRange(-10.0, 10.0)
        self.scale_range_y_min_spin.setDecimals(4)
        self.scale_range_y_min_spin.setSingleStep(0.001)
        self.scale_range_y_min_spin.valueChanged.connect(self._on_modified)
        sr_y_layout.addWidget(self.scale_range_y_min_spin)
        sr_y_layout.addWidget(QLabel("Max:"))
        self.scale_range_y_max_spin = QDoubleSpinBox()
        self.scale_range_y_max_spin.setRange(-10.0, 10.0)
        self.scale_range_y_max_spin.setDecimals(4)
        self.scale_range_y_max_spin.setSingleStep(0.001)
        self.scale_range_y_max_spin.valueChanged.connect(self._on_modified)
        sr_y_layout.addWidget(self.scale_range_y_max_spin)
        random_layout.addRow("Scale Range Y:", sr_y_layout)

        # Rotation Range
        rr_layout = QHBoxLayout()
        rr_layout.addWidget(QLabel("Min:"))
        self.rotation_range_min_spin = QDoubleSpinBox()
        self.rotation_range_min_spin.setRange(-360.0, 360.0)
        self.rotation_range_min_spin.setDecimals(3)
        self.rotation_range_min_spin.setSingleStep(0.1)
        self.rotation_range_min_spin.valueChanged.connect(self._on_modified)
        rr_layout.addWidget(self.rotation_range_min_spin)
        rr_layout.addWidget(QLabel("Max:"))
        self.rotation_range_max_spin = QDoubleSpinBox()
        self.rotation_range_max_spin.setRange(-360.0, 360.0)
        self.rotation_range_max_spin.setDecimals(3)
        self.rotation_range_max_spin.setSingleStep(0.1)
        self.rotation_range_max_spin.valueChanged.connect(self._on_modified)
        rr_layout.addWidget(self.rotation_range_max_spin)
        random_layout.addRow("Rotation Range:", rr_layout)

        # Translation Range
        tr_x_layout = QHBoxLayout()
        tr_x_layout.addWidget(QLabel("Min:"))
        self.translation_range_x_min_spin = QDoubleSpinBox()
        self.translation_range_x_min_spin.setRange(-100.0, 100.0)
        self.translation_range_x_min_spin.setDecimals(3)
        self.translation_range_x_min_spin.setSingleStep(0.1)
        self.translation_range_x_min_spin.valueChanged.connect(self._on_modified)
        tr_x_layout.addWidget(self.translation_range_x_min_spin)
        tr_x_layout.addWidget(QLabel("Max:"))
        self.translation_range_x_max_spin = QDoubleSpinBox()
        self.translation_range_x_max_spin.setRange(-100.0, 100.0)
        self.translation_range_x_max_spin.setDecimals(3)
        self.translation_range_x_max_spin.setSingleStep(0.1)
        self.translation_range_x_max_spin.valueChanged.connect(self._on_modified)
        tr_x_layout.addWidget(self.translation_range_x_max_spin)
        random_layout.addRow("Translation Range X:", tr_x_layout)

        tr_y_layout = QHBoxLayout()
        tr_y_layout.addWidget(QLabel("Min:"))
        self.translation_range_y_min_spin = QDoubleSpinBox()
        self.translation_range_y_min_spin.setRange(-100.0, 100.0)
        self.translation_range_y_min_spin.setDecimals(3)
        self.translation_range_y_min_spin.setSingleStep(0.1)
        self.translation_range_y_min_spin.valueChanged.connect(self._on_modified)
        tr_y_layout.addWidget(self.translation_range_y_min_spin)
        tr_y_layout.addWidget(QLabel("Max:"))
        self.translation_range_y_max_spin = QDoubleSpinBox()
        self.translation_range_y_max_spin.setRange(-100.0, 100.0)
        self.translation_range_y_max_spin.setDecimals(3)
        self.translation_range_y_max_spin.setSingleStep(0.1)
        self.translation_range_y_max_spin.valueChanged.connect(self._on_modified)
        tr_y_layout.addWidget(self.translation_range_y_max_spin)
        random_layout.addRow("Translation Range Y:", tr_y_layout)

        anim_outer_layout.addWidget(self.random_panel)

        # === Morph target panel (shown for jitter_morph and keyframe_morph) ===
        self.morph_panel = QGroupBox("Morph Targets")
        morph_outer = QVBoxLayout(self.morph_panel)
        morph_outer.setContentsMargins(4, 4, 4, 4)

        morph_outer.addWidget(QLabel(
            "Chain: base → mt1 → mt2 → …  (morphAmount 0 = base, 1 = mt1, 2 = mt2, …)"
        ))

        self.morph_list = QListWidget()
        self.morph_list.setMaximumHeight(100)
        self.morph_list.setToolTip(
            "Morph target chain. Files must be in morphTargets/.\n"
            "Use .poly.xml for polygon sets, .curve.xml for open curve sets."
        )
        morph_outer.addWidget(self.morph_list)

        # Row 1: creation buttons
        mt_create_layout = QHBoxLayout()
        self.create_morph_btn = QPushButton("Create")
        self.create_morph_btn.setToolTip(
            "Create the next morph target.\n"
            "If the chain is non-empty: copies the last target as the new starting point.\n"
            "If the chain is empty: opens a file picker to choose the base shape."
        )
        self.create_morph_btn.clicked.connect(self._create_morph_default)
        mt_create_layout.addWidget(self.create_morph_btn)

        self.create_morph_from_base_btn = QPushButton("From Base")
        self.create_morph_from_base_btn.setToolTip(
            "Create a morph target by copying the base shape file.\n"
            "Opens a file picker in polygonSets/ or curveSets/."
        )
        self.create_morph_from_base_btn.clicked.connect(self._create_from_base)
        mt_create_layout.addWidget(self.create_morph_from_base_btn)

        self.add_morph_btn = QPushButton("Add File")
        self.add_morph_btn.setToolTip("Reference an existing file in morphTargets/ without creating a copy")
        self.add_morph_btn.clicked.connect(self._add_morph_target)
        mt_create_layout.addWidget(self.add_morph_btn)

        mt_create_layout.addStretch()
        morph_outer.addLayout(mt_create_layout)

        # Row 2: management buttons
        mt_btn_layout = QHBoxLayout()

        self.remove_morph_btn = QPushButton("Remove")
        self.remove_morph_btn.setToolTip("Remove the selected morph target from the chain")
        self.remove_morph_btn.clicked.connect(self._remove_morph_target)
        mt_btn_layout.addWidget(self.remove_morph_btn)

        self.morph_up_btn = QPushButton("↑")
        self.morph_up_btn.setMaximumWidth(30)
        self.morph_up_btn.clicked.connect(self._morph_move_up)
        mt_btn_layout.addWidget(self.morph_up_btn)

        self.morph_down_btn = QPushButton("↓")
        self.morph_down_btn.setMaximumWidth(30)
        self.morph_down_btn.clicked.connect(self._morph_move_down)
        mt_btn_layout.addWidget(self.morph_down_btn)

        self.edit_morph_btn = QPushButton("Edit in Bezier")
        self.edit_morph_btn.setToolTip(
            "Open the selected morph target in Bezier for editing.\n"
            "Changes are saved back automatically when Bezier closes."
        )
        self.edit_morph_btn.clicked.connect(self._edit_morph_target)
        mt_btn_layout.addWidget(self.edit_morph_btn)

        mt_btn_layout.addStretch()
        morph_outer.addLayout(mt_btn_layout)

        # Morph min/max (shown for jitter_morph only)
        self.morph_range_widget = QWidget()
        morph_range_layout = QFormLayout(self.morph_range_widget)
        morph_range_layout.setContentsMargins(0, 0, 0, 0)

        morph_min_max_layout = QHBoxLayout()
        morph_min_max_layout.addWidget(QLabel("Min:"))
        self.morph_min_spin = QDoubleSpinBox()
        self.morph_min_spin.setRange(0.0, 100.0)
        self.morph_min_spin.setDecimals(3)
        self.morph_min_spin.setSingleStep(0.05)
        self.morph_min_spin.setValue(0.0)
        self.morph_min_spin.setToolTip("Minimum morph amount (0 = base shape)")
        self.morph_min_spin.valueChanged.connect(self._on_modified)
        morph_min_max_layout.addWidget(self.morph_min_spin)

        morph_min_max_layout.addWidget(QLabel("Max:"))
        self.morph_max_spin = QDoubleSpinBox()
        self.morph_max_spin.setRange(0.0, 100.0)
        self.morph_max_spin.setDecimals(3)
        self.morph_max_spin.setSingleStep(0.05)
        self.morph_max_spin.setValue(1.0)
        self.morph_max_spin.setToolTip("Maximum morph amount (N = full last target, where N = number of targets)")
        self.morph_max_spin.valueChanged.connect(self._on_modified)
        morph_min_max_layout.addWidget(self.morph_max_spin)
        morph_range_layout.addRow("Morph Range:", morph_min_max_layout)

        morph_outer.addWidget(self.morph_range_widget)

        self.morph_panel.setVisible(False)
        anim_outer_layout.addWidget(self.morph_panel)

        # === Keyframe panel ===
        self.keyframe_panel = QWidget()
        kf_layout = QVBoxLayout(self.keyframe_panel)
        kf_layout.setContentsMargins(0, 0, 0, 0)

        # Loop mode
        loop_layout = QHBoxLayout()
        loop_layout.addWidget(QLabel("Loop Mode:"))
        self.loop_mode_combo = QComboBox()
        self.loop_mode_combo.addItems(LOOP_MODES)
        self.loop_mode_combo.setToolTip(
            "NONE: stop at last keyframe\n"
            "LOOP: restart from first keyframe\n"
            "PING_PONG: reverse direction at endpoints"
        )
        self.loop_mode_combo.currentTextChanged.connect(self._on_modified)
        loop_layout.addWidget(self.loop_mode_combo)
        loop_layout.addStretch()
        kf_layout.addLayout(loop_layout)

        # Keyframe table
        self.kf_table = QTableWidget()
        self.kf_table.setColumnCount(7)
        self.kf_table.setHorizontalHeaderLabels([
            "Draw Cycle", "Pos X", "Pos Y", "Scale X", "Scale Y", "Rotation", "Easing"
        ])
        header = self.kf_table.horizontalHeader()
        for col in range(6):
            header.setSectionResizeMode(col, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(6, QHeaderView.ResizeMode.Stretch)
        self.kf_table.setMinimumHeight(150)
        self.kf_table.cellChanged.connect(self._on_kf_cell_changed)
        kf_layout.addWidget(self.kf_table)

        # Keyframe buttons
        kf_btn_layout = QHBoxLayout()
        self.kf_add_btn = QPushButton("Add")
        self.kf_add_btn.clicked.connect(self._add_keyframe)
        kf_btn_layout.addWidget(self.kf_add_btn)

        self.kf_remove_btn = QPushButton("Remove")
        self.kf_remove_btn.clicked.connect(self._remove_keyframe)
        kf_btn_layout.addWidget(self.kf_remove_btn)

        self.kf_duplicate_btn = QPushButton("Duplicate")
        self.kf_duplicate_btn.clicked.connect(self._duplicate_keyframe)
        kf_btn_layout.addWidget(self.kf_duplicate_btn)

        self.kf_copy_btn = QPushButton("Copy From...")
        self.kf_copy_btn.clicked.connect(self._copy_keyframes_from_sprite)
        kf_btn_layout.addWidget(self.kf_copy_btn)

        kf_btn_layout.addStretch()
        kf_layout.addLayout(kf_btn_layout)

        anim_outer_layout.addWidget(self.keyframe_panel)

        # Start with keyframe panel hidden
        self.keyframe_panel.setVisible(False)

        anim_layout.addWidget(anim_group)

        gen_layout.addStretch()
        anim_layout.addStretch()

        splitter.addWidget(right_panel)
        splitter.setSizes([280, 520])

    def _refresh_tree(self):
        """Refresh the sprite tree."""
        self._checking = True
        self.tree.clear()
        for sprite_set in self._library.sprite_sets:
            set_item = QTreeWidgetItem(["", sprite_set.name, "", ""])
            set_item.setData(0, Qt.ItemDataRole.UserRole, ("set", sprite_set))

            for sprite in sprite_set.sprites:
                sprite_item = QTreeWidgetItem(["", sprite.name, "", ""])
                sprite_item.setData(0, Qt.ItemDataRole.UserRole, ("sprite", sprite))
                sprite_item.setFlags(sprite_item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
                sprite_item.setCheckState(0, Qt.CheckState.Unchecked)
                sprite_item.setCheckState(2, Qt.CheckState.Checked if sprite.enabled else Qt.CheckState.Unchecked)
                sprite_item.setCheckState(3, Qt.CheckState.Checked if sprite.params.animation_enabled else Qt.CheckState.Unchecked)
                set_item.addChild(sprite_item)

            self.tree.addTopLevelItem(set_item)
            set_item.setExpanded(True)
        self._checking = False

        if self.tree.topLevelItemCount() > 0:
            first = self.tree.topLevelItem(0)
            if first.childCount() > 0:
                self.tree.setCurrentItem(first.child(0))
            else:
                self.tree.setCurrentItem(first)

    def _on_item_selected(self, current, previous):
        """Handle tree item selection."""
        if current is None:
            self._current_set = None
            self._current_sprite = None
            return

        data = current.data(0, Qt.ItemDataRole.UserRole)
        if data is None:
            return

        item_type, item_obj = data

        if item_type == "set":
            self._current_set = item_obj
            self._current_sprite = None
            self._clear_sprite_ui()
        else:
            self._current_sprite = item_obj
            parent = current.parent()
            if parent:
                parent_data = parent.data(0, Qt.ItemDataRole.UserRole)
                if parent_data:
                    self._current_set = parent_data[1]
            self._load_sprite_to_ui(self._current_sprite)
            if parent:
                sprite_set = parent.data(0, Qt.ItemDataRole.UserRole)[1]
                idx = parent.indexOfChild(current)
                self.preview_widget.set_sprite_set(sprite_set, idx)

    def _clear_sprite_ui(self):
        """Clear the sprite editor UI."""
        self._updating = True
        try:
            self.name_edit.clear()
            self.shape_set_combo.setCurrentText("")
            self.shape_name_combo.setCurrentText("")
            self.renderer_set_combo.setCurrentText("")
            self.animator_combo.setCurrentIndex(0)
            self.loc_x_spin.setValue(0)
            self.loc_y_spin.setValue(0)
            self.size_x_spin.setValue(1)
            self.size_y_spin.setValue(1)
            self.start_rot_spin.setValue(0)
            self.rot_off_x_spin.setValue(0)
            self.rot_off_y_spin.setValue(0)
            self.animator_type_combo.setCurrentText("random")
            self.total_draws_spin.setValue(0)
            self.scale_x_spin.setValue(1)
            self.scale_y_spin.setValue(1)
            self.rot_factor_spin.setValue(0)
            self.speed_x_spin.setValue(0)
            self.speed_y_spin.setValue(0)
            self.loop_mode_combo.setCurrentText("NONE")
            self._clear_kf_table()
            self.morph_list.clear()
            self.morph_min_spin.setValue(0.0)
            self.morph_max_spin.setValue(1.0)
            self._update_animator_panels()
        finally:
            self._updating = False

    def _load_sprite_to_ui(self, sprite: SpriteDef):
        """Load a sprite's values into the UI."""
        self._updating = True
        try:
            self.name_edit.setText(sprite.name)

            # References
            self.shape_set_combo.setCurrentText(sprite.shape_set_name)
            self._update_shape_names_dropdown()  # Update shape names for selected set
            self.shape_name_combo.setCurrentText(sprite.shape_name)
            self.renderer_set_combo.setCurrentText(sprite.renderer_set_name)

            idx = self.animator_combo.findText(sprite.animator_type)
            if idx >= 0:
                self.animator_combo.setCurrentIndex(idx)
            else:
                self.animator_combo.setCurrentIndex(0)

            # Params
            p = sprite.params
            self.loc_x_spin.setValue(p.location_x)
            self.loc_y_spin.setValue(p.location_y)
            self.size_x_spin.setValue(p.size_x)
            self.size_y_spin.setValue(p.size_y)
            self.start_rot_spin.setValue(p.start_rotation)
            self.rot_off_x_spin.setValue(p.rot_offset_x)
            self.rot_off_y_spin.setValue(p.rot_offset_y)

            # Animation mode
            anim_type = sprite.animator_type if sprite.animator_type in ANIMATOR_TYPES else "random"
            self.animator_type_combo.setCurrentText(anim_type)
            self.total_draws_spin.setValue(p.total_draws)

            # Random jitter fields
            self.jitter_check.setChecked(p.jitter)
            self.scale_x_spin.setValue(p.scale_factor_x)
            self.scale_y_spin.setValue(p.scale_factor_y)
            self.rot_factor_spin.setValue(p.rotation_factor)
            self.speed_x_spin.setValue(p.speed_factor_x)
            self.speed_y_spin.setValue(p.speed_factor_y)

            # Random ranges
            self.scale_range_x_min_spin.setValue(p.scale_range_x_min)
            self.scale_range_x_max_spin.setValue(p.scale_range_x_max)
            self.scale_range_y_min_spin.setValue(p.scale_range_y_min)
            self.scale_range_y_max_spin.setValue(p.scale_range_y_max)
            self.rotation_range_min_spin.setValue(p.rotation_range_min)
            self.rotation_range_max_spin.setValue(p.rotation_range_max)
            self.translation_range_x_min_spin.setValue(p.translation_range_x_min)
            self.translation_range_x_max_spin.setValue(p.translation_range_x_max)
            self.translation_range_y_min_spin.setValue(p.translation_range_y_min)
            self.translation_range_y_max_spin.setValue(p.translation_range_y_max)

            # Keyframe fields
            self.loop_mode_combo.setCurrentText(p.loop_mode or "NONE")
            self._load_keyframes_to_table(p.keyframes)

            # Morph target fields
            self.morph_list.clear()
            for ref in p.morph_targets:
                self.morph_list.addItem(ref.file if not ref.name else f"{ref.file}  [{ref.name}]")
            self.morph_min_spin.setValue(p.morph_min)
            self.morph_max_spin.setValue(p.morph_max)

            self._update_animator_panels()
        finally:
            self._updating = False
        self._update_preview_keyframes()

    def _save_ui_to_sprite(self):
        """Save UI values back to the current sprite."""
        if self._current_sprite is None:
            return

        self._current_sprite.name = self.name_edit.text()
        # sprite.enabled is managed by tree col 2 checkbox — not saved here

        # References
        self._current_sprite.shape_set_name = self.shape_set_combo.currentText()
        self._current_sprite.shape_name = self.shape_name_combo.currentText()
        self._current_sprite.renderer_set_name = self.renderer_set_combo.currentText()

        # Animator type from the animation mode combo (not the old references combo)
        self._current_sprite.animator_type = self.animator_type_combo.currentText()

        # Params
        p = self._current_sprite.params
        p.location_x = self.loc_x_spin.value()
        p.location_y = self.loc_y_spin.value()
        p.size_x = self.size_x_spin.value()
        p.size_y = self.size_y_spin.value()
        p.start_rotation = self.start_rot_spin.value()
        p.rot_offset_x = self.rot_off_x_spin.value()
        p.rot_offset_y = self.rot_off_y_spin.value()
        p.total_draws = self.total_draws_spin.value()

        # Random jitter fields
        p.jitter = self.jitter_check.isChecked()
        p.scale_factor_x = self.scale_x_spin.value()
        p.scale_factor_y = self.scale_y_spin.value()
        p.rotation_factor = self.rot_factor_spin.value()
        p.speed_factor_x = self.speed_x_spin.value()
        p.speed_factor_y = self.speed_y_spin.value()

        # Random ranges
        p.scale_range_x_min = self.scale_range_x_min_spin.value()
        p.scale_range_x_max = self.scale_range_x_max_spin.value()
        p.scale_range_y_min = self.scale_range_y_min_spin.value()
        p.scale_range_y_max = self.scale_range_y_max_spin.value()
        p.rotation_range_min = self.rotation_range_min_spin.value()
        p.rotation_range_max = self.rotation_range_max_spin.value()
        p.translation_range_x_min = self.translation_range_x_min_spin.value()
        p.translation_range_x_max = self.translation_range_x_max_spin.value()
        p.translation_range_y_min = self.translation_range_y_min_spin.value()
        p.translation_range_y_max = self.translation_range_y_max_spin.value()

        # Keyframe fields
        p.loop_mode = self.loop_mode_combo.currentText()
        p.keyframes = self._read_keyframes_from_table()

        # Morph target fields
        p.morph_targets = self._read_morph_list()
        p.morph_min = self.morph_min_spin.value()
        p.morph_max = self.morph_max_spin.value()

        # Update tree item
        current_item = self.tree.currentItem()
        if current_item:
            current_item.setText(1, self._current_sprite.name)

        # Sync preview
        if self._current_sprite is not None:
            self._sync_preview_selection()

    def _on_name_changed(self):
        if self._updating:
            return
        self._save_ui_to_sprite()
        self.modified.emit()

    def _on_modified(self):
        if self._updating:
            return
        self._save_ui_to_sprite()
        self.modified.emit()

    def _add_set(self):
        """Add a new sprite set."""
        name, ok = QInputDialog.getText(self, "Add Sprite Set", "Name:")
        if ok and name:
            if self._library.get(name):
                QMessageBox.warning(self, "Duplicate Name", f"A sprite set named '{name}' already exists.")
                return
            new_set = SpriteSet(name=name)
            self._library.add(new_set)
            self._refresh_tree()
            for i in range(self.tree.topLevelItemCount()):
                if self.tree.topLevelItem(i).text(0) == name:
                    self.tree.setCurrentItem(self.tree.topLevelItem(i))
                    break
            self.modified.emit()

    def _remove_set(self):
        """Remove the selected sprite set."""
        if self._current_set is None:
            return
        result = QMessageBox.question(
            self, "Remove Sprite Set",
            f"Remove sprite set '{self._current_set.name}' and all its sprites?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result == QMessageBox.StandardButton.Yes:
            for i, s in enumerate(self._library.sprite_sets):
                if s.name == self._current_set.name:
                    self._library.remove(i)
                    break
            self._current_set = None
            self._current_sprite = None
            self._refresh_tree()
            self.modified.emit()

    def _add_sprite(self):
        """Add a new sprite to the current set."""
        if self._current_set is None:
            QMessageBox.warning(self, "No Set Selected", "Please select a sprite set first.")
            return
        name, ok = QInputDialog.getText(self, "Add Sprite", "Name:")
        if ok and name:
            if self._current_set.get(name):
                QMessageBox.warning(self, "Duplicate Name", f"A sprite named '{name}' already exists in this set.")
                return
            new_sprite = SpriteDef(name=name)
            self._current_set.add(new_sprite)
            self._refresh_tree()
            self._select_sprite(self._current_set.name, name)
            self.modified.emit()

    def _remove_sprite(self):
        """Remove the selected sprite."""
        if self._current_sprite is None or self._current_set is None:
            return
        result = QMessageBox.question(
            self, "Remove Sprite",
            f"Remove sprite '{self._current_sprite.name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result == QMessageBox.StandardButton.Yes:
            for i, s in enumerate(self._current_set.sprites):
                if s.name == self._current_sprite.name:
                    self._current_set.remove(i)
                    break
            self._current_sprite = None
            self._refresh_tree()
            self.modified.emit()

    def _duplicate_sprite(self):
        """Duplicate the selected sprite."""
        if self._current_sprite is None or self._current_set is None:
            return
        base_name = self._current_sprite.name
        counter = 1
        while True:
            new_name = f"{base_name}_{counter:03d}"
            if not self._current_set.get(new_name):
                break
            counter += 1

        from dataclasses import replace
        from copy import deepcopy
        new_params = replace(self._current_sprite.params,
                             keyframes=[kf.copy() for kf in self._current_sprite.params.keyframes])
        new_sprite = replace(self._current_sprite, name=new_name, params=new_params)

        self._current_set.add(new_sprite)
        self._refresh_tree()
        self._select_sprite(self._current_set.name, new_name)
        self.modified.emit()

    def _on_item_check_changed(self, item, column):
        """Handle checkbox toggle."""
        if self._checking:
            return
        data = item.data(0, Qt.ItemDataRole.UserRole)
        if data is None or data[0] != "sprite":
            return
        sprite = data[1]
        checked = item.checkState(column) == Qt.CheckState.Checked
        if column == 2:  # Enabled
            sprite.enabled = checked
            self.modified.emit()
        elif column == 3:  # Anim
            sprite.params.animation_enabled = checked
            self.modified.emit()

    def _delete_selected(self):
        """Delete all checked sprite items."""
        to_delete = []  # list of (sprite_set, sprite) tuples
        for i in range(self.tree.topLevelItemCount()):
            set_item = self.tree.topLevelItem(i)
            set_data = set_item.data(0, Qt.ItemDataRole.UserRole)
            if not set_data or set_data[0] != "set":
                continue
            sprite_set = set_data[1]
            for j in range(set_item.childCount()):
                sprite_item = set_item.child(j)
                if sprite_item.checkState(0) == Qt.CheckState.Checked:
                    data = sprite_item.data(0, Qt.ItemDataRole.UserRole)
                    if data and data[0] == "sprite":
                        to_delete.append((sprite_set, data[1]))

        if not to_delete:
            QMessageBox.information(self, "No Selection", "No items are checked for deletion.")
            return

        result = QMessageBox.question(
            self, "Delete Selected",
            f"Delete {len(to_delete)} checked sprite(s)?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result == QMessageBox.StandardButton.Yes:
            for sprite_set, sprite in to_delete:
                for idx, s in enumerate(sprite_set.sprites):
                    if s is sprite:
                        sprite_set.remove(idx)
                        break
            self._current_sprite = None
            self._clear_sprite_ui()
            self._refresh_tree()
            self.modified.emit()

    def _select_sprite(self, set_name: str, sprite_name: str):
        """Select a sprite in the tree."""
        for i in range(self.tree.topLevelItemCount()):
            set_item = self.tree.topLevelItem(i)
            if set_item.text(0) == set_name:
                for j in range(set_item.childCount()):
                    sprite_item = set_item.child(j)
                    if sprite_item.text(0) == sprite_name:
                        self.tree.setCurrentItem(sprite_item)
                        return

    def get_library(self) -> SpriteLibrary:
        """Get the current library."""
        return self._library

    def set_library(self, library: SpriteLibrary) -> None:
        """Set the library to display."""
        self._library = library
        self._refresh_tree()

    def create_default_library(self) -> SpriteLibrary:
        """Create a default library with one set and one sprite."""
        library = SpriteLibrary(name="MainLibrary")
        default_set = SpriteSet(name="default")
        default_sprite = SpriteDef(
            name="DefaultSprite",
            enabled=True,
            params=SpriteParams(size_x=0.7, size_y=0.7)
        )
        default_set.add(default_sprite)
        library.add(default_set)
        return library

    def set_shape_library(self, library) -> None:
        """Set the shape library for populating shape set and shape name dropdowns."""
        self._shape_library = library
        self._refresh_shape_set_dropdown()
        self.preview_widget.set_shape_library(library)

    def set_canvas_size(self, w: int, h: int) -> None:
        self.preview_widget.set_canvas_size(w, h)

    def set_renderer_library(self, library) -> None:
        """Set the renderer library for populating renderer set dropdown."""
        self._renderer_library = library
        self._refresh_renderer_set_dropdown()

    def _on_shape_set_changed(self, text: str) -> None:
        """Handle shape set selection change - update shape names dropdown."""
        self._update_shape_names_dropdown()
        if not self._updating:
            self._save_ui_to_sprite()
            self.modified.emit()

    def _refresh_all_dropdowns(self) -> None:
        """Refresh all reference dropdowns."""
        self._refresh_shape_set_dropdown()
        self._refresh_renderer_set_dropdown()

    def _refresh_shape_set_dropdown(self) -> None:
        """Refresh the shape set dropdown from the shape library."""
        # Block signals to prevent triggering _on_modified during refresh
        self._updating = True
        try:
            current_text = self.shape_set_combo.currentText()
            self.shape_set_combo.clear()

            if self._shape_library is not None:
                try:
                    if hasattr(self._shape_library, 'shape_sets'):
                        names = [ss.name for ss in self._shape_library.shape_sets]
                        names.sort()
                        self.shape_set_combo.addItems(names)
                except Exception:
                    pass

            if current_text:
                index = self.shape_set_combo.findText(current_text)
                if index >= 0:
                    self.shape_set_combo.setCurrentIndex(index)
                else:
                    self.shape_set_combo.setCurrentText(current_text)

            self._update_shape_names_dropdown()
        finally:
            self._updating = False

    def _update_shape_names_dropdown(self) -> None:
        """Update the shape names dropdown based on the selected shape set."""
        # Block signals to prevent triggering _on_modified during refresh
        was_updating = self._updating
        self._updating = True
        try:
            current_text = self.shape_name_combo.currentText()
            self.shape_name_combo.clear()

            if self._shape_library is not None:
                selected_set_name = self.shape_set_combo.currentText()
                if selected_set_name:
                    try:
                        # Find the shape set in the library
                        shape_set = self._shape_library.get(selected_set_name)
                        if shape_set and hasattr(shape_set, 'shapes'):
                            names = [s.name for s in shape_set.shapes]
                            names.sort()
                            self.shape_name_combo.addItems(names)
                    except Exception:
                        pass

            if current_text:
                index = self.shape_name_combo.findText(current_text)
                if index >= 0:
                    self.shape_name_combo.setCurrentIndex(index)
                else:
                    self.shape_name_combo.setCurrentText(current_text)
        finally:
            self._updating = was_updating

    def _refresh_renderer_set_dropdown(self) -> None:
        """Refresh the renderer set dropdown from the renderer library."""
        # Block signals to prevent triggering _on_modified during refresh
        self._updating = True
        try:
            current_text = self.renderer_set_combo.currentText()
            self.renderer_set_combo.clear()

            if self._renderer_library is not None:
                try:
                    if hasattr(self._renderer_library, 'renderer_sets'):
                        names = [rs.name for rs in self._renderer_library.renderer_sets]
                        names.sort()
                        self.renderer_set_combo.addItems(names)
                except Exception:
                    pass

            if current_text:
                index = self.renderer_set_combo.findText(current_text)
                if index >= 0:
                    self.renderer_set_combo.setCurrentIndex(index)
                else:
                    self.renderer_set_combo.setCurrentText(current_text)
        finally:
            self._updating = False

    # === Keyframe Animation Methods ===

    def _on_animator_type_changed(self, text: str) -> None:
        """Handle animator type combo change."""
        self._update_animator_panels()
        if not self._updating:
            self._save_ui_to_sprite()
            self.modified.emit()
            self._update_preview_keyframes()

    def _update_animator_panels(self) -> None:
        """Show/hide panels based on animator type."""
        anim_type = self.animator_type_combo.currentText()
        self.random_panel.setVisible(anim_type == "random")
        self.morph_panel.setVisible(anim_type in ("jitter_morph", "keyframe_morph"))
        self.morph_range_widget.setVisible(anim_type == "jitter_morph")
        self.keyframe_panel.setVisible(anim_type in ("keyframe", "keyframe_morph"))
        # Update keyframe table columns for morph amount
        self._update_kf_table_columns()

    def _clear_kf_table(self) -> None:
        """Clear the keyframe table."""
        self.kf_table.blockSignals(True)
        self.kf_table.setRowCount(0)
        self.kf_table.blockSignals(False)

    def _load_keyframes_to_table(self, keyframes: list) -> None:
        """Load keyframes into the table widget."""
        self.kf_table.blockSignals(True)
        self.kf_table.setRowCount(0)
        for kf in sorted(keyframes, key=lambda k: k.draw_cycle):
            self._add_kf_row(kf)
        self.kf_table.blockSignals(False)

    def _add_kf_row(self, kf: 'Keyframe') -> None:
        """Add a single keyframe row to the table."""
        row = self.kf_table.rowCount()
        self.kf_table.insertRow(row)
        has_morph_col = self.kf_table.columnCount() == 9

        # Draw Cycle (integer)
        dc_item = QTableWidgetItem(str(kf.draw_cycle))
        self.kf_table.setItem(row, 0, dc_item)

        # Numeric columns
        for col, val in [(1, kf.pos_x), (2, kf.pos_y),
                         (3, kf.scale_x), (4, kf.scale_y),
                         (5, kf.rotation)]:
            item = QTableWidgetItem(f"{val:.4g}")
            self.kf_table.setItem(row, col, item)

        if has_morph_col:
            # MT Idx (col 6): integer part of morphAmount (which target: 0=base, 1=mt1, 2=mt2…)
            mt_idx = int(kf.morph_amount)
            amount = kf.morph_amount - mt_idx
            self.kf_table.setItem(row, 6, QTableWidgetItem(str(mt_idx)))
            # Amount (col 7): fraction 0.0–1.0 blending toward next target
            self.kf_table.setItem(row, 7, QTableWidgetItem(f"{amount:.4g}"))

        # Easing combo (col 6 normally, col 8 when morph columns present)
        easing_col = 8 if has_morph_col else 6
        easing_combo = QComboBox()
        easing_combo.addItems(EASING_TYPES)
        idx = easing_combo.findText(kf.easing)
        if idx >= 0:
            easing_combo.setCurrentIndex(idx)
        easing_combo.currentTextChanged.connect(self._on_modified)
        self.kf_table.setCellWidget(row, easing_col, easing_combo)

    def _read_keyframes_from_table(self) -> list:
        """Read keyframes from the table widget."""
        keyframes = []
        has_morph_col = self.kf_table.columnCount() == 9
        easing_col = 8 if has_morph_col else 6

        for row in range(self.kf_table.rowCount()):
            try:
                dc_item = self.kf_table.item(row, 0)
                draw_cycle = int(dc_item.text()) if dc_item else 0

                def get_float(col, default=0.0):
                    item = self.kf_table.item(row, col)
                    if item:
                        try:
                            return float(item.text())
                        except ValueError:
                            return default
                    return default

                easing_widget = self.kf_table.cellWidget(row, easing_col)
                easing = easing_widget.currentText() if easing_widget else "LINEAR"

                if has_morph_col:
                    mt_idx = max(0, int(get_float(6, 0.0)))
                    amount = max(0.0, min(1.0, get_float(7, 0.0)))
                    morph_amount = mt_idx + amount
                else:
                    morph_amount = 0.0

                kf = Keyframe(
                    draw_cycle=draw_cycle,
                    pos_x=get_float(1, 0.0),
                    pos_y=get_float(2, 0.0),
                    scale_x=get_float(3, 1.0),
                    scale_y=get_float(4, 1.0),
                    rotation=get_float(5, 0.0),
                    easing=easing,
                    morph_amount=morph_amount,
                )
                keyframes.append(kf)
            except (ValueError, AttributeError):
                continue
        return sorted(keyframes, key=lambda k: k.draw_cycle)

    def _on_kf_cell_changed(self, row: int, column: int) -> None:
        """Handle keyframe table cell edit."""
        if self._updating:
            return
        self._save_ui_to_sprite()
        self.modified.emit()

    def _add_keyframe(self) -> None:
        """Add a new keyframe."""
        # Determine next draw cycle
        existing = self._read_keyframes_from_table()
        if existing:
            last_cycle = existing[-1].draw_cycle
            new_cycle = last_cycle + 50
        else:
            new_cycle = 0

        new_kf = Keyframe(draw_cycle=new_cycle)
        self.kf_table.blockSignals(True)
        self._add_kf_row(new_kf)
        self.kf_table.blockSignals(False)

        self._save_ui_to_sprite()
        self.modified.emit()
        self._update_preview_keyframes()

    def _remove_keyframe(self) -> None:
        """Remove the selected keyframe."""
        row = self.kf_table.currentRow()
        if row < 0:
            return
        self.kf_table.removeRow(row)
        self._save_ui_to_sprite()
        self.modified.emit()
        self._update_preview_keyframes()

    def _duplicate_keyframe(self) -> None:
        """Duplicate the selected keyframe with draw_cycle incremented."""
        row = self.kf_table.currentRow()
        if row < 0:
            return
        keyframes = self._read_keyframes_from_table()
        if row < len(keyframes):
            kf = keyframes[row].copy()
            kf.draw_cycle += 50
            self.kf_table.blockSignals(True)
            self._add_kf_row(kf)
            self.kf_table.blockSignals(False)
            self._save_ui_to_sprite()
            self.modified.emit()
            self._update_preview_keyframes()

    def _copy_keyframes_from_sprite(self) -> None:
        """Copy keyframes from another sprite via dialog."""
        if self._current_sprite is None:
            return

        # Collect all sprites except current
        all_sprites = []
        for ss in self._library.sprite_sets:
            for sp in ss.sprites:
                if sp is not self._current_sprite:
                    all_sprites.append((f"{ss.name}/{sp.name}", sp))

        if not all_sprites:
            QMessageBox.information(self, "No Sources", "No other sprites to copy from.")
            return

        dialog = CopyKeyframesDialog(all_sprites, self)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            source_sprite = dialog.selected_sprite()
            if source_sprite is None:
                return
            source_kfs = source_sprite.params.keyframes
            if not source_kfs:
                QMessageBox.information(self, "No Keyframes",
                                        f"Sprite '{source_sprite.name}' has no keyframes.")
                return

            copied = [kf.copy() for kf in source_kfs]

            if dialog.is_relative() and copied and self._current_sprite.params.keyframes:
                # Adjust positions relative to first keyframe difference
                src_first = source_kfs[0]
                dst_first = self._current_sprite.params.keyframes[0]
                dx = dst_first.pos_x - src_first.pos_x
                dy = dst_first.pos_y - src_first.pos_y
                for kf in copied:
                    kf.pos_x += dx
                    kf.pos_y += dy

            self._current_sprite.params.keyframes = copied
            self._load_keyframes_to_table(copied)
            self._save_ui_to_sprite()
            self.modified.emit()


    # === Morph Target Methods ===

    def set_project_dir(self, project_dir: str) -> None:
        """Set the project directory for morph target file operations."""
        self._project_dir = project_dir
        self.preview_widget.set_directories(
            os.path.join(project_dir, "polygonSets"),
            os.path.join(project_dir, "curveSets"),
            os.path.join(project_dir, "pointSets"),
        )

    def _on_preview_transform_changed(self, loc_x: float, loc_y: float,
                                       size_x: float, size_y: float,
                                       rotation: float):
        """Called when the user drags a sprite in the Preview canvas."""
        if self._current_sprite is None:
            return
        self._updating = True
        try:
            self.loc_x_spin.setValue(loc_x)
            self.loc_y_spin.setValue(loc_y)
            self.size_x_spin.setValue(size_x)
            self.size_y_spin.setValue(size_y)
            self.start_rot_spin.setValue(rotation)
        finally:
            self._updating = False
        self._save_ui_to_sprite()
        self.modified.emit()

    def _on_preview_kf_transform_changed(self, kf_row: int,
                                          loc_x: float, loc_y: float,
                                          size_x: float, size_y: float,
                                          rotation: float):
        """Called when the user drags a sprite in keyframe mode with Edit KF checked."""
        if self._current_sprite is None:
            return
        if kf_row < 0 or kf_row >= self.kf_table.rowCount():
            return
        self.kf_table.blockSignals(True)
        try:
            for col, val in [(1, loc_x), (2, loc_y), (3, size_x), (4, size_y), (5, rotation)]:
                item = self.kf_table.item(kf_row, col)
                if item is None:
                    from PyQt6.QtWidgets import QTableWidgetItem
                    item = QTableWidgetItem()
                    self.kf_table.setItem(kf_row, col, item)
                item.setText(f"{val:.4g}")
        finally:
            self.kf_table.blockSignals(False)
        self._current_sprite.params.keyframes = self._read_keyframes_from_table()
        self.modified.emit()

    def _update_preview_keyframes(self):
        """Push current sprite's keyframe data to the preview widget."""
        if self._current_sprite is None:
            self.preview_widget.set_keyframes([], "random", [])
            return
        p = self._current_sprite.params
        atype = self._current_sprite.animator_type
        self.preview_widget.set_keyframes(p.keyframes, atype, p.morph_targets)

    def _sync_preview_selection(self):
        """Repaint preview with updated params without re-resolving geometry."""
        sel = self.tree.currentItem()
        if sel and sel.parent():
            idx = sel.parent().indexOfChild(sel)
            self.preview_widget.set_selected_index(idx)

    def _get_morph_targets_dir(self) -> str:
        """Get the morphTargets/ directory path for the current project."""
        if hasattr(self, '_project_dir') and self._project_dir:
            return os.path.join(self._project_dir, "morphTargets")
        return ""

    def _read_morph_list(self):
        """Read MorphTargetRef list from the list widget."""
        refs = []
        for i in range(self.morph_list.count()):
            text = self.morph_list.item(i).text()
            # Strip optional display name suffix "  [name]"
            if "  [" in text and text.endswith("]"):
                file_part = text[:text.rindex("  [")]
                name_part = text[text.rindex("  [") + 3:-1]
            else:
                file_part = text
                name_part = ""
            refs.append(MorphTargetRef(file=file_part, name=name_part))
        return refs

    def _count_topology(self, file_path: str):
        """Return (poly_count, total_vertex_count) for a polygon/curve XML, or None on error."""
        try:
            from lxml import etree
            tree = etree.parse(file_path)
            root = tree.getroot()
            polys = root.findall(".//polygon") + root.findall(".//openCurve")
            poly_count = len(polys)
            vert_count = sum(
                len(p.findall("point")) + len(p.findall("pt"))
                for p in polys
            )
            return (poly_count, vert_count)
        except Exception:
            return None

    def _add_morph_target(self) -> None:
        """Browse for a morph target file and add it to the chain."""
        morph_dir = self._get_morph_targets_dir()
        if not morph_dir:
            QMessageBox.warning(self, "No Project", "No project directory set.")
            return
        os.makedirs(morph_dir, exist_ok=True)

        path, _ = QFileDialog.getOpenFileName(
            self, "Add Morph Target", morph_dir,
            "Morph Target Files (*.poly.xml *.curve.xml *.xml)"
        )
        if not path:
            return

        # Store only the filename (must be in morphTargets/)
        filename = os.path.basename(path)

        # Topology warning: compare against base shape if possible
        if self._current_sprite is not None and self._project_dir:
            base_file = self._resolve_base_shape_file()
            if base_file and os.path.isfile(base_file):
                base_topo = self._count_topology(base_file)
                tgt_topo = self._count_topology(path)
                if base_topo and tgt_topo and base_topo != tgt_topo:
                    QMessageBox.warning(
                        self, "Topology Mismatch",
                        f"The selected morph target has different topology from the base shape:\n"
                        f"  Base:   {base_topo[0]} polygons, {base_topo[1]} vertices\n"
                        f"  Target: {tgt_topo[0]} polygons, {tgt_topo[1]} vertices\n\n"
                        "The morph will still be added but may not render correctly."
                    )

        self.morph_list.addItem(filename)
        self._on_modified()

    def _remove_morph_target(self) -> None:
        """Remove the selected morph target from the chain."""
        row = self.morph_list.currentRow()
        if row < 0:
            return
        self.morph_list.takeItem(row)
        self._on_modified()

    def _morph_move_up(self) -> None:
        """Move the selected morph target up in the chain."""
        row = self.morph_list.currentRow()
        if row <= 0:
            return
        item = self.morph_list.takeItem(row)
        self.morph_list.insertItem(row - 1, item)
        self.morph_list.setCurrentRow(row - 1)
        self._on_modified()

    def _morph_move_down(self) -> None:
        """Move the selected morph target down in the chain."""
        row = self.morph_list.currentRow()
        if row < 0 or row >= self.morph_list.count() - 1:
            return
        item = self.morph_list.takeItem(row)
        self.morph_list.insertItem(row + 1, item)
        self.morph_list.setCurrentRow(row + 1)
        self._on_modified()

    def _resolve_base_shape_file(self) -> str:
        """Try to find the polygon/curve XML file for the current sprite's base shape."""
        if self._current_sprite is None or not self._project_dir:
            return ""
        shape_name = self._current_sprite.shape_name
        if not shape_name:
            return ""
        # Try polygonSets/ then curveSets/
        for subdir in ("polygonSets", "curveSets"):
            candidate = os.path.join(self._project_dir, subdir, shape_name)
            if os.path.isfile(candidate):
                return candidate
            candidate_xml = candidate if candidate.endswith(".xml") else candidate + ".xml"
            if os.path.isfile(candidate_xml):
                return candidate_xml
        return ""

    # === Morph target creation ===

    def _get_base_shape_source_type(self) -> str:
        """Return 'curve' if the current sprite's shape is an open curve set, else 'poly'."""
        if self._current_sprite is None or self._shape_library is None:
            return 'poly'
        sprite = self._current_sprite
        shape_set = self._shape_library.get(sprite.shape_set_name)
        if shape_set is None:
            return 'poly'
        for sd in shape_set.shapes:
            if sd.name == sprite.shape_name:
                from models.shape_config import ShapeSourceType
                if sd.source_type == ShapeSourceType.OPEN_CURVE_SET:
                    return 'curve'
                return 'poly'
        return 'poly'

    def _infer_base_from_morph_filename(self, filename: str) -> str:
        """Strip _mt_N.ext suffix to recover the base name."""
        import re
        m = re.match(r'^(.+)_mt_\d+\.(poly|curve)\.xml$', filename)
        if m:
            return m.group(1)
        for ext in ('.poly.xml', '.curve.xml', '.xml'):
            if filename.lower().endswith(ext):
                return filename[:-len(ext)]
        return filename

    def _next_morph_filename(self, base: str, suffix: str, morph_dir: str) -> str:
        """Return the next available {base}_mt_N.{suffix} filename in morph_dir."""
        counter = 1
        while True:
            name = f"{base}_mt_{counter}.{suffix}"
            if not os.path.exists(os.path.join(morph_dir, name)):
                return name
            counter += 1

    def _create_morph_default(self) -> None:
        """Create from previous if chain non-empty, else from base."""
        if self.morph_list.count() > 0:
            self._create_from_previous()
        else:
            self._create_from_base()

    def _create_from_previous(self) -> None:
        """Copy the last morph target in the chain as the new starting point."""
        morph_dir = self._get_morph_targets_dir()
        if not morph_dir:
            QMessageBox.warning(self, "No Project", "No project directory set.")
            return

        last = self.morph_list.item(self.morph_list.count() - 1).text()
        filename = last[:last.rindex("  [")] if "  [" in last and last.endswith("]") else last
        source_path = os.path.join(morph_dir, filename)

        if not os.path.isfile(source_path):
            QMessageBox.warning(self, "File Not Found",
                                f"Previous morph target not found:\n{source_path}")
            return

        suffix = 'curve.xml' if filename.endswith('.curve.xml') else 'poly.xml'
        self._copy_and_launch(source_path, suffix, morph_dir)

    def _create_from_base(self) -> None:
        """Copy the base shape (user picks file) as a new morph target."""
        morph_dir = self._get_morph_targets_dir()
        if not morph_dir:
            QMessageBox.warning(self, "No Project", "No project directory set.")
            return

        source_type = self._get_base_shape_source_type()
        if source_type == 'curve':
            start_dir = os.path.join(self._project_dir, "curveSets") if self._project_dir else ""
            suffix = 'curve.xml'
            file_filter = "Open Curve Sets (*.xml)"
        else:
            start_dir = os.path.join(self._project_dir, "polygonSets") if self._project_dir else ""
            suffix = 'poly.xml'
            file_filter = "Polygon Sets (*.xml)"

        path, _ = QFileDialog.getOpenFileName(
            self, "Select Base Shape File", start_dir, file_filter
        )
        if not path:
            return

        os.makedirs(morph_dir, exist_ok=True)
        self._copy_and_launch(path, suffix, morph_dir)

    def _copy_and_launch(self, source_path: str, suffix: str, morph_dir: str) -> None:
        """Copy source_path to morphTargets/ with the next _mt_N name, add to list, launch Bezier."""
        base_name = self._infer_base_from_morph_filename(os.path.basename(source_path))
        target_name = self._next_morph_filename(base_name, suffix, morph_dir)
        target_path = os.path.join(morph_dir, target_name)

        try:
            shutil.copy2(source_path, target_path)
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to copy file:\n{e}")
            return

        self.morph_list.addItem(target_name)
        self.morph_list.setCurrentRow(self.morph_list.count() - 1)
        self._on_modified()

        self._launch_bezier_for_morph(target_path, morph_dir, suffix)

    # === Bezier Morph Target Editing ===

    def _edit_morph_target(self) -> None:
        """Launch Bezier to edit the selected morph target file."""
        morph_dir = self._get_morph_targets_dir()
        if not morph_dir or not os.path.isdir(morph_dir):
            QMessageBox.warning(self, "No Project", "Please save the project first.")
            return

        current_item = self.morph_list.currentItem()
        if current_item is None:
            QMessageBox.warning(self, "No Selection",
                                "Please select a morph target in the list first.")
            return

        text = current_item.text()
        target_file = text[:text.rindex("  [")] if "  [" in text and text.endswith("]") else text

        full_path = os.path.join(morph_dir, target_file)
        if not os.path.isfile(full_path):
            QMessageBox.warning(self, "File Not Found",
                                f"Morph target file not found:\n{full_path}")
            return

        suffix = 'curve.xml' if target_file.endswith('.curve.xml') else 'poly.xml'
        self._launch_bezier_for_morph(full_path, morph_dir, suffix)

    def _to_bezier_filename(self, s: str) -> str:
        """Replicate Bezier's toFilename() — strips everything except [a-zA-Z0-9_-]."""
        s = s.strip()
        s = re.sub(r'\s+', '_', s)
        s = re.sub(r'[^a-zA-Z0-9_-]', '', s)
        return s.lower()

    def _strip_morph_suffix(self, filename: str) -> tuple:
        """Return (base_name, suffix) stripping .poly.xml or .curve.xml or .xml."""
        if filename.endswith('.poly.xml'):
            return filename[:-len('.poly.xml')], 'poly.xml'
        if filename.endswith('.curve.xml'):
            return filename[:-len('.curve.xml')], 'curve.xml'
        if filename.endswith('.xml'):
            return filename[:-len('.xml')], 'xml'
        return filename, ''

    def _launch_bezier_for_morph(self, full_path: str, morph_dir: str, suffix: str) -> None:
        """Shared Bezier launch for both create and edit flows."""
        if not os.path.isfile(BEZIER_JAR):
            QMessageBox.warning(self, "Bezier Not Found",
                                f"Bezier JAR not found at:\n{BEZIER_JAR}")
            return

        if (self._bezier_process is not None
                and self._bezier_process.state() != QProcess.ProcessState.NotRunning):
            QMessageBox.information(self, "Bezier Running", "Bezier is already running.")
            return

        self._edit_morph_path = full_path

        # Polygon sets need DOCTYPE for Bezier's XOM validating parser;
        # open curve sets use a non-validating parser so no headers needed.
        if suffix != 'curve.xml':
            self._add_xml_headers(full_path)

        # Bezier's toFilename() strips dots, so passing "s_mt_1.curve" yields "s_mt_1curve".
        # Instead, pass the clean base name (no .poly/.curve suffix) so Bezier saves as
        # "{bezier_name}.xml", then rename/move that file to the correct final path afterward.
        base_name, _ = self._strip_morph_suffix(os.path.basename(full_path))
        bezier_name = self._to_bezier_filename(base_name)

        self._edit_morph_bezier_name = bezier_name

        # Predict where Bezier actually writes the file:
        # - polygonSet: saves a layer bundle to --save-dir; data is in {bezier_name}_layer_1.xml
        #   (Bezier always uses the layer-bundle format: manifest + per-layer file)
        # - openCurveSet: ignores --save-dir, hardcodes {parent(morph_dir)}/curveSets/
        if suffix == 'curve.xml':
            project_dir = os.path.dirname(morph_dir)
            self._edit_morph_bezier_saved = os.path.join(
                project_dir, 'curveSets', bezier_name + '.xml')
        else:
            self._edit_morph_bezier_saved = os.path.join(
                morph_dir, bezier_name + '_layer_1.xml')

        args = ["-Xmx4G", "-jar", BEZIER_JAR,
                "--save-dir", morph_dir,
                "--load", full_path,
                "--name", bezier_name]
        if suffix != 'curve.xml':
            args.append("--point-select")

        self._bezier_process = QProcess(self)
        self._bezier_process.setWorkingDirectory(BEZIER_WORKING_DIR)
        self._bezier_process.finished.connect(self._on_edit_morph_bezier_finished)
        self._bezier_process.start("java", args)

    def _on_edit_morph_bezier_finished(self, exit_code, exit_status) -> None:
        """Handle Bezier process finishing after morph target create/edit."""
        bezier_saved = self._edit_morph_bezier_saved
        target = self._edit_morph_path

        # Move Bezier's actual save location to the correct .poly.xml / .curve.xml path
        if (bezier_saved and target
                and bezier_saved != target
                and os.path.isfile(bezier_saved)):
            try:
                os.replace(bezier_saved, target)
            except Exception as e:
                print(f"Warning: could not rename {bezier_saved} -> {target}: {e}")

        # Strip DOCTYPE/xml-declaration headers (only present on polygon set files)
        if target and os.path.isfile(target) and not target.endswith('.curve.xml'):
            self._strip_xml_headers(target)

        # Clean up junk files Bezier always writes to morphTargets/:
        #   poly:  {bezier_name}.layers.xml  (manifest; _layer_1.xml was moved above)
        #   curve: {bezier_name}.layers.xml + {bezier_name}_layer_N.xml files
        if target and self._edit_morph_bezier_name:
            bname = self._edit_morph_bezier_name
            morph_dir = os.path.dirname(target)
            junk_candidates = [os.path.join(morph_dir, bname + '.layers.xml')]
            if target.endswith('.curve.xml'):
                # Curve type: _layer_N.xml files are also junk (data came from curveSets/)
                try:
                    junk_candidates += [
                        os.path.join(morph_dir, f)
                        for f in os.listdir(morph_dir)
                        if f.startswith(bname + '_layer_') and f.endswith('.xml')
                    ]
                except OSError:
                    pass
            for junk in junk_candidates:
                if os.path.isfile(junk):
                    try:
                        os.remove(junk)
                    except Exception as e:
                        print(f"Warning: could not remove {junk}: {e}")

        self._edit_morph_path = None
        self._edit_morph_bezier_saved = None
        self._edit_morph_bezier_name = None

    def _add_xml_headers(self, filepath: str) -> None:
        """Add XML declaration and DOCTYPE lines required by Bezier's XOM parser.
        Also ensures the DTD file exists at the expected relative path."""
        with open(filepath, 'r') as f:
            content = f.read()
        # Don't add if already present
        if content.lstrip().startswith('<?xml'):
            return
        header = ('<?xml version="1.0" encoding="ISO-8859-1"?>\n'
                  '<!DOCTYPE polygonSet SYSTEM "../dtd/polygonSet.dtd">\n')
        with open(filepath, 'w') as f:
            f.write(header + content)

        # Ensure DTD is available at ../dtd/ relative to the XML file
        xml_dir = os.path.dirname(filepath)
        dtd_dir = os.path.join(os.path.dirname(xml_dir), "dtd")
        dtd_dest = os.path.join(dtd_dir, "polygonSet.dtd")
        if not os.path.isfile(dtd_dest):
            # Copy from Bezier's resources
            dtd_source = os.path.join(BEZIER_WORKING_DIR, "resources", "dtd", "polygonSet.dtd")
            if os.path.isfile(dtd_source):
                os.makedirs(dtd_dir, exist_ok=True)
                shutil.copy2(dtd_source, dtd_dest)

    def _strip_xml_headers(self, filepath: str) -> None:
        """Remove XML declaration and DOCTYPE lines from a polygon set file."""
        with open(filepath, 'r') as f:
            lines = f.readlines()
        cleaned = [l for l in lines
                   if not l.strip().startswith('<?xml')
                   and not l.strip().startswith('<!DOCTYPE')]
        with open(filepath, 'w') as f:
            f.writelines(cleaned)

    # === Dynamic Keyframe Table Column Management ===

    def _update_kf_table_columns(self) -> None:
        """Update keyframe table columns based on whether morph amount is needed."""
        anim_type = self.animator_type_combo.currentText()
        needs_morph = (anim_type == "keyframe_morph")
        current_cols = self.kf_table.columnCount()

        if needs_morph and current_cols == 7:
            # Add MT Idx + Amount columns (cols 6 & 7), push Easing to col 8
            self.kf_table.setColumnCount(9)
            self.kf_table.setHorizontalHeaderLabels([
                "Draw Cycle", "Pos X", "Pos Y", "Scale X", "Scale Y",
                "Rotation", "MT Idx", "Amount", "Easing"
            ])
            header = self.kf_table.horizontalHeader()
            for col in range(8):
                header.setSectionResizeMode(col, QHeaderView.ResizeMode.ResizeToContents)
            header.setSectionResizeMode(8, QHeaderView.ResizeMode.Stretch)
            if self._current_sprite:
                self._load_keyframes_to_table(self._current_sprite.params.keyframes)

        elif not needs_morph and current_cols == 9:
            # Remove morph columns — reload with 7 columns
            self.kf_table.setColumnCount(7)
            self.kf_table.setHorizontalHeaderLabels([
                "Draw Cycle", "Pos X", "Pos Y", "Scale X", "Scale Y",
                "Rotation", "Easing"
            ])
            header = self.kf_table.horizontalHeader()
            for col in range(6):
                header.setSectionResizeMode(col, QHeaderView.ResizeMode.ResizeToContents)
            header.setSectionResizeMode(6, QHeaderView.ResizeMode.Stretch)
            if self._current_sprite:
                self._load_keyframes_to_table(self._current_sprite.params.keyframes)


class CopyKeyframesDialog(QDialog):
    """Dialog for selecting a source sprite to copy keyframes from."""

    def __init__(self, sprites: list, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Copy Keyframes From Sprite")
        self._sprites = sprites  # list of (label, SpriteDef)

        layout = QVBoxLayout(self)

        layout.addWidget(QLabel("Source Sprite:"))
        self._sprite_combo = QComboBox()
        for label, _ in sprites:
            self._sprite_combo.addItem(label)
        layout.addWidget(self._sprite_combo)

        layout.addWidget(QLabel("Copy Mode:"))
        self._mode_group = QButtonGroup(self)
        self._absolute_radio = QRadioButton("Absolute (exact copy)")
        self._relative_radio = QRadioButton("Relative (adjust positions)")
        self._absolute_radio.setChecked(True)
        self._mode_group.addButton(self._absolute_radio)
        self._mode_group.addButton(self._relative_radio)
        layout.addWidget(self._absolute_radio)
        layout.addWidget(self._relative_radio)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def selected_sprite(self):
        idx = self._sprite_combo.currentIndex()
        if 0 <= idx < len(self._sprites):
            return self._sprites[idx][1]
        return None

    def is_relative(self) -> bool:
        return self._relative_radio.isChecked()
