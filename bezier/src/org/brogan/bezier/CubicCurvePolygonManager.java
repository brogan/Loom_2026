package org.brogan.bezier;

import java.awt.AlphaComposite;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.geom.Point2D;
import java.util.ArrayList;
import java.util.List;

import org.brogan.util.Formulas;

public class CubicCurvePolygonManager {

	private ArrayList<CubicCurveManager> cubicCurveManagers = new ArrayList<CubicCurveManager>();
	private CubicCurvePolygonSet polys;//total set of polygons
	private Color strokeColor;
	private WeldRegistry weldRegistry = new WeldRegistry();
	private LayerManager layerManager;

	public WeldRegistry getWeldRegistry() { return weldRegistry; }

	public CubicCurvePolygonManager(Color sC) {
		this(sC, null);
	}

	public CubicCurvePolygonManager(Color sC, LayerManager lm) {
		polys = new CubicCurvePolygonSet(100);//potentially 100 polygons in CubicCurvesPolygonSet (upper limit)
		strokeColor = sC;
		layerManager = lm;
		addManager();
	}

	public void draw(Graphics2D g2D) {
		g2D.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

		int totPolys = polys.getPolygonTotal();
		// Guard against transient mismatch: polys and cubicCurveManagers are updated
		// in two separate steps, so the run-loop thread can briefly see totPolys > managersSize-1.
		int drawUntil = Math.min(totPolys, cubicCurveManagers.size() - 1);
		if (layerManager == null) {
			// No layer system — draw everything as before
			for (int i = 0; i <= drawUntil; i++) {
				cubicCurveManagers.get(i).draw(g2D);
			}
			return;
		}

		int activeId = layerManager.getActiveLayerId();
		for (int i = 0; i <= drawUntil; i++) {
			CubicCurveManager m = cubicCurveManagers.get(i);
			if (i == totPolys) {
				// Active drawing manager — always show
				m.draw(g2D);
				continue;
			}
			Layer layer = layerManager.getLayerById(m.getLayerId());
			if (layer == null || !layer.isVisible()) continue;
			if (m.getLayerId() == activeId) {
				m.draw(g2D);
			} else {
				Graphics2D g = (Graphics2D) g2D.create();
				g.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.2f));
				m.draw(g);
				g.dispose();
			}
		}
	}
	/**
	 * add manager to list of cubic curve managers
	 */
	public void addManager () {
		CubicCurveManager m = new CubicCurveManager(strokeColor, this);
		if (layerManager != null) m.setLayerId(layerManager.getActiveLayerId());
		cubicCurveManagers.add(m);
	}
	public void clearManagers () {
		int totCurveManagers = cubicCurveManagers.size();
		System.out.println("CubicCurvePolygonManager, clearManagers, cubicCurveManagers size: " + totCurveManagers);
		weldRegistry.clear();
		cubicCurveManagers.clear();
		polys.clearPolygonSet();
		System.out.println("CubicCurvePolygonManager, clearManagers, cubicCurveManagers size after clearing: " + cubicCurveManagers.size());
		addManager();
		System.out.println("CubicCurvePolygonManager, clearManagers, cubicCurveManagers size after adding new manager: " + cubicCurveManagers.size());

	}
	public CubicCurveManager getManager (int i) {
		return cubicCurveManagers.get(i);
	}
	/**
	 * add polygon - sent up from cubicCurveManager when polygon closed
	 */
	public void addPolygon(CubicCurvePolygon cP) {
		polys.addPolygon(cP);
	}
	/**
	 * @return the polygons
	 */
	public CubicCurvePolygonSet getPolygons() {
		return polys;
	}
	/**
	 * @return the current polygon
	 */
	public CubicCurvePolygon getCurrentPolygon() {
		int currIndex = getPolygonCount();
		//System.out.println("CubicCurvePolygonManager, getCurrentPolygon, total polygons provides currIndex to manager: " + currIndex);
		//System.out.println("CubicCurvePolygonManager, getCurrentPolygon, total number of CubicCurveManagers: " + cubicCurveManagers.size());
		return cubicCurveManagers.get(currIndex).getCurves();
	}
	/**
	 * @return the polygon at index
	 */
	public CubicCurvePolygon getPolygon(int index) {
		return cubicCurveManagers.get(index).getCurves();
	}
	/**
	 * @return the curveCount
	 */
	public int getPolygonCount() {
		return polys.getPolygonTotal();
	}
	/**
	 *
	 * @return full array of points in all polygons
	 */
	public CubicPoint[] getArrayOfPoints() {
		ArrayList <CubicPoint>points = new ArrayList <CubicPoint>();
		int totPolys = polys.getPolygonTotal();
		for (int p=0;p<totPolys;p++) {
			CubicCurve[] curves = polys.getPolygon(p).getArrayofCubicCurves();
			for (int c = 0; c<curves.length; c++) {
				CubicCurve curve = curves[c];
				CubicPoint[] pts = curve.getPoints();
				for (int j = 0; j<pts.length; j++) {
					points.add(new CubicPoint((pts[j].getPos()), pts[j].getType()));//need to create new points to avoid normalising shared points multiple times
				}
			}
		}
		CubicPoint[] cps = new CubicPoint[points.size()];
		return points.toArray(cps);
	}
	/**
	 * adjust for small offset value of grid from drawPanel (called from PolygonSetXML createXML and cubicCurvePanel loadPolygonSet)
	 */
	public Point2D.Double adjustForOffset (Point2D.Double p, Double offset) {
		Double nX = (p.x-offset);//subtract the offset x from point pos
		Double nY = (p.y-offset);//subtract the offset y from point pos
		return new Point2D.Double(nX, nY);
	}

	public void centerPolygonSet(Point2D.Double screenCentre) {
		Point2D.Double origin = new Point2D.Double(0,0);
		origin.x += screenCentre.x;
		origin.y += screenCentre.y;
		int totPolys = polys.getPolygonTotal();
		if (totPolys == 0) return;
		Point2D.Double[] points = new Point2D.Double [totPolys];//create a list of the average centers of each poly
		for (int i=0;i<totPolys;i++) {
			points[i] = cubicCurveManagers.get(i).getAverageXY();
		}

		double pXsum = 0;
		double pYsum = 0;

		for (int i=0;i<points.length;i++) {//add up those averages
			pXsum += points[i].x;
			pYsum += points[i].y;
		}
		pXsum = pXsum / points.length;//divide by the total number of polys
		pYsum = pYsum / points.length;

		double pXvect = origin.x - pXsum;
		double pYvect = origin.y - pYsum;

		// One shared HashSet so welded points (same Java object across managers) move only once
		java.util.HashSet<CubicPoint> moved = new java.util.HashSet<CubicPoint>();
		for (int i=0;i<totPolys;i++) {
			cubicCurveManagers.get(i).setCenterPosition(new Point2D.Double(pXvect, pYvect), moved);
		}
	}

	/**
	 * Remove the closed polygon and its manager at the given index.
	 * The index must be in range [0, getPolygonCount()-1] (i.e. a closed polygon, not the active drawing manager).
	 */
	public void removeManagerAtIndex(int i) {
		// Unregister all points of this manager from the weld registry
		CubicCurve[] curves = cubicCurveManagers.get(i).getCurves().getArrayofCubicCurves();
		for (CubicCurve cv : curves)
			for (CubicPoint pt : cv.getPoints())
				if (pt != null) weldRegistry.unregisterPoint(pt);
		cubicCurveManagers.remove(i);
		polys.removePolygon(i);
	}

	/**
	 * Create a deep copy of source offset by (offsetX, offsetY) pixels.
	 * The duplicate is inserted before the active drawing manager so the
	 * manager/polygon index correspondence is preserved.
	 * Returns the new CubicCurveManager so the caller can select it.
	 */
	public CubicCurveManager addDuplicateOf(CubicCurveManager source, double offsetX, double offsetY) {
		CubicCurve[] cArray = source.getCurves().getArrayofCubicCurves();
		int N = cArray.length;

		Point2D.Double[] pts = new Point2D.Double[N * 4];
		int idx = 0;
		for (CubicCurve cv : cArray) {
			CubicPoint[] p = cv.getPoints();
			pts[idx++] = new Point2D.Double(p[0].getPos().x + offsetX, p[0].getPos().y + offsetY);
			pts[idx++] = new Point2D.Double(p[1].getPos().x + offsetX, p[1].getPos().y + offsetY);
			pts[idx++] = new Point2D.Double(p[2].getPos().x + offsetX, p[2].getPos().y + offsetY);
			pts[idx++] = new Point2D.Double(p[3].getPos().x + offsetX, p[3].getPos().y + offsetY);
		}

		CubicCurveManager newManager = new CubicCurveManager(strokeColor, this);
		if (layerManager != null) newManager.setLayerId(layerManager.getActiveLayerId());
		if (source.getIsClosed()) {
			// Closed polygon: link last anchor back to first (circular topology)
			newManager.setAllPoints(pts, strokeColor);
			newManager.setIsClosed(true);
		} else {
			// Open curve or single edge: do NOT link last anchor back to first
			newManager.setOpenPoints(pts, strokeColor);
		}
		newManager.setCurrentBezierPosition(newManager.getAverageXY());

		// Register in polys and insert before the last (active drawing) manager
		// so manager index i always corresponds to polys index i.
		polys.addPolygon(newManager.getCurves());
		cubicCurveManagers.add(cubicCurveManagers.size() - 1, newManager);

		return newManager;
	}

	
	/**
	 * Create a new closed polygon manager from an array of N*4 point positions.
	 * The format mirrors setAllPoints(): pts[i*4..i*4+3] = anchor0, ctrl1, ctrl2, anchor1
	 * for each of N curves.  The last curve's anchor1 is automatically shared with
	 * curve 0's anchor0 by setAllPoints().
	 * Used by BezierSvgImporter to add imported SVG paths to the canvas.
	 * Returns the new CubicCurveManager.
	 */
	public CubicCurveManager addClosedFromPoints(Point2D.Double[] pts, Color strokeColor) {
		CubicCurveManager newManager = new CubicCurveManager(strokeColor, this);
		if (layerManager != null) newManager.setLayerId(layerManager.getActiveLayerId());
		newManager.setAllPoints(pts, strokeColor);
		newManager.setIsClosed(true);
		newManager.setCurrentBezierPosition(newManager.getAverageXY());
		polys.addPolygon(newManager.getCurves());
		cubicCurveManagers.add(cubicCurveManagers.size() - 1, newManager);
		return newManager;
	}

	/**
	 * Create a new single-edge (open) polygon manager from 4 point positions.
	 * Unlike addDuplicateOf, this does not close the last anchor back to the first.
	 * Used when duplicating a selected edge in edge-selection mode.
	 * Returns the new CubicCurveManager.
	 */
	public CubicCurveManager addSingleEdge(Point2D.Double[] pts, Color strokeColor) {
		CubicCurveManager newManager = new CubicCurveManager(strokeColor, this);
		if (layerManager != null) newManager.setLayerId(layerManager.getActiveLayerId());
		newManager.setSingleEdgePoints(pts, strokeColor);
		newManager.setIsClosed(false);
		newManager.setCurrentBezierPosition(newManager.getAverageXY());
		polys.addPolygon(newManager.getCurves());
		cubicCurveManagers.add(cubicCurveManagers.size() - 1, newManager);
		return newManager;
	}

	/**
	//not used anymore, does not work
	public void readjustForOffset(Double offset) {
		for (int i = 0; i < cubicCurveManagers.size(); i++) {
			cubicCurveManagers.get(i).readjustForOffset(offset);
		}
	}
	*/

	
	/**
	 * create simpler easier to read versions of point values for xml export (PolygonSetXML - createXML)
	 */
	public Point2D.Double simplifyPointValue(Point2D.Double p) {
		//scale pos values so that they can be represented temporarily as ints
		//this makes point values simple and easier to read than straight double values
		int cX = (int)Math.round(p.x*100);
		int cY = (int)Math.round(p.y*100);
		//then convert them back to simplified doubles for normalised storage (values between 0 and 1, but in this case between -.5 and .5)
		double vX = ((double)(cX))/100;
		double vY = ((double)(cY))/100;
		return new Point2D.Double(vX, vY);
	}
	
	/**
	 * normalise points and shift to center
	 * @param points
	 * @param maxXVal width
	 * @param maxYVal height
	 */
	public void normalisePoints(CubicPoint[] points, int maxXVal, int maxYVal) {
		for (int p=0;p<points.length;p++) {
			double nX = (points[p].getPos().x/(double)maxXVal)-.5;
			double nY = (points[p].getPos().y/(double)maxYVal)-.5;
			points[p].setPos(new Point2D.Double(nX, nY));
		}
	}
	/**
	 * denormalise points and shift points back to where they were
	 * @param points
	 * @param maxXVal width
	 * @param maxYVal height
	 */
	public void deNormalisePoints(CubicPoint[] points, int maxXVal, int maxYVal) {
		//System.out.println("CubicCurvePolygonManager, denormalising point values");
		for (int p=0;p<points.length;p++) {
			double nX = (points[p].getPos().x * (double)maxXVal)+maxXVal/2;
			double nY = (points[p].getPos().y * (double)maxYVal)+maxYVal/2;
			//System.out.println("");
			//System.out.println("CubicCurvePolygonManager, denormalising point values, new X: " + nX + "   old X: " + points[p].getPos().x);
			//System.out.println("CubicCurvePolygonManager, denormalising point values, new Y: " + nY + "   old Y: " + points[p].getPos().y);
			points[p].setPos(new Point2D.Double(nX, nY));
		}
	}
	/**
	 * Restore the full polygon geometry from a GeometrySnapshot.
	 * Clears all existing managers and rebuilds from the snapshot data,
	 * then re-registers cross-manager weld links.
	 */
	public void restoreFromSnapshot(GeometrySnapshot snap, java.awt.Color strokeColor) {
		// Clear without the auto-addManager() that clearManagers() triggers
		weldRegistry.clear();
		cubicCurveManagers.clear();
		polys.clearPolygonSet();

		// Rebuild each polygon manager
		for (GeometrySnapshot.ManagerSnap ms : snap.managers) {
			CubicCurveManager m = new CubicCurveManager(strokeColor, this);
			m.setLayerId(ms.layerId);
			int n = ms.curveCount;
			Point2D.Double[] pts = new Point2D.Double[n * 4];
			for (int i = 0; i < n * 4; i++) {
				pts[i] = new Point2D.Double(ms.px[i], ms.py[i]);
			}
			if (ms.isSingleEdge) {
				m.setSingleEdgePoints(pts, strokeColor);
				m.setIsClosed(false);
			} else if (ms.isClosed) {
				m.setAllPoints(pts, strokeColor);
				m.setIsClosed(true);
			} else {
				m.setOpenPoints(pts, strokeColor);
				m.setIsClosed(false);
			}
			m.setAnchorPressures(ms.anchorPressures);
			polys.addPolygon(m.getCurves());
			cubicCurveManagers.add(m);
		}

		// Add a fresh empty active-drawing manager at the end
		cubicCurveManagers.add(new CubicCurveManager(strokeColor, this));

		// Restore cross-manager weld links by index
		for (GeometrySnapshot.WeldLinkSnap wl : snap.weldLinks) {
			CubicPoint pt0 = cubicCurveManagers.get(wl.mgr0).getCurves().getCurve(wl.cv0).getPoints()[wl.slot0];
			CubicPoint pt1 = cubicCurveManagers.get(wl.mgr1).getCurves().getCurve(wl.cv1).getPoints()[wl.slot1];
			if (pt0 != null && pt1 != null) weldRegistry.registerWeld(pt0, pt1);
		}
	}

	/**
	 * Update the active drawing manager's layerId to match the current active layer.
	 * Call this whenever the active layer is switched so that the next polygon
	 * closed goes to the correct layer.
	 */
	public void syncActiveDrawingManagerLayer() {
		if (layerManager == null) return;
		int idx = polys.getPolygonTotal(); // drawing manager is always at this index
		if (idx < cubicCurveManagers.size()) {
			cubicCurveManagers.get(idx).setLayerId(layerManager.getActiveLayerId());
		}
	}

	/**
	 * Create a new open curve manager from an array of N*4 point positions.
	 * Like addClosedFromPoints but does not link the last anchor back to the first.
	 */
	public CubicCurveManager addOpenCurveFromPoints(Point2D.Double[] pts, Color strokeColor) {
		CubicCurveManager newManager = new CubicCurveManager(strokeColor, this);
		if (layerManager != null) newManager.setLayerId(layerManager.getActiveLayerId());
		newManager.setOpenPoints(pts, strokeColor);
		newManager.setCurrentBezierPosition(newManager.getAverageXY());
		polys.addPolygon(newManager.getCurves());
		cubicCurveManagers.add(cubicCurveManagers.size() - 1, newManager);
		return newManager;
	}

	/** Returns true if the polygon manager at index i is a closed polygon. */
	public boolean isClosedAt(int i) {
		return cubicCurveManagers.get(i).getIsClosed();
	}

	/** Return all closed polygon managers whose layerId matches the given id. */
	public List<CubicCurveManager> getManagersForLayer(int layerId) {
		List<CubicCurveManager> result = new ArrayList<>();
		int count = polys.getPolygonTotal();
		for (int i = 0; i < count; i++) {
			CubicCurveManager m = cubicCurveManagers.get(i);
			if (m.getLayerId() == layerId) result.add(m);
		}
		return result;
	}

	public void replacePoints(CubicPoint currPoint, CubicPoint newPoint) {
		int totPolys = polys.getPolygonTotal();
		for (int p=0;p<totPolys;p++) {
			ArrayList <CubicCurve> curves = polys.getPolygon(p).getCurves();
			for (int c = 0; c<curves.size(); c++) {
				CubicCurve curve = curves.get(c);
				CubicPoint[] pts = curve.getPoints();
				for (int j = 0; j<pts.length; j++) {
					if (pts[j].getPos() == currPoint.getPos()) {
						if (pts[j] != newPoint) {
							//System.out.println("");
							//System.out.println("CubicCurvePolygonManager, replacePoints, current curve: " +  c + "   current point: " + j);
							//System.out.println("CubicCurvePolygonManager, replacePoints, current point: " +  pts[j] + "   new point: " + newPoint);
							curves.get(c).setPoint(j, newPoint);
						} else {
							//System.out.println("CubicCurvePolygonManager, replacePoints, IDENTICAL POINTS, current point: " +  pts[j] + "   dest point: " + newPoint);
						}
					}
				}
			}
		}
	}
	
}
