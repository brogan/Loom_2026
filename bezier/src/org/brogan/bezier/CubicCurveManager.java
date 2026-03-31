package org.brogan.bezier;

import java.awt.*;
import java.awt.geom.*;
import java.awt.geom.CubicCurve2D;
import java.util.*;

import org.brogan.util.Formulas;

public class CubicCurveManager {
	
	private CubicCurvePolygonManager polyManager;
	private CubicCurvePolygon curves;//each set of curves is a polygon
	private CubicCurve currentCurve;
	private int curveCount;
	
	private int pointCount;
	private boolean addPoints;//can we add more points or is shape closed
	private Point2D.Double currentBezierPos;
	private boolean selected = false;
	private boolean selectedRelational = false;
	private boolean scoped = false;
	private int layerId = 0;
	private boolean isClosed = false;
	/** Per-anchor pressure values (0.0–1.0). Index k = anchor k in the open curve.
	 *  Null means uniform pressure (1.0). Only meaningful for open curves. */
	private float[] anchorPressures = null;
	private Set<Integer> discreteEdgeIndices   = new HashSet<>();
	private Set<Integer> relationalEdgeIndices = new HashSet<>();
	private Set<Integer> weldableEdgeIndices   = new HashSet<>();
	private Set<CubicPoint> discretePointSet   = new HashSet<>();
	private Set<CubicPoint> relationalPointSet = new HashSet<>();

	public CubicCurveManager(Color strokeColor, CubicCurvePolygonManager cpM) {

		polyManager = cpM;
		curves = new CubicCurvePolygon(100);
		
		curveCount = 0;
		pointCount = 0;
		currentCurve = new CubicCurve(strokeColor);
		addPoints = true;

	}
	public void draw(Graphics2D g2D) {
		g2D.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
		curves.draw(g2D);
		if (curveCount==0) {//need to draw initial points
			currentCurve.draw(g2D);
		}
		// --- Polygon selection overlay ---
		if (selected) {
			Color selCol = selectedRelational ? new Color(255,140,0,160) : new Color(0,100,255,160);
			g2D.setStroke(new BasicStroke(4f));
			g2D.setColor(selCol);
			for (CubicCurve cv : curves.getArrayofCubicCurves()) {
				CubicPoint[] p = cv.getPoints();
				if (p[0]!=null && p[1]!=null && p[2]!=null && p[3]!=null)
					g2D.draw(new CubicCurve2D.Float(
						(float)p[0].getPos().x, (float)p[0].getPos().y,
						(float)p[1].getPos().x, (float)p[1].getPos().y,
						(float)p[2].getPos().x, (float)p[2].getPos().y,
						(float)p[3].getPos().x, (float)p[3].getPos().y));
			}
		}
		// --- Edge highlights: discrete(blue), relational(orange), weldable(purple) ---
		CubicCurve[] cArr = curves.getArrayofCubicCurves();
		for (int idx = 0; idx < cArr.length; idx++) {
			CubicPoint[] p = cArr[idx].getPoints();
			if (p[0]==null||p[1]==null||p[2]==null||p[3]==null) continue;
			Color col; float sw;
			if      (weldableEdgeIndices.contains(idx))   { col=new Color(220,0,255,200);  sw=5f; }
			else if (relationalEdgeIndices.contains(idx)) { col=new Color(255,140,0,200);  sw=4f; }
			else if (discreteEdgeIndices.contains(idx))   { col=new Color(255,140,0,200);   sw=4f; }
			else continue;
			g2D.setStroke(new BasicStroke(sw));
			g2D.setColor(col);
			g2D.draw(new CubicCurve2D.Float(
				(float)p[0].getPos().x, (float)p[0].getPos().y,
				(float)p[1].getPos().x, (float)p[1].getPos().y,
				(float)p[2].getPos().x, (float)p[2].getPos().y,
				(float)p[3].getPos().x, (float)p[3].getPos().y));
		}
		// --- Point highlights ---
		for (CubicPoint pt : discretePointSet)   drawPointHighlight(g2D, pt, false);
		for (CubicPoint pt : relationalPointSet) drawPointHighlight(g2D, pt, true);
		// --- Pressure-scaled anchor dots for open curves ---
		if (!isClosed && anchorPressures != null) {
			CubicCurve[] pcArr = curves.getArrayofCubicCurves();
			g2D.setStroke(new BasicStroke(1f));
			for (int ai = 0; ai < pcArr.length; ai++) {
				CubicPoint[] pp = pcArr[ai].getPoints();
				if (pp[0] == null || pp[3] == null) continue;
				// anchor ai
				float pa0 = getAnchorPressure(ai);
				int r0 = Math.max(2, (int)(pa0 * 7));
				Point2D.Double pos0 = pp[0].getPos();
				g2D.setColor(new Color(80, 80, 180, 160));
				g2D.fillOval((int)pos0.x - r0, (int)pos0.y - r0, r0 * 2, r0 * 2);
				g2D.setColor(new Color(0, 0, 0, 80));
				g2D.drawOval((int)pos0.x - r0, (int)pos0.y - r0, r0 * 2, r0 * 2);
				// last anchor of last curve
				if (ai == pcArr.length - 1) {
					float paL = getAnchorPressure(ai + 1);
					int rL = Math.max(2, (int)(paL * 7));
					Point2D.Double posL = pp[3].getPos();
					g2D.setColor(new Color(80, 80, 180, 160));
					g2D.fillOval((int)posL.x - rL, (int)posL.y - rL, rL * 2, rL * 2);
					g2D.setColor(new Color(0, 0, 0, 80));
					g2D.drawOval((int)posL.x - rL, (int)posL.y - rL, rL * 2, rL * 2);
				}
			}
		}
		// --- Scope indicator (yellow dashed outline) ---
		if (scoped) {
			g2D.setStroke(new BasicStroke(2f, BasicStroke.CAP_BUTT, BasicStroke.JOIN_MITER,
				10f, new float[]{8,4}, 0f));
			g2D.setColor(new Color(255,255,100,200));
			for (CubicCurve cv : curves.getArrayofCubicCurves()) {
				CubicPoint[] p = cv.getPoints();
				if (p[0]!=null && p[1]!=null && p[2]!=null && p[3]!=null)
					g2D.draw(new CubicCurve2D.Float(
						(float)p[0].getPos().x, (float)p[0].getPos().y,
						(float)p[1].getPos().x, (float)p[1].getPos().y,
						(float)p[2].getPos().x, (float)p[2].getPos().y,
						(float)p[3].getPos().x, (float)p[3].getPos().y));
			}
		}
	}

