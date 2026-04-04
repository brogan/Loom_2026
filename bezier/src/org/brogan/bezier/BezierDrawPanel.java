/**
 * 
 */
package org.brogan.bezier;

import java.awt.*;
import java.awt.geom.*;
import java.awt.image.BufferedImage;
import java.awt.event.*;
import java.io.File;
import java.util.*;


import javax.swing.JPanel;

import org.brogan.util.Formulas;
import org.brogan.ui.CubicCurveFrame;
import org.brogan.ui.CubicCurvePanel;
import org.brogan.util.Transform;

import nu.xom.Attribute;
import nu.xom.Element;
import nu.xom.Elements;

import org.brogan.bezier.CubicCurvePolygon;
import org.brogan.bezier.CubicPoint;
import org.brogan.media.ImageLoader;

/**
 * add one sentence class summary here add class description here
 * 
 * @author brogan
 * @version 1.0, Jul 19, 2006
 */
public class BezierDrawPanel extends JPanel implements Runnable, MouseListener, MouseMotionListener, KeyListener {
	
	public static final int WIDTH = 1040;
	public static final int HEIGHT = 1040;
	public static final int GRIDWIDTH = 1000;
	public static final int GRIDHEIGHT = 1000;
	//public static final int GRIDWIDTH = 1040;
	//public static final int GRIDHEIGHT = 1040;
	// class fields
	private CubicCurvePanel cubicCurvePanel;
	private CubicCurveFrame curveFrame;
	private Grid grid;
	private Thread thread;
	private boolean isRunning;
	private boolean zooming;
	private boolean paused;
	private Image dBuffer = null;
	private Graphics dBufferGraphics;
	private int currentSelectedCurve;
	private int currentSelectedPoint;//the index of the current point
	private CubicPoint currPoint;//the current point
	private boolean curvePointSelected;
	private Point2D.Double currentMousePos;
	private boolean dragging;
	private GridAxes gridAxes;
	private boolean displayReferenceImage;
	private BufferedImage referenceImage;
	private Color strokeColor;
	private ArrayList <CubicPoint> selectedPoints = new ArrayList<CubicPoint>();
	private CubicCurveManager currentCurveManager;//current curve manager associated with polygon - update when mouse pressed

	private boolean polygonSelectionModeEnabled = false;
	private ArrayList<CubicCurveManager> selectedPolygons = new ArrayList<CubicCurveManager>();

	private boolean edgeSelectionModeEnabled = false;
	private ArrayList<SelectedEdge> selectedEdges = new ArrayList<SelectedEdge>();

	public enum SelectionSubMode { DISCRETE, RELATIONAL }

	/** Notified whenever the active selection sub-mode changes (Shift toggle or Shift-click). */
	public interface SubModeChangeListener {
		void onSubModeChanged();
	}
	private SubModeChangeListener subModeChangeListener;
	public void setSubModeChangeListener(SubModeChangeListener l) { subModeChangeListener = l; }

	/** Notified when a plain (unmodified) mode-shortcut key is typed. */
	public interface ModeKeyListener {
		void onModeKey(char key);
	}
	private ModeKeyListener modeKeyListener;
	public void setModeKeyListener(ModeKeyListener l) { modeKeyListener = l; }

	/** Identifies a single spline edge: which polygon manager + which curve index within it. */
	static class SelectedEdge {
		final CubicCurveManager manager;
		final int curveIndex;
		SelectedEdge(CubicCurveManager m, int i) { manager = m; curveIndex = i; }
	}

	/** Snapshot of all selection lists for history navigation (Space=deselect, ←/→ navigate). */
	private static class SelectionSnapshot {
		final ArrayList<CubicPoint>        points;
		final ArrayList<SelectedEdge>      edges;
		final ArrayList<CubicCurveManager> curves; // closed polygons and open curves
		final ArrayList<OvalManager>       ovals;
		SelectionSnapshot(java.util.List<CubicPoint> pts, java.util.List<SelectedEdge> eds,
		                  java.util.List<CubicCurveManager> cvs, java.util.List<OvalManager> ovs) {
			points = new ArrayList<>(pts);
			edges  = new ArrayList<>(eds);
			curves = new ArrayList<>(cvs);
			ovals  = new ArrayList<>(ovs);
		}
		boolean isEmpty() {
			return points.isEmpty() && edges.isEmpty() && curves.isEmpty() && ovals.isEmpty();
		}
	}
	
	private boolean started;

	private SelectionSubMode pointSubMode = SelectionSubMode.RELATIONAL;
	private SelectionSubMode edgeSubMode  = SelectionSubMode.RELATIONAL;
	private SelectionSubMode polySubMode  = SelectionSubMode.RELATIONAL;

	private boolean pointSelectionModeEnabled = false;
	private boolean openCurveSelectionModeEnabled = false;
	private CubicCurveManager scopedManager = null;

	// Rubber-band (marquee) selection — active while Shift+drag in any selection mode
	private boolean rubberBanding = false;
	private Point2D.Double rubberBandStart = null;
	private Point2D.Double rubberBandEnd   = null;

	private ArrayList<SelectedEdge[]> pendingWeldPairs = new ArrayList<>();

	// ── Undo ─────────────────────────────────────────────────────────────────
	private final UndoManager undoManager = new UndoManager();
	/** Set true after slider release; cleared after first snapshot of next gesture. */
	private boolean scaleRotateSnapshotPending = true;
	/** Set true once a drag-gesture snapshot has been taken; reset on mouseReleased. */
	private boolean dragSnapshotTaken = false;

	// ── Extrude (Shift+drag on selected edges) ────────────────────────────────
	/** True from Shift+press until drag starts; triggers extrusion rather than rubber-band. */
	private boolean extrudeOnDrag = false;
	/** True while an extrusion drag is in progress. */
	private boolean extruding = false;
	/** Live duplicate edges being dragged during extrusion. */
	private java.util.List<CubicCurveManager> extrudeLiveEdges = new ArrayList<>();

	// ── Knife cut tool ────────────────────────────────────────────────────────
	public enum PrevMode { NONE, POINT, EDGE, POLYGON }
	private boolean knifeMode = false;
	private Point2D.Double knifeStart = null;
	private Point2D.Double knifeEnd   = null;
	private PrevMode prevModeBeforeKnife = PrevMode.NONE;
	private java.util.Set<CubicCurveManager> preKnifeSelection = new java.util.HashSet<>();

	// ── Auto-weld toggle ─────────────────────────────────────────────────────
	private boolean autoWeldEnabled = true;

	// ── Polygon click-through selection ──────────────────────────────────────
	// When the user clicks inside a selected polygon and there is an unselected
	// polygon underneath, we defer adding the outer polygon until mouseReleased.
	// If the user drags first, the drag takes effect and the deferred add is dropped.
	private CubicCurveManager polygonClickCandidate = null;
	private boolean polygonMouseMoved = false;

	private int edgeOffset;

	private CubicCurvePolygonManager polygonManager;
	private LayerManager layerManager = new LayerManager();
	private static class ClipboardEntry {
		final Point2D.Double[] pts;
		final boolean isClosed;
		ClipboardEntry(Point2D.Double[] pts, boolean isClosed) { this.pts = pts; this.isClosed = isClosed; }
	}
	private java.util.List<ClipboardEntry> clipboard = new ArrayList<>();

	// ── Point mode ────────────────────────────────────────────────────────────
	private java.util.List<Point2D.Double> pointList = new ArrayList<>();
	private boolean pointMode = false;
	/** Index of the currently selected discrete point, or -1 if none. */
	private int selectedDiscretePointIndex = -1;

	// ── Oval mode ─────────────────────────────────────────────────────────────
	private java.util.List<OvalManager> ovalList = new ArrayList<>();
	private java.util.List<OvalManager> selectedOvals = new ArrayList<>();

	// ── Selection history  (Space = deselect, ← / → navigate up to 10 past selections) ──
	private static final int SELECTION_HISTORY_MAX = 10;
	private final ArrayList<SelectionSnapshot> selectionHistory = new ArrayList<>();
	private int     selectionHistoryCursor = -1; // index in selectionHistory; -1 = empty
	private boolean navigatingHistory      = false;
	private int     historyLayerId         = -1; // layer when history was built; mismatch resets

	// ── Freehand draw mode ────────────────────────────────────────────────────
	private boolean freehandMode = false;
	private final java.util.List<Point2D.Double> freehandRaw = new ArrayList<>();
	private boolean freehandActive = false;
	private Point2D.Double freehandFirstPos = null;
	private Point2D.Double freehandCurrentPos = null;
	private double freehandErrorThreshold = 41.0; // matches toolbar default slider=10 → 51-10
	private static final double FREEHAND_MIN_STEP = 3.0;
	private static final double FREEHAND_SNAP_RADIUS = 20.0;

	// ── Pressure sensitivity ──────────────────────────────────────────────────
	private final PressureSource pressureSource = StylusPressureSource.createBest();
	/** Pressure samples parallel to freehandRaw (guarded by freehandRaw monitor). */
	private final java.util.List<Float> freehandPressures = new ArrayList<>();
	/** Per-point pressure parallel to pointList. */
	private java.util.List<Float> pointPressures = new ArrayList<>();

	public BezierDrawPanel(CubicCurvePanel p, CubicCurveFrame  cF, Color strokeCol){
		cubicCurvePanel = p;
		curveFrame = cF;

		addMouseListener(this);
		addMouseMotionListener(this);
		addKeyListener(this);
		setFocusable(true);
		setBackground(Color.WHITE);// panel background
		//row, column, x, y, width, height, offsetX, offsetY
		edgeOffset = (WIDTH-GRIDWIDTH)/2;
		//edgeOffset = 0;
		int numRows = 100;
		int numCols = 100;
		grid = new Grid(numRows, numCols, edgeOffset, edgeOffset, GRIDWIDTH/numRows, GRIDWIDTH/numCols, 0, 0);
		int numAxes = 20;
		gridAxes = new GridAxes(BezierDrawPanel.GRIDWIDTH, numAxes, edgeOffset, new Color(50, 150, 200), new Color(50, 200, 150));
		strokeColor = strokeCol;

		polygonManager = new CubicCurvePolygonManager(strokeColor, layerManager);

		currentSelectedCurve = -1;
		currentSelectedPoint = -1;
		curvePointSelected = false;
		currentMousePos = new Point2D.Double(0,0);
		dragging = false;
		
		isRunning = true;//the key seems to be setting isRunning true by default
		zooming = false;
		paused = false;
		started = false;
		thread = new Thread(this);

	}
	//Linux kludge to make sure thread.start gets called
	//but probably not necessary
	//gets called from CubicCurveFrame constructor after this panel has been created
	//the crucial change was to set isRunning to true in the above constructor
	//rather than trying to set in start()
	public void start() {
		if (!started) {
			thread.start();
			started = true;
		}

		if (!started) {
			System.out.println("+++++++++BezierDrawPanel can't start() draw thread");
			//uiFrame.getDrawManager().getInteractionManager().getProjectInfo().setInfo("BezierDrawPanel can't start() draw thread");
		}
	}
	public void killDrawThread() {
		isRunning = false;
	}
	/**
	 * the animate loop - update and render, sleep 20 and then do it all over
	 * again
	 */
	public void run () {
		System.out.println("begin in run: "+isRunning);
		while (isRunning) {
			if (!paused) {
				//System.out.println("animating");
				animateUpdate();
				animateRender();// to a buffer
			}
			try {
				Thread.sleep(20);
			}
			catch (InterruptedException ex) {System.out.println("exception in run");}
		}
	}
	/*
	 * //panel painting method public void paintComponent(Graphics g) {
	 * super.paintComponent(g);//call to superclass to paint
	 * System.out.println("painting");//print message to console Graphics2D g2D =
	 * (Graphics2D)g; g2D.setRenderingHint(RenderingHints.KEY_ANTIALIASING,
	 * RenderingHints.VALUE_ANTIALIAS_ON); grid.draw(g2D); }
	 */
	private void paintScreen(Graphics g) {
		Graphics2D g2D = (Graphics2D)g;
		if (dBuffer != null) {
			g2D.drawImage(dBuffer, 0, 0, getWidth(), getHeight(), null);
		} else {
			System.out.println("unable to create double buffer");
		}
	}

	@Override
	protected void paintComponent(Graphics g) {
		// When Swing triggers a repaint (resize, expose, or explicit repaint() call)
		// blit the last completed frame rather than filling white.  This prevents
		// the grid and curves from flashing away during mouse interaction.
		if (dBuffer != null) {
			g.drawImage(dBuffer, 0, 0, getWidth(), getHeight(), null);
		} else {
			super.paintComponent(g);
		}
	}

	/**
	 * Maps a component-space mouse point into the fixed 1040×1040 buffer
	 * coordinate space so that hit-testing and drawing work correctly regardless
	 * of the current component size.
	 */
	private Point2D.Double scaleMouse(MouseEvent mE) {
		int w = getWidth(),  h = getHeight();
		double sx = (w > 0) ? (double) WIDTH  / w : 1.0;
		double sy = (h > 0) ? (double) HEIGHT / h : 1.0;
		return new Point2D.Double(mE.getPoint().x * sx, mE.getPoint().y * sy);
	}
	private void update() {
		//grid.update();
		//curveManager.update();
	}
	/**
	 * Called from reference image radio button in ImportImagesPanel that is held in CubicCurveFrame
	 */
	public void displayReferenceImage() {
		File refFile = curveFrame.getImportImagesPanel().getReferenceImageFile();
		System.out.println("BezierDrawPanel, referenceImage path: " + refFile.getPath());
		try {
			referenceImage = (BufferedImage)ImageLoader.loadImage(refFile.getPath());
			displayReferenceImage = true;
		} catch (Exception e) {
			System.out.println("BezierDrawPanel, can't load reference image");
		}
	}
	private void animateUpdate() {
		update();
	}
	public void setPaused() {
		if (paused) {
			paused = false;
		} else {
			paused = true;
		}
	}
	private void animateRender() {
		// System.out.println("rendering animation");

		// only runs first time through
		if (dBuffer == null) {
			dBuffer = createImage(WIDTH, HEIGHT);
			// System.out.println("dBuffer in animateRender: " + dBuffer);
		}
		if (dBuffer != null) {
			dBufferGraphics = dBuffer.getGraphics();
			dBufferGraphics.setColor(Color.WHITE);
			dBufferGraphics.fillRect(0, 0, WIDTH, HEIGHT);
			if (displayReferenceImage) {
				dBufferGraphics.drawImage(referenceImage, edgeOffset, edgeOffset, BezierDrawPanel.GRIDWIDTH, BezierDrawPanel.GRIDWIDTH, null);
			}
			grid.draw(dBufferGraphics);
			gridAxes.draw(dBufferGraphics);
			synchronized (polygonManager) {
				polygonManager.draw((Graphics2D)dBufferGraphics);
			}

			// Rubber-band selection rectangle
			if (rubberBanding && rubberBandStart != null && rubberBandEnd != null) {
				Graphics2D rg = (Graphics2D) dBufferGraphics;
				int rx = (int) Math.min(rubberBandStart.x, rubberBandEnd.x);
				int ry = (int) Math.min(rubberBandStart.y, rubberBandEnd.y);
				int rw = (int) Math.abs(rubberBandEnd.x - rubberBandStart.x);
				int rh = (int) Math.abs(rubberBandEnd.y - rubberBandStart.y);
				rg.setColor(new Color(100, 180, 255, 40));
				rg.fillRect(rx, ry, rw, rh);
				rg.setStroke(new BasicStroke(1f, BasicStroke.CAP_BUTT, BasicStroke.JOIN_MITER,
						10f, new float[]{6, 3}, 0f));
				rg.setColor(new Color(50, 130, 255, 220));
				rg.drawRect(rx, ry, rw, rh);
			}

			// Draw discrete points (point mode) — radius scales with pressure
			if (!pointList.isEmpty()) {
				Graphics2D pg = (Graphics2D) dBufferGraphics;
				pg.setStroke(new BasicStroke(1.5f));
				for (int pi = 0; pi < pointList.size(); pi++) {
					Point2D.Double pt = pointList.get(pi);
					float pr = (pi < pointPressures.size()) ? pointPressures.get(pi) : 1.0f;
					int r = Math.max(3, (int)(pr * 8)); // 3..8 px based on pressure
					int px = (int) pt.x, py = (int) pt.y;
					if (pi == selectedDiscretePointIndex) {
						// Yellow selection ring
						pg.setColor(new Color(255, 220, 0, 220));
						pg.setStroke(new BasicStroke(2f));
						pg.drawOval(px - r - 3, py - r - 3, (r + 3) * 2, (r + 3) * 2);
						pg.setStroke(new BasicStroke(1.5f));
					}
					// Purple body (same colour selected or not)
					pg.setColor(new Color(200, 0, 255, 220));
					pg.fillOval(px - r, py - r, r * 2, r * 2);
				}
			}

			// Draw ovals
			if (!ovalList.isEmpty()) {
				Graphics2D og = (Graphics2D) dBufferGraphics;
				boolean relational = (polySubMode == SelectionSubMode.RELATIONAL);
				for (OvalManager oval : ovalList) {
					if (oval.getLayerId() == layerManager.getActiveLayerId()) {
						oval.draw(og, strokeColor, !relational, relational);
					} else {
						Layer ol = layerManager.getLayerById(oval.getLayerId());
						if (ol != null && ol.isVisible()) {
							java.awt.Composite prev = og.getComposite();
							og.setComposite(java.awt.AlphaComposite.getInstance(
								java.awt.AlphaComposite.SRC_OVER, 0.2f));
							oval.draw(og, strokeColor, true, false);
							og.setComposite(prev);
						}
					}
				}
			}

			// Draw freehand stroke preview — variable-width ribbon based on pressure
			if (freehandActive) {
				Point2D.Double[] fhSnap;
				float[] fpSnap;
				synchronized (freehandRaw) {
					fhSnap = freehandRaw.toArray(new Point2D.Double[0]);
					fpSnap = new float[freehandPressures.size()];
					for (int fi = 0; fi < fpSnap.length; fi++) fpSnap[fi] = freehandPressures.get(fi);
				}
				if (fhSnap.length >= 2) {
					Graphics2D fg = (Graphics2D) dBufferGraphics;
					fg.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
					fg.setColor(new Color(60, 60, 100, 180));
					drawPressureRibbon(fg, fhSnap, fpSnap, 5.0f);
					if (freehandCurrentPos != null && fhSnap.length > 5 &&
							Formulas.hypotenuse(freehandCurrentPos, freehandFirstPos) < FREEHAND_SNAP_RADIUS) {
						fg.setColor(new Color(0, 180, 0, 200));
						fg.fillOval((int)freehandFirstPos.x - 8, (int)freehandFirstPos.y - 8, 16, 16);
					}
				}
			}

			if (knifeMode && knifeStart != null && knifeEnd != null) {
				double dx = knifeEnd.x - knifeStart.x, dy = knifeEnd.y - knifeStart.y;
				double len = Math.sqrt(dx*dx + dy*dy);
				if (len > 1) {
					Graphics2D kg = (Graphics2D) dBufferGraphics;
					kg.setColor(new Color(220, 30, 30, 200));
					// Segment from knifeStart to knifeEnd (dashed)
					kg.setStroke(new BasicStroke(1.5f, BasicStroke.CAP_BUTT, BasicStroke.JOIN_MITER,
							10f, new float[]{6, 4}, 0f));
					kg.draw(new java.awt.geom.Line2D.Double(
						knifeStart.x, knifeStart.y, knifeEnd.x, knifeEnd.y));
					// Perpendicular tick at start to show cut direction
					double px = -dy / len * 8, py = dx / len * 8;
					kg.setStroke(new BasicStroke(1.5f));
					kg.draw(new java.awt.geom.Line2D.Double(
						knifeStart.x - px, knifeStart.y - py,
						knifeStart.x + px, knifeStart.y + py));
					kg.drawOval((int)knifeStart.x - 4, (int)knifeStart.y - 4, 8, 8);
					kg.drawOval((int)knifeEnd.x   - 4, (int)knifeEnd.y   - 4, 8, 8);
				}
			}

			try {
				Graphics g;
				g = this.getGraphics();
				paintScreen(g);
				// dBufferGraphics.dispose();
			} catch (Exception e) {
				System.out.println("dBufferGraphics is null: " + dBufferGraphics);
			}
		}
	}


	/**
	 * Draw a variable-width ribbon along a polyline, where width at each vertex
	 * is proportional to the corresponding pressure value.
	 * @param g          graphics context (antialiasing should already be enabled)
	 * @param pts        polyline vertices
	 * @param pressures  pressure values parallel to pts; values in [0,1]
	 * @param maxHalfW   maximum half-width in pixels at pressure=1.0
	 */
	private void drawPressureRibbon(Graphics2D g, Point2D.Double[] pts, float[] pressures, float maxHalfW) {
		int n = pts.length;
		if (n < 2) return;
		double[] lx = new double[n], ly = new double[n];
		double[] rx = new double[n], ry = new double[n];
		for (int i = 0; i < n; i++) {
			float pr = (i < pressures.length) ? pressures[i] : 1.0f;
			double w = Math.max(0.5, pr * maxHalfW);
			// Perpendicular direction at vertex i (averaged from adjacent segments)
			double nx, ny;
			if (i == 0) {
				double ddx = pts[1].x - pts[0].x, ddy = pts[1].y - pts[0].y;
				double len = Math.sqrt(ddx*ddx + ddy*ddy); if (len < 0.001) len = 1;
				nx = -ddy / len; ny = ddx / len;
			} else if (i == n - 1) {
				double ddx = pts[n-1].x - pts[n-2].x, ddy = pts[n-1].y - pts[n-2].y;
				double len = Math.sqrt(ddx*ddx + ddy*ddy); if (len < 0.001) len = 1;
				nx = -ddy / len; ny = ddx / len;
			} else {
				double ddx1 = pts[i].x - pts[i-1].x, ddy1 = pts[i].y - pts[i-1].y;
				double len1 = Math.sqrt(ddx1*ddx1 + ddy1*ddy1); if (len1 < 0.001) len1 = 1;
				double ddx2 = pts[i+1].x - pts[i].x, ddy2 = pts[i+1].y - pts[i].y;
				double len2 = Math.sqrt(ddx2*ddx2 + ddy2*ddy2); if (len2 < 0.001) len2 = 1;
				nx = (-ddy1/len1 + -ddy2/len2) * 0.5;
				ny = (ddx1/len1 +  ddx2/len2) * 0.5;
				double nlen = Math.sqrt(nx*nx + ny*ny); if (nlen < 0.001) nlen = 1;
				nx /= nlen; ny /= nlen;
			}
			lx[i] = pts[i].x + nx * w;
			ly[i] = pts[i].y + ny * w;
			rx[i] = pts[i].x - nx * w;
			ry[i] = pts[i].y - ny * w;
		}
		// Build closed path: left edge forward, right edge backward
		java.awt.geom.GeneralPath ribbon = new java.awt.geom.GeneralPath();
		ribbon.moveTo(lx[0], ly[0]);
		for (int i = 1; i < n; i++) ribbon.lineTo(lx[i], ly[i]);
		for (int i = n - 1; i >= 0; i--) ribbon.lineTo(rx[i], ry[i]);
		ribbon.closePath();
		g.fill(ribbon);
	}

