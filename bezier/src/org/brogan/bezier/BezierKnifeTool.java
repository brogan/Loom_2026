package org.brogan.bezier;

import java.awt.Color;
import java.awt.geom.Point2D;
import java.util.*;

public class BezierKnifeTool {

    public static class Intersection {
        public final int    curveIndex;
        public final double t;
        public final Point2D.Double pt;
        public final double globalT;  // curveIndex + t, used for ordering
        public Intersection(int ci, double t, Point2D.Double pt) {
            this.curveIndex = ci; this.t = t; this.pt = pt; this.globalT = ci + t;
        }
    }

    // Line equation: a*x + b*y + c = 0
    private static double[] lineCoeffs(Point2D.Double p1, Point2D.Double p2) {
        double a = -(p2.y - p1.y), b = p2.x - p1.x;
        return new double[]{ a, b, -(a * p1.x + b * p1.y) };
    }

    private static double signedDist(Point2D.Double p, double a, double b, double c) {
        return a * p.x + b * p.y + c;
    }

    // Recursive de Casteljau subdivision on signed distances to find curve-line intersections
    private static void findRootsRec(double[] d, double tMin, double tMax,
                                     int ci, CubicCurve cv, List<Intersection> out) {
        boolean allPos = d[0] >= 0 && d[1] >= 0 && d[2] >= 0 && d[3] >= 0;
        boolean allNeg = d[0] <= 0 && d[1] <= 0 && d[2] <= 0 && d[3] <= 0;
        if (allPos || allNeg) return;
        if (tMax - tMin < 1e-6) {
            double tm = (tMin + tMax) / 2;
            out.add(new Intersection(ci, tm, evalBezier(cv, tm)));
            return;
        }
        double tMid = (tMin + tMax) / 2;
        double d01  = (d[0] + d[1]) / 2, d12 = (d[1] + d[2]) / 2, d23 = (d[2] + d[3]) / 2;
        double d012 = (d01 + d12) / 2,   d123 = (d12 + d23) / 2,  d0123 = (d012 + d123) / 2;
        findRootsRec(new double[]{d[0], d01, d012, d0123}, tMin, tMid, ci, cv, out);
        findRootsRec(new double[]{d0123, d123, d23, d[3]}, tMid, tMax, ci, cv, out);
    }

    private static Point2D.Double evalBezier(CubicCurve cv, double t) {
        CubicPoint[] p = cv.getPoints();
        double mt = 1 - t;
        return new Point2D.Double(
            mt*mt*mt*p[0].getPos().x + 3*mt*mt*t*p[1].getPos().x
                + 3*mt*t*t*p[2].getPos().x + t*t*t*p[3].getPos().x,
            mt*mt*mt*p[0].getPos().y + 3*mt*mt*t*p[1].getPos().y
                + 3*mt*t*t*p[2].getPos().y + t*t*t*p[3].getPos().y);
    }

    // Remove near-duplicate intersections (same globalT within 0.015)
    private static List<Intersection> deduplicate(List<Intersection> raw) {
        List<Intersection> out = new ArrayList<>();
        for (Intersection i : raw) {
            boolean dup = false;
            for (Intersection j : out)
                if (Math.abs(i.globalT - j.globalT) < 0.015) { dup = true; break; }
            if (!dup) out.add(i);
        }
        return out;
    }

    // de Casteljau split at t — returns [left[4], right[4]]
    public static Point2D.Double[][] casteljauSplit(Point2D.Double[] p, double t) {
        Point2D.Double q0 = lerp(p[0], p[1], t), q1 = lerp(p[1], p[2], t), q2 = lerp(p[2], p[3], t);
        Point2D.Double r0 = lerp(q0, q1, t),     r1 = lerp(q1, q2, t);
        Point2D.Double s  = lerp(r0, r1, t);
        return new Point2D.Double[][]{ {p[0], q0, r0, s}, {s, r1, q2, p[3]} };
    }