	private void drawPointHighlight(Graphics2D g2D, CubicPoint pt, boolean relational) {
		Point2D.Double pos = pt.getPos();
		Color c;
		if (relational)
			c = (pt.getType() == CubicPoint.ANCHOR_POINT) ? new Color(220,50,30) : new Color(255,220,0);
		else
			c = (pt.getType() == CubicPoint.ANCHOR_POINT) ? new Color(100,150,255) : Color.WHITE;
		g2D.setColor(c);
		g2D.fillOval((int)pos.x-6, (int)pos.y-6, 12, 12);
		g2D.setColor(Color.BLACK);
		g2D.setStroke(new BasicStroke(1f));
		g2D.drawOval((int)pos.x-6, (int)pos.y-6, 12, 12);
	}
	/**
	 * Finish drawing as an open curve without adding a closing synthetic edge.
	 * Works with any number of curves including zero (discrete point placeholder).
	 */
	public void finishOpen() {
		addPoints = false;
		isClosed = false;
		polyManager.addPolygon(curves);
	}

	/**
	 * Load an open curve from an array of N*4 points WITHOUT linking the last anchor
	 * back to the first. Mirrors setAllPoints() but for open paths.
	 * For N=0 (discrete point placeholder) the curves list remains empty.
	 */
	public void setOpenPoints(Point2D.Double[] points, Color strokeColor) {
		addPoints = false;
		isClosed = false;
		int totalCurves = points.length / 4;
		int count = 0;
		for (int i = 0; i < totalCurves; i++) {
			currentCurve = new CubicCurve(strokeColor);
			if (i == 0) {
				currentCurve.setAnchorPoint(points[count], CubicCurve.ANCHOR_FIRST, null);
			} else {
				currentCurve.setAnchorPoint(points[count], CubicCurve.ANCHOR_FIRST, curves.getCurve(i-1).getPoint(3));
			}
			currentCurve.setControlPoint(points[count+1], 1);
			currentCurve.setControlPoint(points[count+2], 2);
			// Last anchor is NOT shared back to curve[0].anchor[0]
			currentCurve.setAnchorPoint(points[count+3], CubicCurve.ANCHOR_LAST, null);
			curves.addCurve(currentCurve);
			count += 4;
		}
	}