	/* (non-Javadoc)
	 * @see java.awt.event.MouseMotionListener#mouseDragged(java.awt.event.MouseEvent)
	 */
	public void mouseDragged(MouseEvent mE) {
		if (freehandMode && freehandActive) {
			Point2D.Double fhPos = scaleMouse(mE);
			synchronized (freehandRaw) {
				if (Formulas.hypotenuse(freehandRaw.get(freehandRaw.size() - 1), fhPos) >= FREEHAND_MIN_STEP) {
					freehandRaw.add(fhPos);
					freehandPressures.add(pressureSource.getPressure());
				}
			}
			freehandCurrentPos = fhPos;
			// No repaint() — the 50fps run loop redraws continuously.
			// Calling repaint() here would trigger paintComponent before the run
			// loop can write to dBuffer, causing a white flash and grid dropout.
			return;
		}
		if (pointMode && selectedDiscretePointIndex >= 0 && selectedDiscretePointIndex < pointList.size()) {
			if (!dragSnapshotTaken) { takeUndoSnapshot(); dragSnapshotTaken = true; }
			Point2D.Double sp = scaleMouse(mE);
			pointList.get(selectedDiscretePointIndex).x = sp.x;
			pointList.get(selectedDiscretePointIndex).y = sp.y;
			currentMousePos.x = sp.x;
			currentMousePos.y = sp.y;
			return;
		}
		if (knifeMode && knifeStart != null) {
			knifeEnd = scaleMouse(mE);
			return;
		}
		if (rubberBanding) {
			Point2D.Double sp = scaleMouse(mE);
			rubberBandEnd.x = sp.x;
			rubberBandEnd.y = sp.y;
			return;
		}
		if (extrudeOnDrag || extruding) {
			if (!extruding) {
				if (!dragSnapshotTaken) { takeUndoSnapshot(); dragSnapshotTaken = true; }
				startExtrude();
			}
			Point2D.Double sp = scaleMouse(mE);
			double dx = sp.x - currentMousePos.x;
			double dy = sp.y - currentMousePos.y;
			java.util.HashSet<CubicPoint> moved = new java.util.HashSet<>();
			for (CubicCurveManager m : extrudeLiveEdges) {
				for (CubicCurve cv : m.getCurves().getArrayofCubicCurves()) {
					for (CubicPoint pt : cv.getPoints()) {
						if (pt != null && moved.add(pt)) {
							pt.setPos(new Point2D.Double(pt.getPos().x + dx, pt.getPos().y + dy));
							pt.setOrigPosToPos();
						}
					}
				}
			}
			currentMousePos.x = sp.x;
			currentMousePos.y = sp.y;
			return;
		}
		if (pointSelectionModeEnabled && selectedDiscretePointIndex >= 0 && selectedDiscretePointIndex < pointList.size()) {
			if (!dragSnapshotTaken) { takeUndoSnapshot(); dragSnapshotTaken = true; }
			Point2D.Double sp = scaleMouse(mE);
			pointList.get(selectedDiscretePointIndex).x = sp.x;
			pointList.get(selectedDiscretePointIndex).y = sp.y;
			currentMousePos.x = sp.x;
			currentMousePos.y = sp.y;
			return;
		}
		if (pointSelectionModeEnabled && !selectedPoints.isEmpty()) {
			if (!dragSnapshotTaken) { takeUndoSnapshot(); dragSnapshotTaken = true; }
			Point2D.Double sp = scaleMouse(mE);
			double dx = sp.x - currentMousePos.x;
			double dy = sp.y - currentMousePos.y;
			translateSelectedPointsByDelta(dx, dy);
			currentMousePos.x = sp.x;
			currentMousePos.y = sp.y;
			return;
		}
		if (edgeSelectionModeEnabled && !selectedEdges.isEmpty()) {
			if (!dragSnapshotTaken) { takeUndoSnapshot(); dragSnapshotTaken = true; }
			Point2D.Double sp = scaleMouse(mE);
			double dx = sp.x - currentMousePos.x;
			double dy = sp.y - currentMousePos.y;
			translateEdgesBy(dx, dy);
			currentMousePos.x = sp.x;
			currentMousePos.y = sp.y;
			return;
		}

		if ((polygonSelectionModeEnabled || openCurveSelectionModeEnabled) && (!selectedPolygons.isEmpty() || !selectedOvals.isEmpty())) {
			if (!dragSnapshotTaken) {
				takeUndoSnapshot();
				dragSnapshotTaken = true;
			}
			polygonMouseMoved = true;  // suppress deferred click-through selection
			Point2D.Double sp = scaleMouse(mE);
			double dx = sp.x - currentMousePos.x;
			double dy = sp.y - currentMousePos.y;
			if (!selectedPolygons.isEmpty()) {
				// One shared HashSet so welded points (same Java object in multiple managers) move only once
				HashSet<CubicPoint> moved = new HashSet<CubicPoint>();
				for (CubicCurveManager m : selectedPolygons) {
					translatePolygonBy(m, dx, dy, moved);
				}
				if (autoWeldEnabled && polygonSelectionModeEnabled) checkDragWeld(); else clearPendingWeld();
			}
			for (OvalManager oval : selectedOvals) {
				oval.translate(dx, dy);
			}
			currentMousePos.x = sp.x;
			currentMousePos.y = sp.y;
			return;
		}

		//set point when initially dragged if dragging currently false
		//why is this needed?

		if (!dragging) {
			if (!dragSnapshotTaken) { takeUndoSnapshot(); dragSnapshotTaken = true; }
			CubicCurvePolygon[] pols = polygonManager.getPolygons().getArrayofCubicCurvePolygons();
			for (int i = 0; i<pols.length; i++) {
				CubicCurve[] curves = pols[i].getArrayofCubicCurves();
				for (int j = 0; j < curves.length; j++) {
					CubicPoint[] points = curves[j].getPoints();
					for (int p = 0; p<points.length; p++) {
						points[p].setCurrentPos();
					}
				}
			}
			dragging = true;//switch dragging to true
			
		}

		System.out.println("mouse dragged");
		Point2D.Double sp = scaleMouse(mE);
		double x = sp.x;
		double y = sp.y;
		Point2D.Double mousePos = new Point2D.Double(x,y);
		Point2D.Double diffXY = Formulas.diffXY(currentMousePos, mousePos);
		Point2D.Double pos;
		
		
		int polygonCount = polygonManager.getPolygonCount();
		
		if (currentCurveManager != null) {

			CubicCurvePolygon currPolygon = currentCurveManager.getCurves();//currentCurveManager set in mousePressed

			CubicCurveManager curveManager = currentCurveManager;//could just use currentCurveManager variable directly - lazy


			int totCurves = currPolygon.getCubicCurveTotal();

			if (curvePointSelected) {
				CubicPoint p = currPolygon.getCurve(currentSelectedCurve).getPoint(currentSelectedPoint);
				
				//if (p.getSelectable()) {//if point is selectable - not selectable if a welded slave
					
					if (p.getType() == CubicPoint.ANCHOR_POINT) {
						System.out.println("ANCHOR POINT SELECTED");
						if (currentSelectedPoint == 0) {//first anchor point
							p.drag(mousePos);
							//if curve is closed
							if (!curveManager.isAddPoints()) {//otherwise control points get badly positioned
								pos = currPolygon.getCurve(currentSelectedCurve).getPoint(1).getCurrentPos();
								System.out.println("BezierDrawPanel, mouseDragged, first anchor selected: pos.x: " + pos.x + "pos.y: " + pos.y);
								//
								currPolygon.getCurve(currentSelectedCurve).getPoint(1).drag(Formulas.addDiff(pos, diffXY));//Problem with control points

								if (currentSelectedCurve != 0) {
									currPolygon.getCurve(currentSelectedCurve-1).getPoint(3).drag(mousePos);
									pos = currPolygon.getCurve(currentSelectedCurve-1).getPoint(2).getCurrentPos();

									//
									currPolygon.getCurve(currentSelectedCurve-1).getPoint(2).drag(Formulas.addDiff(pos, diffXY));
								} else {
									currPolygon.getCurve(totCurves-1).getPoint(3).drag(mousePos);
									pos = currPolygon.getCurve(totCurves-1).getPoint(2).getCurrentPos();

									//
									currPolygon.getCurve(totCurves-1).getPoint(2).drag(Formulas.addDiff(pos, diffXY));
								}
							}
						} else if (currentSelectedPoint == 3) {//last anchor point
							p.drag(mousePos);
							if (!curveManager.isAddPoints()) {
								pos = currPolygon.getCurve(currentSelectedCurve).getPoint(2).getCurrentPos();
								System.out.println("BezierDrawPanel, mouseDragged, last anchor selected: pos.x: " + pos.x + "pos.y: " + pos.y);

								//
								currPolygon.getCurve(currentSelectedCurve).getPoint(2).drag(Formulas.addDiff(pos, diffXY));

								if (currentSelectedCurve < totCurves-1) {
									currPolygon.getCurve(currentSelectedCurve+1).getPoint(0).drag(mousePos);
									pos = currPolygon.getCurve(currentSelectedCurve+1).getPoint(1).getCurrentPos();

									//
									currPolygon.getCurve(currentSelectedCurve+1).getPoint(1).drag(Formulas.addDiff(pos, diffXY));

								} else {
									currPolygon.getCurve(0).getPoint(3).drag(mousePos);
									pos = currPolygon.getCurve(0).getPoint(2).getCurrentPos();

									//
									currPolygon.getCurve(0).getPoint(2).drag(Formulas.addDiff(pos, diffXY));

								}
							} 
						}
					} else {
						System.out.println("CONTROL POINT SELECTED");
						p.drag(mousePos);

					}
				//}
			} else {
				//System.out.println("BezierDrawPanel, mouse dragged, checking for intersect with curves and individual points");
				int[] intersect;
				if (isAnchorSelect() && !isControlSelect()){
					intersect = curveManager.checkForAnchorIntersect(mousePos);//curve intersect, point intersect
				} else if (!isAnchorSelect() && isControlSelect()){
					intersect = curveManager.checkForControlIntersect(mousePos);//curve intersect, point intersect
				} else {//check for intersect of both anchor and control points
					intersect = curveManager.checkForIntersect(mousePos);//curve intersect, point intersect
				}
				if (intersect[0]!=-1 && intersect[1]!=-1) {
					currPoint = currPolygon.getCurve(intersect[0]).getPoint(intersect[1]);
					currPolygon.getCurve(intersect[0]).getPoint(intersect[1]).drag(mousePos);
					curvePointSelected=true;
					currentSelectedCurve = intersect[0];
					currentSelectedPoint = intersect[1];					
				}
			}
		} else {
			System.out.println("BezierDrawPanel, mouseDragged, currentCurveManager is NULL");
		}

	}
	/* (non-Javadoc)
	 * @see java.awt.event.MouseMotionListener#mouseMoved(java.awt.event.MouseEvent)
	 */
	public void mouseMoved(MouseEvent arg0) {
		Point2D.Double sp = scaleMouse(arg0);
		currentMousePos.x = sp.x;
		currentMousePos.y = sp.y;
	}
	/* (non-Javadoc)
	 * @see java.awt.event.MouseListener#mouseClicked(java.awt.event.MouseEvent)
	 */
	public void mouseClicked(MouseEvent mE) {
		
		
	}
	/* (non-Javadoc)
	 * @see java.awt.event.MouseListener#mouseEntered(java.awt.event.MouseEvent)
	 */
	public void mouseEntered(MouseEvent mE) {	
		
	}
	/* (non-Javadoc)
	 * @see java.awt.event.MouseListener#mouseExited(java.awt.event.MouseEvent)
	 */
	public void mouseExited(MouseEvent arg0) {
		// TODO Auto-generated method stub

	}
	/* (non-Javadoc)
	 * @see java.awt.event.MouseListener#mousePressed(java.awt.event.MouseEvent)
	 */
	public void mousePressed(MouseEvent mE) {
		requestFocusInWindow();
		System.out.println("");
		System.out.println("mouse pressed");
		Point2D.Double sp = scaleMouse(mE);
		double x = sp.x;
		double y = sp.y;
		Point2D.Double mousePos = new Point2D.Double(x,y);
		System.out.println("BezierDrawPanel, mousePressed, mouse x: " + mousePos.x + "   mouse y: " + mousePos.y);

		if (freehandMode) {
			takeUndoSnapshot();
			synchronized (freehandRaw) {
				freehandRaw.clear();
				freehandPressures.clear();
				Point2D.Double fhPos = scaleMouse(mE);
				freehandRaw.add(fhPos);
				freehandPressures.add(pressureSource.getPressure());
				freehandFirstPos = fhPos;
			}
			freehandFirstPos = freehandRaw.get(0);
			freehandActive = true;
			return;
		}

		if (pointMode) {
			int hit = findDiscretePointNear(mousePos, 15.0);
			if (hit >= 0) {
				selectedDiscretePointIndex = hit;
			} else {
				selectedDiscretePointIndex = -1;
				addPointAtMouse(mE);
			}
			currentMousePos.x = mousePos.x;
			currentMousePos.y = mousePos.y;
			return;
		}

		if (knifeMode) {
			knifeStart = new Point2D.Double(x, y);
			knifeEnd   = new Point2D.Double(x, y);
			currentMousePos.x = x; currentMousePos.y = y;
			return;
		}

		// Shift+drag in edge mode with edges already selected → extrude, not rubber-band
		if (mE.isShiftDown() && edgeSelectionModeEnabled && !selectedEdges.isEmpty()) {
			extrudeOnDrag = true;
			currentMousePos.x = x;
			currentMousePos.y = y;
			return;
		}

		// Shift+drag in any selection mode → start rubber-band marquee
		if (mE.isShiftDown() && (pointSelectionModeEnabled || edgeSelectionModeEnabled
				|| polygonSelectionModeEnabled || openCurveSelectionModeEnabled)) {
			rubberBanding = true;
			rubberBandStart = new Point2D.Double(x, y);
			rubberBandEnd   = new Point2D.Double(x, y);
			currentMousePos.x = x;
			currentMousePos.y = y;
			return;
		}

		if (openCurveSelectionModeEnabled) {
			handleOpenCurveSelectionClick(mousePos);
			currentMousePos.x = mousePos.x;
			currentMousePos.y = mousePos.y;
			return;
		}

		if (edgeSelectionModeEnabled) {
			handleEdgeScopeOrSelect(mousePos, mE.isMetaDown());
			currentMousePos.x = mousePos.x;
			currentMousePos.y = mousePos.y;
			return;
		}

		if (polygonSelectionModeEnabled) {
			handlePolygonSelectionClick(mousePos);
			currentMousePos.x = mousePos.x;
			currentMousePos.y = mousePos.y;
			return;
		}

		if (pointSelectionModeEnabled) {
			// Free-standing points take priority — check proximity before bezier point hit tests
			int dpHit = findDiscretePointNear(mousePos, 15.0);
			if (dpHit >= 0) {
				selectedDiscretePointIndex = dpHit;
			} else {
				selectedDiscretePointIndex = -1;
				handlePointScopeOrSelect(mousePos, mE.isMetaDown());
			}
			currentMousePos.x = mousePos.x;
			currentMousePos.y = mousePos.y;
			return;
		}

		//identify the polygon associated with the selected point (mousePos)
		//used in mousedragged
		int polygonCount = polygonManager.getPolygonCount();
		for (int i = 0; i < polygonCount; i++) {
			CubicCurveManager curveM = polygonManager.getManager(i);
			int[] intersect = curveM.checkForIntersect(mousePos);
			if (intersect[0]!=-1 && intersect[1]!=-1) {
				currentCurveManager = curveM;//need for mouse drag events
			}
		}

		CubicCurveManager curveManager = polygonManager.getManager(polygonCount);
		//System.out.println("BezierDrawPanel, mousePressed, curveManager index: " + polygonCount);

		if (!zooming) {
			
			if (curveManager.isAddPoints()) {
				System.out.println("BezierDrawPanel, mousePressed, curveManager index: " + polygonCount + " is ADDING points");

				int[] intersect = curveManager.checkForIntersect(mousePos);
				if (intersect[0]==-1 && intersect[1]==-1) {
					takeUndoSnapshot();
					setPoint(mousePos);
					
				}

			} else {//selection mode
				
				System.out.println("BezierDrawPanel, mousePressed, curveManager index: " + polygonCount + " is SELECTING points");

				//Point2D.Double diffXY = Formulas.diffXY(currentMousePos, mousePos);
				//Point2D.Double pos;

				selectPoint(mousePos);
				
			}			

			currentMousePos.x = mousePos.x;
			currentMousePos.y = mousePos.y;
			
		} else { //zooming - not implemented yet


			CubicCurvePolygon[] polys = polygonManager.getPolygons().getArrayofCubicCurvePolygons();
			for (int i = 0; i< polys.length;i++) {
				CubicCurvePolygon poly = polys[i];
				CubicCurve[] curves = poly.getArrayofCubicCurves();
				for (int c = 0; c < curves.length; c++) {
					CubicPoint[] points = curves[c].getPoints();
					for (int p = 0; p < points.length; p++) {
						//
					}	
				}
			}


		}


	}
	/* (non-Javadoc)
	 * @see java.awt.event.MouseListener#mouseReleased(java.awt.event.MouseEvent)
	 */
	public void mouseReleased(MouseEvent e) {
		if (freehandMode && freehandActive) {
			freehandActive = false;
			java.util.List<Point2D.Double> snapshot;
			java.util.List<Float> pressureSnapshot;
			synchronized (freehandRaw) {
				snapshot = new java.util.ArrayList<>(freehandRaw);
				pressureSnapshot = new java.util.ArrayList<>(freehandPressures);
				freehandRaw.clear();
				freehandPressures.clear();
			}
			if (snapshot.size() >= 2) {
				boolean doClose = snapshot.size() > 5 &&
					Formulas.hypotenuse(snapshot.get(snapshot.size() - 1), freehandFirstPos) < FREEHAND_SNAP_RADIUS;
				if (doClose)
					snapshot.add(new Point2D.Double(freehandFirstPos.x, freehandFirstPos.y));
				Point2D.Double[] fitted = CurveFitter.fit(snapshot, freehandErrorThreshold);
				if (fitted != null && fitted.length >= 4) {
					// Map raw pressures to per-anchor pressures after curve fitting
					int numSegments = fitted.length / 4;
					int numAnchors  = numSegments + 1;
					int rawN        = pressureSnapshot.size();
					float[] anchorPressures = new float[numAnchors];
					for (int k = 0; k < numAnchors; k++) {
						int rawIdx = (numAnchors > 1)
							? Math.round((float) k * (rawN - 1) / (numAnchors - 1))
							: 0;
						rawIdx = Math.max(0, Math.min(rawN - 1, rawIdx));
						anchorPressures[k] = pressureSnapshot.get(rawIdx);
					}
					synchronized (polygonManager) {
						CubicCurveManager newMgr;
						if (doClose) newMgr = polygonManager.addClosedFromPoints(fitted, strokeColor);
						else         newMgr = polygonManager.addOpenCurveFromPoints(fitted, strokeColor);
						newMgr.setAnchorPressures(anchorPressures);
						// Do NOT call addManager() here — see comment above.
					}
				}
			}
			return;
		}
		if (knifeMode && knifeStart != null && knifeEnd != null) {
			double dx = knifeEnd.x - knifeStart.x, dy = knifeEnd.y - knifeStart.y;
			if (Math.sqrt(dx*dx + dy*dy) > 5) {
				takeUndoSnapshot();
				synchronized (polygonManager) {
					BezierKnifeTool.performCut(polygonManager, knifeStart, knifeEnd,
					                           strokeColor, preKnifeSelection, selectedPolygons);
				}
			}
			knifeStart = null; knifeEnd = null;
			return;
		}
		extrudeOnDrag = false;
		dragSnapshotTaken = false;
		if (extruding) {
			finalizeExtrude();
			extruding = false;
			return;
		}
		if (rubberBanding) {
			rubberBanding = false;
			finalizeRubberBandSelection();
			return;
		}
		curvePointSelected = false;
		dragging = false;
		if (polygonSelectionModeEnabled && !pendingWeldPairs.isEmpty()) {
			if (autoWeldEnabled) {
				for (SelectedEdge[] pair : pendingWeldPairs) {
					executeDragWeld(pair[0], pair[1]);
				}
			}
			pendingWeldPairs.clear();
		}
		// Click-through deferred selection: if the user clicked a selected polygon
		// without dragging, add the unselected polygon that was underneath it.
		if (polygonSelectionModeEnabled && polygonClickCandidate != null && !polygonMouseMoved) {
			polygonClickCandidate.setSelected(true);
			polygonClickCandidate.setSelectedRelational(polySubMode == SelectionSubMode.RELATIONAL);
			selectedPolygons.add(polygonClickCandidate);
		}
		polygonClickCandidate = null;
		polygonMouseMoved = false;
		pushSelectionToHistory();
	}
	/**
	 * @return the curveManager
	 */
	public CubicCurveManager getCurveManager(int i) {
		return polygonManager.getManager(i);
	}
	/**
	 * @return the anchorSelect
	 */
	public boolean isAnchorSelect() {
		return cubicCurvePanel.isEditAnchorPoints();
	}
	/**
	 * @return the controlSelect
	 */
	public boolean isControlSelect() {
		return cubicCurvePanel.isEditControlPoints();
	}
	public void translateXY(double trans) {
		
		CubicCurvePolygonSet polys = polygonManager.getPolygons();
		int totPolys = polys.getPolygonTotal();
		for (int i=0;i<totPolys+1;i++) {
			CubicCurveManager curveManager = polygonManager.getManager(i);
			CubicCurvePolygon curves = curveManager.getCurves();
			int totCurves = curves.getArrayofCubicCurves().length;
			for (int j = 0; j < totCurves; j++) {
				CubicPoint[] points = curves.getCurve(j).getPoints();
				for (int p = 0; p < points.length; p++) {
					System.out.println("translating....");
					Point2D.Double t = new Point2D.Double(trans, trans);
					points[p].setPos (Transform.translate(points[p].getOrigPos(), t));
				}
			}
		}
		
	}
	public void translateX(double trans) {
		if (pointSelectionModeEnabled && !selectedPoints.isEmpty()) { translateSelectedPointsFromOrig(trans, 0); return; }
		CubicCurvePolygonSet polys = polygonManager.getPolygons();
		int totPolys = polys.getPolygonTotal();
		for (int i=0;i<totPolys+1;i++) {

			CubicCurveManager curveManager = polygonManager.getManager(i);
			CubicCurvePolygon curves = curveManager.getCurves();
			int totCurves = curves.getArrayofCubicCurves().length;

			for (int j = 0; j < totCurves; j++) {
				CubicPoint[] points = curves.getCurve(j).getPoints();
				for (int p = 0; p < points.length; p++) {
					Point2D.Double t = new Point2D.Double(trans, 0);
					points[p].setPos (Transform.translate(points[p].getOrigPos(), t));
				}
			}
		}
	}
	public void translateY(double trans) {
		if (pointSelectionModeEnabled && !selectedPoints.isEmpty()) { translateSelectedPointsFromOrig(0, trans); return; }
		CubicCurvePolygonSet polys = polygonManager.getPolygons();
		int totPolys = polys.getPolygonTotal();
		for (int i=0;i<totPolys+1;i++) {

			CubicCurveManager curveManager = polygonManager.getManager(i);
			CubicCurvePolygon curves = curveManager.getCurves();
			int totCurves = curves.getArrayofCubicCurves().length;

			for (int j = 0; j < totCurves; j++) {
				CubicPoint[] points = curves.getCurve(j).getPoints();
				for (int p = 0; p < points.length; p++) {
					Point2D.Double t = new Point2D.Double(0, trans);
					points[p].setPos (Transform.translate(points[p].getOrigPos(), t));
				}
			}
		}
	}
	public void scaleXY(double scale) {
		if (scaleRotateSnapshotPending) {
			takeUndoSnapshot();
			scaleRotateSnapshotPending = false;
			// Freeze oval orig values so the slider gesture scales from a fixed baseline
			// (mirrors the CubicPoint.origPos pattern used for polygon scaling)
			// Only fall back to all ovals when no selection mode is active.
			java.util.List<OvalManager> freezeOvals = !selectedOvals.isEmpty() ? selectedOvals
					: ((polygonSelectionModeEnabled || openCurveSelectionModeEnabled)
						? java.util.Collections.emptyList() : ovalList);
			for (OvalManager o : freezeOvals) o.freezeOrig();
		}
		// In point/edge mode the slider is a no-op when nothing is selected
		if (pointSelectionModeEnabled) {
			if (!selectedPoints.isEmpty()) scaleSelectedPoints(scale);
			return;
		}
		if (edgeSelectionModeEnabled) {
			if (!selectedEdges.isEmpty()) scaleSelectedEdges(scale);
			return;
		}
		boolean editAnchors = isAnchorSelect();
		boolean editControls = isControlSelect();
		double factor = 1.0 + scale / 100.0;
		int axisMode = cubicCurvePanel.getScaleAxisMode();
		boolean doX = (axisMode != CubicCurvePanel.SCALE_Y);
		boolean doY = (axisMode != CubicCurvePanel.SCALE_X);

		ArrayList<CubicCurveManager> targets;
		if (!selectedPolygons.isEmpty()) {
			targets = selectedPolygons;
		} else if (polygonSelectionModeEnabled || openCurveSelectionModeEnabled) {
			// In a selection mode but no curve managers selected — nothing to scale.
			targets = new ArrayList<>();
		} else {
			// No active selection mode: legacy "transform everything".
			int totPolys = polygonManager.getPolygons().getPolygonTotal();
			targets = new ArrayList<CubicCurveManager>();
			for (int i = 0; i < totPolys; i++) { // exclude the active drawing manager (last slot)
				targets.add(polygonManager.getManager(i));
			}
		}

		// Scale selected ovals only. Fall back to all ovals only when no selection mode is active.
		java.util.List<OvalManager> ovalTargets = !selectedOvals.isEmpty() ? selectedOvals
				: ((polygonSelectionModeEnabled || openCurveSelectionModeEnabled)
					? java.util.Collections.emptyList() : ovalList);
		if (!ovalTargets.isEmpty()) {
			double ocx = 0, ocy = 0; int cnt = 0;
			for (OvalManager o : ovalTargets) { ocx += o.getOrigCx(); ocy += o.getOrigCy(); cnt++; }
			if (cnt > 0) {
				ocx /= cnt; ocy /= cnt;
				for (OvalManager o : ovalTargets) {
					if (doX && doY) o.scaleXYFromOrig(factor, ocx, ocy);
					else if (doX)  o.scaleXFromOrig(factor, ocx);
					else           o.scaleYFromOrig(factor, ocy);
				}
			}
		}

		// Shared centre only when actual polygons are selected in relational mode.
		// When nothing is selected we fall back to per-polygon centres so the empty
		// drawing manager (getCubicCurveTotal()==0) can never produce NaN.
		boolean scaleRelational = polygonSelectionModeEnabled
		                        && polySubMode == SelectionSubMode.RELATIONAL
		                        && !selectedPolygons.isEmpty();

		Point2D.Double sharedCenter = null;
		if (scaleRelational) {
			double cx = 0, cy = 0; int cnt = 0;
			for (CubicCurveManager m : targets) {
				if (m.getCurves().getCubicCurveTotal() > 0) {
					Point2D.Double c = m.getAverageXYFromOrig();
					cx += c.x; cy += c.y; cnt++;
				}
			}
			if (cnt > 0) sharedCenter = new Point2D.Double(cx / cnt, cy / cnt);
		}

		WeldRegistry scaleWR = scaleRelational ? polygonManager.getWeldRegistry() : null;
		HashSet<CubicPoint> scaleProcessed = scaleRelational ? new HashSet<>() : null;

		for (CubicCurveManager curveManager : targets) {
			CubicCurvePolygon curves = curveManager.getCurves();
			int totCurves = curves.getCubicCurveTotal();
			if (totCurves > 0) {
				Point2D.Double center = (scaleRelational && sharedCenter != null)
				                      ? sharedCenter
				                      : curveManager.getAverageXYFromOrig();
				for (int j = 0; j < totCurves; j++) {
					CubicPoint[] points = curves.getCurve(j).getPoints();
					for (int p = 0; p < points.length; p++) {
						boolean isAnchor = (p == 0 || p == 3);
						if (isAnchor && !editAnchors) continue;
						if (!isAnchor && !editControls) continue;
						double ox = points[p].getOrigPos().x - center.x;
						double oy = points[p].getOrigPos().y - center.y;
						double nx = doX ? ox * factor + center.x : points[p].getOrigPos().x;
						double ny = doY ? oy * factor + center.y : points[p].getOrigPos().y;
						points[p].setPos(new Point2D.Double(nx, ny));
						// RELATIONAL: apply same transform to all weld-linked partners
						if (scaleRelational && scaleProcessed.add(points[p])) {
							for (CubicPoint linked : scaleWR.getLinked(points[p])) {
								if (!scaleProcessed.add(linked)) continue;
								double lox = linked.getOrigPos().x - center.x;
								double loy = linked.getOrigPos().y - center.y;
								double lnx = doX ? lox * factor + center.x : linked.getOrigPos().x;
								double lny = doY ? loy * factor + center.y : linked.getOrigPos().y;
								linked.setPos(new Point2D.Double(lnx, lny));
							}
						}
					}
				}
			}
		}
	}
	public void scaleX(double scale) {

		CubicCurvePolygonSet polys = polygonManager.getPolygons();
		int totPolys = polys.getPolygonTotal();
		for (int i=0;i<totPolys+1;i++) {

			CubicCurveManager curveManager = polygonManager.getManager(i);
			CubicCurvePolygon curves = curveManager.getCurves();
			int totCurves = curves.getArrayofCubicCurves().length;

			if (totCurves > 0) {
				curveManager.setBezierPosition(new Point2D.Double(0.0, 0.0));

				for (int j = 0; j < totCurves; j++) {
					CubicPoint[] points = curves.getCurve(j).getPoints();
					for (int p = 0; p < points.length; p++) {
						Point2D.Double t = new Point2D.Double((scale/500)+1.0, 1.0);
						points[p].setPos (Transform.scale(points[p].getPos(), t));
					}
				}

				curveManager.setBezierPosition(curveManager.getCurrentBezierPos());
			}
		}
	}
	public void scaleY(double scale) {

		CubicCurvePolygonSet polys = polygonManager.getPolygons();
		int totPolys = polys.getPolygonTotal();
		for (int i=0;i<totPolys+1;i++) {

			CubicCurveManager curveManager = polygonManager.getManager(i);
			CubicCurvePolygon curves = curveManager.getCurves();
			int totCurves = curves.getArrayofCubicCurves().length;

			if (totCurves > 0) {
				curveManager.setBezierPosition(new Point2D.Double(0.0, 0.0));

				for (int j = 0; j < totCurves; j++) {
					CubicPoint[] points = curves.getCurve(j).getPoints();
					for (int p = 0; p < points.length; p++) {
						Point2D.Double t = new Point2D.Double(1.0, (scale/500)+1.0);
						points[p].setPos(Transform.scale(points[p].getPos(), t));
					}
				}
				curveManager.setBezierPosition(curveManager.getCurrentBezierPos());
			}
		}
	}
	public void rotate(double rot) {
		if (scaleRotateSnapshotPending) { takeUndoSnapshot(); scaleRotateSnapshotPending = false; }
		if (pointSelectionModeEnabled && !selectedPoints.isEmpty()) { rotateSelectedPoints(rot); return; }
		if (edgeSelectionModeEnabled && !selectedEdges.isEmpty()) {
			rotateSelectedEdges(rot);
			return;
		}
		boolean editAnchors = isAnchorSelect();
		boolean editControls = isControlSelect();
		int axisMode = cubicCurvePanel.getRotationAxisMode();

		ArrayList<CubicCurveManager> targets;
		if (!selectedPolygons.isEmpty()) {
			targets = selectedPolygons;
		} else if (polygonSelectionModeEnabled || openCurveSelectionModeEnabled) {
			targets = new ArrayList<>();
		} else {
			int totPolys = polygonManager.getPolygons().getPolygonTotal();
			targets = new ArrayList<CubicCurveManager>();
			for (int i = 0; i < totPolys + 1; i++) {
				targets.add(polygonManager.getManager(i));
			}
		}

		if (axisMode == CubicCurvePanel.ROTATE_COMMON) {
			// All target polygons orbit a single shared pivot — the mean of their centres
			Point2D.Double common = computeCommonCenter(targets);
			for (CubicCurveManager m : targets) {
				rotateManagerAroundCenter(m, rot, common, editAnchors, editControls);
			}
		} else if (axisMode == CubicCurvePanel.ROTATE_ABSOLUTE) {
			// All polygons orbit the absolute centre of the drawing grid
			Point2D.Double absCenter = new Point2D.Double(
				edgeOffset + GRIDWIDTH  / 2.0,
				edgeOffset + GRIDHEIGHT / 2.0);
			for (CubicCurveManager m : targets) {
				rotateManagerAroundCenter(m, rot, absCenter, editAnchors, editControls);
			}
		} else {
			// ROTATE_LOCAL (default) — each polygon orbits its own centre
			for (CubicCurveManager m : targets) {
				rotateManagerAroundCenter(m, rot, m.getAverageXYFromOrig(), editAnchors, editControls);
			}
		}
		// Rotate selected ovals only; fall back to all ovals only when no selection mode is active.
		java.util.List<OvalManager> ovalTargets = !selectedOvals.isEmpty() ? selectedOvals
				: ((polygonSelectionModeEnabled || openCurveSelectionModeEnabled)
					? java.util.Collections.emptyList() : ovalList);
		if (!ovalTargets.isEmpty()) {
			Point2D.Double pivot;
			if (axisMode == CubicCurvePanel.ROTATE_ABSOLUTE) {
				pivot = new Point2D.Double(edgeOffset + GRIDWIDTH / 2.0, edgeOffset + GRIDHEIGHT / 2.0);
			} else {
				double cx = 0, cy = 0; int cnt = 0;
				for (OvalManager o : ovalTargets) { cx += o.getCx(); cy += o.getCy(); cnt++; }
				pivot = (cnt > 0) ? new Point2D.Double(cx / cnt, cy / cnt)
				                  : new Point2D.Double(edgeOffset + GRIDWIDTH / 2.0, edgeOffset + GRIDHEIGHT / 2.0);
			}
			for (OvalManager o : ovalTargets) o.rotate(rot, pivot.x, pivot.y);
		}
	}

