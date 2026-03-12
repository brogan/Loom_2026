package org.brogan.ui;

import org.brogan.bezier.Layer;
import org.brogan.bezier.LayerManager;
import org.brogan.bezier.BezierDrawPanel;

import javax.swing.*;
import javax.swing.border.TitledBorder;
import javax.swing.table.DefaultTableModel;
import javax.swing.table.TableCellRenderer;
import java.awt.*;
import java.awt.event.*;
import java.util.List;

/**
 * A 280px-wide panel placed to the left of the drawing canvas.
 * Displays all layers in a table (Vis | # | Name) and provides
 * buttons to create, rename, duplicate, delete, and reorder layers.
 */
public class LayerPanel extends JPanel {

    private final LayerManager layerManager;
    private final BezierDrawPanel bezier;

    private final DefaultTableModel tableModel;
    private final JTable table;
    private final JButton deleteButton;

    public LayerPanel(LayerManager lm, BezierDrawPanel b) {
        this.layerManager = lm;
        this.bezier = b;

        setPreferredSize(new Dimension(280, 0));
        setLayout(new BorderLayout(0, 4));
        setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createTitledBorder("Layers"),
                BorderFactory.createEmptyBorder(2, 2, 2, 2)));

        // ── Table ──────────────────────────────────────────────────────────
        tableModel = new DefaultTableModel(new Object[]{"Vis", "#", "Name"}, 0) {
            @Override public Class<?> getColumnClass(int col) {
                if (col == 0) return Boolean.class;
                if (col == 1) return Integer.class;
                return String.class;
            }
            @Override public boolean isCellEditable(int row, int col) {
                return col == 0; // only the checkbox column
            }
        };

        table = new JTable(tableModel);
        table.setSelectionMode(ListSelectionModel.SINGLE_SELECTION);
        table.getColumnModel().getColumn(0).setPreferredWidth(30);
        table.getColumnModel().getColumn(0).setMaxWidth(30);
        table.getColumnModel().getColumn(1).setPreferredWidth(30);
        table.getColumnModel().getColumn(1).setMaxWidth(30);
        table.getColumnModel().getColumn(2).setPreferredWidth(200);

        // Bold the name cell for the active layer
        table.getColumnModel().getColumn(2).setCellRenderer(new TableCellRenderer() {
            private final JLabel label = new JLabel();
            public Component getTableCellRendererComponent(JTable t, Object value,
                    boolean isSelected, boolean hasFocus, int row, int col) {
                label.setText(value == null ? "" : value.toString());
                label.setOpaque(true);
                List<Layer> layers = layerManager.getLayers();
                if (row >= 0 && row < layers.size()) {
                    Layer l = layers.get(layers.size() - 1 - row); // display order: newest on top
                    label.setFont(label.getFont().deriveFont(
                            l.getId() == layerManager.getActiveLayerId() ? Font.BOLD : Font.PLAIN));
                }
                label.setBackground(isSelected ? table.getSelectionBackground() : table.getBackground());
                label.setForeground(isSelected ? table.getSelectionForeground() : table.getForeground());
                return label;
            }
        });

        // Checkbox toggles visibility
        tableModel.addTableModelListener(e -> {
            if (e.getColumn() != 0) return;
            int row = e.getFirstRow();
            List<Layer> layers = layerManager.getLayers();
            int idx = layers.size() - 1 - row;
            if (idx < 0 || idx >= layers.size()) return;
            Layer l = layers.get(idx);
            Boolean vis = (Boolean) tableModel.getValueAt(row, 0);
            l.setVisible(vis != null && vis);
            bezier.repaint();
        });

        // Row click → set active layer
        table.getSelectionModel().addListSelectionListener(e -> {
            if (e.getValueIsAdjusting()) return;
            int row = table.getSelectedRow();
            if (row < 0) return;
            List<Layer> layers = layerManager.getLayers();
            int idx = layers.size() - 1 - row;
            if (idx >= 0 && idx < layers.size()) {
                layerManager.setActiveLayerId(layers.get(idx).getId());
                bezier.getPolygonManager().syncActiveDrawingManagerLayer();
                bezier.repaint();
                repaint();
            }
        });

        JScrollPane scroll = new JScrollPane(table);
        add(scroll, BorderLayout.CENTER);

        // ── Buttons ────────────────────────────────────────────────────────
        JButton newBtn  = new JButton("New");
        JButton renBtn  = new JButton("Rename");
        JButton dupBtn  = new JButton("Duplicate");
        deleteButton    = new JButton("Delete");
        JButton upBtn   = new JButton("↑");
        JButton dnBtn   = new JButton("↓");

        newBtn.addActionListener(e -> onNew());
        renBtn.addActionListener(e -> onRename());
        dupBtn.addActionListener(e -> onDuplicate());
        deleteButton.addActionListener(e -> onDelete());
        upBtn.addActionListener(e -> onMove(-1));
        dnBtn.addActionListener(e -> onMove(1));

        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 3, 3));
        btnRow.add(newBtn);
        btnRow.add(renBtn);
        btnRow.add(dupBtn);
        btnRow.add(deleteButton);
        btnRow.add(upBtn);
        btnRow.add(dnBtn);
        add(btnRow, BorderLayout.SOUTH);

        refreshTable();
    }

    // ── Button handlers ────────────────────────────────────────────────────

    private void onNew() {
        String name = JOptionPane.showInputDialog(this, "Layer name:", "New Layer", JOptionPane.PLAIN_MESSAGE);
        if (name == null || name.trim().isEmpty()) return;
        Layer l = layerManager.createLayer(name.trim());
        layerManager.setActiveLayerId(l.getId());
        bezier.getPolygonManager().syncActiveDrawingManagerLayer();
        refreshTable();
        bezier.repaint();
    }

    private void onRename() {
        Layer l = getSelectedLayer();
        if (l == null) return;
        String name = (String) JOptionPane.showInputDialog(this, "New name:", "Rename Layer",
                JOptionPane.PLAIN_MESSAGE, null, null, l.getName());
        if (name == null || name.trim().isEmpty()) return;
        layerManager.renameLayer(l.getId(), name.trim());
        refreshTable();
    }

    private void onDuplicate() {
        Layer l = getSelectedLayer();
        if (l == null) return;
        Layer dup = layerManager.duplicateLayer(l.getId(), bezier.getPolygonManager());
        if (dup != null) {
            layerManager.setActiveLayerId(dup.getId());
            bezier.getPolygonManager().syncActiveDrawingManagerLayer();
            refreshTable();
            bezier.repaint();
        }
    }

    private void onDelete() {
        Layer l = getSelectedLayer();
        if (l == null) return;
        if (layerManager.getLayers().size() <= 1) return;
        // Check if layer has polygons
        boolean hasPolys = !bezier.getPolygonManager().getManagersForLayer(l.getId()).isEmpty();
        if (hasPolys) {
            int confirm = JOptionPane.showConfirmDialog(this,
                    "Layer \"" + l.getName() + "\" contains polygons.\nDelete cannot be undone. Proceed?",
                    "Delete Layer", JOptionPane.YES_NO_OPTION, JOptionPane.WARNING_MESSAGE);
            if (confirm != JOptionPane.YES_OPTION) return;
            // Remove polygons first
            java.util.List<org.brogan.bezier.CubicCurveManager> managers =
                    bezier.getPolygonManager().getManagersForLayer(l.getId());
            // Remove in reverse index order so indices stay valid
            java.util.List<org.brogan.bezier.CubicCurveManager> toDelete = new java.util.ArrayList<>(managers);
            for (int i = toDelete.size() - 1; i >= 0; i--) {
                org.brogan.bezier.CubicCurveManager m = toDelete.get(i);
                int count = bezier.getPolygonManager().getPolygonCount();
                for (int j = 0; j < count; j++) {
                    if (bezier.getPolygonManager().getManager(j) == m) {
                        bezier.getPolygonManager().removeManagerAtIndex(j);
                        break;
                    }
                }
            }
        }
        layerManager.deleteLayer(l.getId());
        refreshTable();
        bezier.repaint();
    }

    /** delta=-1 → move up (toward index 0 = bottom of list), delta=+1 → move down */
    private void onMove(int delta) {
        Layer l = getSelectedLayer();
        if (l == null) return;
        // Display order is reversed (top row = last in list), so UI up = list down
        if (delta < 0) layerManager.moveLayerDown(l.getId());
        else           layerManager.moveLayerUp(l.getId());
        refreshTable();
        // Re-select the moved layer
        selectLayerInTable(l.getId());
        bezier.repaint();
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private Layer getSelectedLayer() {
        int row = table.getSelectedRow();
        if (row < 0) return null;
        List<Layer> layers = layerManager.getLayers();
        int idx = layers.size() - 1 - row;
        if (idx < 0 || idx >= layers.size()) return null;
        return layers.get(idx);
    }

    /** Rebuild the table from the current LayerManager state and re-select the active layer. */
    public void refreshTable() {
        tableModel.setRowCount(0);
        List<Layer> layers = layerManager.getLayers();
        // Display newest / topmost first
        for (int i = layers.size() - 1; i >= 0; i--) {
            Layer l = layers.get(i);
            tableModel.addRow(new Object[]{l.isVisible(), layers.size() - i, l.getName()});
        }
        deleteButton.setEnabled(layers.size() > 1);
        selectLayerInTable(layerManager.getActiveLayerId());
    }

    private void selectLayerInTable(int layerId) {
        List<Layer> layers = layerManager.getLayers();
        for (int i = layers.size() - 1; i >= 0; i--) {
            if (layers.get(i).getId() == layerId) {
                int row = layers.size() - 1 - i;
                if (row >= 0 && row < table.getRowCount()) {
                    table.setRowSelectionInterval(row, row);
                }
                return;
            }
        }
    }
}