	/**
	 * Set up this manager as a single open edge from pts[0..3].
	 * Unlike setAllPoints, the last anchor is NOT closed back to the first.
	 * Used when duplicating a selected edge into a new standalone single-edge polygon.
	 */
	public void setSingleEdgePoints(Point2D.Double[] pts, Color strokeColor) {
		addPoints = false;
		currentCurve = new CubicCurve(strokeColor);
		currentCurve.setAnchorPoint(pts[0], CubicCurve.ANCHOR_FIRST, null);
		currentCurve.setControlPoint(pts[1], 1);
		currentCurve.setControlPoint(pts[2], 2);
		currentCurve.setAnchorPoint(pts[3], CubicCurve.ANCHOR_LAST, null);
		curves.addCurve(currentCurve);
	}

	/**
	 * called from CubicCurvePanel when editing
	 * sets out entire shape
	 * @param points
	 */
	public void setAllPoints(Point2D.Double[] points, Color strokeColor) {
		addPoints = false;//needed???
		int totalCurves = points.length/4;
		//System.out.println("CubicCurveManager, setAllPoints, editing mode totalCurves: "+totalCurves);
		int count = 0;
		for (int i = 0;i<totalCurves;i++) {//cycle through total curves
			currentCurve = new CubicCurve(strokeColor);;
			if (i==0) {
				currentCurve.setAnchorPoint(points[count], CubicCurve.ANCHOR_FIRST, null);
			} else {
				currentCurve.setAnchorPoint(points[count], CubicCurve.ANCHOR_FIRST, curves.getCurve(i-1).getPoint(3));
			}
			currentCurve.setControlPoint(points[count+1], 1);
			currentCurve.setControlPoint(points[count+2], 2);
			if (i==totalCurves-1) {
				currentCurve.setAnchorPoint(points[count+3], CubicCurve.ANCHOR_LAST, curves.getCurve(0).getPoint(0));
			} else {
				currentCurve.setAnchorPoint(points[count+3], CubicCurve.ANCHOR_LAST, null);
			}
			curves.addCurve(currentCurve);
			
			count+=4;
		}
	}
	/**
	 * called from pressing close curve button
	 * @param strokeColor
	 */
	public void closeCurve(Color strokeColor) {
		currentCurve = new CubicCurve(strokeColor);

		CubicPoint lastAnchor = curves.getCurve(curveCount-1).getPoint(3);
		Point2D.Double lastAnchorPoint = lastAnchor.getPos();
		currentCurve.setAnchorPoint(new Point2D.Double(lastAnchorPoint.x, lastAnchorPoint.y), CubicCurve.ANCHOR_FIRST, lastAnchor);
		//System.out.println("CubicCurveManager, closeCurve, last anchor: lastAnchorPoint.x: " + lastAnchorPoint.x + "   lastAnchorPoint.y: " + lastAnchorPoint.y);

		CubicPoint originAnchor = curves.getCurve(0).getPoint(0);
		Point2D.Double originAnchorPoint = originAnchor.getPos();
		currentCurve.setAnchorPoint(new Point2D.Double(originAnchorPoint.x, originAnchorPoint.y), CubicCurve.ANCHOR_LAST, originAnchor);
		//System.out.println("CubicCurveManager, closeCurve, origin anchor: originAnchorPoint.x: " + originAnchorPoint.x + "   originAnchorPoint.y: " + originAnchorPoint.y);
		
		currentCurve.setControlPoints();
		curves.addCurve(currentCurve);

		addPoints = false;
		isClosed = true;

		polyManager.addPolygon(curves);

	}