	/** Rotate all points of curveManager around the given centre by rot degrees.
	 *  In RELATIONAL polygon mode, weld-linked partners are rotated around the same pivot. */
	private void rotateManagerAroundCenter(CubicCurveManager curveManager, double rot,
	                                        Point2D.Double center,
	                                        boolean editAnchors, boolean editControls) {
		boolean relational = polygonSelectionModeEnabled && polySubMode == SelectionSubMode.RELATIONAL;
		WeldRegistry wr = relational ? polygonManager.getWeldRegistry() : null;
		HashSet<CubicPoint> rotProcessed = relational ? new HashSet<>() : null;
		CubicCurvePolygon curves = curveManager.getCurves();
		int totCurves = curves.getArrayofCubicCurves().length;
		if (totCurves > 0) {
			for (int j = 0; j < totCurves; j++) {
				CubicPoint[] points = curves.getCurve(j).getPoints();
				for (int p = 0; p < points.length; p++) {
					boolean isAnchor = (p == 0 || p == 3);
					if (isAnchor && !editAnchors) continue;
					if (!isAnchor && !editControls) continue;
					Point2D.Double relative = new Point2D.Double(
						points[p].getOrigPos().x - center.x,
						points[p].getOrigPos().y - center.y);
					Point2D.Double rotated = Transform.rotate(relative, rot);
					points[p].setPos(new Point2D.Double(rotated.x + center.x, rotated.y + center.y));
					// RELATIONAL: apply same rotation to weld-linked partners
					if (relational && rotProcessed.add(points[p])) {
						for (CubicPoint linked : wr.getLinked(points[p])) {
							if (!rotProcessed.add(linked)) continue;
							Point2D.Double lrel = new Point2D.Double(
								linked.getOrigPos().x - center.x,
								linked.getOrigPos().y - center.y);
							Point2D.Double lrot = Transform.rotate(lrel, rot);
							linked.setPos(new Point2D.Double(lrot.x + center.x, lrot.y + center.y));
						}
					}
				}
			}
		}
	}

	/** Compute the mean centre of all non-empty managers in the list (from origPos). */
	private Point2D.Double computeCommonCenter(ArrayList<CubicCurveManager> targets) {
		double x = 0, y = 0;
		int count = 0;
		for (CubicCurveManager m : targets) {
			if (m.getCurves().getArrayofCubicCurves().length > 0) {
				Point2D.Double c = m.getAverageXYFromOrig();
				x += c.x;
				y += c.y;
				count++;
			}
		}
		return count == 0 ? new Point2D.Double(0, 0) : new Point2D.Double(x / count, y / count);
	}
	public void setPolygonSelectionMode(boolean enabled) {
		polygonSelectionModeEnabled = enabled;
		if (!enabled) {
			for (CubicCurveManager m : selectedPolygons) m.clearAllHighlights();
			selectedPolygons.clear();
			for (OvalManager o : selectedOvals) o.setSelected(false);
			selectedOvals.clear();
			clearPendingWeld();
		}
	}

	public void setOpenCurveSelectionMode(boolean enabled) {
		openCurveSelectionModeEnabled = enabled;
		if (!enabled) {
			for (CubicCurveManager m : selectedPolygons) m.clearAllHighlights();
			selectedPolygons.clear();
		}
	}
	public boolean isOpenCurveSelectionModeEnabled() { return openCurveSelectionModeEnabled; }

	private void handleOpenCurveSelectionClick(Point2D.Double mousePos) {
		int polygonCount = polygonManager.getPolygonCount();
		CubicCurveManager hit = null;
		for (int i = polygonCount - 1; i >= 0; i--) {
			CubicCurveManager m = polygonManager.getManager(i);
			if (m.getIsClosed()) continue;
			if (m.getLayerId() != layerManager.getActiveLayerId()) continue;
			if (nearOpenCurve(m, mousePos, 8.0)) { hit = m; break; }
		}
		if (hit == null) {
			for (CubicCurveManager m : selectedPolygons) m.clearAllHighlights();
			selectedPolygons.clear();
			return;
		}
		if (!hit.isSelected()) {
			for (CubicCurveManager m : selectedPolygons) m.clearAllHighlights();
			selectedPolygons.clear();
			hit.setSelected(true);
			hit.setSelectedRelational(false);
			selectedPolygons.add(hit);
		}
	}

	/** Returns true if mousePos is within hitDist pixels of any point on the curve's path. */
	private boolean nearOpenCurve(CubicCurveManager m, Point2D.Double pos, double hitDist) {
		CubicCurve[] cArray = m.getCurves().getArrayofCubicCurves();
		if (cArray.length == 0) return false;
		java.awt.geom.Path2D.Double path = new java.awt.geom.Path2D.Double();
		CubicPoint[] first = cArray[0].getPoints();
		if (first[0] == null) return false;
		path.moveTo(first[0].getPos().x, first[0].getPos().y);
		for (CubicCurve cv : cArray) {
			CubicPoint[] p = cv.getPoints();
			if (p[0] == null || p[1] == null || p[2] == null || p[3] == null) continue;
			path.curveTo(p[1].getPos().x, p[1].getPos().y,
			             p[2].getPos().x, p[2].getPos().y,
			             p[3].getPos().x, p[3].getPos().y);
		}
		java.awt.Shape stroked = new BasicStroke((float)(hitDist * 2),
			BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND).createStrokedShape(path);
		return stroked.contains(pos.x, pos.y);
	}

	private void handlePolygonSelectionClick(Point2D.Double mousePos) {
		int polygonCount = polygonManager.getPolygonCount();
		polygonClickCandidate = null;
		polygonMouseMoved = false;

		// Check ovals on the active layer first (drawn on top).
		int activeLayer = layerManager.getActiveLayerId();
		for (int i = ovalList.size() - 1; i >= 0; i--) {
			OvalManager oval = ovalList.get(i);
			if (oval.getLayerId() != activeLayer) continue;
			if (!oval.contains(mousePos.x, mousePos.y)) continue;
			if (!oval.isSelected()) {
				oval.setSelected(true);
				selectedOvals.add(oval);
			}
			return;
		}

		// Iterate in reverse (newest / innermost polygon takes priority).
		// Find the highest-priority polygon under the click, then the next one underneath.
		// Only consider polygons on the active layer.
		CubicCurveManager topmost = null;
		CubicCurveManager beneath = null;
		for (int i = polygonCount - 1; i >= 0; i--) {
			CubicCurveManager m = polygonManager.getManager(i);
			if (m.getLayerId() != layerManager.getActiveLayerId()) continue;
			if (!m.containsPoint(mousePos)) continue;
			if (topmost == null) { topmost = m; }
			else if (beneath == null) { beneath = m; break; }
		}

		if (topmost == null) {
			// Click on empty space — deselect all
			for (CubicCurveManager m : selectedPolygons) m.clearAllHighlights();
			selectedPolygons.clear();
			for (OvalManager o : selectedOvals) o.setSelected(false);
			selectedOvals.clear();
			return;
		}

		if (!topmost.isSelected()) {
			// Topmost polygon is unselected — add it to the selection immediately.
			topmost.setSelected(true);
			topmost.setSelectedRelational(polySubMode == SelectionSubMode.RELATIONAL);
			selectedPolygons.add(topmost);
			return;
		}

		// Topmost polygon is already selected.
		// If there is an unselected polygon underneath, defer adding it to mouseReleased
		// so that a subsequent drag can still move the currently-selected polygon(s)
		// without accidentally adding the outer polygon to the selection.
		if (beneath != null && !beneath.isSelected()) {
			polygonClickCandidate = beneath;
		}
		// Leave current selection intact (allows drag to proceed on existing selection).
	}

	/**
	 * Translate all points in curveManager by (dx, dy).
	 * moved is shared across all managers in the same drag event so that a point
	 * is only translated once even if it appears in multiple curves or is visited
	 * again via a weld link.
	 *
	 * After moving each point we also move its WeldRegistry partners — points in
	 * OTHER polygons that are welded to this one. This keeps the weld seam intact
	 * when dragging a single selected polygon: the shared boundary slides with the
	 * dragged polygon while the rest of the neighbour polygon stays fixed.
	 */
	private void translatePolygonBy(CubicCurveManager curveManager, double dx, double dy,
	                                HashSet<CubicPoint> moved) {
		WeldRegistry wr = polygonManager.getWeldRegistry();
		boolean relational = (polySubMode == SelectionSubMode.RELATIONAL);
		CubicCurvePolygon curves = curveManager.getCurves();
		int totCurves = curves.getArrayofCubicCurves().length;
		for (int j = 0; j < totCurves; j++) {
			CubicPoint[] points = curves.getCurve(j).getPoints();
			for (int p = 0; p < points.length; p++) {
				if (!moved.add(points[p])) continue; // already moved
				Point2D.Double pos = points[p].getPos();
				points[p].setPos(new Point2D.Double(pos.x + dx, pos.y + dy));
				points[p].setOrigPosToPos();
				// RELATIONAL: propagate movement to all weld-linked partners.
				if (relational) {
					for (CubicPoint linked : wr.getLinked(points[p])) {
						if (!moved.add(linked)) continue;
						Point2D.Double lpos = linked.getPos();
						linked.setPos(new Point2D.Double(lpos.x + dx, lpos.y + dy));
						linked.setOrigPosToPos();
					}
				}
				// DISCRETE: weld partners stay put; links persist for future use
			}
		}
		curveManager.setCurrentBezierPosition(curveManager.getAverageXY());
	}

	/**
	 * Duplicate all currently selected polygons, placing each copy offset by a
	 * small amount so it is visually adjacent to the original.
	 * The originals are deselected; the duplicates become the new selection.
	 */
	public void duplicateSelectedPolygons() {
		if (selectedPolygons.isEmpty()) return;
		final double OFFSET = 20.0;
		boolean relational = (polySubMode == SelectionSubMode.RELATIONAL);
		ArrayList<CubicCurveManager> duplicates = new ArrayList<CubicCurveManager>();
		for (CubicCurveManager source : selectedPolygons) {
			source.setSelected(false);
			CubicCurveManager dup = polygonManager.addDuplicateOf(source, OFFSET, OFFSET);
			dup.setSelectedRelational(relational);
			duplicates.add(dup);
		}
		selectedPolygons.clear();
		selectedPolygons.addAll(duplicates);
	}

	/**
	 * Delete all currently selected polygons.
	 * Iterates in descending index order so removals don't shift remaining indices.
	 */
	public void deleteSelectedPolygons() {
		if (selectedPolygons.isEmpty()) return;
		int totPolys = polygonManager.getPolygonCount();
		ArrayList<Integer> indices = new ArrayList<Integer>();
		for (CubicCurveManager m : selectedPolygons) {
			for (int i = 0; i < totPolys; i++) {
				if (polygonManager.getManager(i) == m) {
					indices.add(i);
					break;
				}
			}
		}
		// Remove highest indices first to avoid shifting lower indices
		indices.sort((a, b) -> b - a);
		for (int idx : indices) {
			polygonManager.removeManagerAtIndex(idx);
		}
		selectedPolygons.clear();
	}

	/**
	 *
	 * @param strokeColor
	 */
	public void setStrokeColor(Color strokeColor) {
		this.strokeColor = strokeColor;
		
		int polygonCount = polygonManager.getPolygonCount();
		for (int i = 0; i < polygonCount; i++) {
			CubicCurveManager curveM = polygonManager.getManager(i);
			CubicCurvePolygon curves = curveM.getCurves();
			int totCurves = curveM.getCurveCount();
		
			curveM.setCurrentCurveColor(strokeColor);
			CubicCurve[] cs = curveM.getCurves().getArrayofCubicCurves();
			for (int j = 0; j < totCurves; j++) {
				cs[j].setStrokeCol(strokeColor);
			}
		}
	}
	/**
	 * when the slider is released all points original position needs to be
	 * set to modified position
	 */
	public void setOrigPosOfAllPointsToModifiedPos() {
		int polygonCount = polygonManager.getPolygonCount();
		for (int i = 0; i < polygonCount; i++) {
			CubicCurveManager curveM = polygonManager.getManager(i);
			CubicCurvePolygon curves = curveM.getCurves();
			// Use getArrayofCubicCurves().length so the closing curve is included
			// (curveCount field is never incremented by closeCurve(), so getCurveCount()
			// is one short of the true total)
			int totCurves = curves.getArrayofCubicCurves().length;
			if (totCurves > 0) {
				for (int j = 0; j < totCurves; j++) {
					CubicPoint[] points = curves.getCurve(j).getPoints();
					for (int p = 0; p < points.length; p++) {
						points[p].setOrigPosToPos();
						points[p].setOrigScaleToScale();
						points[p].setOrigRotationToRotation();
					}
				}
				curveM.setCurrentBezierPosition(curveM.getAverageXY());
			}
		}
		scaleRotateSnapshotPending = true; // next slider gesture will take a fresh snapshot
	}
	/**
	 *
	 */
	public void snapToGrid(boolean snapControlPoints) {
		takeUndoSnapshot();
		WeldRegistry wr = polygonManager.getWeldRegistry();
		HashSet<CubicPoint> processed = new HashSet<>();
		int al = layerManager.getActiveLayerId();
		int polygonCount = polygonManager.getPolygonCount();
		for (int i = 0; i < polygonCount; i++) {
			CubicCurveManager curveM = polygonManager.getManager(i);
			if (curveM.getLayerId() != al) continue;
			CubicCurvePolygon curves = curveM.getCurves();
			int totCurves = curveM.getCurveCount();
			for (int j = 0; j < totCurves + 1; j++) {
				CubicPoint[] points = curves.getCurve(j).getPoints();
				// Snap each anchor to nearest grid point; propagate to all weld-linked partners
				// so that welded coincident points always land on the same grid coordinate.
				if (points[0] != null && !processed.contains(points[0])) {
					snapPointToPos(points[0], getNearestGridCoordinate(points[0]), wr, processed);
				}
				if (points[3] != null && !processed.contains(points[3])) {
					snapPointToPos(points[3], getNearestGridCoordinate(points[3]), wr, processed);
				}
				if (snapControlPoints) {
					curves.getCurve(j).resetControlPoints();
				}
			}
		}
	}
	/**
	 * 
	 */
	private Point2D.Double getNearestGridCoordinate(CubicPoint p) {
		int[][] horiz = grid.getHoriz();
		int[][] verts = grid.getVerts();
		Point2D.Double gridCoord = new Point2D.Double(0.0, 0.0);
		double h = 800.0;//very large default hypotenuse
		for (int r = 0; r< verts.length; r++) {
			for (int c = 0; c< horiz.length; c++) {
				Point2D.Double tempGridCoord = new Point2D.Double((double)(horiz[c][0]), ((double)(verts[r][0])));
				double currentH = Formulas.hypotenuse(p.getPos(), tempGridCoord);
				if (currentH < h) {
					h = currentH;
					gridCoord = new Point2D.Double(tempGridCoord.x, tempGridCoord.y);
				}
			}
		}
		System.out.println("___________________________________");
		System.out.println("BezierDrawPanel, getNearestGridAxesCoordinate, row: " + gridCoord.x + "   col: "+ gridCoord.y);
		return gridCoord;

	}
	/**
	 * @return the cubicCurvePanel
	 */
	public CubicCurvePanel getCubicCurvePanel() {
		return cubicCurvePanel;
	}
	/**
	 * switch displayReferenceImage
	 */
	public void toggleDisplayReferenceImage() {
		this.displayReferenceImage = !displayReferenceImage;
	}
	
	/**
	 * toggle grid display
	 */
	public void toggleGridDisplay() {
		grid.toggleGridDisplay();
	}
	
	/**
	 * toggle grid axes display
	 */
	public void toggleGridAxesDisplay() {
		gridAxes.toggleGridAxesDisplay();
	}
	/**
	 * @return the strokeColor
	 */
	public Color getStrokeColor() {
		return strokeColor;
	}
	/**
	 * @return the edgeOffset
	 */
	public int getEdgeOffset() {
		return edgeOffset;
	}
	public CubicCurvePolygonManager getPolygonManager() {
		return polygonManager;
	}
	public LayerManager getLayerManager() {
		return layerManager;
	}

