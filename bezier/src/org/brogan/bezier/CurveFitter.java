package org.brogan.bezier;

import java.awt.geom.Point2D;
import java.util.ArrayList;
import java.util.List;

/**
 * Schneider curve-fitting algorithm: fits a polyline of sampled points to a
 * sequence of cubic Bézier segments.
 *
 * Reference: Philip J. Schneider, "An Algorithm for Automatically Fitting
 * Digitized Curves", Graphics Gems I (1990).
 *
 * Public API:
 *   Point2D.Double[] fit(List<Point2D.Double> pts, double errorThreshold)
 *
 * Returns a flat array [a0,c1,c2,a1, a1,c1',c2',a1', ...] — N*4 points for
 * N segments. Adjacent segments share the same end/start anchor value.
 */
public class CurveFitter {

    // ── Public entry point ────────────────────────────────────────────────────

    /**
     * Fit the given polyline to one or more cubic Bézier segments.
     *
     * @param pts            digitised input points (raw mouse positions)
     * @param errorThreshold maximum allowed pixel distance from any sample to the
     *                       fitted curve. Values 1–50 work well; higher → fewer
     *                       segments (looser fit).
     * @return flat array of control points: groups of 4 (a0,c1,c2,a1) per segment,
     *         or null if the input is too short.
     */
    public static Point2D.Double[] fit(List<Point2D.Double> pts, double errorThreshold) {
        List<Point2D.Double> d = removeDuplicates(pts);
        if (d.size() < 2) return null;

        // Pre-simplify with Douglas-Peucker: remove near-collinear intermediate points
        // that lie within errorThreshold of the simplified polyline.  This prevents the
        // Schneider fitter from recursing down to degenerate 2-point base cases on
        // nearly-straight tails (e.g. the user slowing down near the end of a stroke).
        d = douglasPeucker(d, Math.max(errorThreshold, 2.0));
        if (d.size() < 2) return null;

        // error is stored as squared distance throughout
        double err2 = errorThreshold * errorThreshold;

        List<Point2D.Double[]> segments = new ArrayList<>();

        if (d.size() == 2) {
            // Single straight-line segment
            Point2D.Double p0 = d.get(0), p1 = d.get(1);
            Point2D.Double c1 = new Point2D.Double(
                p0.x + (p1.x - p0.x) / 3.0, p0.y + (p1.y - p0.y) / 3.0);
            Point2D.Double c2 = new Point2D.Double(
                p0.x + 2.0 * (p1.x - p0.x) / 3.0, p0.y + 2.0 * (p1.y - p0.y) / 3.0);
            segments.add(new Point2D.Double[]{p0, c1, c2, p1});
        } else {
            Point2D.Double tHat1 = computeLeftTangent(d, 0);
            Point2D.Double tHat2 = computeRightTangent(d, d.size() - 1);
            fitCubic(d, 0, d.size() - 1, tHat1, tHat2, err2, segments);
        }

        // Flatten to a single array
        Point2D.Double[] result = new Point2D.Double[segments.size() * 4];
        for (int i = 0; i < segments.size(); i++) {
            Point2D.Double[] seg = segments.get(i);
            result[i * 4]     = seg[0];
            result[i * 4 + 1] = seg[1];
            result[i * 4 + 2] = seg[2];
            result[i * 4 + 3] = seg[3];
        }
        return result;
    }

    // ── Core recursive fitter ─────────────────────────────────────────────────