	/**
	 * Close an already-committed open curve (e.g. from freehand drawing).
	 * Unlike closeCurve(), this does NOT call addPolygon() since the curves are
	 * already registered in the polygon set.  Uses actual curve count rather than
	 * the interactive curveCount field (which is 0 for programmatically-built curves).
	 */
	public void closeOpenCurve(Color strokeColor) {
		int totalCurves = curves.getCubicCurveTotal();
		if (totalCurves == 0 || isClosed) return;
		currentCurve = new CubicCurve(strokeColor);

		CubicPoint lastAnchor   = curves.getCurve(totalCurves - 1).getPoint(3);
		Point2D.Double lastPos  = lastAnchor.getPos();
		currentCurve.setAnchorPoint(new Point2D.Double(lastPos.x, lastPos.y), CubicCurve.ANCHOR_FIRST, lastAnchor);

		CubicPoint originAnchor  = curves.getCurve(0).getPoint(0);
		Point2D.Double originPos = originAnchor.getPos();
		currentCurve.setAnchorPoint(new Point2D.Double(originPos.x, originPos.y), CubicCurve.ANCHOR_LAST, originAnchor);

		currentCurve.setControlPoints();
		curves.addCurve(currentCurve);

		addPoints = false;
		isClosed  = true;
		// Do NOT call addPolygon — curves are already in the polygon set.
	}

	/**
	 * called from loading xml
	 * @param strokeColor
	 */
	public void closeCurve(Color strokeColor, Point2D.Double C1, Point2D.Double C2) {
		currentCurve = new CubicCurve(strokeColor);
		
		System.out.println("");
		System.out.println("CubicCurveManager, closeCurve, curves - size: " + curves.getCubicCurveTotal());

		CubicPoint lastAnchor = curves.getCurve(curveCount-1).getPoint(3);
		Point2D.Double lastAnchorPoint = lastAnchor.getPos();
		currentCurve.setAnchorPoint(new Point2D.Double(lastAnchorPoint.x, lastAnchorPoint.y), CubicCurve.ANCHOR_FIRST, lastAnchor);
		//System.out.println("CubicCurveManager, closeCurve, last anchor: lastAnchorPoint.x: " + lastAnchorPoint.x + "   lastAnchorPoint.y: " + lastAnchorPoint.y);

		CubicPoint originAnchor = curves.getCurve(0).getPoint(0);
		Point2D.Double originAnchorPoint = originAnchor.getPos();
		currentCurve.setAnchorPoint(new Point2D.Double(originAnchorPoint.x, originAnchorPoint.y), CubicCurve.ANCHOR_LAST, originAnchor);
		//System.out.println("CubicCurveManager, closeCurve, origin anchor: originAnchorPoint.x: " + originAnchorPoint.x + "   originAnchorPoint.y: " + originAnchorPoint.y);
		
		currentCurve.setControlPoints(C1, C2);//the different line - sets control points to a specfic predetermined position (from xml)
		curves.addCurve(currentCurve);

		addPoints = false;
		isClosed = true;

		polyManager.addPolygon(curves);

	}
	
	public void hideControls() {
		ArrayList <CubicCurve> cA = curves.getCurves();
		for (int i = 0; i<cA.size(); i++) {
			CubicPoint[] p = cA.get(i).getPoints();
			cA.get(i).switchDrawLinesToAnchor();
			for (int j = 0; j<p.length; j++) {
				p[j].switchOvalDrawing();
			}
		}
	}
	public void clearAll(Color strokeColor) {
		System.out.println("removing curves"); 
		int tot = curves.getCubicCurveTotal();
		for (int i = tot; i>0;i--) {
			curves.removeCurve(i-1);
			System.out.println("curve removed: "+ i);
		}
		curveCount = 0;
		pointCount = 0;
		currentCurve = new CubicCurve(strokeColor);
		addPoints = true;
	}


