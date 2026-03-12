package org.brogan.bezier;

import java.awt.geom.Point2D;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;
import java.util.List;

/**
 * Exports the current polygon geometry as an SVG file.
 * Each closed polygon becomes a &lt;path&gt; element using M and C commands.
 * Coordinate system: Bezier pixel space → SVG 0-1000 range (subtract edgeOffset).
 * The export is called automatically alongside XML save — no separate user action needed.
 */
public class BezierSvgExporter {

    /** Pixel offset from panel edge to drawing grid (matches BezierDrawPanel.edgeOffset). */
    private static final int EDGE_OFFSET = (BezierDrawPanel.WIDTH - BezierDrawPanel.GRIDWIDTH) / 2;

    /** SVG canvas size in user units — matches BezierDrawPanel.GRIDWIDTH. */
    private static final int VIEW_SIZE = BezierDrawPanel.GRIDWIDTH;

    /**
     * Save an SVG file for the given polygon manager.
     *
     * @param manager    the polygon geometry to export
     * @param svgDirPath target directory (created if absent)
     * @param name       polygon set name — used as the filename (without extension)
     */
    public static void save(CubicCurvePolygonManager manager, String svgDirPath, String name) {
        File svgDir = new File(svgDirPath);
        if (!svgDir.exists()) svgDir.mkdirs();

        File svgFile = new File(svgDir, name + ".svg");

        StringBuilder sb = new StringBuilder();
        sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        sb.append("<svg xmlns=\"http://www.w3.org/2000/svg\"");
        sb.append(" width=\"").append(VIEW_SIZE).append("\"");
        sb.append(" height=\"").append(VIEW_SIZE).append("\"");
        sb.append(" viewBox=\"0 0 ").append(VIEW_SIZE).append(' ').append(VIEW_SIZE).append("\">\n");
        sb.append("  <title>").append(escapeXml(name)).append("</title>\n");

        int count = manager.getPolygonCount();
        for (int i = 0; i < count; i++) {
            CubicCurveManager m = manager.getManager(i);
            CubicCurve[] cvs = m.getCurves().getArrayofCubicCurves();
            if (cvs.length == 0) continue;

            CubicPoint[] first = cvs[0].getPoints();
            if (first[0] == null) continue;

            sb.append("  <path d=\"");
            sb.append(String.format("M %.4f,%.4f",
                    toSvg(first[0].getPos().x),
                    toSvg(first[0].getPos().y)));

            for (CubicCurve cv : cvs) {
                CubicPoint[] pts = cv.getPoints();
                if (pts[1] == null || pts[2] == null || pts[3] == null) continue;
                sb.append(String.format(" C %.4f,%.4f %.4f,%.4f %.4f,%.4f",
                        toSvg(pts[1].getPos().x), toSvg(pts[1].getPos().y),
                        toSvg(pts[2].getPos().x), toSvg(pts[2].getPos().y),
                        toSvg(pts[3].getPos().x), toSvg(pts[3].getPos().y)));
            }
            sb.append(" Z\"");
            sb.append(" fill=\"none\" stroke=\"#000000\" stroke-width=\"1\"");
            sb.append("/>\n");
        }

        sb.append("</svg>\n");

        try (PrintWriter pw = new PrintWriter(new FileWriter(svgFile))) {
            pw.print(sb);
            System.out.println("BezierSvgExporter: saved " + svgFile.getAbsolutePath());
        } catch (IOException e) {
            System.out.println("BezierSvgExporter: failed to write " + svgFile + " — " + e.getMessage());
        }
    }

    /**
     * Save an SVG file for a filtered list of managers (for per-layer export).
     */
    public static void save(List<CubicCurveManager> managers, String svgDirPath, String name) {
        File svgDir = new File(svgDirPath);
        if (!svgDir.exists()) svgDir.mkdirs();

        File svgFile = new File(svgDir, name + ".svg");

        StringBuilder sb = new StringBuilder();
        sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        sb.append("<svg xmlns=\"http://www.w3.org/2000/svg\"");
        sb.append(" width=\"").append(VIEW_SIZE).append("\"");
        sb.append(" height=\"").append(VIEW_SIZE).append("\"");
        sb.append(" viewBox=\"0 0 ").append(VIEW_SIZE).append(' ').append(VIEW_SIZE).append("\">\n");
        sb.append("  <title>").append(escapeXml(name)).append("</title>\n");

        for (CubicCurveManager m : managers) {
            CubicCurve[] cvs = m.getCurves().getArrayofCubicCurves();
            if (cvs.length == 0) continue;
            CubicPoint[] first = cvs[0].getPoints();
            if (first[0] == null) continue;
            sb.append("  <path d=\"");
            sb.append(String.format("M %.4f,%.4f", toSvg(first[0].getPos().x), toSvg(first[0].getPos().y)));
            for (CubicCurve cv : cvs) {
                CubicPoint[] pts = cv.getPoints();
                if (pts[1] == null || pts[2] == null || pts[3] == null) continue;
                sb.append(String.format(" C %.4f,%.4f %.4f,%.4f %.4f,%.4f",
                        toSvg(pts[1].getPos().x), toSvg(pts[1].getPos().y),
                        toSvg(pts[2].getPos().x), toSvg(pts[2].getPos().y),
                        toSvg(pts[3].getPos().x), toSvg(pts[3].getPos().y)));
            }
            sb.append(" Z\"");
            sb.append(" fill=\"none\" stroke=\"#000000\" stroke-width=\"1\"");
            sb.append("/>\n");
        }

        sb.append("</svg>\n");

        try (PrintWriter pw = new PrintWriter(new FileWriter(svgFile))) {
            pw.print(sb);
            System.out.println("BezierSvgExporter: saved " + svgFile.getAbsolutePath());
        } catch (IOException e) {
            System.out.println("BezierSvgExporter: failed to write " + svgFile + " — " + e.getMessage());
        }
    }

    /** Convert a Bezier pixel coordinate to SVG user-unit space. */
    private static double toSvg(double bezierCoord) {
        return bezierCoord - EDGE_OFFSET;
    }

    private static String escapeXml(String s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
    }
}