    public static Point2D.Double lerp(Point2D.Double a, Point2D.Double b, double t) {
        return new Point2D.Double(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
    }

    private static Point2D.Double[] getCurvePts(CubicCurve cv) {
        CubicPoint[] p = cv.getPoints();
        return new Point2D.Double[]{ p[0].getPos(), p[1].getPos(), p[2].getPos(), p[3].getPos() };
    }

    // Sub-curve from t0 to t1 on cv (0 <= t0 < t1 <= 1)
    private static Point2D.Double[] extractSubCurve(CubicCurve cv, double t0, double t1) {
        Point2D.Double[] right = casteljauSplit(getCurvePts(cv), t0)[1];
        if (t1 >= 1.0 - 1e-9) return right;
        double t1p = (t1 - t0) / (1.0 - t0);
        return casteljauSplit(right, t1p)[0];
    }

    // Build the N*4 pts array for the arc from iA to iB (forward direction), closed by a
    // straight edge from iB back to iA.
    private static Point2D.Double[] buildPiecePoints(CubicCurveManager mgr,
                                                      Intersection iA, Intersection iB) {
        CubicCurve[] cvs = mgr.getCurves().getArrayofCubicCurves();
        int N = cvs.length, ia = iA.curveIndex, ib = iB.curveIndex;
        double ta = iA.t, tb = iB.t;
        List<Point2D.Double[]> segs = new ArrayList<>();

        if (ia == ib && ta < tb) {
            // Both on same curve — extract middle sub-segment
            segs.add(extractSubCurve(cvs[ia], ta, tb));
        } else if (ia <= ib) {
            // Forward arc: right-half of ia, middle curves, left-half of ib
            segs.add(casteljauSplit(getCurvePts(cvs[ia]), ta)[1]);
            for (int k = ia + 1; k < ib; k++) segs.add(getCurvePts(cvs[k]));
            segs.add(casteljauSplit(getCurvePts(cvs[ib]), tb)[0]);
        } else {
            // Wrap-around arc (handles ia > ib AND ia == ib with ta >= tb for the last pair)
            segs.add(casteljauSplit(getCurvePts(cvs[ia]), ta)[1]);
            for (int k = ia + 1; k < N; k++) segs.add(getCurvePts(cvs[k]));
            for (int k = 0;      k < ib; k++) segs.add(getCurvePts(cvs[k]));
            segs.add(casteljauSplit(getCurvePts(cvs[ib]), tb)[0]);
        }

        // Straight closing edge Ib → Ia
        segs.add(new Point2D.Double[]{
            iB.pt, lerp(iB.pt, iA.pt, 1.0 / 3.0), lerp(iB.pt, iA.pt, 2.0 / 3.0), iA.pt });

        Point2D.Double[] pts = new Point2D.Double[segs.size() * 4];
        for (int s = 0; s < segs.size(); s++) System.arraycopy(segs.get(s), 0, pts, s * 4, 4);
        return pts;
    }

    // ── Auto-weld ─────────────────────────────────────────────────────────────

    private static final double WELD_EPSILON = 0.1; // pixels

    /**
     * After a cut, scan every pair of CubicPoints across all polygon managers.
     * Any two points from DIFFERENT managers that sit within WELD_EPSILON of each
     * other are welded together. This handles:
     *   - Pieces from the same cut (their straight closing edges are bit-exact mirrors)
     *   - Pieces from a second cut that include a prior cut-line in their arc (3×3 grid etc.)
     * No positional snapping is done — the knife arithmetic already guarantees exact
     * coincidence, and the weld keeps the boundary locked under subsequent moves.
     */
    private static void weldCoincidentPoints(CubicCurvePolygonManager polygonManager) {
        WeldRegistry wr = polygonManager.getWeldRegistry();
        int count = polygonManager.getPolygonCount();

        // Flat lists: parallel arrays (manager, point) for every CubicPoint in every curve
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
                if (mgrOf.get(a) == mgrOf.get(b)) continue;   // same polygon — skip
                if (allPts.get(a) == allPts.get(b)) continue;  // same object — skip
                Point2D.Double pa = allPts.get(a).getPos();
                Point2D.Double pb = allPts.get(b).getPos();
                double dx = pa.x - pb.x, dy = pa.y - pb.y;
                if (dx*dx + dy*dy < eps2) {
                    wr.registerWeld(allPts.get(a), allPts.get(b));
                }
            }
        }
    }

    /**
     * Main entry — cuts all polygons the line crosses.
     * preKnifeSelection: managers selected before knife mode (read-only)
     * selectedPolygons: cleared and repopulated with newly created "was-selected" managers
     */
    public static void performCut(
            CubicCurvePolygonManager polygonManager,
            Point2D.Double lineA, Point2D.Double lineB,
            Color strokeColor,
            Set<CubicCurveManager> preKnifeSelection,
            List<CubicCurveManager> selectedPolygons) {

        double[] abc = lineCoeffs(lineA, lineB);
        double a = abc[0], b = abc[1], c = abc[2];
        int count = polygonManager.getPolygonCount();

        List<Integer>                toRemove    = new ArrayList<>();
        List<List<Point2D.Double[]>> allPieces   = new ArrayList<>();
        List<Boolean>                wasSelected = new ArrayList<>();

        for (int i = 0; i < count; i++) {
            CubicCurveManager mgr = polygonManager.getManager(i);
            CubicCurve[] cvs = mgr.getCurves().getArrayofCubicCurves();
            List<Intersection> raw = new ArrayList<>();
            for (int ci = 0; ci < cvs.length; ci++) {
                CubicPoint[] pts = cvs[ci].getPoints();
                double[] d = {
                    signedDist(pts[0].getPos(), a, b, c), signedDist(pts[1].getPos(), a, b, c),
                    signedDist(pts[2].getPos(), a, b, c), signedDist(pts[3].getPos(), a, b, c) };
                findRootsRec(d, 0, 1, ci, cvs[ci], raw);
            }
            raw.sort(Comparator.comparingDouble(x -> x.globalT));
            List<Intersection> hits = deduplicate(raw);

            // Filter to intersections that lie within the drawn segment [lineA, lineB].
            // The infinite-line equation used above also catches geometry far beyond the
            // endpoints; projecting each hit onto the segment and discarding those outside
            // [0,1] restricts cuts to only what the segment actually crosses.
            double segDX = lineB.x - lineA.x, segDY = lineB.y - lineA.y;
            double segLen2 = segDX * segDX + segDY * segDY;
            if (segLen2 > 1e-10) {
                List<Intersection> inSeg = new ArrayList<>();
                for (Intersection ix : hits) {
                    double s = ((ix.pt.x - lineA.x) * segDX + (ix.pt.y - lineA.y) * segDY) / segLen2;
                    if (s >= -0.02 && s <= 1.02) inSeg.add(ix);
                }
                hits = inSeg;
            }

            if (hits.size() < 2 || hits.size() % 2 != 0) continue;

            boolean sel = preKnifeSelection != null && preKnifeSelection.contains(mgr);
            List<Point2D.Double[]> pieces = new ArrayList<>();
            int NI = hits.size();
            for (int k = 0; k < NI; k++)
                pieces.add(buildPiecePoints(mgr, hits.get(k), hits.get((k + 1) % NI)));
            toRemove.add(i);
            allPieces.add(pieces);
            wasSelected.add(sel);
        }

        if (toRemove.isEmpty()) return;

        // Remove in descending index order to preserve lower indices
        List<Integer> desc = new ArrayList<>(toRemove);
        Collections.sort(desc, Collections.reverseOrder());
        for (int idx : desc) polygonManager.removeManagerAtIndex(idx);

        // Add new piece managers; track which are "selected"
        selectedPolygons.clear();
        for (int g = 0; g < allPieces.size(); g++) {
            boolean sel = wasSelected.get(g);
            for (Point2D.Double[] pts : allPieces.get(g)) {
                CubicCurveManager nm = polygonManager.addClosedFromPoints(pts, strokeColor);
                if (sel) { nm.setSelected(true); selectedPolygons.add(nm); }
            }
        }

        // Weld all coincident boundary points across the full polygon set.
        // This joins the pieces from this cut to each other, and also re-joins
        // them to any existing neighbours whose shared edge was part of a prior cut.
        weldCoincidentPoints(polygonManager);
    }
}