	/**
	 * called from BezierDrawPanel
	 * @param mousePos
	 * @return int array that contains curve index + the relevant point in the curve
	 */
	public int[] checkForIntersect(Point2D.Double mousePos) {
		//System.out.println("####CubicCurveManager, checkForIntersect, curves.getCubicCurveTotal(): " + curves.getCubicCurveTotal());
		int[] a = new int[2];
		for (int c = 0; c<curves.getCubicCurveTotal();c++) {//loop through curves in polygon
			CubicCurve cv = curves.getCurve(c);
			CubicPoint[] p = cv.getPoints();
			for (int i = 0; i<p.length;i++) {//loop through points in curve
				double h = Formulas.hypotenuse(mousePos, p[i].getPos());
				if (h < p[i].getOval().getWidth()) {//if distance between mouse position and point is less than the width of the surrounding oval shape then that particular point is obtained
					a[0]=c;//the curve index
					a[1]=i;//the point index
					return a;//proper return value
				}
			}
		}
		//ERROR CODES
		a[0]=-1;
		a[1]=-1;
		return a;
	}
	/**
	 * called from BezierDrawPanel
	 * @param mousePos
	 * @return int array that contains curve index + the relevant anchor point in the curve
	 */
	public int[] checkForAnchorIntersect(Point2D.Double mousePos) {
		//System.out.println("####CubicCurveManager, checkForAnchorIntersect, curves.getCubicCurveTotal(): " + curves.getCubicCurveTotal());
		int[] a = new int[2];
		for (int c = 0; c<curves.getCubicCurveTotal();c++) {
			CubicCurve cv = curves.getCurve(c);
			CubicPoint[] p = cv.getPoints();
			double h = Formulas.hypotenuse(mousePos, p[0].getPos());
			if (h < p[0].getOval().getWidth()) {
				a[0]=c;//the curve
				a[1]=0;//the point index (first anchor point)
				return a;
			}
			h = Formulas.hypotenuse(mousePos, p[3].getPos());
			if (h < p[3].getOval().getWidth()) {
				a[0]=c;//the curve
				a[1]=3;//the point index (last anchor point)
				return a;
			}
		}
		//ERROR CODES
		a[0]=-1;
		a[1]=-1;
		return a;
	}
	/**
	 * called from BezierDrawPanel
	 * @param mousePos
	 * @return int array that contains curve index + the relevant anchor point in the curve
	 */
	public int[] checkForControlIntersect(Point2D.Double mousePos) {
		System.out.println("####CubicCurveManager, checkForControlIntersect, curves.getCubicCurveTotal(): " + curves.getCubicCurveTotal());
		int[] a = new int[2];
		for (int c = 0; c<curves.getCubicCurveTotal();c++) {
			CubicCurve cv = curves.getCurve(c);
			CubicPoint[] p = cv.getPoints();
			double h = Formulas.hypotenuse(mousePos, p[1].getPos());
			if (h < p[1].getOval().getWidth()) {
				a[0]=c;
				a[1]=1;
				return a;
			}
			h = Formulas.hypotenuse(mousePos, p[2].getPos());
			if (h < p[3].getOval().getWidth()) {
				a[0]=c;
				a[1]=2;
				return a;
			}
		}
		a[0]=-1;
		a[1]=-1;
		return a;
	}
	public int  getLayerId()           { return layerId; }
	public void setLayerId(int id)     { this.layerId = id; }
	public boolean getIsClosed()       { return isClosed; }
	public void    setIsClosed(boolean b) { isClosed = b; }

	/** Set per-anchor pressure data. Pass null to clear (uniform 1.0). */
	public void setAnchorPressures(float[] p) { anchorPressures = p; }
	/** Get per-anchor pressure array (may be null). */
	public float[] getAnchorPressures() { return anchorPressures; }
	/** Return pressure for anchor at index {@code k}, defaulting to 1.0f. */
	public float getAnchorPressure(int k) {
		if (anchorPressures == null || k < 0 || k >= anchorPressures.length) return 1.0f;
		return anchorPressures[k];
	}

	public boolean isSelected() { return selected; }
	public void setSelected(boolean selected) { this.selected = selected; }
	public void setSelectedRelational(boolean b) { selectedRelational = b; }
	public void setScoped(boolean b)             { scoped = b; }

