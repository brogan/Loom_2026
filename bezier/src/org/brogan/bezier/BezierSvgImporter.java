package org.brogan.bezier;

import nu.xom.Builder;
import nu.xom.Document;
import nu.xom.Element;
import nu.xom.Node;

import java.awt.Color;
import java.awt.geom.Point2D;
import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Imports polygon geometry from an SVG file into a CubicCurvePolygonManager.
 * Each SVG <path> element becomes one closed polygon (added to the existing geometry).
 * Supported path commands: M/m, C/c, L/l, Q/q, Z/z.
 * Unsupported commands (H, V, S, T, A) are silently skipped.
 * Coordinates are mapped from the SVG viewBox into Bezier pixel space.
 */
public class BezierSvgImporter {

    private static final int EDGE_OFFSET = (BezierDrawPanel.WIDTH - BezierDrawPanel.GRIDWIDTH) / 2;
    private static final int GRID_SIZE   = BezierDrawPanel.GRIDWIDTH;

    // viewBox origin and size — set from the SVG root element
    private double vbX = 0, vbY = 0, vbW = GRID_SIZE, vbH = GRID_SIZE;

    // ── Public entry point ─────────────────────────────────────────────────────

    /**
     * Parse the SVG file and add each recognised path as a closed polygon
     * to {@code manager}.  Existing geometry is preserved (import adds to it).
     */
    public static void importSvg(File svgFile, CubicCurvePolygonManager manager, Color strokeColor) {
        new BezierSvgImporter().doImport(svgFile, manager, strokeColor);
    }

    // ── Private implementation ─────────────────────────────────────────────────

    private void doImport(File svgFile, CubicCurvePolygonManager manager, Color strokeColor) {
        Document doc;
        try {
            Builder builder = new Builder(false); // non-validating (no DTD required)
            doc = builder.build(svgFile);
        } catch (Exception e) {
            System.out.println("BezierSvgImporter: failed to parse " + svgFile + " — " + e.getMessage());
            return;
        }

        Element root = doc.getRootElement();
        parseViewBox(root);
        collectPaths(root, manager, strokeColor);
    }

    /** Read viewBox attribute from the SVG root and store the coordinate space. */
    private void parseViewBox(Element root) {
        String vb = root.getAttributeValue("viewBox");
        if (vb == null) vb = root.getAttributeValue("viewbox");
        if (vb != null) {
            double[] n = extractNumbers(vb);
            if (n.length >= 4) { vbX = n[0]; vbY = n[1]; vbW = n[2]; vbH = n[3]; }
        }
        if (vbW == 0) vbW = GRID_SIZE;
        if (vbH == 0) vbH = GRID_SIZE;
    }

    /** Depth-first traversal — calls importPath() for each <path> element found. */
    private void collectPaths(Element el, CubicCurvePolygonManager manager, Color strokeColor) {
        for (int i = 0; i < el.getChildCount(); i++) {
            Node child = el.getChild(i);
            if (!(child instanceof Element)) continue;
            Element childEl = (Element) child;
            if ("path".equals(childEl.getLocalName())) {
                String d = childEl.getAttributeValue("d");
                if (d != null && !d.isEmpty()) importPath(d, manager, strokeColor);
            } else {
                collectPaths(childEl, manager, strokeColor);
            }
        }
    }

    /** Convert a single <path d="…"> into a closed polygon and add it to manager. */
    private void importPath(String d, CubicCurvePolygonManager manager, Color strokeColor) {
        List<double[]> curves = parsePath(d); // each entry: {a0x,a0y, c1x,c1y, c2x,c2y, a1x,a1y}
        if (curves.isEmpty()) return;

        int N = curves.size();
        Point2D.Double[] pts = new Point2D.Double[N * 4];
        for (int i = 0; i < N; i++) {
            double[] c = curves.get(i);
            pts[i * 4 + 0] = toScreen(c[0], c[1]);
            pts[i * 4 + 1] = toScreen(c[2], c[3]);
            pts[i * 4 + 2] = toScreen(c[4], c[5]);
            pts[i * 4 + 3] = toScreen(c[6], c[7]);
        }
        manager.addClosedFromPoints(pts, strokeColor);
    }