	public void copySelectedToClipboard() {
		clipboard.clear();
		if (edgeSelectionModeEnabled && !selectedEdges.isEmpty()) {
			for (SelectedEdge se : selectedEdges) {
				CubicCurve cv = se.manager.getCurves().getCurve(se.curveIndex);
				CubicPoint[] p = cv.getPoints();
				Point2D.Double[] pts = new Point2D.Double[4];
				for (int i = 0; i < 4; i++)
					pts[i] = new Point2D.Double(p[i].getPos().x, p[i].getPos().y);
				clipboard.add(new ClipboardEntry(pts, false));
			}
		} else {
			for (CubicCurveManager m : selectedPolygons) {
				CubicCurve[] cvs = m.getCurves().getArrayofCubicCurves();
				Point2D.Double[] pts = new Point2D.Double[cvs.length * 4];
				int k = 0;
				for (CubicCurve cv : cvs) {
					CubicPoint[] p = cv.getPoints();
					for (int i = 0; i < 4; i++) pts[k++] = new Point2D.Double(p[i].getPos().x, p[i].getPos().y);
				}
				clipboard.add(new ClipboardEntry(pts, m.getIsClosed()));
			}
		}
	}

	public void pasteFromClipboard() {
		if (clipboard.isEmpty()) return;
		takeUndoSnapshot();
		// Compute centroid of all clipboard points
		double cx = 0, cy = 0; int cnt = 0;
		for (ClipboardEntry e : clipboard)
			for (Point2D.Double p : e.pts) { cx += p.x; cy += p.y; cnt++; }
		if (cnt > 0) { cx /= cnt; cy /= cnt; }
		// Offset so centroid lands at hover position
		double dx = currentMousePos.x - cx;
		double dy = currentMousePos.y - cy;
		for (ClipboardEntry entry : clipboard) {
			Point2D.Double[] off = new Point2D.Double[entry.pts.length];
			for (int i = 0; i < entry.pts.length; i++)
				off[i] = new Point2D.Double(entry.pts[i].x + dx, entry.pts[i].y + dy);
			if (entry.isClosed) polygonManager.addClosedFromPoints(off, strokeColor);
			else                 polygonManager.addOpenCurveFromPoints(off, strokeColor);
		}
	}
	public void selectAll() {
		int tot = polygonManager.getPolygonCount();
		int al = layerManager.getActiveLayerId();
		if (polygonSelectionModeEnabled) {
			for (int i = 0; i < tot; i++) {
				CubicCurveManager m = polygonManager.getManager(i);
				if (!m.getIsClosed() || m.getLayerId() != al || m.isSelected()) continue;
				m.setSelected(true);
				m.setSelectedRelational(polySubMode == SelectionSubMode.RELATIONAL);
				selectedPolygons.add(m);
			}
			for (OvalManager o : ovalList)
				if (o.getLayerId() == al && !o.isSelected()) { o.setSelected(true); selectedOvals.add(o); }
		} else if (openCurveSelectionModeEnabled) {
			for (int i = 0; i < tot; i++) {
				CubicCurveManager m = polygonManager.getManager(i);
				if (m.getIsClosed() || m.getLayerId() != al || m.isSelected()) continue;
				if (m.getCurves().getCubicCurveTotal() == 0) continue; // skip empty stubs
				m.setSelected(true);
				selectedPolygons.add(m);
			}
		} else if (edgeSelectionModeEnabled) {
			for (int i = 0; i < tot; i++) {
				CubicCurveManager m = polygonManager.getManager(i);
				if (m.getLayerId() != al) continue;
				CubicCurve[] cvs = m.getCurves().getArrayofCubicCurves();
				for (int j = 0; j < cvs.length; j++) {
					final int fi = j; final CubicCurveManager fm = m;
					boolean already = selectedEdges.stream().anyMatch(s -> s.manager == fm && s.curveIndex == fi);
					if (!already) selectedEdges.add(new SelectedEdge(m, j));
				}
			}
			updateEdgeHighlights();
		} else if (pointSelectionModeEnabled) {
			HashSet<CubicPoint> seen = new HashSet<>();
			for (int i = 0; i < tot; i++) {
				CubicCurveManager m = polygonManager.getManager(i);
				if (m.getLayerId() != al) continue;
				for (CubicCurve cv : m.getCurves().getArrayofCubicCurves())
					for (CubicPoint pt : cv.getPoints())
						if (pt != null && seen.add(pt) && !selectedPoints.contains(pt))
							selectedPoints.add(pt);
			}
			updatePointHighlights();
		}
		pushSelectionToHistory();
	}

	public void deselectAll() {
		selectedPoints.clear();
		selectedEdges.clear();
		for (CubicCurveManager m : selectedPolygons) m.clearAllHighlights();
		selectedPolygons.clear();
		for (OvalManager o : selectedOvals) o.setSelected(false);
		selectedOvals.clear();
		clearScopeHighlight();
		updatePointHighlights();
		updateEdgeHighlights();
	}

	// ── Selection history helpers ────────────────────────────────────────────

	private SelectionSnapshot takeSelectionSnapshot() {
		return new SelectionSnapshot(selectedPoints, selectedEdges, selectedPolygons, selectedOvals);
	}

	/** Push the current non-empty selection to history. No-op while navigating or if unchanged. */
	public void pushSelectionToHistory() {
		if (navigatingHistory) return;
		if (selectedPoints.isEmpty() && selectedEdges.isEmpty()
				&& selectedPolygons.isEmpty() && selectedOvals.isEmpty()) return;
		int currentLayer = (layerManager != null) ? layerManager.getActiveLayerId() : -1;
		if (currentLayer != historyLayerId) {
			selectionHistory.clear();
			selectionHistoryCursor = -1;
			historyLayerId = currentLayer;
		}
		// Truncate forward entries if a new selection is made while mid-navigation
		if (selectionHistoryCursor >= 0 && selectionHistoryCursor < selectionHistory.size() - 1)
			selectionHistory.subList(selectionHistoryCursor + 1, selectionHistory.size()).clear();
		// Skip if identical to the most recent entry
		if (!selectionHistory.isEmpty()) {
			SelectionSnapshot last = selectionHistory.get(selectionHistory.size() - 1);
			if (last.curves.size()  == selectedPolygons.size() && last.curves.containsAll(selectedPolygons)
			 && last.ovals.size()   == selectedOvals.size()    && last.ovals.containsAll(selectedOvals)
			 && last.edges.size()   == selectedEdges.size()
			 && last.points.size()  == selectedPoints.size()   && last.points.containsAll(selectedPoints))
				return;
		}
		selectionHistory.add(takeSelectionSnapshot());
		if (selectionHistory.size() > SELECTION_HISTORY_MAX)
			selectionHistory.remove(0);
		selectionHistoryCursor = selectionHistory.size() - 1;
	}

	/** Clear history — call on layer switch or undo. */
	public void clearSelectionHistory() {
		selectionHistory.clear();
		selectionHistoryCursor = -1;
		historyLayerId = (layerManager != null) ? layerManager.getActiveLayerId() : -1;
	}

	/** Navigate to an older selection (← key). */
	public void navigateSelectionBack() {
		int currentLayer = (layerManager != null) ? layerManager.getActiveLayerId() : -1;
		if (currentLayer != historyLayerId) { clearSelectionHistory(); return; }
		if (selectionHistoryCursor <= 0) return;
		selectionHistoryCursor--;
		restoreSelectionSnapshot(selectionHistory.get(selectionHistoryCursor));
	}

	/** Navigate to a more recent selection (→ key). */
	public void navigateSelectionForward() {
		int currentLayer = (layerManager != null) ? layerManager.getActiveLayerId() : -1;
		if (currentLayer != historyLayerId) { clearSelectionHistory(); return; }
		if (selectionHistoryCursor < 0 || selectionHistoryCursor >= selectionHistory.size() - 1) return;
		selectionHistoryCursor++;
		restoreSelectionSnapshot(selectionHistory.get(selectionHistoryCursor));
	}

	private void restoreSelectionSnapshot(SelectionSnapshot snap) {
		navigatingHistory = true;
		for (CubicCurveManager m : selectedPolygons) m.clearAllHighlights();
		for (OvalManager o : selectedOvals) o.setSelected(false);
		selectedPoints.clear();
		selectedEdges.clear();
		selectedPolygons.clear();
		selectedOvals.clear();
		clearScopeHighlight();
		int al = (layerManager != null) ? layerManager.getActiveLayerId() : -1;
		if (polygonSelectionModeEnabled) {
			for (CubicCurveManager m : snap.curves) {
				if (!m.getIsClosed() || m.getLayerId() != al) continue;
				m.setSelected(true);
				m.setSelectedRelational(polySubMode == SelectionSubMode.RELATIONAL);
				selectedPolygons.add(m);
			}
			for (OvalManager o : snap.ovals) {
				if (o.getLayerId() != al) continue;
				o.setSelected(true);
				selectedOvals.add(o);
			}
		} else if (openCurveSelectionModeEnabled) {
			for (CubicCurveManager m : snap.curves) {
				if (m.getIsClosed() || m.getLayerId() != al) continue;
				m.setSelected(true);
				selectedPolygons.add(m);
			}
		} else if (edgeSelectionModeEnabled) {
			selectedEdges.addAll(snap.edges);
			updateEdgeHighlights();
		} else if (pointSelectionModeEnabled) {
			selectedPoints.addAll(snap.points);
			updatePointHighlights();
		}
		updatePointHighlights();
		updateEdgeHighlights();
		navigatingHistory = false;
		repaint();
	}

	//NOT WORKING YET
	public void weldSelectedPoints() {
		System.out.println("BezierDrawPanel, weldSelectedPoints, selectedPoints size: " + selectedPoints.size());
		int selectedPointsTotal = selectedPoints.size();
		if (selectedPointsTotal > 1) {
			for (int i = 0; i < selectedPointsTotal; i++) {
				System.out.println("...");
				System.out.println("BezierDrawPanel, weldSelectedPoints, selectedPoint index: " + i + "   selected point: " + selectedPoints.get(i));
				if (i > 0) {
					System.out.println("___BezierDrawPanel, weldSelectedPoints, selectedPoints index: " + i);
					selectedPoints.get(i).setPos (new Point2D.Double(selectedPoints.get(0).getPos().x, selectedPoints.get(0).getPos().y));
					//selectedPoints.get(i).setSlave(selectedPoints.get(0));
					//selectedPoints.set(i, selectedPoints.get(0));
					polygonManager.replacePoints(selectedPoints.get(i), selectedPoints.get(0));

				}
			}
		}
	}
	/**
	 * Empty list of selected points after weld operation and when clicking anywhere on canvas other than points
	 */
	public void emptySelectedPoints() {
		System.out.println("BezierDrawPanel, mousePressed, selectedPoints size: " + selectedPoints.size());
		int selectedPointsTotal = selectedPoints.size();
		for (int i = 0; i < selectedPointsTotal; i++) {
				System.out.println("BezierDrawPanel, mousePressed, selectedPoints index: " + i);
			    selectedPoints.get(i).toggleSelected();
		}
		selectedPoints.clear();
	}
	
	public int getGridWidth() {
		return GRIDWIDTH;
	}
	public int getGridHeight() {
		return GRIDHEIGHT;
	}
	/**
	 * setZooming - from zoom button in BezierToolBarPanel
	 * @param b
	 */
	public void setZooming(boolean b) {
		zooming = b;
	}
	/**
	 * Zoom in — scale all geometry toward the canvas centre by factor 1.25.
	 */
	public void zoomIn() {
		takeUndoSnapshot();
		applyZoom(1.25);
	}
	/**
	 * Zoom out — scale all geometry away from the canvas centre by factor 0.8.
	 */
	public void zoomOut() {
		takeUndoSnapshot();
		applyZoom(0.8);
	}
	private void applyZoom(double factor) {
		Point2D.Double center = getZoomPivot();
		java.util.HashSet<CubicPoint> processed = new java.util.HashSet<>();
		int tot = polygonManager.getPolygonCount();
		for (int i = 0; i < tot; i++) {
			for (CubicCurve cv : polygonManager.getManager(i).getCurves().getArrayofCubicCurves()) {
				for (CubicPoint pt : cv.getPoints()) {
					if (pt == null || !processed.add(pt)) continue;
					double ox = pt.getPos().x - center.x;
					double oy = pt.getPos().y - center.y;
					pt.setPos(new Point2D.Double(ox * factor + center.x, oy * factor + center.y));
					pt.setOrigPosToPos();
				}
			}
		}
		for (OvalManager oval : ovalList) oval.scaleXY(factor, center.x, center.y);
	}

	/**
	 * Returns the pivot point for zoom operations.
	 * Uses the centroid of the current selection (points/edges/polygons) if any,
	 * otherwise falls back to the canvas centre.
	 */
	private Point2D.Double getZoomPivot() {
		if (!selectedPoints.isEmpty()) {
			double cx = 0, cy = 0;
			for (CubicPoint pt : selectedPoints) { cx += pt.getPos().x; cy += pt.getPos().y; }
			return new Point2D.Double(cx / selectedPoints.size(), cy / selectedPoints.size());
		}
		if (!selectedEdges.isEmpty()) {
			double cx = 0, cy = 0; int cnt = 0;
			for (SelectedEdge e : selectedEdges) {
				CubicPoint[] pts = e.manager.getCurves().getCurve(e.curveIndex).getPoints();
				if (pts[0] != null && pts[3] != null) {
					cx += (pts[0].getPos().x + pts[3].getPos().x) / 2.0;
					cy += (pts[0].getPos().y + pts[3].getPos().y) / 2.0;
					cnt++;
				}
			}
			if (cnt > 0) return new Point2D.Double(cx / cnt, cy / cnt);
		}
		if (!selectedPolygons.isEmpty()) {
			double cx = 0, cy = 0; int cnt = 0;
			for (CubicCurveManager m : selectedPolygons) {
				if (m.getCurves().getCubicCurveTotal() > 0) {
					Point2D.Double c = m.getAverageXY();
					cx += c.x; cy += c.y; cnt++;
				}
			}
			if (cnt > 0) return new Point2D.Double(cx / cnt, cy / cnt);
		}
		return new Point2D.Double(edgeOffset + GRIDWIDTH / 2.0, edgeOffset + GRIDHEIGHT / 2.0);
	}

	/**
	 * Centre selected polygons as a group to the canvas centre.
	 * If nothing is selected, centres all polygons.
	 */
	public void performCentre() {
		takeUndoSnapshot();
		Point2D.Double screenCentre = new Point2D.Double(edgeOffset + GRIDWIDTH / 2.0, edgeOffset + GRIDHEIGHT / 2.0);
		int al = layerManager.getActiveLayerId();
		java.util.List<CubicCurveManager> targets = selectedPolygons.isEmpty()
			? getManagersInLayer(al) : selectedPolygons;
		java.util.List<OvalManager> ovalTargets = selectedOvals.isEmpty()
			? getOvalsInLayer(al) : selectedOvals;
		double cx = 0, cy = 0; int cnt = 0;
		for (CubicCurveManager m : targets) {
			if (m.getCurves().getCubicCurveTotal() > 0) {
				Point2D.Double c = m.getAverageXY();
				cx += c.x; cy += c.y; cnt++;
			}
		}
		for (OvalManager o : ovalTargets) { cx += o.getCx(); cy += o.getCy(); cnt++; }
		if (cnt == 0) return;
		double dx = screenCentre.x - cx / cnt;
		double dy = screenCentre.y - cy / cnt;
		java.util.HashSet<CubicPoint> moved = new java.util.HashSet<>();
		for (CubicCurveManager m : targets) {
			m.setCenterPosition(new Point2D.Double(dx, dy), moved);
		}
		for (OvalManager o : ovalTargets) o.translate(dx, dy);
	}

	/**
	 * Flip selected polygons around their collective centroid.
	 * If nothing is selected, flips all polygons.
	 * @param horizontal  true = flip left/right (mirror on vertical axis),
	 *                    false = flip up/down (mirror on horizontal axis)
	 */
	public void performFlip(boolean horizontal) {
		takeUndoSnapshot();
		int al = layerManager.getActiveLayerId();
		java.util.List<CubicCurveManager> targets = selectedPolygons.isEmpty()
			? getManagersInLayer(al) : selectedPolygons;
		java.util.List<OvalManager> ovalTargets = selectedOvals.isEmpty()
			? getOvalsInLayer(al) : selectedOvals;
		double cx = 0, cy = 0; int cnt = 0;
		for (CubicCurveManager m : targets) {
			if (m.getCurves().getCubicCurveTotal() > 0) {
				Point2D.Double c = m.getAverageXY();
				cx += c.x; cy += c.y; cnt++;
			}
		}
		for (OvalManager o : ovalTargets) { cx += o.getCx(); cy += o.getCy(); cnt++; }
		if (cnt == 0) return;
		cx /= cnt; cy /= cnt;
		java.util.HashSet<CubicPoint> processed = new java.util.HashSet<>();
		for (CubicCurveManager m : targets) {
			for (CubicCurve cv : m.getCurves().getArrayofCubicCurves()) {
				for (CubicPoint pt : cv.getPoints()) {
					if (pt == null || !processed.add(pt)) continue;
					double px = pt.getPos().x;
					double py = pt.getPos().y;
					if (horizontal) pt.setPos(new Point2D.Double(2 * cx - px, py));
					else            pt.setPos(new Point2D.Double(px, 2 * cy - py));
					pt.setOrigPosToPos();
				}
			}
		}
		for (OvalManager o : ovalTargets) {
			if (horizontal) o.flipH(cx);
			else            o.flipV(cy);
		}
	}

	/** Returns all polygon managers (excludes the active drawing manager). */
	private java.util.List<CubicCurveManager> getAllManagers() {
		int tot = polygonManager.getPolygonCount();
		java.util.List<CubicCurveManager> all = new ArrayList<>();
		for (int i = 0; i < tot; i++) all.add(polygonManager.getManager(i));
		return all;
	}

	/** Returns all managers on the given layer. */
	private java.util.List<CubicCurveManager> getManagersInLayer(int layerId) {
		int tot = polygonManager.getPolygonCount();
		java.util.List<CubicCurveManager> result = new ArrayList<>();
		for (int i = 0; i < tot; i++) {
			CubicCurveManager m = polygonManager.getManager(i);
			if (m.getLayerId() == layerId) result.add(m);
		}
		return result;
	}

	/** Returns all ovals on the given layer. */
	private java.util.List<OvalManager> getOvalsInLayer(int layerId) {
		java.util.List<OvalManager> result = new ArrayList<>();
		for (OvalManager o : ovalList)
			if (o.getLayerId() == layerId) result.add(o);
		return result;
	}

	// ── Undo machinery ───────────────────────────────────────────────────────

	/** Build a full snapshot of the current geometry for undo. */
	private GeometrySnapshot takeSnapshot() {
		int count = polygonManager.getPolygonCount();
		GeometrySnapshot.ManagerSnap[] managers = new GeometrySnapshot.ManagerSnap[count];
		HashMap<CubicPoint, int[]> pointIndex = new HashMap<>();

		for (int i = 0; i < count; i++) {
			CubicCurveManager m = polygonManager.getManager(i);
			CubicCurve[] cvs = m.getCurves().getArrayofCubicCurves();
			int n = cvs.length;
			boolean isSingleEdge = (n == 1) && (cvs[0].getPoints()[3] != cvs[0].getPoints()[0]);
			double[] px = new double[n * 4];
			double[] py = new double[n * 4];
			for (int j = 0; j < n; j++) {
				CubicPoint[] pts = cvs[j].getPoints();
				for (int k = 0; k < 4; k++) {
					if (pts[k] != null) {
						int idx = j * 4 + k;
						px[idx] = pts[k].getPos().x;
						py[idx] = pts[k].getPos().y;
						pointIndex.put(pts[k], new int[]{i, j, k});
					}
				}
			}
				float[] aps = m.getAnchorPressures();
			float[] apsCopy = (aps != null) ? java.util.Arrays.copyOf(aps, aps.length) : null;
			managers[i] = new GeometrySnapshot.ManagerSnap(isSingleEdge, m.getIsClosed(), n, px, py, m.getLayerId(), apsCopy);
		}

		// Capture cross-manager weld links (deduplicated by canonical index key)
		HashSet<String> seenLinks = new HashSet<>();
		ArrayList<GeometrySnapshot.WeldLinkSnap> weldLinks = new ArrayList<>();
		for (Map.Entry<CubicPoint, Set<CubicPoint>> entry :
				polygonManager.getWeldRegistry().getEntries()) {
			CubicPoint pt0 = entry.getKey();
			int[] idx0 = pointIndex.get(pt0);
			if (idx0 == null) continue;
			for (CubicPoint pt1 : entry.getValue()) {
				if (pt0 == pt1) continue;
				int[] idx1 = pointIndex.get(pt1);
				if (idx1 == null) continue;
				if (idx0[0] == idx1[0]) continue; // skip same-manager (implicit in setAllPoints)
				String kA = idx0[0]+","+idx0[1]+","+idx0[2];
				String kB = idx1[0]+","+idx1[1]+","+idx1[2];
				String key = kA.compareTo(kB) <= 0 ? kA+"|"+kB : kB+"|"+kA;
				if (seenLinks.add(key)) {
					weldLinks.add(new GeometrySnapshot.WeldLinkSnap(
						idx0[0], idx0[1], idx0[2],
						idx1[0], idx1[1], idx1[2]));
				}
			}
		}
		// Snapshot the discrete point list
		Point2D.Double[] pointsSnap = pointList.toArray(new Point2D.Double[0]);
		// Snapshot per-point pressures
		float[] ppSnap = null;
		if (!pointPressures.isEmpty()) {
			ppSnap = new float[pointPressures.size()];
			for (int i = 0; i < ppSnap.length; i++) ppSnap[i] = pointPressures.get(i);
		}
		// Snapshot ovals
		GeometrySnapshot.OvalSnap[] ovalsSnap = new GeometrySnapshot.OvalSnap[ovalList.size()];
		for (int i = 0; i < ovalList.size(); i++) {
			OvalManager o = ovalList.get(i);
			ovalsSnap[i] = new GeometrySnapshot.OvalSnap(o.getCx(), o.getCy(), o.getRx(), o.getRy(), o.getLayerId());
		}
		return new GeometrySnapshot(managers,
			weldLinks.toArray(new GeometrySnapshot.WeldLinkSnap[0]),
			pointsSnap, ovalsSnap, ppSnap);
	}

	/** Push the current geometry state onto the undo stack. */
	public void takeUndoSnapshot() {
		undoManager.push(takeSnapshot());
	}

	/** Restore the most recent undo snapshot (Cmd+Z). */
	public void undo() {
		GeometrySnapshot snap = undoManager.pop();
		if (snap == null) return;
		clearSelectionHistory();
		// Clear all selection state first
		selectedPoints.clear();
		selectedEdges.clear();
		for (CubicCurveManager m : selectedPolygons) m.clearAllHighlights();
		selectedPolygons.clear();
		clearScopeHighlight();
		dragSnapshotTaken = false;
		scaleRotateSnapshotPending = true;
		// Restore geometry
		polygonManager.restoreFromSnapshot(snap, strokeColor);
		// Restore discrete points
		pointList.clear();
		pointPressures.clear();
		for (int i = 0; i < snap.points.length; i++) {
			Point2D.Double pt = snap.points[i];
			pointList.add(new Point2D.Double(pt.x, pt.y));
			float pr = (snap.pointPressures != null && i < snap.pointPressures.length)
				? snap.pointPressures[i] : 1.0f;
			pointPressures.add(pr);
		}
		// Restore ovals
		ovalList.clear();
		selectedOvals.clear();
		for (GeometrySnapshot.OvalSnap os : snap.ovals) {
			OvalManager om = new OvalManager(os.cx, os.cy, os.rx, os.ry);
			om.setLayerId(os.layerId);
			ovalList.add(om);
		}
	}
	/**
	 * setPolygonSet from loaded PolygonSet xml file (single-layer load).
	 * Loads polygons then immediately denormalises.
	 * @param root
	 */
	public void setPolygonSet(Element root) {
		appendPolygonSet(root);
		denormaliseAllPoints();
	}

