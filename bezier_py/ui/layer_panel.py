"""
LayerPanel — 280-px panel listing all layers (Vis | # | Name).
Mirrors Java LayerPanel.java / org.brogan.ui.LayerPanel.

The panel has two sections:
  • QTableWidget  — regular geometry layers (newest on top)
  • TraceLayerWidget — special collapsed/expanded row for the trace layer;
    only visible when a trace layer exists.

The Trace layer is never greyed out in the table (it is rendered at the
user-configured alpha regardless of which layer is currently active).
"""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QTableWidget, QTableWidgetItem,
    QAbstractItemView, QPushButton, QInputDialog, QMessageBox,
    QHeaderView, QSizePolicy, QCheckBox, QLabel, QSlider, QFrame,
)
from PySide6.QtGui import QFont

from model.layer import Layer
from model.layer_manager import LayerManager


# ── Trace layer widget ────────────────────────────────────────────────────────

class TraceLayerWidget(QFrame):
    """
    Compact row + collapsible slider section for the Trace layer.

    Layout (collapsed):
      [ ✓ ] [ T ]  Trace
      [ ▶ ]

    Layout (expanded, after clicking ▶):
      [ ✓ ] [ T ]  Trace
      [ ▼ ]
      ─────────────────
      Scale  ────●───  1.00×
      Alpha  ────────●  1.00
    """

    def __init__(self, bw, lm: LayerManager,
                 parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._bw = bw
        self._lm = lm
        self._expanded: bool = False
        self._updating: bool = False

        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setFrameShadow(QFrame.Shadow.Raised)
        self._setup_ui()

    # ── UI setup ──────────────────────────────────────────────────────────────

    def _setup_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setContentsMargins(3, 3, 3, 3)
        root.setSpacing(2)

        # ── row 1: vis | index | name ──────────────────────────────────────
        top = QHBoxLayout()
        top.setSpacing(4)

        self._vis_chk = QCheckBox()
        self._vis_chk.setChecked(True)
        self._vis_chk.setFixedWidth(20)
        self._vis_chk.toggled.connect(self._on_vis_changed)
        top.addWidget(self._vis_chk)

        idx_lbl = QLabel("T")
        idx_lbl.setFixedWidth(16)
        idx_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        top.addWidget(idx_lbl)

        self._name_lbl = QLabel("Trace")
        top.addWidget(self._name_lbl, stretch=1)
        root.addLayout(top)

        # ── row 2: expand arrow (lower-left of the row) ────────────────────
        arrow_row = QHBoxLayout()
        arrow_row.setSpacing(0)
        self._arrow_btn = QPushButton("▶")
        self._arrow_btn.setFixedSize(18, 18)
        self._arrow_btn.setFlat(True)
        self._arrow_btn.setToolTip("Show / hide Scale & Alpha sliders")
        self._arrow_btn.clicked.connect(self._toggle_expand)
        arrow_row.addWidget(self._arrow_btn)
        arrow_row.addStretch()
        root.addLayout(arrow_row)

        # ── collapsible slider section ─────────────────────────────────────
        self._slider_widget = QWidget()
        sl = QVBoxLayout(self._slider_widget)
        sl.setContentsMargins(4, 2, 4, 2)
        sl.setSpacing(4)

        # Scale row
        scale_row = QHBoxLayout()
        scale_row.addWidget(QLabel("Scale"))
        self._scale_slider = QSlider(Qt.Orientation.Horizontal)
        self._scale_slider.setRange(10, 400)   # 0.10× … 4.00×
        self._scale_slider.setValue(100)
        scale_row.addWidget(self._scale_slider, stretch=1)
        self._scale_lbl = QLabel("1.00×")
        self._scale_lbl.setFixedWidth(42)
        scale_row.addWidget(self._scale_lbl)
        sl.addLayout(scale_row)

        # Alpha row
        alpha_row = QHBoxLayout()
        alpha_row.addWidget(QLabel("Alpha"))
        self._alpha_slider = QSlider(Qt.Orientation.Horizontal)
        self._alpha_slider.setRange(0, 100)    # 0.00 … 1.00
        self._alpha_slider.setValue(100)
        alpha_row.addWidget(self._alpha_slider, stretch=1)
        self._alpha_lbl = QLabel("1.00")
        self._alpha_lbl.setFixedWidth(32)
        alpha_row.addWidget(self._alpha_lbl)
        sl.addLayout(alpha_row)

        self._slider_widget.setVisible(False)
        root.addWidget(self._slider_widget)

        # Signals
        self._scale_slider.valueChanged.connect(self._on_scale_changed)
        self._alpha_slider.valueChanged.connect(self._on_alpha_changed)

    # ── public ────────────────────────────────────────────────────────────────

    def refresh(self, is_active: bool) -> None:
        """Sync widget state from the current trace layer."""
        trace = self._lm.get_trace_layer()
        if trace is None:
            return
        self._updating = True
        try:
            self._vis_chk.setChecked(trace.visible)
            self._scale_slider.setValue(int(round(trace.trace_scale * 100)))
            self._scale_lbl.setText(f"{trace.trace_scale:.2f}×")
            self._alpha_slider.setValue(int(round(trace.trace_alpha * 100)))
            self._alpha_lbl.setText(f"{trace.trace_alpha:.2f}")
        finally:
            self._updating = False

        # Bold name when this is the active layer; always fully opaque in UI
        f = self._name_lbl.font()
        f.setBold(is_active)
        self._name_lbl.setFont(f)

    # ── interaction ───────────────────────────────────────────────────────────

    def mousePressEvent(self, event) -> None:
        """Clicking the widget row activates the trace layer."""
        trace = self._lm.get_trace_layer()
        if trace is not None:
            self._bw.set_active_layer(trace.id)
            # Tell the parent LayerPanel to deselect geometry table rows and
            # redraw bold states.  We walk up to find LayerPanel.
            parent = self.parent()
            while parent is not None:
                if isinstance(parent, LayerPanel):
                    parent._deselect_table()
                    parent.refresh_table()
                    break
                parent = parent.parent()
        super().mousePressEvent(event)

    # ── slot handlers ─────────────────────────────────────────────────────────

    def _toggle_expand(self) -> None:
        self._expanded = not self._expanded
        self._arrow_btn.setText("▼" if self._expanded else "▶")
        self._slider_widget.setVisible(self._expanded)
        # Resize parent so the panel reflows
        if self.parent():
            self.parent().adjustSize()

    def _on_vis_changed(self, checked: bool) -> None:
        if self._updating:
            return
        trace = self._lm.get_trace_layer()
        if trace is not None:
            trace.visible = checked
            self._bw.update()

    def _on_scale_changed(self, value: int) -> None:
        if self._updating:
            return
        trace = self._lm.get_trace_layer()
        if trace is not None:
            trace.trace_scale = value / 100.0
            self._scale_lbl.setText(f"{trace.trace_scale:.2f}×")
            self._bw.update()

    def _on_alpha_changed(self, value: int) -> None:
        if self._updating:
            return
        trace = self._lm.get_trace_layer()
        if trace is not None:
            trace.trace_alpha = value / 100.0
            self._alpha_lbl.setText(f"{trace.trace_alpha:.2f}")
            self._bw.update()


# ── LayerPanel ────────────────────────────────────────────────────────────────

class LayerPanel(QWidget):
    """
    Left-side panel showing a QTableWidget of geometry layers (newest on top)
    plus an optional TraceLayerWidget at the bottom.

    Communicates with BezierWidget exclusively through BezierWidget's public API.
    """

    # Width matching Java's 280 px
    PANEL_WIDTH = 280

    def __init__(self, bezier_widget, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._bw = bezier_widget
        self._lm: LayerManager = bezier_widget.layer_manager
        self._updating: bool = False   # guard against re-entrant cell-change signals

        self.setFixedWidth(self.PANEL_WIDTH)
        self.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Expanding)

        self._setup_ui()
        self.refresh_table()

    # ── UI setup ──────────────────────────────────────────────────────────────

    def _setup_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setContentsMargins(4, 4, 4, 4)
        root.setSpacing(4)

        # ── geometry layer table ───────────────────────────────────────────
        self._table = QTableWidget(0, 3)
        self._table.setHorizontalHeaderLabels(["Vis", "#", "Name"])
        self._table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self._table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self._table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)

        hdr = self._table.horizontalHeader()
        hdr.setSectionResizeMode(0, QHeaderView.ResizeMode.Fixed)
        hdr.setSectionResizeMode(1, QHeaderView.ResizeMode.Fixed)
        hdr.setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        self._table.setColumnWidth(0, 30)
        self._table.setColumnWidth(1, 30)

        self._table.itemChanged.connect(self._on_item_changed)
        self._table.itemSelectionChanged.connect(self._on_selection_changed)
        root.addWidget(self._table)

        # ── trace layer widget (initially hidden) ─────────────────────────
        self._trace_widget = TraceLayerWidget(self._bw, self._lm, self)
        self._trace_widget.setVisible(False)
        root.addWidget(self._trace_widget)

        # ── buttons — 3 rows of 2 ─────────────────────────────────────────
        self._btn_new  = QPushButton("New")
        self._btn_ren  = QPushButton("Rename")
        self._btn_dup  = QPushButton("Duplicate")
        self._btn_del  = QPushButton("Delete")
        self._btn_up   = QPushButton("↑")
        self._btn_dn   = QPushButton("↓")

        self._btn_new.clicked.connect(self._on_new)
        self._btn_ren.clicked.connect(self._on_rename)
        self._btn_del.clicked.connect(self._on_delete)
        self._btn_dup.clicked.connect(self._on_duplicate)
        self._btn_up.clicked.connect(lambda: self._on_move(-1))
        self._btn_dn.clicked.connect(lambda: self._on_move(1))

        btn_section = QVBoxLayout()
        btn_section.setSpacing(3)
        for pair in ((self._btn_new, self._btn_ren),
                     (self._btn_dup, self._btn_del),
                     (self._btn_up,  self._btn_dn)):
            row = QHBoxLayout()
            row.setSpacing(3)
            row.addWidget(pair[0])
            row.addWidget(pair[1])
            btn_section.addLayout(row)
        root.addLayout(btn_section)

    # ── public API ────────────────────────────────────────────────────────────

    def refresh_table(self) -> None:
        """Rebuild the table from the current LayerManager state."""
        self._updating = True
        try:
            geo_layers = self._lm.geometry_layers()
            self._table.setRowCount(0)
            # Display newest geometry layer (highest index) on top
            for i in range(len(geo_layers) - 1, -1, -1):
                layer = geo_layers[i]
                row = self._table.rowCount()
                self._table.insertRow(row)

                # Col 0: visibility checkbox
                vis_item = QTableWidgetItem()
                vis_item.setFlags(Qt.ItemFlag.ItemIsUserCheckable |
                                  Qt.ItemFlag.ItemIsEnabled |
                                  Qt.ItemFlag.ItemIsSelectable)
                vis_item.setCheckState(
                    Qt.CheckState.Checked if layer.visible
                    else Qt.CheckState.Unchecked
                )
                self._table.setItem(row, 0, vis_item)

                # Col 1: display index (1 = bottom geometry layer)
                idx_item = QTableWidgetItem(str(len(geo_layers) - i))
                idx_item.setFlags(Qt.ItemFlag.ItemIsEnabled |
                                  Qt.ItemFlag.ItemIsSelectable)
                self._table.setItem(row, 1, idx_item)

                # Col 2: name (bold if active)
                name_item = QTableWidgetItem(layer.name)
                name_item.setFlags(Qt.ItemFlag.ItemIsEnabled |
                                   Qt.ItemFlag.ItemIsSelectable)
                if layer.id == self._lm.active_layer_id:
                    f = name_item.font()
                    f.setBold(True)
                    name_item.setFont(f)
                self._table.setItem(row, 2, name_item)

            # Show/hide trace widget and sync its state
            trace = self._lm.get_trace_layer()
            self._trace_widget.setVisible(trace is not None)
            if trace is not None:
                is_trace_active = (trace.id == self._lm.active_layer_id)
                self._trace_widget.refresh(is_trace_active)

            # Highlight current active layer row (if it is a geometry layer)
            self._select_layer_in_table(self._lm.active_layer_id)
            self._btn_del.setEnabled(
                len(geo_layers) > 1
                or (trace is not None and self._lm.active_layer_id == trace.id)
            )
        finally:
            self._updating = False

    def _deselect_table(self) -> None:
        """Clear the geometry table selection (called when trace layer is activated)."""
        self._updating = True
        try:
            self._table.clearSelection()
        finally:
            self._updating = False

    # ── signal handlers ───────────────────────────────────────────────────────

    def _on_item_changed(self, item: QTableWidgetItem) -> None:
        if self._updating:
            return
        if item.column() != 0:
            return
        layer = self._layer_at_row(item.row())
        if layer is None:
            return
        layer.visible = (item.checkState() == Qt.CheckState.Checked)
        self._bw.update()

    def _on_selection_changed(self) -> None:
        if self._updating:
            return
        layer = self._get_selected_layer()
        if layer is None:
            return
        self._bw.set_active_layer(layer.id)
        # Refresh to update bold without full table rebuild
        self.refresh_table()

    # ── button handlers ───────────────────────────────────────────────────────

    def _on_new(self) -> None:
        name, ok = QInputDialog.getText(self, "New Layer", "Layer name:")
        if not ok or not name.strip():
            return
        layer = self._lm.create_layer(name.strip())
        self._bw.set_active_layer(layer.id)
        self.refresh_table()

    def _on_rename(self) -> None:
        layer = self._get_selected_layer()
        if layer is None:
            return
        name, ok = QInputDialog.getText(self, "Rename Layer", "New name:",
                                        text=layer.name)
        if not ok or not name.strip():
            return
        self._lm.rename_layer(layer.id, name.strip())
        self.refresh_table()

    def _on_delete(self) -> None:
        # Determine which layer to delete: geometry table selection, or trace widget
        active_id = self._lm.active_layer_id
        trace     = self._lm.get_trace_layer()
        is_trace_delete = (trace is not None and active_id == trace.id)

        if is_trace_delete:
            ans = QMessageBox.question(
                self, "Delete Trace Layer",
                "Remove the Trace layer?\nThis cannot be undone.",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            )
            if ans != QMessageBox.StandardButton.Yes:
                return
            self._lm.delete_layer(trace.id)
            self._bw.polygon_manager.sync_active_drawing_manager_layer()
            self.refresh_table()
            self._bw.modified.emit()
            return

        # Regular geometry layer deletion
        layer = self._get_selected_layer()
        if layer is None or len(self._lm.geometry_layers()) <= 1:
            return
        has_polys = bool(
            self._bw.polygon_manager.get_managers_for_layer(layer.id)
        )
        if has_polys:
            ans = QMessageBox.question(
                self, "Delete Layer",
                f'Layer "{layer.name}" contains polygons.\nDelete cannot be undone. Proceed?',
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            )
            if ans != QMessageBox.StandardButton.Yes:
                return
            committed = self._bw.polygon_manager.committed_managers()
            to_remove = [m for m in committed if m.layer_id == layer.id]
            for m in to_remove:
                try:
                    idx = self._bw.polygon_manager._managers.index(m)
                    self._bw.polygon_manager._managers.pop(idx)
                except ValueError:
                    pass
        self._bw.oval_list = [o for o in self._bw.oval_list
                              if o.layer_id != layer.id]
        self._lm.delete_layer(layer.id)
        self._bw.polygon_manager.sync_active_drawing_manager_layer()
        self.refresh_table()
        self._bw.modified.emit()

    def _on_duplicate(self) -> None:
        layer = self._get_selected_layer()
        if layer is None:
            return
        dup = self._lm.duplicate_layer(layer.id,
                                        self._bw.polygon_manager)
        if dup is not None:
            self._bw.set_active_layer(dup.id)
            self.refresh_table()
            self._bw.modified.emit()

    def _on_move(self, delta: int) -> None:
        """
        delta=-1 → button "↑" (move layer toward top of display = toward end of list)
        delta=+1 → button "↓" (move layer toward bottom of display = toward start of list)
        Display order is reversed from list order, so ↑ = moveLayerDown in Java.
        """
        layer = self._get_selected_layer()
        if layer is None:
            return
        if delta < 0:
            self._lm.move_layer_down(layer.id)
        else:
            self._lm.move_layer_up(layer.id)
        self.refresh_table()
        self._select_layer_in_table(layer.id)

    # ── helpers ───────────────────────────────────────────────────────────────

    def _layer_at_row(self, row: int) -> Layer | None:
        """Map a table row index to the corresponding geometry Layer."""
        geo = self._lm.geometry_layers()
        # Row 0 = last in geometry list (newest on top)
        idx = len(geo) - 1 - row
        if 0 <= idx < len(geo):
            return geo[idx]
        return None

    def _get_selected_layer(self) -> Layer | None:
        rows = self._table.selectedItems()
        if not rows:
            return None
        return self._layer_at_row(self._table.currentRow())

    def _select_layer_in_table(self, layer_id: int) -> None:
        geo = self._lm.geometry_layers()
        for i in range(len(geo) - 1, -1, -1):
            if geo[i].id == layer_id:
                row = len(geo) - 1 - i
                self._table.selectRow(row)
                return
        # layer_id belongs to trace layer — clear table selection
        self._table.clearSelection()
