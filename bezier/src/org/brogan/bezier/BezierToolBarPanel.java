package org.brogan.bezier;

import java.awt.Dimension;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.awt.Color;

import javax.swing.*;
import javax.swing.event.ChangeListener;

public class BezierToolBarPanel extends JPanel {

	private BezierDrawPanel bezier;
	private JToolBar toolBar;

	// Toggle buttons — show selected icon while their mode is active
	private JToggleButton selectionMode, edgeSelectionMode, polygonSelectionMode;
	private JToggleButton polygonMode, pointModeToggle;
	private JToggleButton hideGrid, hideControls, hideReferenceImage;
	private JToggleButton knifeTool;
	private JToggleButton openCurveSelectionMode;
	private JToggleButton drawCurveMode;
	private JSlider detailSlider;

	// Paired selected-state icons for the three selection modes (relational vs discrete)
	private ImageIcon pointRelationalIcon, pointDiscreteIcon;
	private ImageIcon edgeRelationalIcon,  edgeDiscreteIcon;
	private ImageIcon polyRelationalIcon,  polyDiscreteIcon;

	// Action buttons — momentary, no persistent highlight
	private JButton createOvalButton;
	private JButton closeCurves, finishOpenCurve, intersect, duplicatePolygon, flipHorizontal, flipVertical;
	private JButton snapAnchors, snapAll, centre;
	private JButton zoomIn, zoomOut;
	private JButton clearGrid, deleteSelected;

	// Weld — toggle controls auto-weld during polygon drag; also performs manual edge weld
	private JToggleButton weld;
	private JButton weldAll;

	public BezierToolBarPanel(BezierDrawPanel bez) {
		bezier = bez;
		createToolBar();
		bezier.setStrokeColor(new Color(0, 0, 0));
	}