    private static void fitCubic(List<Point2D.Double> d,
                                  int first, int last,
                                  Point2D.Double tHat1, Point2D.Double tHat2,
                                  double err2,
                                  List<Point2D.Double[]> result) {
        if (last - first == 1) {
            // Only two points — emit a straight segment
            Point2D.Double p0 = d.get(first), p1 = d.get(last);
            double dist = distance(p0, p1) / 3.0;
            Point2D.Double c1 = new Point2D.Double(
                p0.x + tHat1.x * dist, p0.y + tHat1.y * dist);
            Point2D.Double c2 = new Point2D.Double(
                p1.x + tHat2.x * dist, p1.y + tHat2.y * dist);
            result.add(new Point2D.Double[]{p0, c1, c2, p1});
            return;
        }

        double[] u      = chordLengthParam(d, first, last);
        Point2D.Double[] bezier = generateBezier(d, first, last, u, tHat1, tHat2);

        double[] me    = maxError(d, first, last, bezier, u);
        double maxDist = me[0];
        int splitIdx   = (int) me[1];

        // Accept only if within error AND not looping.
        // wouldLoop() detects when control arms together overshoot the chord,
        // which produces self-intersecting cubics on highly curved arcs.
        if (maxDist < err2 && !wouldLoop(bezier)) {
            result.add(bezier);
            return;
        }

        // Attempt Newton-Raphson reparameterisation only when the initial fit is
        // not looping (a looping bezier reparameterises to another looping bezier).
        if (!wouldLoop(bezier) && maxDist < err2 * 4.0) {
            double[] uPrime   = reparameterize(d, first, last, u, bezier);
            Point2D.Double[] bezier2 = generateBezier(d, first, last, uPrime, tHat1, tHat2);
            double[] me2      = maxError(d, first, last, bezier2, uPrime);
            if (me2[0] < err2 && !wouldLoop(bezier2)) {
                result.add(bezier2);
                return;
            }
            splitIdx = (int) me2[1];
        }

        // Split at the point of maximum error and recurse
        Point2D.Double tCenter    = centerTangent(d, splitIdx);
        Point2D.Double tCenterNeg = new Point2D.Double(-tCenter.x, -tCenter.y);
        fitCubic(d, first,    splitIdx, tHat1,       tCenter,    err2, result);
        fitCubic(d, splitIdx, last,     tCenterNeg,  tHat2,      err2, result);
    }

    // ── Chord-length parameterisation ─────────────────────────────────────────

    private static double[] chordLengthParam(List<Point2D.Double> d, int first, int last) {
        int count = last - first + 1;
        double[] u = new double[count];
        u[0] = 0.0;
        for (int i = 1; i < count; i++) {
            u[i] = u[i - 1] + distance(d.get(first + i - 1), d.get(first + i));
        }
        double total = u[count - 1];
        if (total > 0) {
            for (int i = 1; i < count; i++) u[i] /= total;
        }
        u[count - 1] = 1.0; // ensure last point is exactly 1
        return u;
    }

    // ── Least-squares Bézier generation ──────────────────────────────────────

    private static Point2D.Double[] generateBezier(List<Point2D.Double> d,
                                                    int first, int last,
                                                    double[] u,
                                                    Point2D.Double tHat1,
                                                    Point2D.Double tHat2) {
        Point2D.Double p0 = d.get(first);
        Point2D.Double p3 = d.get(last);
        int count = last - first + 1;

        // A1[i], A2[i] are 2-vectors (x,y components stored as double[2])
        double[][] A1x = new double[count][1]; // we'll inline x/y
        double[] a1x = new double[count], a1y = new double[count];
        double[] a2x = new double[count], a2y = new double[count];

        for (int i = 0; i < count; i++) {
            double t = u[i];
            double b1 = B1(t), b2 = B2(t);
            a1x[i] = b1 * tHat1.x;
            a1y[i] = b1 * tHat1.y;
            a2x[i] = b2 * tHat2.x;
            a2y[i] = b2 * tHat2.y;
        }

        // Build the 2×2 system C * [alpha1; alpha2] = X
        double c00 = 0, c01 = 0, c11 = 0;
        double x0  = 0, x1  = 0;

        for (int i = 0; i < count; i++) {
            double t  = u[i];
            double b0 = B0(t), b3 = B3(t);

            c00 += a1x[i] * a1x[i] + a1y[i] * a1y[i];
            c01 += a1x[i] * a2x[i] + a1y[i] * a2y[i];
            c11 += a2x[i] * a2x[i] + a2y[i] * a2y[i];

            Point2D.Double pt = d.get(first + i);
            double tx = pt.x - (b0 * p0.x + b3 * p3.x);
            double ty = pt.y - (b0 * p0.y + b3 * p3.y);

            x0 += a1x[i] * tx + a1y[i] * ty;
            x1 += a2x[i] * tx + a2y[i] * ty;
        }

        double c10  = c01; // symmetric
        double det  = c00 * c11 - c01 * c10;
        double alpha1, alpha2;

        if (Math.abs(det) > 1e-12) {
            alpha1 = (x0 * c11 - c01 * x1) / det;
            alpha2 = (c00 * x1 - x0 * c10) / det;
        } else {
            // Degenerate: fallback to chord/3 heuristic
            double dist = distance(p0, p3) / 3.0;
            alpha1 = dist;
            alpha2 = dist;
        }

        // Guard against negative alphas (would flip tangent direction)
        if (alpha1 < 1e-6 || alpha2 < 1e-6) {
            double dist = distance(p0, p3) / 3.0;
            alpha1 = dist;
            alpha2 = dist;
        }

        Point2D.Double c1 = new Point2D.Double(
            p0.x + alpha1 * tHat1.x, p0.y + alpha1 * tHat1.y);
        Point2D.Double c2 = new Point2D.Double(
            p3.x + alpha2 * tHat2.x, p3.y + alpha2 * tHat2.y);

        return new Point2D.Double[]{p0, c1, c2, p3};
    }

