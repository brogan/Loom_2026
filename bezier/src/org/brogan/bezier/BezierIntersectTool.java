package org.brogan.bezier;

import java.awt.Color;
import java.awt.geom.Point2D;
import java.util.*;

public class BezierIntersectTool {

    private static final double ROTATION_TOLERANCE_DEG = 5.0;
    private static final double WELD_EPSILON = 0.1;

    // ── Validation helpers ────────────────────────────────────────────────────

    private static int curveCount(CubicCurveManager m) {
        return m.getCurves().getArrayofCubicCurves().length;
    }

    private static Point2D.Double centroid(CubicCurveManager m) {
        CubicCurve[] cvs = m.getCurves().getArrayofCubicCurves();
        double sx = 0, sy = 0;
        for (CubicCurve cv : cvs) {
            Point2D.Double p = cv.getPoints()[0].getPos();
            sx += p.x; sy += p.y;
        }
        int n = cvs.length;
        return new Point2D.Double(sx / n, sy / n);
    }

    private static double orientationDeg(CubicCurveManager m) {
        Point2D.Double c  = centroid(m);
        Point2D.Double a0 = m.getCurves().getArrayofCubicCurves()[0].getPoints()[0].getPos();
        return Math.toDegrees(Math.atan2(a0.y - c.y, a0.x - c.x));
    }

    private static boolean isRotationCompatible(CubicCurveManager a, CubicCurveManager b) {
        double diff = Math.abs(orientationDeg(a) - orientationDeg(b)) % 360.0;
        if (diff > 180.0) diff = 360.0 - diff;
        return diff < ROTATION_TOLERANCE_DEG;
    }

    /** True if every anchor point of inner lies inside outer's polygon boundary. */
    private static boolean isFullyInside(CubicCurveManager outer, CubicCurveManager inner) {
        for (CubicCurve cv : inner.getCurves().getArrayofCubicCurves()) {
            if (!outer.containsPoint(cv.getPoints()[0].getPos())) return false;
        }
        return true;
    }

    /**
     * Returns {outer, inner} if one polygon is fully inside the other, else null.
     */
    private static CubicCurveManager[] identifyOuterInner(CubicCurveManager a, CubicCurveManager b) {
        if (isFullyInside(a, b)) return new CubicCurveManager[]{a, b};
        if (isFullyInside(b, a)) return new CubicCurveManager[]{b, a};
        return null;
    }

    // ── Geometry helpers ──────────────────────────────────────────────────────

    private static Point2D.Double lerp(Point2D.Double a, Point2D.Double b, double t) {
        return new Point2D.Double(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
    }

    private static Point2D.Double[] straightEdgePts(Point2D.Double from, Point2D.Double to) {
        return new Point2D.Double[]{
            from, lerp(from, to, 1.0 / 3.0), lerp(from, to, 2.0 / 3.0), to
        };
    }

    // ── Weld (same proximity scan used by BezierKnifeTool) ────────────────────

    private static void weldCoincidentPoints(CubicCurvePolygonManager polygonManager) {
        WeldRegistry wr = polygonManager.getWeldRegistry();
        int count = polygonManager.getPolygonCount();
        List<CubicCurveManager> mgrOf  = new ArrayList<>();
        List<CubicPoint>        allPts = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            CubicCurveManager mgr = polygonManager.getManager(i);
            for (CubicCurve cv : mgr.getCurves().getArrayofCubicCurves()) {
                for (CubicPoint pt : cv.getPoints()) {
                    if (pt == null) continue;
                    mgrOf.add(mgr);
                    allPts.add(pt);
                }
            }
        }
        double eps2 = WELD_EPSILON * WELD_EPSILON;
        int n = allPts.size();
        for (int a = 0; a < n; a++) {
            for (int b = a + 1; b < n; b++) {
                if (mgrOf.get(a) == mgrOf.get(b)) continue;
                if (allPts.get(a) == allPts.get(b)) continue;
                Point2D.Double pa = allPts.get(a).getPos();
                Point2D.Double pb = allPts.get(b).getPos();
                double dx = pa.x - pb.x, dy = pa.y - pb.y;
                if (dx * dx + dy * dy < eps2) {
                    wr.registerWeld(allPts.get(a), allPts.get(b));
                }
            }
        }
    }

    // ── Pre-check (no mutation) ───────────────────────────────────────────────

    /** Returns true if performIntersect would succeed for these two managers. */
    public static boolean canPerform(CubicCurvePolygonManager polygonManager,
                                     CubicCurveManager a, CubicCurveManager b) {
        int N = curveCount(a);
        if (N != curveCount(b) || N < 3) return false;
        if (!isRotationCompatible(a, b)) return false;
        return identifyOuterInner(a, b) != null;
    }

    // ── Main entry ────────────────────────────────────────────────────────────