	private void createToolBar() {

		CubicCurvePolygonManager polygonManager = bezier.getPolygonManager();

		toolBar = new JToolBar("tools");
		toolBar.setFloatable(false);

		// ── Selection modes ────────────────────────────────────────────────────

		selectionMode = new JToggleButton();
		initToggle(selectionMode, "Point Selection Mode (Cmd+click for Discrete)", "selectPoint");
		pointRelationalIcon = loadIcon("selectPoint_selected");
		pointDiscreteIcon   = loadIcon("selectPoint_selected_shift");
		selectionMode.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.autoFinishOpenCurveIfNeeded();
				int idx = polygonManager.getPolygonCount();
				polygonManager.getManager(idx).setAddPoints(false);
				polygonMode.setSelected(false);
				pointModeToggle.setSelected(false);
				edgeSelectionMode.setSelected(false);
				polygonSelectionMode.setSelected(false);
				openCurveSelectionMode.setSelected(false);
				knifeTool.setSelected(false);
				drawCurveMode.setSelected(false);
				bezier.setKnifeMode(false);
				bezier.setFreehandMode(false);
				bezier.setOpenCurveSelectionMode(false);
				bezier.setPointMode(false);
				bezier.setEdgeSelectionMode(false);
				bezier.setPolygonSelectionMode(false);
				bezier.setPointSelectionMode(selectionMode.isSelected());
				BezierDrawPanel.SelectionSubMode m = ((e.getModifiers() & ActionEvent.META_MASK) != 0)
					? BezierDrawPanel.SelectionSubMode.DISCRETE
					: BezierDrawPanel.SelectionSubMode.RELATIONAL;
				bezier.setPointSubMode(m);
				selectionMode.setSelectedIcon(m == BezierDrawPanel.SelectionSubMode.DISCRETE
					? pointDiscreteIcon : pointRelationalIcon);
			}
		});
		toolBar.add(selectionMode);

		edgeSelectionMode = new JToggleButton();
		initToggle(edgeSelectionMode, "Edge Selection Mode (Cmd+click for Discrete)", "selectEdge");
		edgeRelationalIcon = loadIcon("selectEdge_selected");
		edgeDiscreteIcon   = loadIcon("selectEdge_selected_shift");
		edgeSelectionMode.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.autoFinishOpenCurveIfNeeded();
				int idx = polygonManager.getPolygonCount();
				polygonManager.getManager(idx).setAddPoints(false);
				polygonMode.setSelected(false);
				pointModeToggle.setSelected(false);
				selectionMode.setSelected(false);
				polygonSelectionMode.setSelected(false);
				openCurveSelectionMode.setSelected(false);
				knifeTool.setSelected(false);
				drawCurveMode.setSelected(false);
				bezier.setKnifeMode(false);
				bezier.setFreehandMode(false);
				bezier.setOpenCurveSelectionMode(false);
				bezier.setPointMode(false);
				bezier.setPolygonSelectionMode(false);
				bezier.setPointSelectionMode(false);
				bezier.setEdgeSelectionMode(edgeSelectionMode.isSelected());
				BezierDrawPanel.SelectionSubMode m = ((e.getModifiers() & ActionEvent.META_MASK) != 0)
					? BezierDrawPanel.SelectionSubMode.DISCRETE
					: BezierDrawPanel.SelectionSubMode.RELATIONAL;
				bezier.setEdgeSubMode(m);
				edgeSelectionMode.setSelectedIcon(m == BezierDrawPanel.SelectionSubMode.DISCRETE
					? edgeDiscreteIcon : edgeRelationalIcon);
			}
		});
		toolBar.add(edgeSelectionMode);

		openCurveSelectionMode = new JToggleButton();
		initToggle(openCurveSelectionMode, "Open Curve Selection Mode", "curve");
		openCurveSelectionMode.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.autoFinishOpenCurveIfNeeded();
				int idx = polygonManager.getPolygonCount();
				polygonManager.getManager(idx).setAddPoints(false);
				polygonMode.setSelected(false);
				pointModeToggle.setSelected(false);
				selectionMode.setSelected(false);
				edgeSelectionMode.setSelected(false);
				polygonSelectionMode.setSelected(false);
				knifeTool.setSelected(false);
				drawCurveMode.setSelected(false);
				bezier.setKnifeMode(false);
				bezier.setFreehandMode(false);
				bezier.setPointMode(false);
				bezier.setEdgeSelectionMode(false);
				bezier.setPolygonSelectionMode(false);
				bezier.setPointSelectionMode(false);
				bezier.setOpenCurveSelectionMode(openCurveSelectionMode.isSelected());
			}
		});
		toolBar.add(openCurveSelectionMode);

		polygonSelectionMode = new JToggleButton();
		initToggle(polygonSelectionMode, "Polygon Selection Mode (Cmd+click for Discrete)", "selectPolygon");
		polyRelationalIcon = loadIcon("selectPolygon_selected");
		polyDiscreteIcon   = loadIcon("selectPolygon_selected_shift");
		polygonSelectionMode.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.autoFinishOpenCurveIfNeeded();
				int idx = polygonManager.getPolygonCount();
				polygonManager.getManager(idx).setAddPoints(false);
				polygonMode.setSelected(false);
				pointModeToggle.setSelected(false);
				selectionMode.setSelected(false);
				edgeSelectionMode.setSelected(false);
				openCurveSelectionMode.setSelected(false);
				knifeTool.setSelected(false);
				drawCurveMode.setSelected(false);
				bezier.setKnifeMode(false);
				bezier.setFreehandMode(false);
				bezier.setOpenCurveSelectionMode(false);
				bezier.setPointMode(false);
				bezier.setEdgeSelectionMode(false);
				bezier.setPointSelectionMode(false);
				bezier.setPolygonSelectionMode(polygonSelectionMode.isSelected());
				BezierDrawPanel.SelectionSubMode m = ((e.getModifiers() & ActionEvent.META_MASK) != 0)
					? BezierDrawPanel.SelectionSubMode.DISCRETE
					: BezierDrawPanel.SelectionSubMode.RELATIONAL;
				bezier.setPolySubMode(m);
				polygonSelectionMode.setSelectedIcon(m == BezierDrawPanel.SelectionSubMode.DISCRETE
					? polyDiscreteIcon : polyRelationalIcon);
			}
		});
		toolBar.add(polygonSelectionMode);

		toolBar.addSeparator();

		// ── Creation / editing ─────────────────────────────────────────────────

		pointModeToggle = new JToggleButton();
		initToggle(pointModeToggle, "Create Points Mode", "createPoint");
		pointModeToggle.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.autoFinishOpenCurveIfNeeded();
				int idx = polygonManager.getPolygonCount();
				polygonManager.getManager(idx).setAddPoints(false);
				selectionMode.setSelected(false);
				edgeSelectionMode.setSelected(false);
				polygonSelectionMode.setSelected(false);
				openCurveSelectionMode.setSelected(false);
				polygonMode.setSelected(false);
				knifeTool.setSelected(false);
				drawCurveMode.setSelected(false);
				bezier.setKnifeMode(false);
				bezier.setFreehandMode(false);
				bezier.setOpenCurveSelectionMode(false);
				bezier.setEdgeSelectionMode(false);
				bezier.setPolygonSelectionMode(false);
				bezier.setPointSelectionMode(false);
				bezier.setPointMode(pointModeToggle.isSelected());
			}
		});
		toolBar.add(pointModeToggle);

		createOvalButton = new JButton();
		initButton(createOvalButton, "Create Oval", "oval");
		createOvalButton.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.autoFinishOpenCurveIfNeeded();
				// Turn off all other modes
				int idx = polygonManager.getPolygonCount();
				polygonManager.getManager(idx).setAddPoints(false);
				selectionMode.setSelected(false);
				edgeSelectionMode.setSelected(false);
				polygonSelectionMode.setSelected(true);
				openCurveSelectionMode.setSelected(false);
				pointModeToggle.setSelected(false);
				polygonMode.setSelected(false);
				knifeTool.setSelected(false);
				drawCurveMode.setSelected(false);
				bezier.setKnifeMode(false);
				bezier.setFreehandMode(false);
				bezier.setOpenCurveSelectionMode(false);
				bezier.setPointMode(false);
				bezier.setEdgeSelectionMode(false);
				bezier.setPointSelectionMode(false);
				bezier.setPolygonSelectionMode(true);
				bezier.createOval();
			}
		});
		toolBar.add(createOvalButton);

		polygonMode = new JToggleButton();
		initToggle(polygonMode, "Create Polygons Mode", "createPolygon");
		polygonMode.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				if (!polygonMode.isSelected()) bezier.autoFinishOpenCurveIfNeeded();
				int idx = polygonManager.getPolygonCount();
				polygonManager.getManager(idx).setAddPoints(polygonMode.isSelected());
				selectionMode.setSelected(false);
				pointModeToggle.setSelected(false);
				edgeSelectionMode.setSelected(false);
				polygonSelectionMode.setSelected(false);
				openCurveSelectionMode.setSelected(false);
				drawCurveMode.setSelected(false);
				bezier.setFreehandMode(false);
				bezier.setOpenCurveSelectionMode(false);
				bezier.setPointMode(false);
				bezier.setEdgeSelectionMode(false);
				bezier.setPolygonSelectionMode(false);
				bezier.setPointSelectionMode(false);
			}
		});
		toolBar.add(polygonMode);

		toolBar.addSeparator();

		drawCurveMode = new JToggleButton();
		initToggle(drawCurveMode,
			"Freehand Draw Curve — drag to draw; approach start point to close as polygon",
			"draw");
		drawCurveMode.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.autoFinishOpenCurveIfNeeded();
				int idx = polygonManager.getPolygonCount();
				polygonManager.getManager(idx).setAddPoints(false);
				selectionMode.setSelected(false);
				edgeSelectionMode.setSelected(false);
				polygonSelectionMode.setSelected(false);
				polygonMode.setSelected(false);
				pointModeToggle.setSelected(false);
				knifeTool.setSelected(false);
				bezier.setKnifeMode(false);
				bezier.setPointMode(false);
				bezier.setEdgeSelectionMode(false);
				bezier.setPolygonSelectionMode(false);
				bezier.setPointSelectionMode(false);
				openCurveSelectionMode.setSelected(false);
				bezier.setOpenCurveSelectionMode(false);
				bezier.setFreehandMode(drawCurveMode.isSelected());
			}
		});
		toolBar.add(drawCurveMode);

		JLabel detailLabel = new JLabel("Detail:");
		detailLabel.setFont(detailLabel.getFont().deriveFont(10f));
		toolBar.add(detailLabel);
		detailSlider = new JSlider(1, 50, 10);
		detailSlider.setPreferredSize(new Dimension(80, 24));
		detailSlider.setMaximumSize(new Dimension(80, 24));
		detailSlider.setToolTipText("Freehand detail: right = more segments (accurate fit), left = fewer/simpler");
		detailSlider.addChangeListener(e -> bezier.setFreehandErrorThreshold(51 - detailSlider.getValue()));
		toolBar.add(detailSlider);

		toolBar.addSeparator();

		closeCurves = new JButton();
		initButton(closeCurves, "Close Polygon", "closePolygon");
		closeCurves.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.takeUndoSnapshot();
				int polygonCount = polygonManager.getPolygonCount();
				CubicCurveManager curveManager = polygonManager.getManager(polygonCount);

				// If the active drawing manager has no points, check whether the most
				// recently committed shape is an open curve and close that instead.
				// This supports: draw freehand open curve → click Close Polygon.
				if (curveManager.getCurves().getCubicCurveTotal() == 0 && polygonCount > 0) {
					CubicCurveManager prev = polygonManager.getManager(polygonCount - 1);
					if (!prev.getIsClosed() && prev.getCurves().getCubicCurveTotal() > 0) {
						prev.closeOpenCurve(bezier.getStrokeColor());
						prev.setCurrentBezierPosition(prev.getAverageXY());
						activatePolygonSelectionMode();
						bezier.repaint();
						return;
					}
				}

				curveManager.closeCurve(bezier.getStrokeColor());
				curveManager.setCurrentBezierPosition(curveManager.getAverageXY());
				polygonManager.addManager();
				activatePolygonSelectionMode();
			}
		});
		toolBar.add(closeCurves);

		finishOpenCurve = new JButton();
		initButton(finishOpenCurve, "Finish Open Curve (no closing edge)", "openCurve");
		finishOpenCurve.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.takeUndoSnapshot();
				int polygonCount = polygonManager.getPolygonCount();
				CubicCurveManager curveManager = polygonManager.getManager(polygonCount);
				curveManager.finishOpen();
				curveManager.setCurrentBezierPosition(curveManager.getAverageXY());
				polygonManager.addManager();
				activatePolygonSelectionMode();
			}
		});
		toolBar.add(finishOpenCurve);

		toolBar.addSeparator();

		intersect = new JButton();
		initButton(intersect, "Intersect — build quad mesh between two concentric polygons (Shift: keep inner)", "intersect");
		intersect.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				boolean keepInner = (e.getModifiers() & ActionEvent.SHIFT_MASK) != 0;
				bezier.performIntersect(keepInner);
			}
		});
		toolBar.add(intersect);

		knifeTool = new JToggleButton();
		initToggle(knifeTool, "Knife Cut Tool", "knife");
		knifeTool.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				boolean active = knifeTool.isSelected();
				if (active) {
					bezier.autoFinishOpenCurveIfNeeded();
					polygonMode.setSelected(false);
					pointModeToggle.setSelected(false);
					selectionMode.setSelected(false);
					edgeSelectionMode.setSelected(false);
					polygonSelectionMode.setSelected(false);
					drawCurveMode.setSelected(false);
					bezier.setPointMode(false);
					bezier.setFreehandMode(false);
					openCurveSelectionMode.setSelected(false);
					bezier.setOpenCurveSelectionMode(false);
					bezier.setKnifeMode(true);
				} else {
					bezier.setKnifeMode(false);
					BezierDrawPanel.PrevMode prev = bezier.getPrevModeBeforeKnife();
					if (prev == BezierDrawPanel.PrevMode.POINT) {
						selectionMode.setSelected(true);
						bezier.setPointSelectionMode(true);
					} else if (prev == BezierDrawPanel.PrevMode.EDGE) {
						edgeSelectionMode.setSelected(true);
						bezier.setEdgeSelectionMode(true);
					} else if (prev == BezierDrawPanel.PrevMode.POLYGON) {
						polygonSelectionMode.setSelected(true);
						bezier.setPolygonSelectionMode(true);
					}
					refreshSubModeIcons();
				}
			}
		});
		toolBar.add(knifeTool);

		toolBar.addSeparator();

		duplicatePolygon = new JButton();
		initButton(duplicatePolygon, "Duplicate Selected Polygons", "duplicatePolygon");
		duplicatePolygon.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.performDuplicate();
			}
		});
		toolBar.add(duplicatePolygon);

		flipHorizontal = new JButton();
		initButton(flipHorizontal, "Flip Horizontal", "flipHorizontal");
		flipHorizontal.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.performFlip(true);
			}
		});
		toolBar.add(flipHorizontal);

		flipVertical = new JButton();
		initButton(flipVertical, "Flip Vertical", "flipVertical");
		flipVertical.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.performFlip(false);
			}
		});
		toolBar.add(flipVertical);

		weld = new JToggleButton();
		initToggle(weld, "Auto-Weld on drag (toggle); click with edges selected to weld manually", "weld");
		weld.setSelected(true);  // auto-weld on by default
		weld.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				if (bezier.isEdgeSelectionModeEnabled() && bezier.hasSelectedEdges()) {
					// Manual edge weld — act like a button, keep auto-weld state unchanged
					bezier.performWeld();
					weld.setSelected(!weld.isSelected()); // revert toggle visual state
				} else {
					// Pure toggle — enable/disable auto-weld during polygon drag
					bezier.setAutoWeldEnabled(weld.isSelected());
				}
			}
		});
		toolBar.add(weld);

		weldAll = new JButton();
		initButton(weldAll, "Weld All Adjacent — snap and link all edge pairs within 5 px", "weldAll");
		weldAll.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.weldAllAdjacent(5.0);
			}
		});
		toolBar.add(weldAll);

		toolBar.addSeparator();

		// ── Snapping ───────────────────────────────────────────────────────────

		snapAnchors = new JButton();
		initButton(snapAnchors, "Snap Anchor Points to Grid", "snapAnchors");
		snapAnchors.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.snapToGrid(false);
			}
		});
		toolBar.add(snapAnchors);

		snapAll = new JButton();
		initButton(snapAll, "Snap Anchor & Control Points to Grid", "snapAnchorsControls");
		snapAll.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.snapToGrid(true);
			}
		});
		toolBar.add(snapAll);

		centre = new JButton();
		initButton(centre, "Centre Selected Polygons", "center");
		centre.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.performCentre();
			}
		});
		toolBar.add(centre);

		toolBar.addSeparator();

		// ── Zoom ──────────────────────────────────────────────────────────────

		zoomIn = new JButton();
		initButton(zoomIn, "Zoom In", "zoomIn");
		zoomIn.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.zoomIn();
			}
		});
		toolBar.add(zoomIn);

		zoomOut = new JButton();
		initButton(zoomOut, "Zoom Out", "zoomOut");
		zoomOut.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.zoomOut();
			}
		});
		toolBar.add(zoomOut);

		toolBar.addSeparator();

		// ── View toggles ───────────────────────────────────────────────────────

		hideGrid = new JToggleButton();
		initToggle(hideGrid, "Toggle Grid Display", "hideGrid");
		hideGrid.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.toggleGridDisplay();
				bezier.toggleGridAxesDisplay();
			}
		});
		toolBar.add(hideGrid);

		hideControls = new JToggleButton();
		initToggle(hideControls, "Toggle Control Point Display", "hideControlPoints");
		hideControls.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				int tot = polygonManager.getPolygonCount();
				for (int i = 0; i < tot; i++) polygonManager.getManager(i).hideControls();
			}
		});
		toolBar.add(hideControls);

		hideReferenceImage = new JToggleButton();
		initToggle(hideReferenceImage, "Toggle Reference Image Display", "hideReferenceImage");
		hideReferenceImage.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.toggleDisplayReferenceImage();
			}
		});
		toolBar.add(hideReferenceImage);

		toolBar.addSeparator();

		// ── Destructive actions ────────────────────────────────────────────────

		clearGrid = new JButton();
		initButton(clearGrid, "Clear All Geometry", "clearGeometry");
		clearGrid.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.takeUndoSnapshot();
				polygonManager.clearManagers();
				bezier.clearOvals();
				bezier.clearPoints();
			}
		});
		toolBar.add(clearGrid);

		deleteSelected = new JButton();
		initButton(deleteSelected, "Erase Selected Polygons", "eraseSelectedPolygons");
		deleteSelected.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				bezier.performDelete();
			}
		});
		toolBar.add(deleteSelected);

		// ── Sub-mode icon sync (Shift key toggle while mode is active) ──────────
		bezier.setSubModeChangeListener(new BezierDrawPanel.SubModeChangeListener() {
			public void onSubModeChanged() {
				refreshSubModeIcons();
			}
		});
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	/**
	 * Sync the selected-state icon on the three selection buttons with the
	 * current sub-mode (Relational = normal selected icon, Discrete = shift icon).
	 * Called after a Shift-key toggle and after knife-mode restore.
	 */
	private void refreshSubModeIcons() {
		if (bezier.isPointSelectionModeEnabled()) {
			selectionMode.setSelectedIcon(
				bezier.getPointSubMode() == BezierDrawPanel.SelectionSubMode.DISCRETE
					? pointDiscreteIcon : pointRelationalIcon);
		}
		if (bezier.isEdgeSelectionModeEnabled()) {
			edgeSelectionMode.setSelectedIcon(
				bezier.getEdgeSubMode() == BezierDrawPanel.SelectionSubMode.DISCRETE
					? edgeDiscreteIcon : edgeRelationalIcon);
		}
		if (bezier.isPolygonSelectionModeEnabled()) {
			polygonSelectionMode.setSelectedIcon(
				bezier.getPolySubMode() == BezierDrawPanel.SelectionSubMode.DISCRETE
					? polyDiscreteIcon : polyRelationalIcon);
		}
	}

	private ImageIcon loadIcon(String fileName) {
		java.net.URL url = getClass().getResource("/resources/images/" + fileName + ".png");
		if (url != null) return new ImageIcon(url);
		return new ImageIcon("resources/images/" + fileName + ".png");
	}

	/**
	 * Set up a toggle button with a normal icon and a separate selected-state icon
	 * (iconName_selected.png). Using setSelectedIcon() is platform-safe — no
	 * background painting tricks needed.
	 */
	private void initToggle(JToggleButton btn, String tooltip, String iconName) {
		btn.setToolTipText(tooltip);
		btn.setIcon(loadIcon(iconName));
		btn.setSelectedIcon(loadIcon(iconName + "_selected"));
		btn.setPreferredSize(new Dimension(32, 32));
		btn.setMaximumSize(new Dimension(32, 32));
	}

	private void initButton(JButton btn, String tooltip, String iconName) {
		btn.setToolTipText(tooltip);
		btn.setIcon(loadIcon(iconName));
		btn.setPreferredSize(new Dimension(32, 32));
		btn.setMaximumSize(new Dimension(32, 32));
	}

	// ── Public API ────────────────────────────────────────────────────────────

	/**
	 * Activate Point Selection Mode programmatically (e.g. when editing a morph target).
	 */
	public void activatePointSelectionMode() {
		bezier.autoFinishOpenCurveIfNeeded();
		CubicCurvePolygonManager polygonManager = bezier.getPolygonManager();
		int idx = polygonManager.getPolygonCount();
		polygonManager.getManager(idx).setAddPoints(false);
		polygonMode.setSelected(false);
		edgeSelectionMode.setSelected(false);
		polygonSelectionMode.setSelected(false);
		openCurveSelectionMode.setSelected(false);
		bezier.setEdgeSelectionMode(false);
		bezier.setPolygonSelectionMode(false);
		bezier.setOpenCurveSelectionMode(false);
		selectionMode.setSelected(true);
		bezier.setPointSelectionMode(true);
	}

	/**
	 * Activate Polygon Selection Mode programmatically (e.g. when editing a saved polygon set).
	 */
	public void activatePolygonSelectionMode() {
		CubicCurvePolygonManager polygonManager = bezier.getPolygonManager();
		int idx = polygonManager.getPolygonCount();
		polygonManager.getManager(idx).setAddPoints(false);
		polygonMode.setSelected(false);
		selectionMode.setSelected(false);
		edgeSelectionMode.setSelected(false);
		openCurveSelectionMode.setSelected(false);
		bezier.setEdgeSelectionMode(false);
		bezier.setPointSelectionMode(false);
		bezier.setOpenCurveSelectionMode(false);
		polygonSelectionMode.setSelected(true);
		bezier.setPolygonSelectionMode(true);
	}

	/**
	 * Activate Open Curve Selection Mode programmatically.
	 */
	public void activateOpenCurveSelectionMode() {
		CubicCurvePolygonManager polygonManager = bezier.getPolygonManager();
		int idx = polygonManager.getPolygonCount();
		polygonManager.getManager(idx).setAddPoints(false);
		polygonMode.setSelected(false);
		selectionMode.setSelected(false);
		edgeSelectionMode.setSelected(false);
		polygonSelectionMode.setSelected(false);
		bezier.setEdgeSelectionMode(false);
		bezier.setPointSelectionMode(false);
		bezier.setPolygonSelectionMode(false);
		openCurveSelectionMode.setSelected(true);
		bezier.setOpenCurveSelectionMode(true);
	}

	/**
	 * Activate Create Polygon Mode programmatically (e.g. when opening a new project).
	 */
	public void activatePolygonMode() {
		CubicCurvePolygonManager polygonManager = bezier.getPolygonManager();
		int idx = polygonManager.getPolygonCount();
		polygonManager.getManager(idx).setAddPoints(true);
		selectionMode.setSelected(false);
		edgeSelectionMode.setSelected(false);
		polygonSelectionMode.setSelected(false);
		openCurveSelectionMode.setSelected(false);
		bezier.setEdgeSelectionMode(false);
		bezier.setPolygonSelectionMode(false);
		bezier.setPointSelectionMode(false);
		bezier.setOpenCurveSelectionMode(false);
		polygonMode.setSelected(true);
	}

	/**
	 * Activate Point Placement Mode programmatically (e.g. when loading a point set).
	 */
	public void activatePointMode() {
		bezier.autoFinishOpenCurveIfNeeded();
		CubicCurvePolygonManager polygonManager = bezier.getPolygonManager();
		int idx = polygonManager.getPolygonCount();
		polygonManager.getManager(idx).setAddPoints(false);
		selectionMode.setSelected(false);
		edgeSelectionMode.setSelected(false);
		polygonSelectionMode.setSelected(false);
		polygonMode.setSelected(false);
		knifeTool.setSelected(false);
		openCurveSelectionMode.setSelected(false);
		bezier.setEdgeSelectionMode(false);
		bezier.setPolygonSelectionMode(false);
		bezier.setPointSelectionMode(false);
		bezier.setOpenCurveSelectionMode(false);
		pointModeToggle.setSelected(true);
		bezier.setPointMode(true);
	}

	/**
	 * Activate Freehand Draw Mode programmatically.
	 */
	public void activateFreehandMode() {
		CubicCurvePolygonManager polygonManager = bezier.getPolygonManager();
		int idx = polygonManager.getPolygonCount();
		polygonManager.getManager(idx).setAddPoints(false);
		selectionMode.setSelected(false);
		edgeSelectionMode.setSelected(false);
		polygonSelectionMode.setSelected(false);
		polygonMode.setSelected(false);
		pointModeToggle.setSelected(false);
		knifeTool.setSelected(false);
		bezier.setKnifeMode(false);
		bezier.setPointMode(false);
		openCurveSelectionMode.setSelected(false);
		bezier.setEdgeSelectionMode(false);
		bezier.setPolygonSelectionMode(false);
		bezier.setPointSelectionMode(false);
		bezier.setOpenCurveSelectionMode(false);
		drawCurveMode.setSelected(true);
		bezier.setFreehandMode(true);
	}

	/**
	 * @return the toolBar
	 */
	public JToolBar getToolBar() {
		return toolBar;
	}
}