    // ── Max error ─────────────────────────────────────────────────────────────

    /** Returns {maxSquaredDist, splitIndex}. */
    private static double[] maxError(List<Point2D.Double> d,
                                      int first, int last,
                                      Point2D.Double[] bezier,
                                      double[] u) {
        double maxDist = 0;
        int splitIdx   = (first + last) / 2;
        for (int i = first + 1; i < last; i++) {
            Point2D.Double pt = bezierPoint(bezier, u[i - first]);
            double dx   = pt.x - d.get(i).x;
            double dy   = pt.y - d.get(i).y;
            double dist = dx * dx + dy * dy;
            if (dist > maxDist) {
                maxDist  = dist;
                splitIdx = i;
            }
        }
        return new double[]{maxDist, splitIdx};
    }

    // ── Newton-Raphson reparameterisation ─────────────────────────────────────

    private static double[] reparameterize(List<Point2D.Double> d,
                                            int first, int last,
                                            double[] u,
                                            Point2D.Double[] bezier) {
        int count = last - first + 1;
        double[] uPrime = new double[count];
        for (int i = 0; i < count; i++) {
            uPrime[i] = newtonRaphsonStep(bezier, d.get(first + i), u[i]);
        }
        return uPrime;
    }

    /** One Newton-Raphson step to find the closest t on the cubic for point p. */
    private static double newtonRaphsonStep(Point2D.Double[] bezier,
                                             Point2D.Double p, double u) {
        Point2D.Double q  = bezierPoint(bezier, u);
        Point2D.Double q1 = bezierTangent(bezier, u);
        Point2D.Double q2 = bezierSecondDeriv(bezier, u);

        double numer = (q.x - p.x) * q1.x + (q.y - p.y) * q1.y;
        double denom = q1.x * q1.x + q1.y * q1.y
                     + (q.x - p.x) * q2.x + (q.y - p.y) * q2.y;
        if (Math.abs(denom) < 1e-12) return u;
        double uNew = u - numer / denom;
        if (uNew < 0) uNew = 0;
        if (uNew > 1) uNew = 1;
        return uNew;
    }

    // ── Tangent helpers ───────────────────────────────────────────────────────

    private static Point2D.Double computeLeftTangent(List<Point2D.Double> d, int end) {
        return normalize(sub(d.get(end + 1), d.get(end)));
    }

    private static Point2D.Double computeRightTangent(List<Point2D.Double> d, int end) {
        return normalize(sub(d.get(end - 1), d.get(end)));
    }

    private static Point2D.Double centerTangent(List<Point2D.Double> d, int center) {
        // Must point BACKWARD (toward center-1) to match the "right tangent" convention:
        // tHat2 for the left sub-curve and negated to tHat1 for the right sub-curve,
        // so that c2/c1 are placed on the interior side of the split point.
        return normalize(sub(d.get(center - 1), d.get(center + 1)));
    }

    // ── Bézier evaluation ─────────────────────────────────────────────────────

    private static Point2D.Double bezierPoint(Point2D.Double[] b, double t) {
        double b0 = B0(t), b1 = B1(t), b2 = B2(t), b3 = B3(t);
        return new Point2D.Double(
            b0 * b[0].x + b1 * b[1].x + b2 * b[2].x + b3 * b[3].x,
            b0 * b[0].y + b1 * b[1].y + b2 * b[2].y + b3 * b[3].y);
    }

    /** First derivative Q'(t). */
    private static Point2D.Double bezierTangent(Point2D.Double[] b, double t) {
        double mt = 1 - t;
        double k0 = 3 * mt * mt;
        double k1 = 6 * mt * t;
        double k2 = 3 * t  * t;
        return new Point2D.Double(
            k0 * (b[1].x - b[0].x) + k1 * (b[2].x - b[1].x) + k2 * (b[3].x - b[2].x),
            k0 * (b[1].y - b[0].y) + k1 * (b[2].y - b[1].y) + k2 * (b[3].y - b[2].y));
    }