	/**
	 * Load polygons from a polygonSet XML root element WITHOUT denormalising.
	 * Use this when loading multiple layers; call denormaliseAllPoints() once
	 * after all layers are loaded.
	 */
	public void appendPolygonSet(Element root) {
		double offset = (edgeOffset)/1000.0;

		Elements polys = root.getChildElements("polygon");

		for (int p=0;p<polys.size();p++) {

			System.out.println("BezierDrawPanel, appendPolygonSet, polygon number: " + p);

			Element poly = (Element) polys.get(p);
			String isClosedAttr = poly.getAttributeValue("isClosed");
			boolean isOpen = "false".equals(isClosedAttr);

			Elements curves = poly.getChildElements();
			int totCurves = curves.size();

			if (isOpen) {
				// Open curve: all <curve> elements are real curves, no closing synthetic curve.
				for (int c = 0; c < totCurves; c++) {
					Element curve = curves.get(c);
					Elements points = curve.getChildElements();

					Double A1x = Double.valueOf(points.get(0).getAttributeValue("x")) + offset;
					Double A1y = Double.valueOf(points.get(0).getAttributeValue("y")) + offset;
					Point2D.Double A1 = new Point2D.Double(A1x, A1y);

					Double C1x = Double.valueOf(points.get(1).getAttributeValue("x")) + offset;
					Double C1y = Double.valueOf(points.get(1).getAttributeValue("y")) + offset;
					Point2D.Double C1 = new Point2D.Double(C1x, C1y);

					Double C2x = Double.valueOf(points.get(2).getAttributeValue("x")) + offset;
					Double C2y = Double.valueOf(points.get(2).getAttributeValue("y")) + offset;
					Point2D.Double C2 = new Point2D.Double(C2x, C2y);

					Double A2x = Double.valueOf(points.get(3).getAttributeValue("x")) + offset;
					Double A2y = Double.valueOf(points.get(3).getAttributeValue("y")) + offset;
					Point2D.Double A2 = new Point2D.Double(A2x, A2y);

					if (c == 0) {
						setPoint(A1, C1, C2);
						setPoint(A2, C1, C2);
					} else {
						setPoint(A2, C1, C2);
					}
				}
				// Finalise as open curve (safe even if totCurves == 0)
				int polygonCount = polygonManager.getPolygonCount();
				CubicCurveManager curveManager = polygonManager.getManager(polygonCount);
				curveManager.finishOpen();
				curveManager.setCurrentBezierPosition(curveManager.getAverageXY());
				polygonManager.addManager();
				currentCurveManager = polygonManager.getManager(p);

			} else {
				// Closed polygon: last <curve> element is the synthetic closing curve.
				for (int c = 0; c < totCurves; c++) {
					Element curve = curves.get(c);
					Elements points = curve.getChildElements();

					Double A1x = Double.valueOf(points.get(0).getAttributeValue("x")) + offset;
					Double A1y = Double.valueOf(points.get(0).getAttributeValue("y")) + offset;
					Point2D.Double A1 = new Point2D.Double(A1x, A1y);

					Double C1x = Double.valueOf(points.get(1).getAttributeValue("x")) + offset;
					Double C1y = Double.valueOf(points.get(1).getAttributeValue("y")) + offset;
					Point2D.Double C1 = new Point2D.Double(C1x, C1y);

					Double C2x = Double.valueOf(points.get(2).getAttributeValue("x")) + offset;
					Double C2y = Double.valueOf(points.get(2).getAttributeValue("y")) + offset;
					Point2D.Double C2 = new Point2D.Double(C2x, C2y);

					Double A2x = Double.valueOf(points.get(3).getAttributeValue("x")) + offset;
					Double A2y = Double.valueOf(points.get(3).getAttributeValue("y")) + offset;
					Point2D.Double A2 = new Point2D.Double(A2x, A2y);

					int polygonCount = polygonManager.getPolygonCount();
					CubicCurveManager curveManager = polygonManager.getManager(polygonCount);
					if (c == 0) {
						setPoint(A1, C1, C2);
						setPoint(A2, C1, C2);
					} else if (c == totCurves-1) {
						curveManager.closeCurve(strokeColor, C1, C2);
						curveManager.setCurrentBezierPosition(curveManager.getAverageXY());
						polygonManager.addManager();
						currentCurveManager = polygonManager.getManager(p);
					} else {
						setPoint(A2, C1, C2);
					}
				}
			}
		}
	}

	/**
	 * Load open curves from an openCurveSet XML root element WITHOUT denormalising.
	 * Call denormaliseAllPoints() after this.
	 */
	public void appendOpenCurveSet(Element root) {
		double offset = (edgeOffset) / 1000.0;

		Elements openCurves = root.getChildElements("openCurve");

		for (int p = 0; p < openCurves.size(); p++) {
			Element openCurve = openCurves.get(p);
			Elements curves = openCurve.getChildElements("curve");
			int totCurves = curves.size();

			java.util.List<Float> anchorPrList = new java.util.ArrayList<>();

			for (int c = 0; c < totCurves; c++) {
				Element curve = curves.get(c);
				Elements points = curve.getChildElements("point");

				Double A1x = Double.valueOf(points.get(0).getAttributeValue("x")) + offset;
				Double A1y = Double.valueOf(points.get(0).getAttributeValue("y")) + offset;
				Point2D.Double A1 = new Point2D.Double(A1x, A1y);

				Double C1x = Double.valueOf(points.get(1).getAttributeValue("x")) + offset;
				Double C1y = Double.valueOf(points.get(1).getAttributeValue("y")) + offset;
				Point2D.Double C1 = new Point2D.Double(C1x, C1y);

				Double C2x = Double.valueOf(points.get(2).getAttributeValue("x")) + offset;
				Double C2y = Double.valueOf(points.get(2).getAttributeValue("y")) + offset;
				Point2D.Double C2 = new Point2D.Double(C2x, C2y);

				Double A2x = Double.valueOf(points.get(3).getAttributeValue("x")) + offset;
				Double A2y = Double.valueOf(points.get(3).getAttributeValue("y")) + offset;
				Point2D.Double A2 = new Point2D.Double(A2x, A2y);

				// Collect anchor pressures (anchor = index 0 and 3 of each curve)
				if (c == 0) {
					String p0pr = points.get(0).getAttributeValue("pressure");
					anchorPrList.add(p0pr != null ? Float.parseFloat(p0pr) : 1.0f);
				}
				String p3pr = points.get(3).getAttributeValue("pressure");
				anchorPrList.add(p3pr != null ? Float.parseFloat(p3pr) : 1.0f);

				if (c == 0) {
					setPoint(A1, C1, C2);
					setPoint(A2, C1, C2);
				} else {
					setPoint(A2, C1, C2);
				}
			}

			// Finalise as open curve
			int polygonCount = polygonManager.getPolygonCount();
			CubicCurveManager curveManager = polygonManager.getManager(polygonCount);
			curveManager.finishOpen();
			curveManager.setCurrentBezierPosition(curveManager.getAverageXY());
			// Restore anchor pressures
			if (!anchorPrList.isEmpty()) {
				float[] aps = new float[anchorPrList.size()];
				for (int i = 0; i < aps.length; i++) aps[i] = anchorPrList.get(i);
				curveManager.setAnchorPressures(aps);
			}
			polygonManager.addManager();
		}
	}

	/**
	 * Denormalise all currently-loaded polygon points into buffer pixel space.
	 * Call once after all layers have been loaded via appendPolygonSet().
	 */
	public void denormaliseAllPoints() {
		ArrayList<CubicPoint> allPoints = new ArrayList<CubicPoint>();
		CubicCurvePolygon[] polygons = polygonManager.getPolygons().getArrayofCubicCurvePolygons();
		for (int i = 0; i < polygons.length; i++) {
			CubicCurvePolygon poly = polygons[i];
			CubicCurve[] curves = poly.getArrayofCubicCurves();
			for (int c = 0; c < curves.length; c++) {
				CubicPoint[] points = curves[c].getPoints();
				for (int p = 0; p < points.length; p++) {
					if (!allPoints.contains(points[p])) {
						allPoints.add(points[p]);
					}
				}
			}
		}
		System.out.println("*****BezierDrawPanel, denormaliseAllPoints: " + allPoints.size() + " points");
		CubicPoint[] aP = new CubicPoint[allPoints.size()];
		allPoints.toArray(aP);
		polygonManager.deNormalisePoints(aP, GRIDWIDTH, GRIDHEIGHT);
	}
	// ── Point mode ───────────────────────────────────────────────────────────

	/** Toggle point-placement mode. */
	public void setPointMode(boolean b) { pointMode = b; if (!b) selectedDiscretePointIndex = -1; }
	public boolean isPointMode()         { return pointMode; }

	/** Retrieve a copy of the current discrete point list (for saving/undo). */
	public java.util.List<Point2D.Double> getPoints() {
		return new ArrayList<>(pointList);
	}

	/** Retrieve a copy of the per-point pressure list (parallel to getPoints()). */
	public java.util.List<Float> getPointPressures() {
		return new ArrayList<>(pointPressures);
	}

	/** Replace the discrete point list (used by undo). */
	public void setPoints(java.util.List<Point2D.Double> pts) {
		pointList.clear();
		pointList.addAll(pts);
	}

	/** Clear all discrete points. */
	public void clearPoints() {
		pointList.clear();
	}

	/** Add a point at the scaled mouse position, capturing current pressure. */
	public void addPointAtMouse(MouseEvent mE) {
		takeUndoSnapshot();
		Point2D.Double sp = scaleMouse(mE);
		pointList.add(new Point2D.Double(sp.x, sp.y));
		pointPressures.add(pressureSource.getPressure());
	}

	/** Return the index of the first discrete point within {@code radius} of {@code pos}, or -1. */
	private int findDiscretePointNear(Point2D.Double pos, double radius) {
		for (int i = 0; i < pointList.size(); i++) {
			Point2D.Double pt = pointList.get(i);
			double dx = pt.x - pos.x, dy = pt.y - pos.y;
			if (dx * dx + dy * dy <= radius * radius) return i;
		}
		return -1;
	}

	/**
	 * Load discrete points from a <pointSet> XML root element.
	 * Reads <point x y/> children, applies offset and denormalises to pixel coords.
	 */
	public void appendPointSet(Element root) {
		double offset = edgeOffset / 1000.0;
		Elements pts = root.getChildElements("point");
		for (int i = 0; i < pts.size(); i++) {
			Element ptEl = pts.get(i);
			double valX = Double.parseDouble(ptEl.getAttributeValue("x")) + offset;
			double valY = Double.parseDouble(ptEl.getAttributeValue("y")) + offset;
			double pixelX = valX * GRIDWIDTH  + GRIDWIDTH  / 2.0;
			double pixelY = valY * GRIDHEIGHT + GRIDHEIGHT / 2.0;
			pointList.add(new Point2D.Double(pixelX, pixelY));
			String prStr = ptEl.getAttributeValue("pressure");
			pointPressures.add(prStr != null ? Float.parseFloat(prStr) : 1.0f);
		}
	}

	// ── Oval mode ────────────────────────────────────────────────────────────

	/** Create a new oval centred on the canvas, 1/3 of the grid size; select it. */
	public void createOval() {
		takeUndoSnapshot();
		double cx = edgeOffset + GRIDWIDTH / 2.0;
		double cy = edgeOffset + GRIDHEIGHT / 2.0;
		double rx = GRIDWIDTH / 6.0;
		double ry = GRIDHEIGHT / 6.0;
		OvalManager oval = new OvalManager(cx, cy, rx, ry);
		oval.setLayerId(layerManager.getActiveLayerId());
		ovalList.add(oval);
		// Select the new oval; enable polygon selection mode
		for (CubicCurveManager m : selectedPolygons) m.clearAllHighlights();
		selectedPolygons.clear();
		for (OvalManager o : selectedOvals) o.setSelected(false);
		selectedOvals.clear();
		oval.setSelected(true);
		selectedOvals.add(oval);
		polygonSelectionModeEnabled = true;
	}

	/** Clear all ovals (called when loading a fresh file). */
	public void clearOvals() {
		ovalList.clear();
		selectedOvals.clear();
	}

	/** Return a snapshot copy of the oval list for saving. */
	public java.util.List<OvalManager> getOvals() {
		return new ArrayList<>(ovalList);
	}

	/** True if ovals are selected — used to grey out Edit Mode in the UI. */
	public boolean hasSelectedOvals() {
		return !selectedOvals.isEmpty();
	}

	/**
	 * Load ovals from an ovalSet XML root element (denormalises from -0.5..+0.5 to pixel space).
	 */
	public void appendOvalSet(Element root) {
		Elements ovals = root.getChildElements("oval");
		for (int i = 0; i < ovals.size(); i++) {
			Element el = ovals.get(i);
			double normCx = Double.parseDouble(el.getAttributeValue("cx"));
			double normCy = Double.parseDouble(el.getAttributeValue("cy"));
			double normRx = Double.parseDouble(el.getAttributeValue("rx"));
			double normRy = Double.parseDouble(el.getAttributeValue("ry"));
			// Inverse of toNorm: px = (normCoord + 0.5) * GRIDWIDTH + edgeOffset
			double cx = (normCx + 0.5) * GRIDWIDTH + edgeOffset;
			double cy = (normCy + 0.5) * GRIDHEIGHT + edgeOffset;
			double rx = normRx * GRIDWIDTH;
			double ry = normRy * GRIDHEIGHT;
			OvalManager oval = new OvalManager(cx, cy, rx, ry);
			oval.setLayerId(layerManager.getActiveLayerId());
			ovalList.add(oval);
		}
	}

	/**
	 * setPoint: called from mousePressed
	 * & adds curves
	 * @param curveManager
	 * @param currPolygon
	 * @param pos
	 */
	public void setPoint(Point2D.Double pos) {
		
		int polygonCount = polygonManager.getPolygonCount();
			
		System.out.println("BezierDrawPanel, setPoint, polygon Count: " + polygonCount + "  currPolygon index: " + polygonManager.getPolygonCount() + "   curveManager index: " + polygonCount);

		CubicCurvePolygon currPolygon = polygonManager.getCurrentPolygon();

		CubicCurveManager curveManager = polygonManager.getManager(polygonCount);

		//int[] intersect = curveManager.checkForIntersect(pos);
		//if (intersect[0]==-1 && intersect[1]==-1) {

			int pointCount = curveManager.getPointCount();
			int curveCount = curveManager.getCurveCount();
			//System.out.println("!!!!BezierDrawPanel, setPoint, curveCount: " + curveCount + "  point count: " + pointCount);

			CubicCurve currentCurve = curveManager.getCurrentCurve();

			if (curveManager.getCurveCount()==0) {//first curve to be created

				if (pointCount==0) {

					//System.out.println("BezierDrawPanel, setPoint, first anchor point in first curve: "+ pointCount + "   pos: " + pos.x + "  " + pos.y);

					currentCurve.setAnchorPoint(pos, pointCount, null);
					curveManager.setPointCount(++pointCount);

				} else {
					//System.out.println("BezierDrawPanel, setPoint, final anchor point in first curve: "+ pointCount + "   pos: " + pos.x + "  " + pos.y);
					currentCurve.setAnchorPoint(pos, pointCount, null);
					currentCurve.setControlPoints();
					currPolygon.addCurve(currentCurve);
					curveManager.setPointCount(0);
					curveManager.setCurveCount(++curveCount);
					//System.out.println("####BezierDrawPanel, setPoint, curveCount: " + curveCount);
					curveManager.setCurrentCurve(new CubicCurve(this.getStrokeColor()));

				}

			} else { //all later curves
				//System.out.println("!!!!BezierDrawPanel, setPoint, subsequent curves, curveCount: " + curveCount + "  point count: " + pointCount);

				if (pointCount==0) {

					//System.out.println("BezierDrawPanel, setPoint, additional point in subsequent curve: "+ pointCount + "   pos: " + pos.x + "  " + pos.y);

					CubicPoint lastAnchor = currPolygon.getCurve(curveCount-1).getPoint(3);
					Point2D.Double lastAnchorPoint = lastAnchor.getPos();

					//currentCurve.setAnchorPoint(new Point2D.Double(lastAnchorPoint.x, lastAnchorPoint.y), CubicCurve.ANCHOR_FIRST, lastAnchor);//Older
					currentCurve.setAnchorPoint(lastAnchorPoint, CubicCurve.ANCHOR_FIRST, lastAnchor);//newer

					//currentCurve.setAnchorPoint(mousePos, CubicCurve.ANCHOR_LAST, null);
					currentCurve.setAnchorPoint(pos, CubicCurve.ANCHOR_LAST, null);
					currentCurve.setControlPoints();
					currPolygon.addCurve(currentCurve);
					curveManager.setPointCount(0);
					curveManager.setCurveCount(++curveCount);
					curveManager.setCurrentCurve(new CubicCurve(this.getStrokeColor()));
					
				}
			//}
		}
		System.out.println("");

	}
	/**
	 * setPoint: called when loading an existing polygon set xml file (setPolygonSet() just above)
	 * needs to send control point positions
	 * & adds curves
	 * @param curveManager
	 * @param currPolygon
	 * @param pos
	 */
	public void setPoint(Point2D.Double pos, Point2D.Double c1, Point2D.Double c2) {
		
		int polygonCount = polygonManager.getPolygonCount();
			
		System.out.println("BezierDrawPanel, setPoint, polygon Count: " + polygonCount + "  currPolygon index: " + polygonManager.getPolygonCount() + "   curveManager index: " + polygonCount);

		CubicCurvePolygon currPolygon = polygonManager.getCurrentPolygon();

		CubicCurveManager curveManager = polygonManager.getManager(polygonCount);

		//int[] intersect = curveManager.checkForIntersect(pos);
		//if (intersect[0]==-1 && intersect[1]==-1) {

			int pointCount = curveManager.getPointCount();
			int curveCount = curveManager.getCurveCount();
			//System.out.println("!!!!BezierDrawPanel, setPoint, curveCount: " + curveCount + "  point count: " + pointCount);

			CubicCurve currentCurve = curveManager.getCurrentCurve();

			if (curveManager.getCurveCount()==0) {//first curve to be created

				if (pointCount==0) {

					//System.out.println("BezierDrawPanel, setPoint, first anchor point in first curve: "+ pointCount + "   pos: " + pos.x + "  " + pos.y);

					currentCurve.setAnchorPoint(pos, pointCount, null);
					curveManager.setPointCount(++pointCount);

				} else {
					//System.out.println("BezierDrawPanel, setPoint, final anchor point in first curve: "+ pointCount + "   pos: " + pos.x + "  " + pos.y);
					currentCurve.setAnchorPoint(pos, pointCount, null);
					currentCurve.setControlPoints(c1, c2);
					currPolygon.addCurve(currentCurve);
					curveManager.setPointCount(0);
					curveManager.setCurveCount(++curveCount);
					//System.out.println("####BezierDrawPanel, setPoint, curveCount: " + curveCount);
					curveManager.setCurrentCurve(new CubicCurve(this.getStrokeColor()));

				}

			} else { //all later curves
				//System.out.println("!!!!BezierDrawPanel, setPoint, subsequent curves, curveCount: " + curveCount + "  point count: " + pointCount);

				if (pointCount==0) {

					//System.out.println("BezierDrawPanel, setPoint, additional point in subsequent curve: "+ pointCount + "   pos: " + pos.x + "  " + pos.y);

					CubicPoint lastAnchor = currPolygon.getCurve(curveCount-1).getPoint(3);
					Point2D.Double lastAnchorPoint = lastAnchor.getPos();

					//currentCurve.setAnchorPoint(new Point2D.Double(lastAnchorPoint.x, lastAnchorPoint.y), CubicCurve.ANCHOR_FIRST, lastAnchor);//Older
					currentCurve.setAnchorPoint(lastAnchorPoint, CubicCurve.ANCHOR_FIRST, lastAnchor);//newer

					//currentCurve.setAnchorPoint(mousePos, CubicCurve.ANCHOR_LAST, null);
					currentCurve.setAnchorPoint(pos, CubicCurve.ANCHOR_LAST, null);
					currentCurve.setControlPoints(c1, c2);
					currPolygon.addCurve(currentCurve);
					curveManager.setPointCount(0);
					curveManager.setCurveCount(++curveCount);
					curveManager.setCurrentCurve(new CubicCurve(this.getStrokeColor()));
					
				}
			//}
		}
		System.out.println("");

	}
	// ─────────────────────────────────────────────────────────────────────────
	// EDGE SELECTION MODE
	// ─────────────────────────────────────────────────────────────────────────

	public void setEdgeSelectionMode(boolean enabled) {
		edgeSelectionModeEnabled = enabled;
		if (!enabled) {
			extrudeOnDrag = false;
			extruding = false;
			extrudeLiveEdges.clear();
			selectedEdges.clear();
			updateEdgeHighlights();
			clearScopeHighlight();
		}
	}

	/** Re-compute which curves in each manager should show blue/orange/purple highlights. */
	private void updateEdgeHighlights() {
		int count = polygonManager.getPolygonCount();
		for (int i = 0; i < count; i++) {
			polygonManager.getManager(i).setDiscreteEdgeIndices(Collections.emptySet());
			polygonManager.getManager(i).setRelationalEdgeIndices(Collections.emptySet());
			polygonManager.getManager(i).setWeldableEdgeIndices(Collections.emptySet());
		}
		if (selectedEdges.isEmpty()) return;

		boolean weldable = areEdgesWeldable();

		Map<CubicCurveManager, Set<Integer>> byMgr = new LinkedHashMap<>();
		for (SelectedEdge e : selectedEdges) {
			byMgr.computeIfAbsent(e.manager, k -> new HashSet<>()).add(e.curveIndex);
		}
		for (Map.Entry<CubicCurveManager, Set<Integer>> en : byMgr.entrySet()) {
			if (weldable)
				en.getKey().setWeldableEdgeIndices(en.getValue());
			else if (edgeSubMode == SelectionSubMode.RELATIONAL)
				en.getKey().setRelationalEdgeIndices(en.getValue());
			else
				en.getKey().setDiscreteEdgeIndices(en.getValue());
		}
	}

	/**
	 * Handle a click in edge selection mode: find the nearest edge, toggle its
	 * selection; clicking empty space deselects all.
	 */
	private void handleEdgeSelectionClick(Point2D.Double mousePos) {
		SelectedEdge hit = findNearestEdge(mousePos);
		if (hit == null) {
			selectedEdges.clear();
			updateEdgeHighlights();
			return;
		}
		// Toggle: if already selected, deselect it; otherwise add it
		for (int i = 0; i < selectedEdges.size(); i++) {
			SelectedEdge e = selectedEdges.get(i);
			if (e.manager == hit.manager && e.curveIndex == hit.curveIndex) {
				selectedEdges.remove(i);
				updateEdgeHighlights();
				return;
			}
		}
		selectedEdges.add(hit);
		updateEdgeHighlights();
	}

	/**
	 * Find the nearest bezier curve to mousePos across all closed polygons.
	 * Returns null if nothing is within the 15px threshold.
	 */
	private SelectedEdge findNearestEdge(Point2D.Double mousePos) {
		final double THRESHOLD = 15.0;
		double bestDist = THRESHOLD;
		SelectedEdge best = null;
		int polygonCount = polygonManager.getPolygonCount();
		for (int i = 0; i < polygonCount; i++) {
			CubicCurveManager m = polygonManager.getManager(i);
			if (m.getLayerId() != layerManager.getActiveLayerId()) continue;
			CubicCurve[] cArray = m.getCurves().getArrayofCubicCurves();
			for (int c = 0; c < cArray.length; c++) {
				CubicPoint[] p = cArray[c].getPoints();
				if (p[0] == null || p[1] == null || p[2] == null || p[3] == null) continue;
				double dist = distanceToEdge(mousePos, p);
				if (dist < bestDist) {
					bestDist = dist;
					best = new SelectedEdge(m, c);
				}
			}
		}
		return best;
	}

	/** Overload: delegate to CubicPoint[] variant. */
	private double distanceToEdge(Point2D.Double mousePos, CubicCurve curve) {
		return distanceToEdge(mousePos, curve.getPoints());
	}

	/** Sample the cubic bezier at 30 points and return the minimum distance to mousePos. */
	private double distanceToEdge(Point2D.Double mousePos, CubicPoint[] p) {
		final int SAMPLES = 30;
		double minDist = Double.MAX_VALUE;
		double x0 = p[0].getPos().x, y0 = p[0].getPos().y;
		double x1 = p[1].getPos().x, y1 = p[1].getPos().y;
		double x2 = p[2].getPos().x, y2 = p[2].getPos().y;
		double x3 = p[3].getPos().x, y3 = p[3].getPos().y;
		for (int i = 0; i <= SAMPLES; i++) {
			double t = (double) i / SAMPLES;
			double u = 1.0 - t;
			double bx = u*u*u*x0 + 3*u*u*t*x1 + 3*u*t*t*x2 + t*t*t*x3;
			double by = u*u*u*y0 + 3*u*u*t*y1 + 3*u*t*t*y2 + t*t*t*y3;
			double dx = mousePos.x - bx, dy = mousePos.y - by;
			double d = Math.sqrt(dx*dx + dy*dy);
			if (d < minDist) minDist = d;
		}
		return minDist;
	}

