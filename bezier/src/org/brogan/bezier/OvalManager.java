package org.brogan.bezier;

import java.awt.*;
import java.awt.geom.*;

/**
 * Represents a single axis-aligned ellipse on the canvas.
 * Coordinates are in the BezierDrawPanel pixel space (0..GRIDWIDTH/GRIDHEIGHT
 * with 20 px edgeOffset border). Normalisation to -0.5..+0.5 happens at save time.
 *
 * Ovals participate in Polygon Selection mode (select/move/scale/rotate/flip)
 * but do NOT support point or edge sub-selection.
 */
public class OvalManager {

    private double cx;   // centre x in canvas pixel space
    private double cy;   // centre y in canvas pixel space
    private double rx;   // x-radius in canvas pixel space
    private double ry;   // y-radius in canvas pixel space
    // Frozen values for scale gestures — set once at gesture start, like CubicPoint.origPos
    private double origCx;
    private double origCy;
    private double origRx;
    private double origRy;
    private int layerId = 0;
    private boolean selected = false;

    public OvalManager(double cx, double cy, double rx, double ry) {
        this.cx = cx;
        this.cy = cy;
        this.rx = rx;
        this.ry = ry;
        this.origCx = cx;
        this.origCy = cy;
        this.origRx = rx;
        this.origRy = ry;
    }

    // ── Accessors ──────────────────────────────────────────────────────────

    public double getCx() { return cx; }
    public double getCy() { return cy; }
    public double getRx() { return rx; }
    public double getRy() { return ry; }
    public double getOrigCx() { return origCx; }
    public double getOrigCy() { return origCy; }
    public void setCx(double v) { cx = v; }
    public void setCy(double v) { cy = v; }
    public void setRx(double v) { rx = v; }
    public void setRy(double v) { ry = v; }
    public int  getLayerId()    { return layerId; }
    public void setLayerId(int id) { layerId = id; }
    public boolean isSelected() { return selected; }
    public void setSelected(boolean s) { selected = s; }

    // ── Geometry ──────────────────────────────────────────────────────────

    /** True if the given canvas-space point is inside this ellipse. */
    public boolean contains(double px, double py) {
        double dx = (px - cx) / Math.max(rx, 1.0);
        double dy = (py - cy) / Math.max(ry, 1.0);
        return dx * dx + dy * dy <= 1.0;
    }

    /** Translate centre by (dx, dy). */
    public void translate(double dx, double dy) {
        cx += dx;
        cy += dy;
    }

    /**
     * Freeze current values as the origin for this scale gesture.
     * Must be called once at the start of each slider gesture (equivalent to
     * CubicPoint.setOrigPos used by polygon scaling).
     */
    public void freezeOrig() {
        origCx = cx; origCy = cy; origRx = rx; origRy = ry;
    }

    /**
     * Scale around the given pivot using the FROZEN origin values.
     * Safe to call repeatedly with different factors — always relative to the
     * state captured by freezeOrig(), so slider direction reversal works correctly.
     */
    public void scaleXYFromOrig(double factor, double pivotX, double pivotY) {
        cx = pivotX + (origCx - pivotX) * factor;
        cy = pivotY + (origCy - pivotY) * factor;
        rx = Math.abs(origRx * factor);
        ry = Math.abs(origRy * factor);
    }

    public void scaleXFromOrig(double factor, double pivotX) {
        cx = pivotX + (origCx - pivotX) * factor;
        rx = Math.abs(origRx * factor);
    }

    public void scaleYFromOrig(double factor, double pivotY) {
        cy = pivotY + (origCy - pivotY) * factor;
        ry = Math.abs(origRy * factor);
    }

    /**
     * Scale around the given pivot point (cumulative — avoid in slider gestures).
     * Scales both centre position and radii uniformly (XY) or on one axis.
     */
    public void scaleXY(double factor, double pivotX, double pivotY) {
        cx = pivotX + (cx - pivotX) * factor;
        cy = pivotY + (cy - pivotY) * factor;
        rx = Math.abs(rx * factor);
        ry = Math.abs(ry * factor);
    }

    public void scaleX(double factor, double pivotX) {
        cx = pivotX + (cx - pivotX) * factor;
        rx = Math.abs(rx * factor);
    }

    public void scaleY(double factor, double pivotY) {
        cy = pivotY + (cy - pivotY) * factor;
        ry = Math.abs(ry * factor);
    }

    /** Rotate centre around the given pivot by degrees. Radii unchanged (oval stays axis-aligned). */
    public void rotate(double degrees, double pivotX, double pivotY) {
        double rad = Math.toRadians(degrees);
        double dx = cx - pivotX;
        double dy = cy - pivotY;
        double cosA = Math.cos(rad);
        double sinA = Math.sin(rad);
        cx = pivotX + dx * cosA - dy * sinA;
        cy = pivotY + dx * sinA + dy * cosA;
    }

    /** Flip horizontally around the given x-centre. */
    public void flipH(double centerX) {
        cx = 2.0 * centerX - cx;
    }

    /** Flip vertically around the given y-centre. */
    public void flipV(double centerY) {
        cy = 2.0 * centerY - cy;
    }

    // ── Rendering ─────────────────────────────────────────────────────────

    /**
     * Draw the oval into the given Graphics2D.
     * Selected ovals are drawn with a 3 px coloured outline.
     * Unselected ovals are drawn with the given stroke colour.
     */
    public void draw(Graphics2D g2D, Color strokeColor,
                     boolean discrete, boolean relational) {
        double x = cx - rx;
        double y = cy - ry;
        double w = rx * 2;
        double h = ry * 2;

        RenderingHints rh = new RenderingHints(
            RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g2D.setRenderingHints(rh);

        if (selected) {
            Color selColor = relational
                ? new Color(255, 140, 0)   // orange — relational
                : new Color(100, 150, 255); // blue — discrete
            g2D.setColor(selColor);
            g2D.setStroke(new BasicStroke(4f));
            g2D.draw(new Ellipse2D.Double(x, y, w, h));
        } else {
            g2D.setColor(strokeColor);
            g2D.setStroke(new BasicStroke(1.5f));
            g2D.draw(new Ellipse2D.Double(x, y, w, h));
        }
    }

    /** Deep copy for undo / clipboard use. */
    public OvalManager copy() {
        OvalManager m = new OvalManager(cx, cy, rx, ry);
        m.layerId = this.layerId;
        m.selected = false;
        return m;
    }
}