	/** Backward-compat: maps to discreteEdgeIndices */
	public void setSelectedEdgeIndices(Set<Integer> indices) {
		discreteEdgeIndices = new HashSet<>(indices);
	}
	public void setDiscreteEdgeIndices(Set<Integer> s)   { discreteEdgeIndices = s; }
	public void setRelationalEdgeIndices(Set<Integer> s) { relationalEdgeIndices = s; }
	public void setDiscretePoints(Set<CubicPoint> s)     { discretePointSet = s; }
	public void setRelationalPoints(Set<CubicPoint> s)   { relationalPointSet = s; }
	public void setWeldableEdgeIndices(Set<Integer> indices) {
		weldableEdgeIndices = new HashSet<>(indices);
	}
	public void clearEdgeHighlights() {
		discreteEdgeIndices.clear();
		relationalEdgeIndices.clear();
		weldableEdgeIndices.clear();
	}
	public void clearAllHighlights() {
		selected = false; selectedRelational = false; scoped = false;
		discreteEdgeIndices.clear(); relationalEdgeIndices.clear(); weldableEdgeIndices.clear();
		discretePointSet.clear(); relationalPointSet.clear();
	}

	/**
	 * Returns true if mousePos is inside the closed bezier polygon.
	 * Uses Path2D for accurate hit-testing on the spline outline.
	 */
	public boolean containsPoint(Point2D.Double mousePos) {
		CubicCurve[] cArray = curves.getArrayofCubicCurves();
		if (cArray.length == 0) return false;
		CubicPoint[] first = cArray[0].getPoints();
		if (first[0] == null) return false;
		java.awt.geom.Path2D.Double path = new java.awt.geom.Path2D.Double();
		path.moveTo(first[0].getPos().x, first[0].getPos().y);
		for (CubicCurve cv : cArray) {
			CubicPoint[] p = cv.getPoints();
			if (p[0] == null || p[1] == null || p[2] == null || p[3] == null) continue;
			path.curveTo(p[1].getPos().x, p[1].getPos().y,
			             p[2].getPos().x, p[2].getPos().y,
			             p[3].getPos().x, p[3].getPos().y);
		}
		path.closePath();
		return path.contains(mousePos.x, mousePos.y);
	}

	/**
	 * @return the average x, y of all anchor points computed from origPos (not corrupted by transforms)
	 */
	public Point2D.Double getAverageXYFromOrig() {
		double x = 0, y = 0;
		for (int c = 0; c < curves.getCubicCurveTotal(); c++) {
			CubicPoint[] p = curves.getCurve(c).getPoints();
			x += p[0].getOrigPos().x; x += p[3].getOrigPos().x;
			y += p[0].getOrigPos().y; y += p[3].getOrigPos().y;
		}
		int n = curves.getCubicCurveTotal();
		return new Point2D.Double(x / (2 * n), y / (2 * n));
	}

	/**
	 *
	 * @return the average x, y of all anchor points
	 */
	public Point2D.Double getAverageXY() {
		if (curves.getCubicCurveTotal() == 0) {
			return new Point2D.Double(520, 520); // canvas centre; safe default for discrete points
		}
		int x = 0;
		int y = 0;
		for (int c = 0; c<curves.getCubicCurveTotal();c++) {
			CubicCurve cv = curves.getCurve(c);
			CubicPoint[] p = cv.getPoints();
			x += p[0].getPos().x;
			x += p[3].getPos().x;
			y += p[0].getPos().y;
			y += p[3].getPos().y;
		}
		System.out.println("\nCubicCurveManager, total CubicCurves: " + curves.getCubicCurveTotal() +"\n");
		x = x/(2*(curves.getCubicCurveTotal()));
		y = y/(2*(curves.getCubicCurveTotal()));
		System.out.println("CubicCurveManager, getAverageXY, x: " + x + "   y: " + y);
		return new Point2D.Double(x, y);
	}
	/**
	 * set the initial position of the bezier handles
	 * @param pos
	 */
	public void setBezierPosition(Point2D.Double pos) {
		Point2D.Double average = getAverageXY();
		double xShift = pos.x - average.x;
		double yShift = pos.y - average.y;
		System.out.println("CubicCurveManager, setBezierPosition, xShift: " + xShift + "   yShift: " + yShift);
		for (int c = 0; c<curves.getCubicCurveTotal();c++) {
			CubicCurve cv = curves.getCurve(c);
			CubicPoint[] p = cv.getPoints();
			for (int i = 0; i< p.length; i++) {
				if (i == 0 || i == 3) {
					p[i].setPos(new Point2D.Double(p[i].getPos().x + xShift/2, p[i].getPos().y + yShift/2));
					p[i].setOrigPosToPos();
				} else {
					p[i].setPos(new Point2D.Double(p[i].getPos().x + xShift, p[i].getPos().y + yShift));
					p[i].setOrigPosToPos();
				}
			}
		}
	}