	/**
	 * Returns true when exactly 2 edges are selected, they belong to different
	 * polygons, their midpoints are within 80px, and their directions are within
	 * roughly 45° of parallel (dot product > 0.7).
	 */
	private boolean areEdgesWeldable() {
		if (selectedEdges.size() != 2) return false;
		SelectedEdge e0 = selectedEdges.get(0);
		SelectedEdge e1 = selectedEdges.get(1);
		if (e0.manager == e1.manager) return false;
		CubicPoint[] p0 = e0.manager.getCurves().getCurve(e0.curveIndex).getPoints();
		CubicPoint[] p1 = e1.manager.getCurves().getCurve(e1.curveIndex).getPoints();
		if (p0[0] == null || p0[3] == null || p1[0] == null || p1[3] == null) return false;
		// Midpoint proximity
		double mx0 = (p0[0].getPos().x + p0[3].getPos().x) / 2;
		double my0 = (p0[0].getPos().y + p0[3].getPos().y) / 2;
		double mx1 = (p1[0].getPos().x + p1[3].getPos().x) / 2;
		double my1 = (p1[0].getPos().y + p1[3].getPos().y) / 2;
		double midDist = Math.sqrt((mx1-mx0)*(mx1-mx0) + (my1-my0)*(my1-my0));
		if (midDist > 80) return false;
		// Direction parallelism
		double dx0 = p0[3].getPos().x - p0[0].getPos().x;
		double dy0 = p0[3].getPos().y - p0[0].getPos().y;
		double dx1 = p1[3].getPos().x - p1[0].getPos().x;
		double dy1 = p1[3].getPos().y - p1[0].getPos().y;
		double len0 = Math.sqrt(dx0*dx0 + dy0*dy0);
		double len1 = Math.sqrt(dx1*dx1 + dy1*dy1);
		if (len0 < 1e-6 || len1 < 1e-6) return false;
		double dot = (dx0*dx1 + dy0*dy1) / (len0 * len1);
		if (Math.abs(dot) <= 0.7) return false;
		// Endpoint-pair proximity: the better of same/reversed alignment must be close enough.
		double distSame    = Formulas.hypotenuse(p0[0].getPos(), p1[0].getPos())
		                   + Formulas.hypotenuse(p0[3].getPos(), p1[3].getPos());
		double distReverse = Formulas.hypotenuse(p0[0].getPos(), p1[3].getPos())
		                   + Formulas.hypotenuse(p0[3].getPos(), p1[0].getPos());
		return Math.min(distSame, distReverse) <= 140;
	}

	/**
	 * Weld the two selected edges together: auto-detect direction alignment
	 * then move each matching pair of anchor points to their midpoint.
	 */
	public void weldSelectedEdges() {
		if (!areEdgesWeldable()) return;
		SelectedEdge e0 = selectedEdges.get(0);
		SelectedEdge e1 = selectedEdges.get(1);
		CubicPoint[] p0 = e0.manager.getCurves().getCurve(e0.curveIndex).getPoints();
		CubicPoint[] p1 = e1.manager.getCurves().getCurve(e1.curveIndex).getPoints();
		// Auto-detect direction: which pairing of anchor pairs minimises total distance?
		// When distances are nearly equal (symmetric / coincident edges), use the dot
		// product sign: anti-parallel edges (dot<0) should use the reversed pairing.
		double dx0 = p0[3].getPos().x - p0[0].getPos().x, dy0 = p0[3].getPos().y - p0[0].getPos().y;
		double dx1 = p1[3].getPos().x - p1[0].getPos().x, dy1 = p1[3].getPos().y - p1[0].getPos().y;
		double dot = dx0*dx1 + dy0*dy1;
		double distSame    = Formulas.hypotenuse(p0[0].getPos(), p1[0].getPos())
		                   + Formulas.hypotenuse(p0[3].getPos(), p1[3].getPos());
		double distReverse = Formulas.hypotenuse(p0[0].getPos(), p1[3].getPos())
		                   + Formulas.hypotenuse(p0[3].getPos(), p1[0].getPos());
		boolean reversed = (Math.abs(distSame - distReverse) < 1.0) ? (dot < 0) : (distReverse < distSame);
		CubicPoint pa0 = p0[0], pa3 = p0[3];
		CubicPoint pb0 = reversed ? p1[3] : p1[0];
		CubicPoint pb3 = reversed ? p1[0] : p1[3];
		// Control points adjacent to each anchor:
		//   p0: p[1] is near pa0, p[2] is near pa3
		//   p1: if non-reversed p[1] near pb0 & p[2] near pb3; if reversed they swap
		CubicPoint pc0_near = p0[1];
		CubicPoint pc0_far  = p0[2];
		CubicPoint pc1_near = reversed ? p1[2] : p1[1];
		CubicPoint pc1_far  = reversed ? p1[1] : p1[2];
		// Move each anchor pair to their midpoint
		Point2D.Double mid0 = new Point2D.Double(
			(pa0.getPos().x + pb0.getPos().x) / 2,
			(pa0.getPos().y + pb0.getPos().y) / 2);
		Point2D.Double mid3 = new Point2D.Double(
			(pa3.getPos().x + pb3.getPos().x) / 2,
			(pa3.getPos().y + pb3.getPos().y) / 2);
		pa0.setPos(mid0); pa0.setOrigPosToPos();
		pa3.setPos(mid3); pa3.setOrigPosToPos();
		pb0.setPos(mid0); pb0.setOrigPosToPos();
		pb3.setPos(mid3); pb3.setOrigPosToPos();
		// Move each control point pair to their midpoint
		Point2D.Double ctrlMid0 = new Point2D.Double(
			(pc0_near.getPos().x + pc1_near.getPos().x) / 2,
			(pc0_near.getPos().y + pc1_near.getPos().y) / 2);
		Point2D.Double ctrlMid3 = new Point2D.Double(
			(pc0_far.getPos().x + pc1_far.getPos().x) / 2,
			(pc0_far.getPos().y + pc1_far.getPos().y) / 2);
		pc0_near.setPos(ctrlMid0); pc0_near.setOrigPosToPos();
		pc0_far.setPos(ctrlMid3);  pc0_far.setOrigPosToPos();
		pc1_near.setPos(ctrlMid0); pc1_near.setOrigPosToPos();
		pc1_far.setPos(ctrlMid3);  pc1_far.setOrigPosToPos();
		WeldRegistry wr = polygonManager.getWeldRegistry();
		wr.registerWeld(pa0, pb0); wr.registerWeld(pa3, pb3);
		wr.registerWeld(pc0_near, pc1_near); wr.registerWeld(pc0_far, pc1_far);
		selectedEdges.clear();
		updateEdgeHighlights();
	}

	/**
	 * Delete all currently selected edges (remove their curves from their polygons).
	 * Indices are processed in descending order per polygon to avoid index shifting.
	 */
	public void deleteSelectedEdges() {
		if (selectedEdges.isEmpty()) return;
		java.util.Map<CubicCurveManager, ArrayList<Integer>> byManager =
			new java.util.LinkedHashMap<CubicCurveManager, ArrayList<Integer>>();
		for (SelectedEdge e : selectedEdges) {
			ArrayList<Integer> list = byManager.get(e.manager);
			if (list == null) { list = new ArrayList<Integer>(); byManager.put(e.manager, list); }
			list.add(e.curveIndex);
		}
		for (java.util.Map.Entry<CubicCurveManager, ArrayList<Integer>> entry : byManager.entrySet()) {
			ArrayList<Integer> indices = entry.getValue();
			indices.sort((a, b) -> b - a); // descending — prevents index shifting
			CubicCurvePolygon poly = entry.getKey().getCurves();
			for (int idx : indices) {
				poly.removeCurve(idx);
			}
		}
		selectedEdges.clear();
		updateEdgeHighlights();
	}

	/**
	 * Duplicate each selected edge as a new standalone single-edge polygon,
	 * offset by 20px. The duplicates become the new selection.
	 */
	public void duplicateSelectedEdge() {
		if (selectedEdges.isEmpty()) return;
		final double OFFSET = 20.0;
		ArrayList<SelectedEdge> duplicates = new ArrayList<SelectedEdge>();
		for (SelectedEdge e : selectedEdges) {
			CubicPoint[] src = e.manager.getCurves().getCurve(e.curveIndex).getPoints();
			Point2D.Double[] pts = new Point2D.Double[]{
				new Point2D.Double(src[0].getPos().x + OFFSET, src[0].getPos().y + OFFSET),
				new Point2D.Double(src[1].getPos().x + OFFSET, src[1].getPos().y + OFFSET),
				new Point2D.Double(src[2].getPos().x + OFFSET, src[2].getPos().y + OFFSET),
				new Point2D.Double(src[3].getPos().x + OFFSET, src[3].getPos().y + OFFSET)
			};
			CubicCurveManager newManager = polygonManager.addSingleEdge(pts, strokeColor);
			duplicates.add(new SelectedEdge(newManager, 0));
		}
		selectedEdges.clear();
		selectedEdges.addAll(duplicates);
		updateEdgeHighlights();
	}

	/**
	 * Translate all selected edges by (dx, dy), propagating to the adjacent
	 * control points of neighbouring curves to maintain tangent continuity.
	 */
	private void translateEdgesBy(double dx, double dy) {
		boolean relational = (edgeSubMode == SelectionSubMode.RELATIONAL);
		WeldRegistry wr = relational ? polygonManager.getWeldRegistry() : null;
		HashSet<CubicPoint> moved = new HashSet<>();
		for (SelectedEdge e : selectedEdges) {
			CubicCurve[] cArray = e.manager.getCurves().getArrayofCubicCurves();
			CubicPoint[] pts = cArray[e.curveIndex].getPoints();
			// Move all 4 points of the selected edge (+ weld partners in RELATIONAL mode)
			for (int i = 0; i < pts.length; i++) {
				if (!moved.add(pts[i])) continue;
				Point2D.Double pos = pts[i].getPos();
				pts[i].setPos(new Point2D.Double(pos.x + dx, pos.y + dy));
				pts[i].setOrigPosToPos();
				if (relational) {
					for (CubicPoint linked : wr.getLinked(pts[i])) {
						if (!moved.add(linked)) continue;
						Point2D.Double lpos = linked.getPos();
						linked.setPos(new Point2D.Double(lpos.x + dx, lpos.y + dy));
						linked.setOrigPosToPos();
					}
				}
			}
			// Propagate to adjacent control points in neighbouring curves
			int numCurves = cArray.length;
			if (numCurves > 1) {
				int prevIdx = (e.curveIndex == 0) ? numCurves - 1 : e.curveIndex - 1;
				int nextIdx = (e.curveIndex == numCurves - 1) ? 0 : e.curveIndex + 1;
				CubicPoint prevCtrl2 = cArray[prevIdx].getPoints()[2];
				if (prevCtrl2 != null && moved.add(prevCtrl2)) {
					Point2D.Double pos = prevCtrl2.getPos();
					prevCtrl2.setPos(new Point2D.Double(pos.x + dx, pos.y + dy));
					prevCtrl2.setOrigPosToPos();
				}
				CubicPoint nextCtrl1 = cArray[nextIdx].getPoints()[1];
				if (nextCtrl1 != null && moved.add(nextCtrl1)) {
					Point2D.Double pos = nextCtrl1.getPos();
					nextCtrl1.setPos(new Point2D.Double(pos.x + dx, pos.y + dy));
					nextCtrl1.setOrigPosToPos();
				}
			}
		}
	}

	/** Scale selected edges around their combined anchor centroid (from origPos). */
	private void scaleSelectedEdges(double scale) {
		double factor = 1.0 + scale / 100.0;
		double cx = 0, cy = 0;
		int count = 0;
		for (SelectedEdge e : selectedEdges) {
			CubicPoint[] p = e.manager.getCurves().getCurve(e.curveIndex).getPoints();
			cx += p[0].getOrigPos().x; cy += p[0].getOrigPos().y;
			cx += p[3].getOrigPos().x; cy += p[3].getOrigPos().y;
			count += 2;
		}
		if (count == 0) return;
		cx /= count; cy /= count;
		boolean relational = (edgeSubMode == SelectionSubMode.RELATIONAL);
		WeldRegistry wr = relational ? polygonManager.getWeldRegistry() : null;
		HashSet<CubicPoint> processed = new HashSet<>();
		for (SelectedEdge e : selectedEdges) {
			CubicPoint[] pts = e.manager.getCurves().getCurve(e.curveIndex).getPoints();
			for (CubicPoint pt : pts) {
				if (!processed.add(pt)) continue;
				double ox = pt.getOrigPos().x - cx;
				double oy = pt.getOrigPos().y - cy;
				pt.setPos(new Point2D.Double(ox * factor + cx, oy * factor + cy));
				if (relational) {
					for (CubicPoint linked : wr.getLinked(pt)) {
						if (!processed.add(linked)) continue;
						double lox = linked.getOrigPos().x - cx;
						double loy = linked.getOrigPos().y - cy;
						linked.setPos(new Point2D.Double(lox * factor + cx, loy * factor + cy));
					}
				}
			}
		}
	}

