"""
Shape configuration tab for the parameter editor.
Provides UI for editing shapes.xml settings.
"""

_SUBDIV_NONE = "(none)"   # sentinel shown in dropdown; maps to empty subdivision_params_set_name
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QSpinBox, QDoubleSpinBox, QComboBox, QTreeWidget,
    QTreeWidgetItem, QPushButton, QSplitter, QLabel, QStackedWidget,
    QMessageBox, QInputDialog, QScrollArea
)
from PyQt6.QtCore import pyqtSignal, Qt
from models.shape_config import (
    ShapeSourceType, Shape3DType, Vector2D,
    ShapeDef, ShapeSet, ShapeLibrary
)


class ShapeTab(QWidget):
    """Tab widget for editing shape configuration."""

    modified = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._library = ShapeLibrary()
        self._current_set: ShapeSet = None
        self._current_shape: ShapeDef = None
        self._updating = False
        self._checking = False
        self._subdivision_collection = None  # Reference to subdivision collection for dropdown
        self._polygon_library = None  # Reference to polygon library for dropdown
        self._open_curve_library = None  # Reference to open curve library for dropdown
        self._point_set_library = None  # Reference to point set library for dropdown
        self._oval_set_library = None   # Reference to oval set library for dropdown

        self._setup_ui()
        self._refresh_tree()

    def _setup_ui(self):
        """Set up the UI layout."""
        main_layout = QHBoxLayout(self)

        # Create splitter for left panel and right panel
        splitter = QSplitter(Qt.Orientation.Horizontal)
        main_layout.addWidget(splitter)

        # Left panel - shape tree
        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)

        left_layout.addWidget(QLabel("Shape Library:"))

        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["Sel", "Name", "Type"])
        self.tree.setColumnWidth(0, 35)
        self.tree.setColumnWidth(1, 180)
        self.tree.setColumnWidth(2, 80)
        self.tree.currentItemChanged.connect(self._on_item_selected)
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

        # Buttons for shapes
        shape_btn_layout = QHBoxLayout()
        self.add_shape_btn = QPushButton("+ Shape")
        self.add_shape_btn.clicked.connect(self._add_shape)
        shape_btn_layout.addWidget(self.add_shape_btn)

        self.remove_shape_btn = QPushButton("- Shape")
        self.remove_shape_btn.clicked.connect(self._remove_shape)
        shape_btn_layout.addWidget(self.remove_shape_btn)

        self.duplicate_btn = QPushButton("Duplicate")
        self.duplicate_btn.clicked.connect(self._duplicate_shape)
        shape_btn_layout.addWidget(self.duplicate_btn)

        self.rename_shape_btn = QPushButton("Rename")
        self.rename_shape_btn.clicked.connect(self._rename_shape)
        shape_btn_layout.addWidget(self.rename_shape_btn)
        left_layout.addLayout(shape_btn_layout)

        # Delete Selected button
        del_sel_layout = QHBoxLayout()
        self.delete_selected_btn = QPushButton("Delete Selected")
        self.delete_selected_btn.clicked.connect(self._delete_selected)
        del_sel_layout.addWidget(self.delete_selected_btn)
        del_sel_layout.addStretch()
        left_layout.addLayout(del_sel_layout)

        splitter.addWidget(left_panel)

        # Right panel - properties editor in scroll area
        right_panel = QScrollArea()
        right_panel.setWidgetResizable(True)
        right_content = QWidget()
        right_layout = QVBoxLayout(right_content)

        # Shape name
        name_group = QGroupBox("Shape")
        name_layout = QFormLayout(name_group)

        self.name_edit = QLineEdit()
        self.name_edit.textChanged.connect(self._on_name_changed)
        name_layout.addRow("Name:", self.name_edit)

        right_layout.addWidget(name_group)

        # Polygon Source
        source_group = QGroupBox("Polygon Source")
        source_layout = QFormLayout(source_group)

        self.source_type_combo = QComboBox()
        # Items map: index 0 → POLYGON_SET, index 1 → OPEN_CURVE_SET, index 2 → POINT_SET, index 3 → OVAL_SET
        self.source_type_combo.addItems(["Polygon Set Reference", "Open Curve Set", "Point Set", "Oval Set"])
        self.source_type_combo.currentIndexChanged.connect(self._on_source_type_changed)
        source_layout.addRow("Source Type:", self.source_type_combo)

        # Source-specific widgets in a stacked widget
        self.source_stack = QStackedWidget()

        # Polygon set reference (includes both spline and regular polygon sets) — stack index 0
        poly_ref_widget = QWidget()
        poly_ref_layout = QFormLayout(poly_ref_widget)
        self.polygon_set_combo = QComboBox()
        self.polygon_set_combo.setEditable(True)
        self.polygon_set_combo.setPlaceholderText("Name of PolygonSet from polygons.xml")
        self.polygon_set_combo.currentTextChanged.connect(self._on_modified)
        poly_ref_layout.addRow("Polygon Set:", self.polygon_set_combo)

        # Refresh button for polygon sets
        poly_refresh_layout = QHBoxLayout()
        self.refresh_polygon_btn = QPushButton("Refresh List")
        self.refresh_polygon_btn.clicked.connect(self._refresh_polygon_dropdown)
        poly_refresh_layout.addStretch()
        poly_refresh_layout.addWidget(self.refresh_polygon_btn)
        poly_ref_layout.addRow("", poly_refresh_layout)

        self.source_stack.addWidget(poly_ref_widget)

        # Open curve set reference — stack index 1
        open_curve_widget = QWidget()
        open_curve_layout = QFormLayout(open_curve_widget)
        self.open_curve_set_combo = QComboBox()
        self.open_curve_set_combo.setEditable(True)
        self.open_curve_set_combo.setPlaceholderText("Name of OpenCurveSet from curves.xml")
        self.open_curve_set_combo.currentTextChanged.connect(self._on_modified)
        open_curve_layout.addRow("Open Curve Set:", self.open_curve_set_combo)

        oc_refresh_layout = QHBoxLayout()
        self.refresh_open_curve_btn = QPushButton("Refresh List")
        self.refresh_open_curve_btn.clicked.connect(self._refresh_open_curve_dropdown)
        oc_refresh_layout.addStretch()
        oc_refresh_layout.addWidget(self.refresh_open_curve_btn)
        open_curve_layout.addRow("", oc_refresh_layout)
        self.source_stack.addWidget(open_curve_widget)

        # Point set reference — stack index 2
        point_set_widget = QWidget()
        point_set_layout = QFormLayout(point_set_widget)
        self.point_set_combo = QComboBox()
        self.point_set_combo.setEditable(True)
        self.point_set_combo.setPlaceholderText("Name of PointSet from points.xml")
        self.point_set_combo.currentTextChanged.connect(self._on_modified)
        point_set_layout.addRow("Point Set:", self.point_set_combo)

        ps_refresh_layout = QHBoxLayout()
        self.refresh_point_set_btn = QPushButton("Refresh List")
        self.refresh_point_set_btn.clicked.connect(self._refresh_point_set_dropdown)
        ps_refresh_layout.addStretch()
        ps_refresh_layout.addWidget(self.refresh_point_set_btn)
        point_set_layout.addRow("", ps_refresh_layout)
        self.source_stack.addWidget(point_set_widget)

        # Oval set reference — stack index 3
        oval_set_widget = QWidget()
        oval_set_layout = QFormLayout(oval_set_widget)
        self.oval_set_combo = QComboBox()
        self.oval_set_combo.setEditable(True)
        self.oval_set_combo.setPlaceholderText("Name of OvalSet from ovals.xml")
        self.oval_set_combo.currentTextChanged.connect(self._on_modified)
        oval_set_layout.addRow("Oval Set:", self.oval_set_combo)

        os_refresh_layout = QHBoxLayout()
        self.refresh_oval_set_btn = QPushButton("Refresh List")
        self.refresh_oval_set_btn.clicked.connect(self._refresh_oval_set_dropdown)
        os_refresh_layout.addStretch()
        os_refresh_layout.addWidget(self.refresh_oval_set_btn)
        oval_set_layout.addRow("", os_refresh_layout)
        self.source_stack.addWidget(oval_set_widget)

        source_layout.addRow(self.source_stack)
        right_layout.addWidget(source_group)

        # Subdivision Parameters Reference
        subdiv_group = QGroupBox("Subdivision Parameters")
        subdiv_layout = QFormLayout(subdiv_group)

        self.subdiv_set_combo = QComboBox()
        self.subdiv_set_combo.setEditable(True)  # Allow custom entry if not in list
        self.subdiv_set_combo.setPlaceholderText("Name of SubdivisionParamsSet from subdivision.xml")
        self.subdiv_set_combo.currentTextChanged.connect(self._on_modified)
        subdiv_layout.addRow("Params Set:", self.subdiv_set_combo)

        # Refresh button for subdivision sets
        subdiv_refresh_layout = QHBoxLayout()
        self.refresh_subdiv_btn = QPushButton("Refresh List")
        self.refresh_subdiv_btn.clicked.connect(self._refresh_subdivision_dropdown)
        subdiv_refresh_layout.addStretch()
        subdiv_refresh_layout.addWidget(self.refresh_subdiv_btn)
        subdiv_layout.addRow("", subdiv_refresh_layout)

        right_layout.addWidget(subdiv_group)

        # 3D Shape Generation (optional)
        shape3d_group = QGroupBox("3D Shape Generation (Optional)")
        shape3d_layout = QFormLayout(shape3d_group)

        self.shape3d_combo = QComboBox()
        self.shape3d_combo.addItems(["None", "Crystal", "Rect Prism", "Extrusion", "Grid Plane", "Grid Block"])
        self.shape3d_combo.currentIndexChanged.connect(self._on_3d_type_changed)
        shape3d_layout.addRow("3D Type:", self.shape3d_combo)

        # 3D parameters
        self.param1_spin = QSpinBox()
        self.param1_spin.setRange(1, 100)
        self.param1_spin.setValue(4)
        self.param1_spin.valueChanged.connect(self._on_modified)
        self.param1_label = QLabel("Param 1:")
        shape3d_layout.addRow(self.param1_label, self.param1_spin)

        self.param2_spin = QSpinBox()
        self.param2_spin.setRange(1, 100)
        self.param2_spin.setValue(4)
        self.param2_spin.valueChanged.connect(self._on_modified)
        self.param2_label = QLabel("Param 2:")
        shape3d_layout.addRow(self.param2_label, self.param2_spin)

        self.param3_spin = QSpinBox()
        self.param3_spin.setRange(1, 100)
        self.param3_spin.setValue(4)
        self.param3_spin.valueChanged.connect(self._on_modified)
        self.param3_label = QLabel("Param 3:")
        shape3d_layout.addRow(self.param3_label, self.param3_spin)

        right_layout.addWidget(shape3d_group)

        # Transform
        transform_group = QGroupBox("Transform")
        transform_layout = QFormLayout(transform_group)

        # Translation
        trans_layout = QHBoxLayout()
        self.trans_x_spin = QDoubleSpinBox()
        self.trans_x_spin.setRange(-100.0, 100.0)
        self.trans_x_spin.setDecimals(3)
        self.trans_x_spin.valueChanged.connect(self._on_modified)
        trans_layout.addWidget(QLabel("X:"))
        trans_layout.addWidget(self.trans_x_spin)

        self.trans_y_spin = QDoubleSpinBox()
        self.trans_y_spin.setRange(-100.0, 100.0)
        self.trans_y_spin.setDecimals(3)
        self.trans_y_spin.valueChanged.connect(self._on_modified)
        trans_layout.addWidget(QLabel("Y:"))
        trans_layout.addWidget(self.trans_y_spin)
        transform_layout.addRow("Translation:", trans_layout)

        # Scale
        scale_layout = QHBoxLayout()
        self.scale_x_spin = QDoubleSpinBox()
        self.scale_x_spin.setRange(0.001, 100.0)
        self.scale_x_spin.setDecimals(3)
        self.scale_x_spin.setValue(1.0)
        self.scale_x_spin.valueChanged.connect(self._on_modified)
        scale_layout.addWidget(QLabel("X:"))
        scale_layout.addWidget(self.scale_x_spin)

        self.scale_y_spin = QDoubleSpinBox()
        self.scale_y_spin.setRange(0.001, 100.0)
        self.scale_y_spin.setDecimals(3)
        self.scale_y_spin.setValue(1.0)
        self.scale_y_spin.valueChanged.connect(self._on_modified)
        scale_layout.addWidget(QLabel("Y:"))
        scale_layout.addWidget(self.scale_y_spin)
        transform_layout.addRow("Scale:", scale_layout)

        # Rotation
        self.rotation_spin = QDoubleSpinBox()
        self.rotation_spin.setRange(-360.0, 360.0)
        self.rotation_spin.setDecimals(1)
        self.rotation_spin.valueChanged.connect(self._on_modified)
        transform_layout.addRow("Rotation:", self.rotation_spin)

        right_layout.addWidget(transform_group)

        right_layout.addStretch()
        right_panel.setWidget(right_content)

        splitter.addWidget(right_panel)
        splitter.setSizes([280, 520])

        # Initial state
        self._update_3d_param_labels()

    _SHAPE_TYPE_ABBREV = {
        "POLYGON_SET": "PSET",
        "REGULAR_POLYGON": "REG",
        "INLINE_POINTS": "IPT",
        "OPEN_CURVE_SET": "OCS",
        "POINT_SET": "PTS",
        "OVAL_SET": "OVL",
    }

    def _refresh_tree(self):
        """Refresh the shape tree."""
        self._checking = True
        self.tree.clear()
        for shape_set in self._library.shape_sets:
            set_item = QTreeWidgetItem(["", shape_set.name, "Set"])
            set_item.setData(0, Qt.ItemDataRole.UserRole, ("set", shape_set))
            set_item.setFlags(set_item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
            set_item.setCheckState(0, Qt.CheckState.Unchecked)

            for shape in shape_set.shapes:
                abbrev = self._SHAPE_TYPE_ABBREV.get(shape.source_type.name, shape.source_type.name)
                shape_item = QTreeWidgetItem(["", shape.name, abbrev])
                shape_item.setData(0, Qt.ItemDataRole.UserRole, ("shape", shape))
                shape_item.setFlags(shape_item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
                shape_item.setCheckState(0, Qt.CheckState.Unchecked)
                set_item.addChild(shape_item)

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
            self._current_shape = None
            return

        data = current.data(0, Qt.ItemDataRole.UserRole)
        if data is None:
            return

        item_type, item_obj = data

        if item_type == "set":
            self._current_set = item_obj
            self._current_shape = None
            self._clear_shape_ui()
        else:
            self._current_shape = item_obj
            # Find parent set
            parent = current.parent()
            if parent:
                parent_data = parent.data(0, Qt.ItemDataRole.UserRole)
                if parent_data:
                    self._current_set = parent_data[1]
            self._load_shape_to_ui(self._current_shape)

    def _clear_shape_ui(self):
        """Clear the shape editor UI."""
        self._updating = True
        try:
            self.name_edit.clear()
            self.source_type_combo.setCurrentIndex(0)
            self.polygon_set_combo.setCurrentText("")
            self.subdiv_set_combo.setCurrentText(_SUBDIV_NONE)
            self.shape3d_combo.setCurrentIndex(0)
            self.param1_spin.setValue(4)
            self.param2_spin.setValue(4)
            self.param3_spin.setValue(4)
            self.trans_x_spin.setValue(0)
            self.trans_y_spin.setValue(0)
            self.scale_x_spin.setValue(1)
            self.scale_y_spin.setValue(1)
            self.rotation_spin.setValue(0)
        finally:
            self._updating = False

    def _load_shape_to_ui(self, shape: ShapeDef):
        """Load a shape's values into the UI."""
        self._updating = True
        try:
            self.name_edit.setText(shape.name)

            # Source type — map enum to combo index
            # POLYGON_SET (0) → combo 0, REGULAR_POLYGON (1) → combo 0,
            # INLINE_POINTS (legacy) → combo 0, OPEN_CURVE_SET (3) → combo 1,
            # POINT_SET (4) → combo 2, OVAL_SET (5) → combo 3
            if shape.source_type == ShapeSourceType.OPEN_CURVE_SET:
                self.source_type_combo.setCurrentIndex(1)
                self.source_stack.setCurrentIndex(1)
                self.open_curve_set_combo.setCurrentText(shape.open_curve_set_name)
            elif shape.source_type == ShapeSourceType.POINT_SET:
                self.source_type_combo.setCurrentIndex(2)
                self.source_stack.setCurrentIndex(2)
                self.point_set_combo.setCurrentText(shape.point_set_name)
            elif shape.source_type == ShapeSourceType.OVAL_SET:
                self.source_type_combo.setCurrentIndex(3)
                self.source_stack.setCurrentIndex(3)
                self.oval_set_combo.setCurrentText(shape.oval_set_name)
            else:
                # POLYGON_SET, REGULAR_POLYGON, and legacy INLINE_POINTS all show as polygon set reference
                self.source_type_combo.setCurrentIndex(0)
                self.source_stack.setCurrentIndex(0)
                self.polygon_set_combo.setCurrentText(shape.polygon_set_name)

            # Subdivision — empty name → "(none)" sentinel
            subdiv_display = shape.subdivision_params_set_name or _SUBDIV_NONE
            self.subdiv_set_combo.setCurrentText(subdiv_display)

            # 3D type
            self.shape3d_combo.setCurrentIndex(shape.shape_3d_type.value)
            self.param1_spin.setValue(shape.shape_3d_param1)
            self.param2_spin.setValue(shape.shape_3d_param2)
            self.param3_spin.setValue(shape.shape_3d_param3)
            self._update_3d_param_labels()

            # Transform
            self.trans_x_spin.setValue(shape.translate_x)
            self.trans_y_spin.setValue(shape.translate_y)
            self.scale_x_spin.setValue(shape.scale_x)
            self.scale_y_spin.setValue(shape.scale_y)
            self.rotation_spin.setValue(shape.rotation)
        finally:
            self._updating = False

    def _save_ui_to_shape(self):
        """Save UI values back to the current shape."""
        if self._current_shape is None:
            return

        self._current_shape.name = self.name_edit.text()

        # Source type — combo index 0=POLYGON_SET, 1=OPEN_CURVE_SET, 2=POINT_SET, 3=OVAL_SET
        combo_idx = self.source_type_combo.currentIndex()
        if combo_idx == 1:
            self._current_shape.source_type = ShapeSourceType.OPEN_CURVE_SET
            self._current_shape.open_curve_set_name = self.open_curve_set_combo.currentText()
        elif combo_idx == 2:
            self._current_shape.source_type = ShapeSourceType.POINT_SET
            self._current_shape.point_set_name = self.point_set_combo.currentText()
        elif combo_idx == 3:
            self._current_shape.source_type = ShapeSourceType.OVAL_SET
            self._current_shape.oval_set_name = self.oval_set_combo.currentText()
        else:
            self._current_shape.source_type = ShapeSourceType.POLYGON_SET
            self._current_shape.polygon_set_name = self.polygon_set_combo.currentText()

        # Subdivision — "(none)" sentinel maps back to empty string (no element in XML)
        subdiv_text = self.subdiv_set_combo.currentText()
        self._current_shape.subdivision_params_set_name = "" if subdiv_text == _SUBDIV_NONE else subdiv_text

        # 3D type
        self._current_shape.shape_3d_type = Shape3DType(self.shape3d_combo.currentIndex())
        self._current_shape.shape_3d_param1 = self.param1_spin.value()
        self._current_shape.shape_3d_param2 = self.param2_spin.value()
        self._current_shape.shape_3d_param3 = self.param3_spin.value()

        # Transform
        self._current_shape.translate_x = self.trans_x_spin.value()
        self._current_shape.translate_y = self.trans_y_spin.value()
        self._current_shape.scale_x = self.scale_x_spin.value()
        self._current_shape.scale_y = self.scale_y_spin.value()
        self._current_shape.rotation = self.rotation_spin.value()

        # Update tree item text
        current_item = self.tree.currentItem()
        if current_item:
            current_item.setText(1, self._current_shape.name)
            abbrev = self._SHAPE_TYPE_ABBREV.get(self._current_shape.source_type.name, self._current_shape.source_type.name)
            current_item.setText(2, abbrev)

    def _update_3d_param_labels(self):
        """Update 3D parameter labels based on selected type."""
        shape_type = Shape3DType(self.shape3d_combo.currentIndex())

        # Show/hide parameters based on type
        show_params = shape_type != Shape3DType.NONE

        self.param1_label.setVisible(show_params)
        self.param1_spin.setVisible(show_params)
        self.param2_label.setVisible(show_params and shape_type in [Shape3DType.GRID_PLANE, Shape3DType.GRID_BLOCK])
        self.param2_spin.setVisible(show_params and shape_type in [Shape3DType.GRID_PLANE, Shape3DType.GRID_BLOCK])
        self.param3_label.setVisible(shape_type == Shape3DType.GRID_BLOCK)
        self.param3_spin.setVisible(shape_type == Shape3DType.GRID_BLOCK)

        # Update labels
        if shape_type == Shape3DType.CRYSTAL:
            self.param1_label.setText("Horizontal Points:")
        elif shape_type == Shape3DType.RECT_PRISM:
            self.param1_label.setText("Horizontal Points:")
        elif shape_type == Shape3DType.EXTRUSION:
            self.param1_label.setText("Extrude Depth:")
        elif shape_type == Shape3DType.GRID_PLANE:
            self.param1_label.setText("Rows:")
            self.param2_label.setText("Columns:")
        elif shape_type == Shape3DType.GRID_BLOCK:
            self.param1_label.setText("Rows:")
            self.param2_label.setText("Columns:")
            self.param3_label.setText("Layers:")

    def _on_name_changed(self):
        """Handle name change."""
        if self._updating:
            return
        self._save_ui_to_shape()
        self.modified.emit()

    def _on_source_type_changed(self, index):
        """Handle source type change."""
        self.source_stack.setCurrentIndex(index)
        if not self._updating:
            self._save_ui_to_shape()
            self.modified.emit()

    def _on_3d_type_changed(self, index):
        """Handle 3D type change."""
        self._update_3d_param_labels()
        if not self._updating:
            self._save_ui_to_shape()
            self.modified.emit()

    def _on_modified(self):
        """Handle any value change."""
        if self._updating:
            return
        self._save_ui_to_shape()
        self.modified.emit()

    def _add_set(self):
        """Add a new shape set."""
        name, ok = QInputDialog.getText(self, "Add Shape Set", "Name:")
        if ok and name:
            # Check for duplicate name
            if self._library.get(name):
                QMessageBox.warning(self, "Duplicate Name", f"A shape set named '{name}' already exists.")
                return

            new_set = ShapeSet(name=name)
            self._library.add(new_set)
            self._refresh_tree()
            # Select the new set
            for i in range(self.tree.topLevelItemCount()):
                item = self.tree.topLevelItem(i)
                if item.text(1) == name:
                    self.tree.setCurrentItem(item)
                    break
            self.modified.emit()

    def _remove_set(self):
        """Remove the selected shape set."""
        if self._current_set is None:
            return

        result = QMessageBox.question(
            self, "Remove Shape Set",
            f"Remove shape set '{self._current_set.name}' and all its shapes?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result == QMessageBox.StandardButton.Yes:
            # Find and remove the set
            for i, s in enumerate(self._library.shape_sets):
                if s.name == self._current_set.name:
                    self._library.remove(i)
                    break
            self._current_set = None
            self._current_shape = None
            self._refresh_tree()
            self.modified.emit()

    def _add_shape(self):
        """Add a new shape to the current set."""
        if self._current_set is None:
            QMessageBox.warning(self, "No Set Selected", "Please select a shape set first.")
            return

        name, ok = QInputDialog.getText(self, "Add Shape", "Name:")
        if ok and name:
            # Check for duplicate name in this set
            if self._current_set.get(name):
                QMessageBox.warning(self, "Duplicate Name", f"A shape named '{name}' already exists in this set.")
                return

            new_shape = ShapeDef(name=name)
            self._current_set.add(new_shape)
            self._refresh_tree()
            # Select the new shape
            self._select_shape(self._current_set.name, name)
            self.modified.emit()

    def _remove_shape(self):
        """Remove the selected shape."""
        if self._current_shape is None or self._current_set is None:
            return

        result = QMessageBox.question(
            self, "Remove Shape",
            f"Remove shape '{self._current_shape.name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result == QMessageBox.StandardButton.Yes:
            # Find and remove the shape
            for i, s in enumerate(self._current_set.shapes):
                if s.name == self._current_shape.name:
                    self._current_set.remove(i)
                    break
            self._current_shape = None
            self._refresh_tree()
            self.modified.emit()

    def _duplicate_shape(self):
        """Duplicate the selected item — set if a set is selected, shape otherwise."""
        if self._current_set is None:
            return

        if self._current_shape is None:
            # ── Duplicate the shape set ──────────────────────────────────────
            base_name = self._current_set.name
            counter = 1
            while True:
                new_name = f"{base_name}_{counter:03d}"
                if not self._library.get(new_name):
                    break
                counter += 1
            new_name, ok = QInputDialog.getText(
                self, "Duplicate Shape Set", "Name for copy:", text=new_name)
            if not ok or not new_name.strip():
                return
            new_name = new_name.strip()
            if self._library.get(new_name):
                QMessageBox.warning(self, "Duplicate Name",
                                    f"A shape set named '{new_name}' already exists.")
                return
            from copy import deepcopy
            new_set = deepcopy(self._current_set)
            new_set.name = new_name
            self._library.add(new_set)
            self._refresh_tree()
            for i in range(self.tree.topLevelItemCount()):
                if self.tree.topLevelItem(i).text(1) == new_name:
                    self.tree.setCurrentItem(self.tree.topLevelItem(i))
                    break
        else:
            # ── Duplicate the shape ──────────────────────────────────────────
            base_name = self._current_shape.name
            counter = 1
            while True:
                new_name = f"{base_name}_{counter:03d}"
                if not self._current_set.get(new_name):
                    break
                counter += 1
            from dataclasses import replace
            new_shape = replace(self._current_shape, name=new_name)
            new_shape.inline_points = [Vector2D(p.x, p.y) for p in self._current_shape.inline_points]
            self._current_set.add(new_shape)
            self._refresh_tree()
            self._select_shape(self._current_set.name, new_name)

        self.modified.emit()

    def _rename_shape(self):
        """Rename the selected item — set if a set is selected, shape otherwise."""
        if self._current_set is None:
            return

        if self._current_shape is None:
            # ── Rename the shape set ─────────────────────────────────────────
            new_name, ok = QInputDialog.getText(
                self, "Rename Shape Set", "New name:", text=self._current_set.name)
            if not ok or not new_name.strip():
                return
            new_name = new_name.strip()
            if new_name == self._current_set.name:
                return
            if self._library.get(new_name):
                QMessageBox.warning(self, "Duplicate Name",
                                    f"A shape set named '{new_name}' already exists.")
                return
            self._current_set.name = new_name
            self._refresh_tree()
            for i in range(self.tree.topLevelItemCount()):
                if self.tree.topLevelItem(i).text(1) == new_name:
                    self.tree.setCurrentItem(self.tree.topLevelItem(i))
                    break
        else:
            # ── Rename the shape ─────────────────────────────────────────────
            new_name, ok = QInputDialog.getText(
                self, "Rename Shape", "New name:", text=self._current_shape.name)
            if not ok or not new_name.strip():
                return
            new_name = new_name.strip()
            if new_name == self._current_shape.name:
                return
            if self._current_set.get(new_name):
                QMessageBox.warning(self, "Duplicate Name",
                                    f"A shape named '{new_name}' already exists in this set.")
                return
            self._current_shape.name = new_name
            self._refresh_tree()
            self._select_shape(self._current_set.name, new_name)

        self.modified.emit()

    def _on_item_check_changed(self, item, column):
        """Handle checkbox toggle — prevent it from changing selection."""
        if self._checking:
            return

    def _delete_selected(self):
        """Delete all checked items (sets or shapes)."""
        sets_to_delete = []    # ShapeSet objects
        shapes_to_delete = []  # (shape_set, shape) pairs
        for i in range(self.tree.topLevelItemCount()):
            set_item = self.tree.topLevelItem(i)
            set_data = set_item.data(0, Qt.ItemDataRole.UserRole)
            if not set_data or set_data[0] != "set":
                continue
            shape_set = set_data[1]
            if set_item.checkState(0) == Qt.CheckState.Checked:
                sets_to_delete.append(shape_set)
            else:
                for j in range(set_item.childCount()):
                    shape_item = set_item.child(j)
                    if shape_item.checkState(0) == Qt.CheckState.Checked:
                        data = shape_item.data(0, Qt.ItemDataRole.UserRole)
                        if data and data[0] == "shape":
                            shapes_to_delete.append((shape_set, data[1]))

        total = len(sets_to_delete) + len(shapes_to_delete)
        if total == 0:
            QMessageBox.information(self, "No Selection", "No items are checked for deletion.")
            return

        parts = []
        if sets_to_delete:
            parts.append(f"{len(sets_to_delete)} set(s)")
        if shapes_to_delete:
            parts.append(f"{len(shapes_to_delete)} shape(s)")
        result = QMessageBox.question(
            self, "Delete Selected",
            f"Delete {' and '.join(parts)}?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if result == QMessageBox.StandardButton.Yes:
            for shape_set in sets_to_delete:
                for idx, s in enumerate(self._library.shape_sets):
                    if s is shape_set:
                        self._library.remove(idx)
                        break
            for shape_set, shape in shapes_to_delete:
                for idx, s in enumerate(shape_set.shapes):
                    if s is shape:
                        shape_set.remove(idx)
                        break
            self._current_set = None
            self._current_shape = None
            self._clear_shape_ui()
            self._refresh_tree()
            self.modified.emit()

    def _select_shape(self, set_name: str, shape_name: str):
        """Select a shape in the tree by set and shape name."""
        for i in range(self.tree.topLevelItemCount()):
            set_item = self.tree.topLevelItem(i)
            if set_item.text(1) == set_name:
                for j in range(set_item.childCount()):
                    shape_item = set_item.child(j)
                    if shape_item.text(1) == shape_name:
                        self.tree.setCurrentItem(shape_item)
                        return

    def get_library(self) -> ShapeLibrary:
        """Get the current library."""
        return self._library

    def set_library(self, library: ShapeLibrary) -> None:
        """Set the library to display."""
        self._library = library
        self._refresh_tree()

    def create_default_library(self) -> ShapeLibrary:
        """Create a default library with one set and one shape."""
        library = ShapeLibrary(name="MainLibrary")
        default_set = ShapeSet(name="default")
        default_shape = ShapeDef(
            name="DefaultShape",
            source_type=ShapeSourceType.POLYGON_SET,
            polygon_set_name=""
        )
        default_set.add(default_shape)
        library.add(default_set)
        return library

    def set_subdivision_collection(self, collection) -> None:
        """Set the subdivision collection for populating the params set dropdown."""
        self._subdivision_collection = collection
        self._refresh_subdivision_dropdown()

    def _refresh_subdivision_dropdown(self) -> None:
        """Refresh the subdivision params set dropdown from the collection."""
        # Block signals to prevent triggering _on_modified during refresh
        self._updating = True
        try:
            # Remember current selection
            current_text = self.subdiv_set_combo.currentText()

            self.subdiv_set_combo.clear()
            self.subdiv_set_combo.addItem(_SUBDIV_NONE)   # always first

            if self._subdivision_collection is not None:
                # Get param set names from the collection
                try:
                    # Assuming the collection has params_sets attribute with SubdivisionParamsSet objects
                    if hasattr(self._subdivision_collection, 'params_sets'):
                        names = [ps.name for ps in self._subdivision_collection.params_sets]
                        names.sort()
                        self.subdiv_set_combo.addItems(names)
                except Exception:
                    pass  # Collection not accessible

            # Restore previous selection
            if current_text and current_text != _SUBDIV_NONE:
                index = self.subdiv_set_combo.findText(current_text)
                if index >= 0:
                    self.subdiv_set_combo.setCurrentIndex(index)
                else:
                    # If not found, set as custom text
                    self.subdiv_set_combo.setCurrentText(current_text)
            else:
                self.subdiv_set_combo.setCurrentIndex(0)   # select "(none)"
        finally:
            self._updating = False

    def set_open_curve_library(self, library) -> None:
        """Set the open curve library for populating the open curve set dropdown."""
        self._open_curve_library = library
        self._refresh_open_curve_dropdown()

    def _refresh_open_curve_dropdown(self) -> None:
        """Refresh the open curve set dropdown from the open curve library."""
        self._updating = True
        try:
            current_text = self.open_curve_set_combo.currentText()
            self.open_curve_set_combo.clear()
            if self._open_curve_library is not None:
                try:
                    if hasattr(self._open_curve_library, 'curve_sets'):
                        names = sorted(cs.name for cs in self._open_curve_library.curve_sets)
                        self.open_curve_set_combo.addItems(names)
                except Exception:
                    pass
            if current_text:
                index = self.open_curve_set_combo.findText(current_text)
                if index >= 0:
                    self.open_curve_set_combo.setCurrentIndex(index)
                else:
                    self.open_curve_set_combo.setCurrentText(current_text)
        finally:
            self._updating = False

    def set_point_set_library(self, library) -> None:
        """Set the point set library for populating the point set dropdown."""
        self._point_set_library = library
        self._refresh_point_set_dropdown()

    def _refresh_point_set_dropdown(self) -> None:
        """Refresh the point set dropdown from the point set library."""
        self._updating = True
        try:
            current_text = self.point_set_combo.currentText()
            self.point_set_combo.clear()
            if self._point_set_library is not None:
                try:
                    if hasattr(self._point_set_library, 'point_sets'):
                        names = sorted(ps.name for ps in self._point_set_library.point_sets)
                        self.point_set_combo.addItems(names)
                except Exception:
                    pass
            if current_text:
                index = self.point_set_combo.findText(current_text)
                if index >= 0:
                    self.point_set_combo.setCurrentIndex(index)
                else:
                    self.point_set_combo.setCurrentText(current_text)
        finally:
            self._updating = False

    def set_oval_set_library(self, library) -> None:
        """Set the oval set library for populating the oval set dropdown."""
        self._oval_set_library = library
        self._refresh_oval_set_dropdown()

    def _refresh_oval_set_dropdown(self) -> None:
        """Refresh the oval set dropdown from the oval set library."""
        self._updating = True
        try:
            current_text = self.oval_set_combo.currentText()
            self.oval_set_combo.clear()
            if self._oval_set_library is not None:
                try:
                    if hasattr(self._oval_set_library, 'oval_sets'):
                        names = sorted(od.name for od in self._oval_set_library.oval_sets)
                        self.oval_set_combo.addItems(names)
                except Exception:
                    pass
            if current_text:
                index = self.oval_set_combo.findText(current_text)
                if index >= 0:
                    self.oval_set_combo.setCurrentIndex(index)
                else:
                    self.oval_set_combo.setCurrentText(current_text)
        finally:
            self._updating = False

    def set_polygon_library(self, library) -> None:
        """Set the polygon library for populating the polygon set dropdown."""
        self._polygon_library = library
        self._refresh_polygon_dropdown()

    def _refresh_polygon_dropdown(self) -> None:
        """Refresh the polygon set dropdown from the polygon library."""
        self._updating = True
        try:
            current_text = self.polygon_set_combo.currentText()
            self.polygon_set_combo.clear()

            if self._polygon_library is not None:
                try:
                    if hasattr(self._polygon_library, 'polygon_sets'):
                        names = [ps.name for ps in self._polygon_library.polygon_sets]
                        names.sort()
                        self.polygon_set_combo.addItems(names)
                except Exception:
                    pass

            if current_text:
                index = self.polygon_set_combo.findText(current_text)
                if index >= 0:
                    self.polygon_set_combo.setCurrentIndex(index)
                else:
                    self.polygon_set_combo.setCurrentText(current_text)
        finally:
            self._updating = False