	/**
	 * called when centering full polygon set.
	 * moved is a shared HashSet passed from centerPolygonSet() so that welded
	 * points (same object referenced across multiple managers) are only shifted once.
	 * @param vectDiff  translation vector to apply
	 * @param moved     shared set tracking already-translated CubicPoint objects
	 */
	public void setCenterPosition(Point2D.Double vectDiff, java.util.HashSet<CubicPoint> moved) {
		double xShift = vectDiff.x;
		double yShift = vectDiff.y;
		for (int c = 0; c < curves.getCubicCurveTotal(); c++) {
			CubicCurve cv = curves.getCurve(c);
			CubicPoint[] p = cv.getPoints();
			for (int i = 0; i < p.length; i++) {
				if (!moved.add(p[i])) continue; // already moved this shared point
				p[i].setPos(new Point2D.Double(p[i].getPos().x + xShift, p[i].getPos().y + yShift));
				p[i].setOrigPosToPos();
			}
		}
	}
	/**
   //NOT USED ANYMORE - does not work
	public void readjustForOffset(double offset) {
		for (int c = 0; c<curves.getCubicCurveTotal();c++) {
			CubicCurve cv = curves.getCurve(c);
			CubicPoint[] p = cv.getPoints();
			for (int i = 0; i< p.length; i++) {
				System.out.println("Cubic Curve Manager readjust for offset - curve number: " + c);
				System.out.println("                                          point number: " + i);
				System.out.println("                                          offset value: " + offset);
				System.out.println("                                       original point position x: " + p[i].getPos().x);
				System.out.println("                                       original point position y: " + p[i].getPos().y);
				Point2D.Double nP = new Point2D.Double(p[i].getPos().x, p[i].getPos().y);
				Point2D.Double nP2 = polyManager.adjustForOffset (nP, offset);
				p[i].setPos(nP2);
				System.out.println("                                            new point position x: " + nP2.x);
				System.out.println("                                            new point position y: " + nP2.y);
				System.out.println(" ");
			}
		}
	}
	*/
	/**
	 * @return the curves
	 */
	public CubicCurvePolygon getCurves() {
		return curves;
	}
	/**
	 * @return the currentCurve
	 */
	public CubicCurve getCurrentCurve() {
		return currentCurve;
	}
	/**
	 * @return the curveCount
	 */
	public int getCurveCount() {
		return curveCount;
	}
	/**
	 * @return the pointCount
	 */
	public int getPointCount() {
		return pointCount;
	}
	/**
	 * @return the addPoints
	 */
	public boolean isAddPoints() {
		return addPoints;
	}
	/**
	 * @return the addPoints
	 */
	public void setAddPoints(boolean b) {
		addPoints = b;
	}

	/**
	 * @param curveCount the curveCount to set
	 */
	public void setCurveCount(int curveCount) {
		this.curveCount = curveCount;
	}
	/**
	 * @param pointCount the pointCount to set
	 */
	public void setPointCount(int pointCount) {
		this.pointCount = pointCount;
		//System.out.println("setting pointCount: "+ pointCount);
	}
	/**
	 * @param currentCurve the currentCurve to set
	 */
	public void setCurrentCurve(CubicCurve currentCurve) {
		this.currentCurve = currentCurve;
	}
	/**
	 * @return the currentBezierPos
	 */
	public Point2D.Double getCurrentBezierPos() {
		return currentBezierPos;
	}
	/**
	 * @param currentBezierPos the currentBezierPos to set
	 */
	public void setCurrentBezierPosition(Point2D.Double currentBezierPos) {
		this.currentBezierPos = currentBezierPos;
	}
	public void setCurrentCurveColor(Color strokeColor) {
		currentCurve.setStrokeCol(strokeColor);
	}
	

}