	/** Rotate selected edges around a pivot determined by the rotation axis mode. */
	private void rotateSelectedEdges(double rot) {
		int axisMode = cubicCurvePanel.getRotationAxisMode();
		Point2D.Double center;
		if (axisMode == CubicCurvePanel.ROTATE_ABSOLUTE) {
			center = new Point2D.Double(edgeOffset + GRIDWIDTH / 2.0, edgeOffset + GRIDHEIGHT / 2.0);
		} else {
			// COMMON and LOCAL both use the mean anchor centroid of selected edges
			double cx = 0, cy = 0;
			int count = 0;
			for (SelectedEdge e : selectedEdges) {
				CubicPoint[] p = e.manager.getCurves().getCurve(e.curveIndex).getPoints();
				cx += p[0].getOrigPos().x; cy += p[0].getOrigPos().y;
				cx += p[3].getOrigPos().x; cy += p[3].getOrigPos().y;
				count += 2;
			}
			if (count == 0) return;
			center = new Point2D.Double(cx / count, cy / count);
		}
		boolean relational = (edgeSubMode == SelectionSubMode.RELATIONAL);
		WeldRegistry wr = relational ? polygonManager.getWeldRegistry() : null;
		HashSet<CubicPoint> processed = new HashSet<>();
		for (SelectedEdge e : selectedEdges) {
			CubicPoint[] pts = e.manager.getCurves().getCurve(e.curveIndex).getPoints();
			for (CubicPoint pt : pts) {
				if (!processed.add(pt)) continue;
				Point2D.Double relative = new Point2D.Double(
					pt.getOrigPos().x - center.x,
					pt.getOrigPos().y - center.y);
				Point2D.Double rotated = Transform.rotate(relative, rot);
				pt.setPos(new Point2D.Double(rotated.x + center.x, rotated.y + center.y));
				if (relational) {
					for (CubicPoint linked : wr.getLinked(pt)) {
						if (!processed.add(linked)) continue;
						Point2D.Double lrel = new Point2D.Double(
							linked.getOrigPos().x - center.x,
							linked.getOrigPos().y - center.y);
						Point2D.Double lrot = Transform.rotate(lrel, rot);
						linked.setPos(new Point2D.Double(lrot.x + center.x, lrot.y + center.y));
					}
				}
			}
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// CONTEXT-AWARE TOOLBAR ACTIONS (weld / duplicate / delete)
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Build an annular quad mesh between two selected concentric polygons.
	 * keepInner true = Shift mode: retain the inner polygon after the operation.
	 */
	public void performIntersect(boolean keepInner) {
		if (selectedPolygons.size() != 2) return;
		CubicCurveManager a = selectedPolygons.get(0);
		CubicCurveManager b = selectedPolygons.get(1);
		// Validate before taking snapshot so a no-op leaves undo history clean
		if (!BezierIntersectTool.canPerform(polygonManager, a, b)) return;
		takeUndoSnapshot();
		BezierIntersectTool.performIntersect(polygonManager, a, b, strokeColor, keepInner, selectedPolygons);
		// Apply relational highlight to newly selected quads
		boolean relational = (polySubMode == SelectionSubMode.RELATIONAL);
		for (CubicCurveManager m : selectedPolygons) m.setSelectedRelational(relational);
	}

	public void setAutoWeldEnabled(boolean b) { autoWeldEnabled = b; }
	public boolean hasSelectedEdges() { return !selectedEdges.isEmpty(); }

	/** Weld in edge mode (if weldable), otherwise weld selected points. */
	public void performWeld() {
		takeUndoSnapshot();
		if (edgeSelectionModeEnabled && !selectedEdges.isEmpty()) {
			weldSelectedEdges();
		} else {
			weldSelectedPoints();
			emptySelectedPoints();
		}
	}

	/** Duplicate in edge mode → duplicate selected edge; otherwise duplicate selected polygons. */
	public void performDuplicate() {
		takeUndoSnapshot();
		if (edgeSelectionModeEnabled && !selectedEdges.isEmpty()) {
			duplicateSelectedEdge();
		} else if (!selectedPolygons.isEmpty()) {
			duplicateSelectedPolygons();
		}
	}

	/** Delete selected geometry: edges, polygons/ovals, or a selected free-standing point. */
	public void performDelete() {
		takeUndoSnapshot();
		if (edgeSelectionModeEnabled && !selectedEdges.isEmpty()) {
			deleteSelectedEdges();
		} else {
			if (!selectedPolygons.isEmpty()) deleteSelectedPolygons();
			if (!selectedOvals.isEmpty()) {
				ovalList.removeAll(selectedOvals);
				selectedOvals.clear();
			}
			if (selectedDiscretePointIndex >= 0 && selectedDiscretePointIndex < pointList.size()) {
				pointList.remove(selectedDiscretePointIndex);
				selectedDiscretePointIndex = -1;
			}
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// SELECTION SUB-MODE CONTROL & KEYBOARD
	// ─────────────────────────────────────────────────────────────────────────

	public void setPointSubMode(SelectionSubMode m) { pointSubMode = m; }
	public void setEdgeSubMode(SelectionSubMode m)  { edgeSubMode  = m; }
	public void setPolySubMode(SelectionSubMode m)  { polySubMode  = m; }

	public SelectionSubMode getPointSubMode() { return pointSubMode; }
	public SelectionSubMode getEdgeSubMode()  { return edgeSubMode; }
	public SelectionSubMode getPolySubMode()  { return polySubMode; }
	public boolean isPointSelectionModeEnabled()   { return pointSelectionModeEnabled; }
	public boolean isEdgeSelectionModeEnabled()    { return edgeSelectionModeEnabled; }
	public boolean isPolygonSelectionModeEnabled() { return polygonSelectionModeEnabled; }

	public void setPointSelectionMode(boolean enabled) {
		pointSelectionModeEnabled = enabled;
		if (!enabled) { selectedPoints.clear(); selectedDiscretePointIndex = -1; clearScopeHighlight(); updatePointHighlights(); }
	}

	/**
	 * If there is an in-progress polygon being drawn (polygon draw mode has
	 * accumulated at least one curve segment), commit it as an open curve.
	 * Called by the toolbar whenever the user switches away from polygon draw mode
	 * so they don't have to click "Finish Open Curve" explicitly.
	 */
	public void autoFinishOpenCurveIfNeeded() {
		int polygonCount = polygonManager.getPolygonCount();
		CubicCurveManager m = polygonManager.getManager(polygonCount);
		if (m.getCurveCount() > 0) {
			m.finishOpen();
			m.setCurrentBezierPosition(m.getAverageXY());
			polygonManager.addManager();
		}
	}

	public void setFreehandMode(boolean b) {
		freehandMode = b;
		if (!b) { freehandActive = false; freehandRaw.clear(); }
	}
	public boolean isFreehandMode() { return freehandMode; }
	public void setFreehandErrorThreshold(double t) { freehandErrorThreshold = t; }

	public void setKnifeMode(boolean enabled) {
		if (enabled) {
			prevModeBeforeKnife = pointSelectionModeEnabled   ? PrevMode.POINT   :
			                      edgeSelectionModeEnabled    ? PrevMode.EDGE    :
			                      polygonSelectionModeEnabled ? PrevMode.POLYGON : PrevMode.NONE;
			preKnifeSelection = new java.util.HashSet<>(selectedPolygons);
			setPolygonSelectionMode(false);
			setOpenCurveSelectionMode(false);
			setEdgeSelectionMode(false);
			setPointSelectionMode(false);
			knifeMode = true;
			knifeStart = null; knifeEnd = null;
		} else {
			knifeMode = false;
			knifeStart = null; knifeEnd = null;
		}
	}

	public PrevMode getPrevModeBeforeKnife() { return prevModeBeforeKnife; }

	public void keyPressed(KeyEvent e) {
		int code = e.getKeyCode();
		int mods = e.getModifiersEx();
		if (mods == 0) {
			if (code == KeyEvent.VK_SPACE) { deselectAll();              return; }
			if (code == KeyEvent.VK_LEFT)  { navigateSelectionBack();    return; }
			if (code == KeyEvent.VK_RIGHT) { navigateSelectionForward(); return; }
		}
	}
	public void keyReleased(KeyEvent e) {}
	public void keyTyped(KeyEvent e) {
		// Plain (unmodified) letter shortcuts activate toolbar modes
		if (e.getModifiersEx() == 0 && modeKeyListener != null) {
			char c = e.getKeyChar();
			if (c == 'a' || c == 's' || c == 'd' || c == 'f' ||
				c == 'h' || c == 'j' || c == 'k' || c == 'l') {
				modeKeyListener.onModeKey(c);
			}
		}
	}

	private void toggleActiveSubMode() {
		if (pointSelectionModeEnabled) {
			pointSubMode = (pointSubMode == SelectionSubMode.RELATIONAL)
				? SelectionSubMode.DISCRETE : SelectionSubMode.RELATIONAL;
			updatePointHighlights();
		} else if (edgeSelectionModeEnabled) {
			edgeSubMode = (edgeSubMode == SelectionSubMode.RELATIONAL)
				? SelectionSubMode.DISCRETE : SelectionSubMode.RELATIONAL;
			updateEdgeHighlights();
		} else if (polygonSelectionModeEnabled) {
			polySubMode = (polySubMode == SelectionSubMode.RELATIONAL)
				? SelectionSubMode.DISCRETE : SelectionSubMode.RELATIONAL;
			updatePolygonHighlights();
		}
		if (subModeChangeListener != null) subModeChangeListener.onSubModeChanged();
	}

	// ─────────────────────────────────────────────────────────────────────────
	// SCOPE HELPERS
	// ─────────────────────────────────────────────────────────────────────────

	private void clearScopeHighlight() {
		if (scopedManager != null) { scopedManager.setScoped(false); scopedManager = null; }
	}

	private void clearPendingWeld() {
		// Clear purple highlight from every manager referenced in pending pairs
		Set<CubicCurveManager> seen = new HashSet<>();
		for (SelectedEdge[] pair : pendingWeldPairs) {
			for (SelectedEdge e : pair)
				if (seen.add(e.manager)) e.manager.setWeldableEdgeIndices(Collections.emptySet());
		}
		pendingWeldPairs.clear();
	}

	// ─────────────────────────────────────────────────────────────────────────
	// POINT SCOPE / SELECT
	// ─────────────────────────────────────────────────────────────────────────

	private void handlePointScopeOrSelect(Point2D.Double mousePos, boolean cmdDown) {
		int count = polygonManager.getPolygonCount();
		// Priority 1: direct point hit in the already-scoped manager
		if (scopedManager != null) {
			int[] hit = scopedManager.checkForIntersect(mousePos);
			if (hit[0] != -1) {
				CubicPoint clicked = scopedManager.getCurves().getCurve(hit[0]).getPoint(hit[1]);
				togglePointSelection(clicked, cmdDown);
				updatePointHighlights();
				return;
			}
		}
		// Priority 2: direct point hit in ANY manager on the active layer (auto-scope to that polygon)
		for (int i = 0; i < count; i++) {
			CubicCurveManager m = polygonManager.getManager(i);
			if (m.getLayerId() != layerManager.getActiveLayerId()) continue;
			int[] hit = m.checkForIntersect(mousePos);
			if (hit[0] != -1) {
				clearScopeHighlight();
				scopedManager = m;
				m.setScoped(true);
				CubicPoint clicked = m.getCurves().getCurve(hit[0]).getPoint(hit[1]);
				togglePointSelection(clicked, cmdDown);
				updatePointHighlights();
				return;
			}
		}
		// Priority 3: click inside a polygon with no point hit — scope it for next click
		clearScopeHighlight();
		if (!cmdDown) selectedPoints.clear();
		for (int i = 0; i < count; i++) {
			CubicCurveManager m = polygonManager.getManager(i);
			if (m.getLayerId() != layerManager.getActiveLayerId()) continue;
			if (m.containsPoint(mousePos)) { scopedManager = m; m.setScoped(true); updatePointHighlights(); return; }
		}
		// Click on empty canvas — clear everything
		updatePointHighlights();
	}

	private void togglePointSelection(CubicPoint clicked, boolean cmdDown) {
		if (selectedPoints.contains(clicked)) { selectedPoints.remove(clicked); return; }
		if (pointSubMode == SelectionSubMode.RELATIONAL) {
			selectedPoints.addAll(collectRelationalFromPoint(clicked, !cmdDown));
		} else {
			selectedPoints.add(clicked);
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// EDGE SCOPE / SELECT
	// ─────────────────────────────────────────────────────────────────────────

	private void handleEdgeScopeOrSelect(Point2D.Double mousePos, boolean cmdDown) {
		// Priority 1: edge hit in the already-scoped manager
		if (scopedManager != null) {
			SelectedEdge hit = findNearestEdgeInManager(mousePos, scopedManager);
			if (hit != null) {
				// If already selected, leave intact so a subsequent drag can move it.
				boolean already = selectedEdges.stream()
					.anyMatch(s -> s.manager == hit.manager && s.curveIndex == hit.curveIndex);
				if (!already) {
					toggleEdgeSelection(hit, cmdDown);
					updateEdgeHighlights();
				}
				return;
			}
		}
		// Priority 2: edge hit in ANY manager — auto-scope and select
		SelectedEdge hit = findNearestEdge(mousePos);
		if (hit != null) {
			if (scopedManager != hit.manager) {
				clearScopeHighlight();
				scopedManager = hit.manager;
				hit.manager.setScoped(true);
			}
			// If already selected, leave intact so a subsequent drag can move it.
			boolean already = selectedEdges.stream()
				.anyMatch(s -> s.manager == hit.manager && s.curveIndex == hit.curveIndex);
			if (!already) {
				toggleEdgeSelection(hit, cmdDown);
				updateEdgeHighlights();
			}
			return;
		}
		// Click on empty canvas — clear
		clearScopeHighlight();
		selectedEdges.clear();
		updateEdgeHighlights();
	}

	private SelectedEdge findNearestEdgeInManager(Point2D.Double mousePos, CubicCurveManager mgr) {
		CubicCurve[] curves = mgr.getCurves().getArrayofCubicCurves();
		double minDist = 15.0; int bestIdx = -1;
		for (int j = 0; j < curves.length; j++) {
			double d = distanceToEdge(mousePos, curves[j]);
			if (d < minDist) { minDist = d; bestIdx = j; }
		}
		return bestIdx >= 0 ? new SelectedEdge(mgr, bestIdx) : null;
	}

	private void toggleEdgeSelection(SelectedEdge e, boolean cmdDown) {
		boolean already = selectedEdges.stream()
			.anyMatch(s -> s.manager == e.manager && s.curveIndex == e.curveIndex);
		if (already) {
			selectedEdges.removeIf(s -> s.manager == e.manager && s.curveIndex == e.curveIndex);
			return;
		}
		if (edgeSubMode == SelectionSubMode.RELATIONAL)
			selectedEdges.addAll(collectRelationalFromEdge(e, !cmdDown));
		else
			selectedEdges.add(e);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// HIGHLIGHT UPDATE METHODS
	// ─────────────────────────────────────────────────────────────────────────

	private void updatePointHighlights() {
		int tot = polygonManager.getPolygonCount();
		for (int i = 0; i <= tot; i++) {
			polygonManager.getManager(i).setDiscretePoints(Collections.emptySet());
			polygonManager.getManager(i).setRelationalPoints(Collections.emptySet());
		}
		if (selectedPoints.isEmpty()) return;
		Map<CubicCurveManager, Set<CubicPoint>> byMgr = new HashMap<>();
		for (CubicPoint pt : selectedPoints) {
			CubicCurveManager owner = findManagerForPoint(pt);
			if (owner != null) byMgr.computeIfAbsent(owner, k -> new HashSet<>()).add(pt);
		}
		for (Map.Entry<CubicCurveManager, Set<CubicPoint>> en : byMgr.entrySet()) {
			if (pointSubMode == SelectionSubMode.RELATIONAL) en.getKey().setRelationalPoints(en.getValue());
			else                                             en.getKey().setDiscretePoints(en.getValue());
		}
	}

	private void updatePolygonHighlights() {
		boolean rel = (polySubMode == SelectionSubMode.RELATIONAL);
		for (CubicCurveManager m : selectedPolygons) m.setSelectedRelational(rel);
	}

	// ── Rubber-band (marquee) selection ───────────────────────────────────────

	private void finalizeRubberBandSelection() {
		if (rubberBandStart == null || rubberBandEnd == null) return;
		double x1 = Math.min(rubberBandStart.x, rubberBandEnd.x);
		double y1 = Math.min(rubberBandStart.y, rubberBandEnd.y);
		double x2 = Math.max(rubberBandStart.x, rubberBandEnd.x);
		double y2 = Math.max(rubberBandStart.y, rubberBandEnd.y);
		Rectangle2D rect = new Rectangle2D.Double(x1, y1, x2 - x1, y2 - y1);
		if (pointSelectionModeEnabled) {
			selectPointsInRect(rect);
			updatePointHighlights();
		} else if (edgeSelectionModeEnabled) {
			selectEdgesInRect(rect);
			updateEdgeHighlights();
		} else if (polygonSelectionModeEnabled) {
			selectPolygonsInRect(rect);
		} else if (openCurveSelectionModeEnabled) {
			selectOpenCurvesInRect(rect);
		}
		pushSelectionToHistory();
	}

	/** Select all points (anchors and controls) whose position falls inside rect. */
	private void selectPointsInRect(Rectangle2D rect) {
		HashSet<CubicPoint> seen = new HashSet<>();
		int tot = polygonManager.getPolygonCount();
		int activeLayer = layerManager.getActiveLayerId();
		for (int i = 0; i < tot; i++) {
			CubicCurveManager m = polygonManager.getManager(i);
			if (m.getLayerId() != activeLayer) continue;
			for (CubicCurve cv : m.getCurves().getArrayofCubicCurves()) {
				for (CubicPoint pt : cv.getPoints()) {
					if (pt == null || !seen.add(pt)) continue;
					if (rect.contains(pt.getPos()) && !selectedPoints.contains(pt))
						selectedPoints.add(pt);
				}
			}
		}
	}

	/** Select all edges whose anchor midpoint falls inside rect. */
	private void selectEdgesInRect(Rectangle2D rect) {
		int tot = polygonManager.getPolygonCount();
		int activeLayer = layerManager.getActiveLayerId();
		for (int i = 0; i < tot; i++) {
			CubicCurveManager m = polygonManager.getManager(i);
			if (m.getLayerId() != activeLayer) continue;
			CubicCurve[] cvs = m.getCurves().getArrayofCubicCurves();
			for (int j = 0; j < cvs.length; j++) {
				CubicPoint[] pts = cvs[j].getPoints();
				if (pts[0] == null || pts[3] == null) continue;
				double mx = (pts[0].getPos().x + pts[3].getPos().x) / 2.0;
				double my = (pts[0].getPos().y + pts[3].getPos().y) / 2.0;
				if (rect.contains(mx, my)) {
					final int fi = j;
					final CubicCurveManager fm = m;
					boolean already = selectedEdges.stream().anyMatch(s -> s.manager == fm && s.curveIndex == fi);
					if (!already) selectedEdges.add(new SelectedEdge(m, j));
				}
			}
		}
	}

	/** Select all closed polygons and ovals whose centroid falls inside rect. */
	private void selectPolygonsInRect(Rectangle2D rect) {
		int tot = polygonManager.getPolygonCount();
		int activeLayer = layerManager.getActiveLayerId();
		for (int i = 0; i < tot; i++) {
			CubicCurveManager m = polygonManager.getManager(i);
			if (!m.getIsClosed()) continue;
			if (m.getLayerId() != activeLayer) continue;
			Point2D.Double center = m.getAverageXY();
			if (rect.contains(center) && !m.isSelected()) {
				m.setSelected(true);
				m.setSelectedRelational(polySubMode == SelectionSubMode.RELATIONAL);
				selectedPolygons.add(m);
			}
		}
		for (OvalManager oval : ovalList) {
			if (rect.contains(oval.getCx(), oval.getCy()) && !oval.isSelected()) {
				oval.setSelected(true);
				selectedOvals.add(oval);
			}
		}
	}

	/** Select all open curves whose centroid falls inside rect. */
	private void selectOpenCurvesInRect(Rectangle2D rect) {
		int tot = polygonManager.getPolygonCount();
		int activeLayer = layerManager.getActiveLayerId();
		for (int i = 0; i < tot; i++) {
			CubicCurveManager m = polygonManager.getManager(i);
			if (m.getIsClosed()) continue;
			if (m.getLayerId() != activeLayer) continue;
			Point2D.Double center = m.getAverageXY();
			if (rect.contains(center) && !m.isSelected()) {
				m.setSelected(true);
				selectedPolygons.add(m);
			}
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// CHAIN-AND-CLOSE: weld selected open curves into a new closed polygon
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Attempt to chain all selected open curves into a single new closed polygon.
	 * The original open curves are left untouched.
	 * @return null on success, or a human-readable error message on failure.
	 */
	public String closeSelectedOpenCurvesAsPolygon() {
		// Filter out empty managers (e.g. stubs loaded from XML) before chaining.
		ArrayList<CubicCurveManager> nonEmpty = new ArrayList<>();
		for (CubicCurveManager m : selectedPolygons)
			if (m.getCurves().getCubicCurveTotal() > 0) nonEmpty.add(m);

		if (nonEmpty.size() < 2)
			return "Select at least 2 open curves to close as a polygon.";

		final double TOLERANCE = 15.0;

		ArrayList<CubicCurveManager> remaining = new ArrayList<>(nonEmpty);
		ArrayList<CubicCurveManager> chain    = new ArrayList<>();
		ArrayList<Boolean>           chainFwd = new ArrayList<>();

		// Seed: first curve, forward direction
		chain.add(remaining.remove(0));
		chainFwd.add(Boolean.TRUE);

		while (!remaining.isEmpty()) {
			Point2D.Double lastPt = chainEndPos(chain.get(chain.size() - 1), chainFwd.get(chainFwd.size() - 1));
			CubicCurveManager bestMgr  = null;
			boolean           bestFwd  = true;
			double            bestDist = Double.MAX_VALUE;

			for (CubicCurveManager m : remaining) {
				double d0 = euclidean(lastPt, anchorPos(m, true));
				double dn = euclidean(lastPt, anchorPos(m, false));
				if (d0 < bestDist) { bestDist = d0; bestMgr = m; bestFwd = true; }
				if (dn < bestDist) { bestDist = dn; bestMgr = m; bestFwd = false; }
			}

			if (bestMgr == null || bestDist > TOLERANCE)
				return "Curves do not connect within tolerance (gap: " + Math.round(bestDist) + " px).";

			remaining.remove(bestMgr);
			chain.add(bestMgr);
			chainFwd.add(bestFwd);
		}

		// Verify the chain closes back to its own start
		Point2D.Double chainStart = anchorPos(chain.get(0), true); // chain[0] is always forward
		Point2D.Double chainEnd   = chainEndPos(chain.get(chain.size() - 1), chainFwd.get(chainFwd.size() - 1));
		double closureGap = euclidean(chainStart, chainEnd);
		if (closureGap > TOLERANCE)
			return "The curve chain does not close (gap: " + Math.round(closureGap) + " px).";

		// Build flat point array: 4 entries per bezier segment [a0, c1, c2, a1]
		ArrayList<Point2D.Double> pts = new ArrayList<>();
		Point2D.Double prevEnd = null;

		for (int i = 0; i < chain.size(); i++) {
			CubicCurve[] cvs = chain.get(i).getCurves().getArrayofCubicCurves();
			boolean fwd = chainFwd.get(i);
			boolean firstInGroup = true;

			if (fwd) {
				for (CubicCurve cv : cvs) {
					CubicPoint[] p = cv.getPoints();
					// Snap boundary anchor to exact previous endpoint
					Point2D.Double a0 = (firstInGroup && prevEnd != null) ? copyPt(prevEnd) : copyPt(p[0].getPos());
					pts.add(a0);
					pts.add(copyPt(p[1].getPos()));
					pts.add(copyPt(p[2].getPos()));
					pts.add(copyPt(p[3].getPos()));
					firstInGroup = false;
				}
			} else {
				// Reversed: iterate segments in reverse, swap c1↔c2 and a0↔a3
				for (int j = cvs.length - 1; j >= 0; j--) {
					CubicPoint[] p = cvs[j].getPoints();
					Point2D.Double a0 = (firstInGroup && prevEnd != null) ? copyPt(prevEnd) : copyPt(p[3].getPos());
					pts.add(a0);
					pts.add(copyPt(p[2].getPos()));
					pts.add(copyPt(p[1].getPos()));
					pts.add(copyPt(p[0].getPos()));
					firstInGroup = false;
				}
			}
			prevEnd = pts.get(pts.size() - 1);
		}

		// Snap final anchor to match the very first anchor for a clean closure
		if (!pts.isEmpty())
			pts.set(pts.size() - 1, copyPt(pts.get(0)));

		takeUndoSnapshot();
		polygonManager.addClosedFromPoints(pts.toArray(new Point2D.Double[0]), strokeColor);
		return null; // success
	}

	/** First or last anchor position of a manager (direction-agnostic). */
	private static Point2D.Double anchorPos(CubicCurveManager m, boolean first) {
		CubicCurve[] cvs = m.getCurves().getArrayofCubicCurves();
		if (cvs.length == 0) return new Point2D.Double(0, 0);
		CubicPoint[] pts = first ? cvs[0].getPoints() : cvs[cvs.length - 1].getPoints();
		return first ? pts[0].getPos() : pts[3].getPos();
	}

	/** Effective end position of a chain entry given its traversal direction. */
	private static Point2D.Double chainEndPos(CubicCurveManager m, boolean fwd) {
		return anchorPos(m, !fwd);
	}

	private static double euclidean(Point2D.Double a, Point2D.Double b) {
		double dx = a.x - b.x, dy = a.y - b.y;
		return Math.sqrt(dx * dx + dy * dy);
	}

	private static Point2D.Double copyPt(Point2D.Double p) {
		return new Point2D.Double(p.x, p.y);
	}

	private CubicCurveManager findManagerForPoint(CubicPoint pt) {
		int tot = polygonManager.getPolygonCount();
		for (int i = 0; i <= tot; i++) {
			CubicCurveManager m = polygonManager.getManager(i);
			for (CubicCurve cv : m.getCurves().getArrayofCubicCurves())
				for (CubicPoint p : cv.getPoints()) if (p == pt) return m;
		}
		return null;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// RELATIONAL TRAVERSAL
	// ─────────────────────────────────────────────────────────────────────────

	private Set<CubicPoint> collectRelationalFromPoint(CubicPoint start, boolean includeCtrls) {
		Set<CubicPoint> result = new HashSet<>();
		Queue<CubicPoint> queue = new LinkedList<>();
		Set<CubicPoint> visited = new HashSet<>();
		queue.add(start);
		while (!queue.isEmpty()) {
			CubicPoint p = queue.poll();
			if (!visited.add(p)) continue;
			result.add(p);
			for (CubicPoint linked : polygonManager.getWeldRegistry().getLinked(p)) queue.add(linked);
			if (includeCtrls && p.getType() == CubicPoint.ANCHOR_POINT)
				result.addAll(findAdjacentCtrlPoints(p));
		}
		return result;
	}

	private Set<CubicPoint> findAdjacentCtrlPoints(CubicPoint anchor) {
		Set<CubicPoint> result = new HashSet<>();
		int tot = polygonManager.getPolygonCount();
		for (int i = 0; i <= tot; i++) {
			for (CubicCurve cv : polygonManager.getManager(i).getCurves().getArrayofCubicCurves()) {
				CubicPoint[] pts = cv.getPoints();
				if (pts[0] == anchor) result.add(pts[1]);
				if (pts[3] == anchor) result.add(pts[2]);
			}
		}
		return result;
	}

	private ArrayList<SelectedEdge> collectRelationalFromEdge(SelectedEdge start, boolean includeCtrls) {
		ArrayList<SelectedEdge> result = new ArrayList<>();
		Set<String> visited = new HashSet<>();
		Queue<SelectedEdge> queue = new LinkedList<>();
		queue.add(start);
		WeldRegistry wr = polygonManager.getWeldRegistry();
		while (!queue.isEmpty()) {
			SelectedEdge e = queue.poll();
			String key = System.identityHashCode(e.manager) + ":" + e.curveIndex;
			if (!visited.add(key)) continue;
			result.add(e);
			CubicPoint[] pts = e.manager.getCurves().getCurve(e.curveIndex).getPoints();
			// Find only the directly-welded partner edge: the edge whose two anchor points
			// are exactly the weld partners of this edge's two anchor points.
			if (pts[0] != null && pts[3] != null) {
				for (CubicPoint linked0 : wr.getLinked(pts[0])) {
					for (CubicPoint linked3 : wr.getLinked(pts[3])) {
						SelectedEdge partner = findEdgeWithBothAnchors(linked0, linked3);
						if (partner != null) queue.add(partner);
					}
				}
			}
			if (includeCtrls) {
				if (pts[1] != null) selectedPoints.add(pts[1]);
				if (pts[2] != null) selectedPoints.add(pts[2]);
			}
		}
		return result;
	}

	/** Returns the edge (if any) whose two anchor slots are exactly a and b (in either order). */
	private SelectedEdge findEdgeWithBothAnchors(CubicPoint a, CubicPoint b) {
		int tot = polygonManager.getPolygonCount();
		for (int i = 0; i < tot; i++) {
			CubicCurveManager m = polygonManager.getManager(i);
			CubicCurve[] cvs = m.getCurves().getArrayofCubicCurves();
			for (int j = 0; j < cvs.length; j++) {
				CubicPoint[] pts = cvs[j].getPoints();
				if ((pts[0] == a && pts[3] == b) || (pts[0] == b && pts[3] == a))
					return new SelectedEdge(m, j);
			}
		}
		return null;
	}

	private ArrayList<SelectedEdge> findEdgesContainingAnchor(CubicPoint anchor) {
		ArrayList<SelectedEdge> result = new ArrayList<>();
		int tot = polygonManager.getPolygonCount();
		for (int i = 0; i < tot; i++) {
			CubicCurveManager m = polygonManager.getManager(i);
			CubicCurve[] cvs = m.getCurves().getArrayofCubicCurves();
			for (int j = 0; j < cvs.length; j++) {
				CubicPoint[] pts = cvs[j].getPoints();
				if (pts[0] == anchor || pts[3] == anchor) result.add(new SelectedEdge(m, j));
			}
		}
		return result;
	}

	private Set<CubicCurveManager> collectRelationalFromPolygon(CubicCurveManager start) {
		Set<CubicCurveManager> result = new HashSet<>();
		Set<CubicCurveManager> visited = new HashSet<>();
		Queue<CubicCurveManager> queue = new LinkedList<>();
		queue.add(start);
		while (!queue.isEmpty()) {
			CubicCurveManager m = queue.poll();
			if (!visited.add(m)) continue;
			result.add(m);
			for (CubicCurve cv : m.getCurves().getArrayofCubicCurves()) {
				for (int ai : new int[]{0, 3}) {
					CubicPoint anchor = cv.getPoints()[ai];
					if (anchor == null) continue;
					for (CubicPoint linked : polygonManager.getWeldRegistry().getLinked(anchor))
						for (SelectedEdge e : findEdgesContainingAnchor(linked))
							queue.add(e.manager);
				}
			}
		}
		return result;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// DRAG-TO-WELD
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * At the start of a DISCRETE polygon drag, remove all weld links between
	 * the selected polygons and any non-selected polygon.  Links between two
	 * selected polygons are left intact so multi-polygon selections stay coherent.
	 */
	private void breakCrossSelectionWelds() {
		WeldRegistry wr = polygonManager.getWeldRegistry();
		Set<CubicCurveManager> selSet = new HashSet<>(selectedPolygons);
		for (CubicCurveManager m : selectedPolygons) {
			for (CubicCurve cv : m.getCurves().getArrayofCubicCurves()) {
				for (CubicPoint pt : cv.getPoints()) {
					if (pt == null) continue;
					for (CubicPoint partner : new HashSet<>(wr.getLinked(pt))) {
						if (!pointIsInManagers(partner, selSet)) {
							wr.unregisterLink(pt, partner);
						}
					}
				}
			}
		}
	}

	private boolean pointIsInManagers(CubicPoint pt, Set<CubicCurveManager> managers) {
		for (CubicCurveManager m : managers) {
			for (CubicCurve cv : m.getCurves().getArrayofCubicCurves()) {
				for (CubicPoint p : cv.getPoints()) {
					if (p == pt) return true;
				}
			}
		}
		return false;
	}
	/**
	 * Weld all edge pairs across different polygons whose endpoints are within
	 * {@code thresholdPx} pixels of each other.  Snaps matched endpoints to their
	 * midpoint and registers weld links, so the grid moves as a unit in RELATIONAL mode.
	 * Already-welded pairs (both anchor links already registered) are skipped.
	 */
	public void weldAllAdjacent(double thresholdPx) {
		try {
			takeUndoSnapshot();
			WeldRegistry wr = polygonManager.getWeldRegistry();
			int tot = polygonManager.getPolygonCount();
			org.brogan.scaffold.BezierErrorLogger.log(
				"weldAllAdjacent: " + tot + " polygons, threshold=" + thresholdPx);
			for (int i = 0; i < tot; i++) {
				CubicCurveManager mi = polygonManager.getManager(i);
				CubicCurve[] ci = mi.getCurves().getArrayofCubicCurves();
				for (int j = i + 1; j < tot; j++) {
					CubicCurveManager mj = polygonManager.getManager(j);
					CubicCurve[] cj = mj.getCurves().getArrayofCubicCurves();
					for (CubicCurve ei : ci) {
						for (CubicCurve ej : cj) {
							tryAutoWeld(ei, ej, wr, thresholdPx);
						}
					}
					tryAutoWeldCorners(ci, cj, wr, thresholdPx);
				}
			}
			org.brogan.scaffold.BezierErrorLogger.log("weldAllAdjacent: complete");
			repaint();
		} catch (Exception e) {
			org.brogan.scaffold.BezierErrorLogger.log("weldAllAdjacent failed", e);
		}
	}

	/**
	 * If edges e0 and e1 have both endpoint pairs within thresholdPx of each other,
	 * snap them to their midpoints and register weld links.
	 */
	private void tryAutoWeld(CubicCurve e0, CubicCurve e1, WeldRegistry wr, double threshold) {
		CubicPoint[] p0 = e0.getPoints();
		CubicPoint[] p1 = e1.getPoints();
		if (p0[0]==null||p0[3]==null||p1[0]==null||p1[3]==null) return;
		double distSame    = Formulas.hypotenuse(p0[0].getPos(), p1[0].getPos())
		                   + Formulas.hypotenuse(p0[3].getPos(), p1[3].getPos());
		double distReverse = Formulas.hypotenuse(p0[0].getPos(), p1[3].getPos())
		                   + Formulas.hypotenuse(p0[3].getPos(), p1[0].getPos());
		if (Math.min(distSame, distReverse) > threshold * 2) return;
		// Determine direction (same tiebreaker as weldSelectedEdges)
		double adx0 = p0[3].getPos().x - p0[0].getPos().x, ady0 = p0[3].getPos().y - p0[0].getPos().y;
		double adx1 = p1[3].getPos().x - p1[0].getPos().x, ady1 = p1[3].getPos().y - p1[0].getPos().y;
		double adot = adx0*adx1 + ady0*ady1;
		boolean reversed = (Math.abs(distSame - distReverse) < 1.0) ? (adot < 0) : (distReverse < distSame);
		CubicPoint pa0=p0[0], pa3=p0[3];
		CubicPoint pb0=reversed?p1[3]:p1[0], pb3=reversed?p1[0]:p1[3];
		// Skip if both anchor pairs already welded
		if (wr.getLinked(pa0).contains(pb0) && wr.getLinked(pa3).contains(pb3)) return;
		// Snap anchors
		HashSet<CubicPoint> processed = new HashSet<>();
		Point2D.Double m0 = new Point2D.Double((pa0.getPos().x+pb0.getPos().x)/2, (pa0.getPos().y+pb0.getPos().y)/2);
		Point2D.Double m3 = new Point2D.Double((pa3.getPos().x+pb3.getPos().x)/2, (pa3.getPos().y+pb3.getPos().y)/2);
		snapPointToPos(pa0, m0, wr, processed); snapPointToPos(pb0, m0, wr, processed);
		snapPointToPos(pa3, m3, wr, processed); snapPointToPos(pb3, m3, wr, processed);
		// Snap control points
		CubicPoint pc0n=p0[1], pc0f=p0[2];
		CubicPoint pc1n=reversed?p1[2]:p1[1], pc1f=reversed?p1[1]:p1[2];
		Point2D.Double cm0 = new Point2D.Double((pc0n.getPos().x+pc1n.getPos().x)/2, (pc0n.getPos().y+pc1n.getPos().y)/2);
		Point2D.Double cm3 = new Point2D.Double((pc0f.getPos().x+pc1f.getPos().x)/2, (pc0f.getPos().y+pc1f.getPos().y)/2);
		snapPointToPos(pc0n, cm0, wr, processed); snapPointToPos(pc1n, cm0, wr, processed);
		snapPointToPos(pc0f, cm3, wr, processed); snapPointToPos(pc1f, cm3, wr, processed);
		// Register links
		wr.registerWeld(pa0, pb0); wr.registerWeld(pa3, pb3);
		wr.registerWeld(pc0n, pc1n); wr.registerWeld(pc0f, pc1f);
	}

	/**
	 * Link corner-only contacts between polygons ci and cj: anchor points from
	 * different polygons within threshold px of each other that are not already
	 * linked via edge welds.  Registers pairwise links between the full weld groups
	 * so that translatePolygonBy reaches all corner co-inhabitants.
	 */
	private void tryAutoWeldCorners(CubicCurve[] ci, CubicCurve[] cj, WeldRegistry wr, double threshold) {
		Set<CubicPoint> anchorsI = new LinkedHashSet<>();
		Set<CubicPoint> anchorsJ = new LinkedHashSet<>();
		for (CubicCurve c : ci) {
			CubicPoint[] p = c.getPoints();
			if (p[0] != null) anchorsI.add(p[0]);
			if (p[3] != null) anchorsI.add(p[3]);
		}
		for (CubicCurve c : cj) {
			CubicPoint[] p = c.getPoints();
			if (p[0] != null) anchorsJ.add(p[0]);
			if (p[3] != null) anchorsJ.add(p[3]);
		}
		for (CubicPoint ai : anchorsI) {
			for (CubicPoint aj : anchorsJ) {
				if (wr.getLinked(ai).contains(aj)) continue;
				double dist = Formulas.hypotenuse(ai.getPos(), aj.getPos());
				if (dist > threshold) continue;
				Point2D.Double mid = new Point2D.Double(
					(ai.getPos().x + aj.getPos().x) / 2,
					(ai.getPos().y + aj.getPos().y) / 2);
				HashSet<CubicPoint> processed = new HashSet<>();
				snapPointToPos(ai, mid, wr, processed);
				snapPointToPos(aj, mid, wr, processed);
				Set<CubicPoint> groupI = collectWeldGroup(ai, wr);
				Set<CubicPoint> groupJ = collectWeldGroup(aj, wr);
				for (CubicPoint a : groupI) {
					for (CubicPoint b : groupJ) {
						if (!wr.getLinked(a).contains(b)) wr.registerWeld(a, b);
					}
				}
			}
		}
	}

	private Set<CubicPoint> collectWeldGroup(CubicPoint start, WeldRegistry wr) {
		Set<CubicPoint> group = new HashSet<>();
		Queue<CubicPoint> queue = new LinkedList<>();
		queue.add(start);
		while (!queue.isEmpty()) {
			CubicPoint p = queue.poll();
			if (!group.add(p)) continue;
			for (CubicPoint linked : wr.getLinked(p)) queue.add(linked);
		}
		return group;
	}

	private void checkDragWeld() {
		clearPendingWeld();
		Set<CubicCurveManager> selSet = new HashSet<>(selectedPolygons);
		int tot = polygonManager.getPolygonCount();
		// Collect ALL edge pairs that meet the weld criteria (proximity + alignment)
		for (CubicCurveManager selMgr : selectedPolygons) {
			CubicCurve[] sCvs = selMgr.getCurves().getArrayofCubicCurves();
			for (int si = 0; si < sCvs.length; si++) {
				for (int ni = 0; ni < tot; ni++) {
					CubicCurveManager nMgr = polygonManager.getManager(ni);
					if (selSet.contains(nMgr)) continue;
					CubicCurve[] nCvs = nMgr.getCurves().getArrayofCubicCurves();
					for (int nj = 0; nj < nCvs.length; nj++) {
						SelectedEdge e0 = new SelectedEdge(selMgr, si);
						SelectedEdge e1 = new SelectedEdge(nMgr, nj);
						if (areEdgesWeldableForPair(e0, e1)) {
							pendingWeldPairs.add(new SelectedEdge[]{e0, e1});
						}
					}
				}
			}
		}
		// Apply purple highlight to every involved manager+edge
		Map<CubicCurveManager, Set<Integer>> highlights = new HashMap<>();
		for (SelectedEdge[] pair : pendingWeldPairs) {
			for (SelectedEdge e : pair)
				highlights.computeIfAbsent(e.manager, k -> new HashSet<>()).add(e.curveIndex);
		}
		for (Map.Entry<CubicCurveManager, Set<Integer>> en : highlights.entrySet()) {
			en.getKey().setWeldableEdgeIndices(en.getValue());
		}
	}

	private boolean areEdgesWeldableForPair(SelectedEdge e0, SelectedEdge e1) {
		if (e0.manager == e1.manager) return false;
		CubicPoint[] p0 = e0.manager.getCurves().getCurve(e0.curveIndex).getPoints();
		CubicPoint[] p1 = e1.manager.getCurves().getCurve(e1.curveIndex).getPoints();
		if (p0[0]==null||p0[3]==null||p1[0]==null||p1[3]==null) return false;
		// Midpoint proximity
		double mx0=(p0[0].getPos().x+p0[3].getPos().x)/2, my0=(p0[0].getPos().y+p0[3].getPos().y)/2;
		double mx1=(p1[0].getPos().x+p1[3].getPos().x)/2, my1=(p1[0].getPos().y+p1[3].getPos().y)/2;
		if (Math.sqrt((mx1-mx0)*(mx1-mx0)+(my1-my0)*(my1-my0)) > 60) return false;
		// Direction parallelism
		double dx0=p0[3].getPos().x-p0[0].getPos().x, dy0=p0[3].getPos().y-p0[0].getPos().y;
		double dx1=p1[3].getPos().x-p1[0].getPos().x, dy1=p1[3].getPos().y-p1[0].getPos().y;
		double len0=Math.sqrt(dx0*dx0+dy0*dy0), len1=Math.sqrt(dx1*dx1+dy1*dy1);
		if (len0<1e-6||len1<1e-6) return false;
		if (Math.abs((dx0*dx1+dy0*dy1)/(len0*len1)) <= 0.85) return false;
		// Endpoint-pair proximity: the better of same/reversed alignment must be close enough.
		// This prevents parallel edges that merely happen to be nearby from matching.
		double distSame    = Formulas.hypotenuse(p0[0].getPos(), p1[0].getPos())
		                   + Formulas.hypotenuse(p0[3].getPos(), p1[3].getPos());
		double distReverse = Formulas.hypotenuse(p0[0].getPos(), p1[3].getPos())
		                   + Formulas.hypotenuse(p0[3].getPos(), p1[0].getPos());
		return Math.min(distSame, distReverse) <= 100;
	}

	private double edgeMidpointDistance(SelectedEdge e0, SelectedEdge e1) {
		CubicPoint[] p0 = e0.manager.getCurves().getCurve(e0.curveIndex).getPoints();
		CubicPoint[] p1 = e1.manager.getCurves().getCurve(e1.curveIndex).getPoints();
		double mx0=(p0[0].getPos().x+p0[3].getPos().x)/2, my0=(p0[0].getPos().y+p0[3].getPos().y)/2;
		double mx1=(p1[0].getPos().x+p1[3].getPos().x)/2, my1=(p1[0].getPos().y+p1[3].getPos().y)/2;
		return Math.sqrt((mx1-mx0)*(mx1-mx0)+(my1-my0)*(my1-my0));
	}

	private void executeDragWeld(SelectedEdge e0, SelectedEdge e1) {
		WeldRegistry wr = polygonManager.getWeldRegistry();
		CubicPoint[] p0 = e0.manager.getCurves().getCurve(e0.curveIndex).getPoints();
		CubicPoint[] p1 = e1.manager.getCurves().getCurve(e1.curveIndex).getPoints();
		double edx0 = p0[3].getPos().x - p0[0].getPos().x, edy0 = p0[3].getPos().y - p0[0].getPos().y;
		double edx1 = p1[3].getPos().x - p1[0].getPos().x, edy1 = p1[3].getPos().y - p1[0].getPos().y;
		double edot = edx0*edx1 + edy0*edy1;
		double distSame    = Formulas.hypotenuse(p0[0].getPos(), p1[0].getPos())
		                   + Formulas.hypotenuse(p0[3].getPos(), p1[3].getPos());
		double distReverse = Formulas.hypotenuse(p0[0].getPos(), p1[3].getPos())
		                   + Formulas.hypotenuse(p0[3].getPos(), p1[0].getPos());
		boolean reversed = (Math.abs(distSame - distReverse) < 1.0) ? (edot < 0) : (distReverse < distSame);
		CubicPoint pa0=p0[0], pa3=p0[3];
		CubicPoint pb0=reversed?p1[3]:p1[0], pb3=reversed?p1[0]:p1[3];
		CubicPoint pc0n=p0[1], pc0f=p0[2];
		CubicPoint pc1n=reversed?p1[2]:p1[1], pc1f=reversed?p1[1]:p1[2];
		// Compute midpoints BEFORE moving anything
		Point2D.Double m0  = new Point2D.Double((pa0.getPos().x+pb0.getPos().x)/2, (pa0.getPos().y+pb0.getPos().y)/2);
		Point2D.Double m3  = new Point2D.Double((pa3.getPos().x+pb3.getPos().x)/2, (pa3.getPos().y+pb3.getPos().y)/2);
		Point2D.Double cm0 = new Point2D.Double((pc0n.getPos().x+pc1n.getPos().x)/2, (pc0n.getPos().y+pc1n.getPos().y)/2);
		Point2D.Double cm3 = new Point2D.Double((pc0f.getPos().x+pc1f.getPos().x)/2, (pc0f.getPos().y+pc1f.getPos().y)/2);
		// Snap each point and all its existing weld-linked siblings to the midpoint.
		// This ensures multi-polygon shapes move their internally-welded neighbours correctly.
		HashSet<CubicPoint> processed = new HashSet<>();
		snapPointToPos(pa0,  m0,  wr, processed);
		snapPointToPos(pb0,  m0,  wr, processed);
		snapPointToPos(pa3,  m3,  wr, processed);
		snapPointToPos(pb3,  m3,  wr, processed);
		snapPointToPos(pc0n, cm0, wr, processed);
		snapPointToPos(pc1n, cm0, wr, processed);
		snapPointToPos(pc0f, cm3, wr, processed);
		snapPointToPos(pc1f, cm3, wr, processed);
		// Register the new cross-shape weld links
		wr.registerWeld(pa0, pb0); wr.registerWeld(pa3, pb3);
		wr.registerWeld(pc0n, pc1n); wr.registerWeld(pc0f, pc1f);
		e0.manager.setWeldableEdgeIndices(Collections.emptySet());
		e1.manager.setWeldableEdgeIndices(Collections.emptySet());
	}

	/**
	 * Snap a point to the given position and flood-fill through all existing weld
	 * links in the registry, moving every transitively-linked point to the same pos.
	 */
	private void snapPointToPos(CubicPoint pt, Point2D.Double pos, WeldRegistry wr, HashSet<CubicPoint> processed) {
		Queue<CubicPoint> queue = new LinkedList<>();
		queue.add(pt);
		while (!queue.isEmpty()) {
			CubicPoint p = queue.poll();
			if (!processed.add(p)) continue;
			p.setPos(pos);
			p.setOrigPosToPos();
			for (CubicPoint linked : wr.getLinked(p)) queue.add(linked);
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// EXTRUDE (Shift+drag on selected edges)
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Begin extrusion: create a live single-edge duplicate for each selected edge,
	 * positioned exactly on top of the original and highlighted purple.
	 * Called on the first drag movement after Shift+press with edges selected.
	 */
	private void startExtrude() {
		extruding = true;
		extrudeOnDrag = false;
		extrudeLiveEdges.clear();

		for (SelectedEdge se : selectedEdges) {
			CubicCurve cv = se.manager.getCurves().getCurve(se.curveIndex);
			CubicPoint[] pts = cv.getPoints();
			if (pts[0] == null || pts[1] == null || pts[2] == null || pts[3] == null) continue;

			Point2D.Double[] newPts = new Point2D.Double[] {
				new Point2D.Double(pts[0].getPos().x, pts[0].getPos().y),
				new Point2D.Double(pts[1].getPos().x, pts[1].getPos().y),
				new Point2D.Double(pts[2].getPos().x, pts[2].getPos().y),
				new Point2D.Double(pts[3].getPos().x, pts[3].getPos().y)
			};

			CubicCurveManager liveMgr = polygonManager.addSingleEdge(newPts, strokeColor);
			// Show as purple (weldable) while dragging
			java.util.HashSet<Integer> edgeSet = new java.util.HashSet<>();
			edgeSet.add(0);
			liveMgr.setWeldableEdgeIndices(edgeSet);
			extrudeLiveEdges.add(liveMgr);
		}
	}

	/**
	 * Finalize extrusion on mouse release:
	 * For each (original edge, live edge) pair:
	 *   - Remove the live preview edge manager
	 *   - Build a closed 4-sided quad polygon: bottom=original, right connector, top=live reversed, left connector
	 *   - If the source edge belonged to a closed polygon, weld the bottom edge anchors to the originals
	 *   - Select curve[2] of the new quad (the far/top edge) for chain-extrusion
	 */
	private void finalizeExtrude() {
		WeldRegistry wr = polygonManager.getWeldRegistry();
		java.util.List<SelectedEdge> newSelection = new ArrayList<>();

		int i = 0;
		for (SelectedEdge se : selectedEdges) {
			if (i >= extrudeLiveEdges.size()) break;
			CubicCurveManager liveMgr = extrudeLiveEdges.get(i++);

			CubicPoint[] origPts = se.manager.getCurves().getCurve(se.curveIndex).getPoints();
			CubicPoint[] livePts = liveMgr.getCurves().getCurve(0).getPoints();
			if (origPts[0] == null || origPts[3] == null) continue;

			// Snapshot orig anchor positions before removing the live manager
			Point2D.Double origA0 = origPts[0].getPos();
			Point2D.Double origC1 = origPts[1].getPos();
			Point2D.Double origC2 = origPts[2].getPos();
			Point2D.Double origA3 = origPts[3].getPos();

			Point2D.Double liveA0 = livePts[0].getPos();
			Point2D.Double liveA3 = livePts[3].getPos();

			// Remove the live preview edge
			int liveIdx = -1;
			for (int j = 0; j < polygonManager.getPolygonCount(); j++) {
				if (polygonManager.getManager(j) == liveMgr) { liveIdx = j; break; }
			}
			if (liveIdx >= 0) polygonManager.removeManagerAtIndex(liveIdx);

			// Build 16-point array for a 4-sided closed quad:
			//   curve[0]: bottom = original edge (preserved bezier)
			//   curve[1]: right connector = origA3 → liveA3 (straight)
			//   curve[2]: top = live edge REVERSED (liveA3 → liveA0, swap c1/c2)
			//   curve[3]: left connector = liveA0 → origA0 (straight)
			Point2D.Double[] quadPts = new Point2D.Double[16];
			// curve[0] bottom
			quadPts[0] = new Point2D.Double(origA0.x, origA0.y);
			quadPts[1] = new Point2D.Double(origC1.x, origC1.y);
			quadPts[2] = new Point2D.Double(origC2.x, origC2.y);
			quadPts[3] = new Point2D.Double(origA3.x, origA3.y);
			// curve[1] right connector
			quadPts[4] = new Point2D.Double(origA3.x, origA3.y);
			quadPts[5] = new Point2D.Double(origA3.x + (liveA3.x - origA3.x) / 3.0, origA3.y + (liveA3.y - origA3.y) / 3.0);
			quadPts[6] = new Point2D.Double(origA3.x + 2*(liveA3.x - origA3.x) / 3.0, origA3.y + 2*(liveA3.y - origA3.y) / 3.0);
			quadPts[7] = new Point2D.Double(liveA3.x, liveA3.y);
			// curve[2] top = live edge reversed
			quadPts[8]  = new Point2D.Double(liveA3.x, liveA3.y);
			quadPts[9]  = new Point2D.Double(livePts[2].getPos().x, livePts[2].getPos().y);  // c2 becomes c1
			quadPts[10] = new Point2D.Double(livePts[1].getPos().x, livePts[1].getPos().y);  // c1 becomes c2
			quadPts[11] = new Point2D.Double(liveA0.x, liveA0.y);
			// curve[3] left connector
			quadPts[12] = new Point2D.Double(liveA0.x, liveA0.y);
			quadPts[13] = new Point2D.Double(liveA0.x + (origA0.x - liveA0.x) / 3.0, liveA0.y + (origA0.y - liveA0.y) / 3.0);
			quadPts[14] = new Point2D.Double(liveA0.x + 2*(origA0.x - liveA0.x) / 3.0, liveA0.y + 2*(origA0.y - liveA0.y) / 3.0);
			quadPts[15] = new Point2D.Double(origA0.x, origA0.y);

			CubicCurveManager quadMgr = polygonManager.addClosedFromPoints(quadPts, strokeColor);

			// Weld bottom edge to source only when source is a closed polygon
			if (se.manager.getIsClosed()) {
				CubicPoint quadA0 = quadMgr.getCurves().getCurve(0).getPoints()[0];
				CubicPoint quadA3 = quadMgr.getCurves().getCurve(0).getPoints()[3];
				wr.registerWeld(origPts[0], quadA0);
				wr.registerWeld(origPts[3], quadA3);
			}

			// Select curve[2] (the far top edge) for chain-extrusion
			newSelection.add(new SelectedEdge(quadMgr, 2));
		}

		// Clear old selection and select the new edge(s)
		for (SelectedEdge se : selectedEdges) {
			se.manager.setDiscreteEdgeIndices(Collections.emptySet());
			se.manager.setRelationalEdgeIndices(Collections.emptySet());
		}
		selectedEdges.clear();
		selectedEdges.addAll(newSelection);
		updateEdgeHighlights();

		extrudeLiveEdges.clear();
	}

	/** Build a 4-point straight-line cubic bezier from a to b (control points at 1/3 and 2/3). */
	private static Point2D.Double[] straightEdgePts(Point2D.Double a, Point2D.Double b) {
		return new Point2D.Double[] {
			new Point2D.Double(a.x, a.y),
			new Point2D.Double(a.x + (b.x - a.x) / 3.0, a.y + (b.y - a.y) / 3.0),
			new Point2D.Double(a.x + 2*(b.x - a.x) / 3.0, a.y + 2*(b.y - a.y) / 3.0),
			new Point2D.Double(b.x, b.y)
		};
	}

	// ─────────────────────────────────────────────────────────────────────────
	// POINT-MODE TRANSFORMS
	// ─────────────────────────────────────────────────────────────────────────

	private void scaleSelectedPoints(double scale) {
		double f = 1.0 + scale / 100.0;
		double cx = 0, cy = 0;
		for (CubicPoint pt : selectedPoints) { cx += pt.getOrigPos().x; cy += pt.getOrigPos().y; }
		cx /= selectedPoints.size(); cy /= selectedPoints.size();
		for (CubicPoint pt : selectedPoints) {
			double ox = pt.getOrigPos().x - cx, oy = pt.getOrigPos().y - cy;
			pt.setPos(new Point2D.Double(ox * f + cx, oy * f + cy));
		}
	}

	private void rotateSelectedPoints(double rot) {
		int axisMode = cubicCurvePanel.getRotationAxisMode();
		Point2D.Double pivot;
		if (axisMode == CubicCurvePanel.ROTATE_ABSOLUTE) {
			pivot = new Point2D.Double(edgeOffset + GRIDWIDTH / 2.0, edgeOffset + GRIDHEIGHT / 2.0);
		} else {
			double cx = 0, cy = 0;
			for (CubicPoint pt : selectedPoints) { cx += pt.getOrigPos().x; cy += pt.getOrigPos().y; }
			pivot = new Point2D.Double(cx / selectedPoints.size(), cy / selectedPoints.size());
		}
		for (CubicPoint pt : selectedPoints) {
			Point2D.Double rel = new Point2D.Double(pt.getOrigPos().x - pivot.x, pt.getOrigPos().y - pivot.y);
			Point2D.Double r = Transform.rotate(rel, rot);
			pt.setPos(new Point2D.Double(r.x + pivot.x, r.y + pivot.y));
		}
	}

	/** Mouse-drag translation: cumulative deltas, commits origPos each step. */
	private void translateSelectedPointsByDelta(double dx, double dy) {
		boolean relational = (pointSubMode == SelectionSubMode.RELATIONAL);
		WeldRegistry wr = relational ? polygonManager.getWeldRegistry() : null;
		HashSet<CubicPoint> moved = new HashSet<>();
		for (CubicPoint pt : selectedPoints) {
			if (!moved.add(pt)) continue;
			Point2D.Double pos = pt.getPos();
			pt.setPos(new Point2D.Double(pos.x + dx, pos.y + dy));
			pt.setOrigPosToPos();
			if (relational) {
				for (CubicPoint linked : wr.getLinked(pt)) {
					if (!moved.add(linked)) continue;
					Point2D.Double lpos = linked.getPos();
					linked.setPos(new Point2D.Double(lpos.x + dx, lpos.y + dy));
					linked.setOrigPosToPos();
				}
			}
		}
	}

	/** Slider-based translation: offset from origPos (does not commit origPos). */
	private void translateSelectedPointsFromOrig(double tx, double ty) {
		boolean relational = (pointSubMode == SelectionSubMode.RELATIONAL);
		WeldRegistry wr = relational ? polygonManager.getWeldRegistry() : null;
		HashSet<CubicPoint> moved = new HashSet<>();
		for (CubicPoint pt : selectedPoints) {
			if (!moved.add(pt)) continue;
			pt.setPos(new Point2D.Double(pt.getOrigPos().x + tx, pt.getOrigPos().y + ty));
			if (relational) {
				for (CubicPoint linked : wr.getLinked(pt)) {
					if (!moved.add(linked)) continue;
					linked.setPos(new Point2D.Double(linked.getOrigPos().x + tx, linked.getOrigPos().y + ty));
				}
			}
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// LEGACY POINT SELECTION (UNCHANGED — used in non-selection-mode path)
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * selectPoint: called from mousePressed
	 * @param curveManager
	 * @param currPolygon
	 * @param pos
	 */
	public void selectPoint(Point2D.Double pos) {
		
		if (currentCurveManager != null) {
			System.out.println("currentCurveManager is NOT null");

			CubicCurvePolygon cPolygon = currentCurveManager.getCurves();//currentCurveManager set in mousePressed

			//System.out.println("BezierDrawPanel, mouse dragged, checking for intersect with curves and individual points");
			int[] intersect;
			if (isAnchorSelect() && !isControlSelect()){
				intersect = currentCurveManager.checkForAnchorIntersect(pos);//curve intersect, point intersect
			} else if (!isAnchorSelect() && isControlSelect()){
				intersect = currentCurveManager.checkForControlIntersect(pos);//curve intersect, point intersect
			} else {//check for intersect of both anchor and control points
				intersect = currentCurveManager.checkForIntersect(pos);//curve intersect, point intersect
			}
			if (intersect[0]!=-1 && intersect[1]!=-1) {
				currPoint = cPolygon.getCurve(intersect[0]).getPoint(intersect[1]);
				cPolygon.getCurve(intersect[0]).getPoint(intersect[1]).drag(pos);
				curvePointSelected=true;
				currentSelectedCurve = intersect[0];
				currentSelectedPoint = intersect[1];
				//if ((currentSelectedPoint == 0)  || (currentSelectedPoint == 3)) {//this was to just select anchor points
				if (!selectedPoints.contains(currPoint)) {
					selectedPoints.add(currPoint);
				} else {
					selectedPoints.remove(currPoint);
				}
				currPoint.toggleSelected();
				//}

			} else {//clicked elsewhere - drop all selected points
				System.out.println("BezierDrawPanel, mousePressed, drop all selected points");
				emptySelectedPoints();
			}

		} else {

			System.out.println("currentCurveManager is null");
		}
		
	}

}