    /**
     * Parse SVG path d attribute into a list of cubic-bezier curves.
     * Each entry: [a0x, a0y, c1x, c1y, c2x, c2y, a1x, a1y]
     */
    private List<double[]> parsePath(String d) {
        List<double[]> curves = new ArrayList<>();

        double cx = 0, cy = 0;       // current point
        double startX = 0, startY = 0; // current subpath start

        // Tokenise: split on command letters, keep the letter with its numeric arguments
        Matcher tok = Pattern.compile(
            "([MmCcLlQqZzHhVvSsTtAa])([^MmCcLlQqZzHhVvSsTtAa]*)").matcher(d);

        while (tok.find()) {
            char cmd  = tok.group(1).charAt(0);
            double[] n = extractNumbers(tok.group(2));
            int ni = 0;

            switch (cmd) {
                case 'M':
                    if (n.length >= 2) {
                        cx = n[0]; cy = n[1]; ni = 2;
                        startX = cx; startY = cy;
                    }
                    // implicit L after first coordinate pair
                    while (ni + 1 < n.length) {
                        double ex = n[ni], ey = n[ni + 1]; ni += 2;
                        curves.add(lineToCubic(cx, cy, ex, ey));
                        cx = ex; cy = ey;
                    }
                    break;

                case 'm':
                    if (n.length >= 2) {
                        cx += n[0]; cy += n[1]; ni = 2;
                        startX = cx; startY = cy;
                    }
                    while (ni + 1 < n.length) {
                        double ex = cx + n[ni], ey = cy + n[ni + 1]; ni += 2;
                        curves.add(lineToCubic(cx, cy, ex, ey));
                        cx = ex; cy = ey;
                    }
                    break;

                case 'C':
                    while (ni + 5 < n.length) {
                        double c1x = n[ni], c1y = n[ni+1], c2x = n[ni+2], c2y = n[ni+3];
                        double ex  = n[ni+4], ey = n[ni+5]; ni += 6;
                        curves.add(new double[]{cx, cy, c1x, c1y, c2x, c2y, ex, ey});
                        cx = ex; cy = ey;
                    }
                    break;

                case 'c':
                    while (ni + 5 < n.length) {
                        double c1x = cx + n[ni], c1y = cy + n[ni+1];
                        double c2x = cx + n[ni+2], c2y = cy + n[ni+3];
                        double ex  = cx + n[ni+4], ey = cy + n[ni+5]; ni += 6;
                        curves.add(new double[]{cx, cy, c1x, c1y, c2x, c2y, ex, ey});
                        cx = ex; cy = ey;
                    }
                    break;

                case 'L':
                    while (ni + 1 < n.length) {
                        double ex = n[ni], ey = n[ni + 1]; ni += 2;
                        curves.add(lineToCubic(cx, cy, ex, ey));
                        cx = ex; cy = ey;
                    }
                    break;

                case 'l':
                    while (ni + 1 < n.length) {
                        double ex = cx + n[ni], ey = cy + n[ni + 1]; ni += 2;
                        curves.add(lineToCubic(cx, cy, ex, ey));
                        cx = ex; cy = ey;
                    }
                    break;

                case 'Q':
                    while (ni + 3 < n.length) {
                        double qx = n[ni], qy = n[ni+1], ex = n[ni+2], ey = n[ni+3]; ni += 4;
                        curves.add(quadToCubic(cx, cy, qx, qy, ex, ey));
                        cx = ex; cy = ey;
                    }
                    break;

                case 'q':
                    while (ni + 3 < n.length) {
                        double qx = cx + n[ni], qy = cy + n[ni+1];
                        double ex  = cx + n[ni+2], ey = cy + n[ni+3]; ni += 4;
                        curves.add(quadToCubic(cx, cy, qx, qy, ex, ey));
                        cx = ex; cy = ey;
                    }
                    break;

                case 'Z':
                case 'z':
                    // Add closing segment only if current point differs from subpath start
                    if (Math.abs(cx - startX) > 0.001 || Math.abs(cy - startY) > 0.001)
                        curves.add(lineToCubic(cx, cy, startX, startY));
                    cx = startX; cy = startY;
                    break;

                // H, V, S, T, A — silently skipped
                default:
                    break;
            }
        }

        // setAllPoints() wraps the last curve's end-anchor back to the first curve's
        // start-anchor automatically, so any explicit closing segment that brings us
        // back to startX/startY is redundant — remove it.
        if (!curves.isEmpty()) {
            double[] last  = curves.get(curves.size() - 1);
            double[] first = curves.get(0);
            if (Math.abs(last[6] - first[0]) < 0.01 && Math.abs(last[7] - first[1]) < 0.01)
                curves.remove(curves.size() - 1);
        }

        return curves;
    }

    // ── Geometry helpers ───────────────────────────────────────────────────────

    /** Line segment → cubic bezier with collinear control points at 1/3 and 2/3. */
    private static double[] lineToCubic(double x0, double y0, double x1, double y1) {
        return new double[]{
            x0, y0,
            x0 + (x1 - x0) / 3.0, y0 + (y1 - y0) / 3.0,
            x0 + 2.0 * (x1 - x0) / 3.0, y0 + 2.0 * (y1 - y0) / 3.0,
            x1, y1
        };
    }

    /** Quadratic bezier → cubic bezier (exact conversion via degree elevation). */
    private static double[] quadToCubic(double x0, double y0, double qx, double qy,
                                        double x1, double y1) {
        return new double[]{
            x0, y0,
            x0 + 2.0 / 3.0 * (qx - x0), y0 + 2.0 / 3.0 * (qy - y0),
            x1 + 2.0 / 3.0 * (qx - x1), y1 + 2.0 / 3.0 * (qy - y1),
            x1, y1
        };
    }

    /** Map SVG coordinate → Bezier screen pixel coordinate. */
    private Point2D.Double toScreen(double svgX, double svgY) {
        double bx = (svgX - vbX) / vbW * GRID_SIZE + EDGE_OFFSET;
        double by = (svgY - vbY) / vbH * GRID_SIZE + EDGE_OFFSET;
        return new Point2D.Double(bx, by);
    }

    /**
     * Extract all numbers from a string.
     * Handles negative values, decimals, and scientific notation.
     */
    private static double[] extractNumbers(String s) {
        if (s == null || s.isEmpty()) return new double[0];
        List<Double> list = new ArrayList<>();
        Matcher m = Pattern.compile("-?[0-9]*\\.?[0-9]+(?:[eE][+-]?[0-9]+)?").matcher(s);
        while (m.find()) {
            try { list.add(Double.parseDouble(m.group())); } catch (NumberFormatException ignored) {}
        }
        double[] arr = new double[list.size()];
        for (int i = 0; i < list.size(); i++) arr[i] = list.get(i);
        return arr;
    }
}