    /** Second derivative Q''(t). */
    private static Point2D.Double bezierSecondDeriv(Point2D.Double[] b, double t) {
        double mt = 1 - t;
        double k0 = 6 * mt;
        double k1 = 6 * t;
        return new Point2D.Double(
            k0 * (b[2].x - 2 * b[1].x + b[0].x) + k1 * (b[3].x - 2 * b[2].x + b[1].x),
            k0 * (b[2].y - 2 * b[1].y + b[0].y) + k1 * (b[3].y - 2 * b[2].y + b[1].y));
    }

    // ── Bernstein basis polynomials ───────────────────────────────────────────

    private static double B0(double t) { double mt = 1 - t; return mt * mt * mt; }
    private static double B1(double t) { double mt = 1 - t; return 3 * mt * mt * t; }
    private static double B2(double t) { double mt = 1 - t; return 3 * mt * t  * t; }
    private static double B3(double t) { return t * t * t; }

    // ── Utility ───────────────────────────────────────────────────────────────

    /**
     * Douglas-Peucker polyline simplification.
     * Removes intermediate points that deviate less than {@code epsilon} pixels
     * from the straight line between their neighbours, recursively.
     */
    private static List<Point2D.Double> douglasPeucker(List<Point2D.Double> pts, double epsilon) {
        if (pts.size() <= 2) return new ArrayList<>(pts);
        Point2D.Double start = pts.get(0);
        Point2D.Double end   = pts.get(pts.size() - 1);
        double maxDist = 0;
        int    maxIdx  = 1;
        for (int i = 1; i < pts.size() - 1; i++) {
            double d = pointToLineDistance(pts.get(i), start, end);
            if (d > maxDist) { maxDist = d; maxIdx = i; }
        }
        if (maxDist > epsilon) {
            List<Point2D.Double> left  = douglasPeucker(pts.subList(0, maxIdx + 1), epsilon);
            List<Point2D.Double> right = douglasPeucker(pts.subList(maxIdx, pts.size()), epsilon);
            List<Point2D.Double> result = new ArrayList<>(left);
            result.addAll(right.subList(1, right.size())); // avoid duplicating split point
            return result;
        } else {
            List<Point2D.Double> result = new ArrayList<>();
            result.add(start);
            result.add(end);
            return result;
        }
    }

    /** Perpendicular distance from point {@code p} to the infinite line through {@code a} and {@code b}. */
    private static double pointToLineDistance(Point2D.Double p,
                                              Point2D.Double a, Point2D.Double b) {
        double dx = b.x - a.x, dy = b.y - a.y;
        double len2 = dx * dx + dy * dy;
        if (len2 < 1e-12) return distance(p, a);
        double t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2;
        double cx = a.x + t * dx, cy = a.y + t * dy;
        double ex = p.x - cx,     ey = p.y - cy;
        return Math.sqrt(ex * ex + ey * ey);
    }

    private static List<Point2D.Double> removeDuplicates(List<Point2D.Double> pts) {
        List<Point2D.Double> result = new ArrayList<>();
        for (Point2D.Double p : pts) {
            if (result.isEmpty() || distance(result.get(result.size() - 1), p) > 0.01)
                result.add(p);
        }
        return result;
    }

    private static double distance(Point2D.Double a, Point2D.Double b) {
        double dx = b.x - a.x, dy = b.y - a.y;
        return Math.sqrt(dx * dx + dy * dy);
    }

    /**
     * Returns true if the cubic bezier would self-intersect (loop).
     * When the sum of the two control-arm lengths exceeds the chord, the curve
     * bends back on itself for arcs > ~142°. We force a split in that case.
     */
    private static boolean wouldLoop(Point2D.Double[] bezier) {
        double arm1  = distance(bezier[0], bezier[1]);
        double arm2  = distance(bezier[3], bezier[2]);
        double chord = distance(bezier[0], bezier[3]);
        return chord > 1.0 && (arm1 + arm2) > chord;
    }

    private static Point2D.Double sub(Point2D.Double a, Point2D.Double b) {
        return new Point2D.Double(a.x - b.x, a.y - b.y);
    }

    private static Point2D.Double normalize(Point2D.Double v) {
        double len = Math.sqrt(v.x * v.x + v.y * v.y);
        if (len < 1e-10) return new Point2D.Double(1, 0);
        return new Point2D.Double(v.x / len, v.y / len);
    }
}
