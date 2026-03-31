package org.brogan.bezier;

/**
 * Immutable snapshot of all closed polygon geometry (point positions + cross-manager
 * weld links). Used by UndoManager for multi-level undo.
 */
public class GeometrySnapshot {

    /** Snapshot of one polygon manager's curve data. */
    public static class ManagerSnap {
        /** True if this was a single open edge (restore via setSingleEdgePoints). */
        public final boolean isSingleEdge;
        /** True if this polygon is closed (restore via setAllPoints); false = open curve or point. */
        public final boolean isClosed;
        /** Number of curves in this manager. */
        public final int curveCount;
        /** Flat array of 4*curveCount x-positions. */
        public final double[] px;
        /** Flat array of 4*curveCount y-positions. */
        public final double[] py;
        /** Layer this polygon belongs to. */
        public final int layerId;
        /** Per-anchor pressure values; null means uniform 1.0. Only set for open curves. */
        public final float[] anchorPressures;

        public ManagerSnap(boolean isSingleEdge, boolean isClosed, int curveCount, double[] px, double[] py, int layerId, float[] anchorPressures) {
            this.isSingleEdge    = isSingleEdge;
            this.isClosed        = isClosed;
            this.curveCount      = curveCount;
            this.px              = px;
            this.py              = py;
            this.layerId         = layerId;
            this.anchorPressures = anchorPressures;
        }
    }

    /**
     * One cross-manager weld link: two endpoints identified by
     * (managerIndex, curveIndex, pointSlot) tuples.
     * Within-manager anchor sharing is implicit in setAllPoints and not stored here.
     */
    public static class WeldLinkSnap {
        public final int mgr0, cv0, slot0;
        public final int mgr1, cv1, slot1;

        public WeldLinkSnap(int mgr0, int cv0, int slot0,
                             int mgr1, int cv1, int slot1) {
            this.mgr0  = mgr0;  this.cv0  = cv0;  this.slot0 = slot0;
            this.mgr1  = mgr1;  this.cv1  = cv1;  this.slot1 = slot1;
        }
    }

    /** Snapshot of one oval's parameters. */
    public static class OvalSnap {
        public final double cx, cy, rx, ry;
        public final int layerId;
        public OvalSnap(double cx, double cy, double rx, double ry, int layerId) {
            this.cx = cx; this.cy = cy;
            this.rx = rx; this.ry = ry;
            this.layerId = layerId;
        }
    }

    public final ManagerSnap[]  managers;
    public final WeldLinkSnap[] weldLinks;
    /** Snapshot of the discrete point list (copied, never null). */
    public final java.awt.geom.Point2D.Double[] points;
    /** Snapshot of the oval list (copied, never null). */
    public final OvalSnap[] ovals;
    /** Per-point pressure values, parallel to {@code points}. May be null (all 1.0). */
    public final float[] pointPressures;

    public GeometrySnapshot(ManagerSnap[] managers, WeldLinkSnap[] weldLinks,
                             java.awt.geom.Point2D.Double[] points,
                             OvalSnap[] ovals, float[] pointPressures) {
        this.managers       = managers;
        this.weldLinks      = weldLinks;
        this.points         = points;
        this.ovals          = ovals;
        this.pointPressures = pointPressures;
    }
}