    /**
     * Validates and performs the intersect operation.
     * Validation rules:
     *   - Exactly the two passed managers are used (caller ensures selection count == 2)
     *   - Same number of anchor points (curves), minimum 3
     *   - Rotation difference < 5 degrees
     *   - One polygon fully inside the other (all its anchors inside the boundary)
     *
     * On success:
     *   - Both originals removed (outer always; inner removed unless keepInner)
     *   - N quad polygons added spanning the annular region
     *   - Adjacent spokes welded via proximity scan
     *   - selectedPolygons cleared and repopulated with the new quads
     *
     * Returns false (no changes) if validation fails, true on success.
     */
    public static boolean performIntersect(
            CubicCurvePolygonManager polygonManager,
            CubicCurveManager a, CubicCurveManager b,
            Color strokeColor, boolean keepInner,
            List<CubicCurveManager> selectedPolygons) {

        // ── 1. Same anchor count ──────────────────────────────────────────────
        int N = curveCount(a);
        if (N != curveCount(b) || N < 3) {
            System.out.println("BezierIntersectTool: anchor count mismatch or < 3");
            return false;
        }

        // ── 2. Rotation compatibility ─────────────────────────────────────────
        if (!isRotationCompatible(a, b)) {
            System.out.println("BezierIntersectTool: rotation difference exceeds 5 degrees");
            return false;
        }

        // ── 3. One fully inside the other ─────────────────────────────────────
        CubicCurveManager[] oi = identifyOuterInner(a, b);
        if (oi == null) {
            System.out.println("BezierIntersectTool: neither polygon is fully inside the other");
            return false;
        }
        CubicCurveManager outer = oi[0];
        CubicCurveManager inner = oi[1];

        // ── 4. Build N quad polygons ──────────────────────────────────────────
        //
        // Each quad i spans:
        //   Curve 0 (outer edge i):   outer anchor[i]   → outer anchor[i+1]  (bezier from outer)
        //   Curve 1 (right spoke):    outer anchor[i+1] → inner anchor[i+1]  (straight)
        //   Curve 2 (inner edge rev): inner anchor[i+1] → inner anchor[i]    (bezier from inner, reversed)
        //   Curve 3 (left spoke):     inner anchor[i]   → outer anchor[i]    (straight, closes loop)
        //
        // pts layout: N curves × 4 points = 16 points.
        // For curves 1-3, pts[curveStart] (anchor0) is ignored by setAllPoints —
        // the anchor is linked to the previous curve's anchor3.  We set it anyway
        // for clarity; setAllPoints will overwrite the reference.

        CubicCurve[] oCvs = outer.getCurves().getArrayofCubicCurves();
        CubicCurve[] iCvs = inner.getCurves().getArrayofCubicCurves();
        List<Point2D.Double[]> quads = new ArrayList<>();

        for (int i = 0; i < N; i++) {
            CubicPoint[] oP = oCvs[i].getPoints();   // [oA_i, oC1, oC2, oA_i+1]
            CubicPoint[] iP = iCvs[i].getPoints();   // [iA_i, iC1, iC2, iA_i+1]

            Point2D.Double oAi   = oP[0].getPos();   // outer anchor i
            Point2D.Double oAi1  = oP[3].getPos();   // outer anchor i+1
            Point2D.Double iAi   = iP[0].getPos();   // inner anchor i
            Point2D.Double iAi1  = iP[3].getPos();   // inner anchor i+1

            Point2D.Double[] rSpoke = straightEdgePts(oAi1, iAi1);
            Point2D.Double[] lSpoke = straightEdgePts(iAi,  oAi);

            Point2D.Double[] pts = new Point2D.Double[16];

            // Curve 0: outer edge i (forward)
            pts[0] = oAi;            pts[1] = oP[1].getPos(); pts[2] = oP[2].getPos(); pts[3] = oAi1;

            // Curve 1: right spoke (straight)
            pts[4] = rSpoke[0]; pts[5] = rSpoke[1]; pts[6] = rSpoke[2]; pts[7] = rSpoke[3];

            // Curve 2: inner edge i reversed
            pts[8]  = iAi1;           pts[9]  = iP[2].getPos(); pts[10] = iP[1].getPos(); pts[11] = iAi;

            // Curve 3: left spoke (straight, closes back to oAi)
            pts[12] = lSpoke[0]; pts[13] = lSpoke[1]; pts[14] = lSpoke[2]; pts[15] = lSpoke[3];

            quads.add(pts);
        }

        // ── 5. Find indices of originals before any removal ───────────────────
        int outerIdx = -1, innerIdx = -1;
        int count = polygonManager.getPolygonCount();
        for (int i = 0; i < count; i++) {
            CubicCurveManager m = polygonManager.getManager(i);
            if (m == outer) outerIdx = i;
            if (m == inner) innerIdx = i;
        }

        // ── 6. Remove originals (descending index to avoid shift) ─────────────
        if (keepInner) {
            polygonManager.removeManagerAtIndex(outerIdx);
        } else {
            int hi = Math.max(outerIdx, innerIdx);
            int lo = Math.min(outerIdx, innerIdx);
            polygonManager.removeManagerAtIndex(hi);
            polygonManager.removeManagerAtIndex(lo);
        }

        // ── 7. Add quad managers ──────────────────────────────────────────────
        selectedPolygons.clear();
        for (Point2D.Double[] pts : quads) {
            CubicCurveManager nm = polygonManager.addClosedFromPoints(pts, strokeColor);
            nm.setSelected(true);
            selectedPolygons.add(nm);
        }

        // ── 8. Weld all coincident boundary points ───────────────────────────
        // Adjacent quads share spoke endpoints and control points at exactly the
        // same positions — the proximity scan registers all weld links in one pass.
        // If keepInner, the retained inner polygon's anchors are also coincident
        // with the quads' inner-edge anchors and will be welded automatically.
        weldCoincidentPoints(polygonManager);

        return true;
    }
}
