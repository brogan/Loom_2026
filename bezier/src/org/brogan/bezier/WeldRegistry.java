package org.brogan.bezier;
import java.util.*;

public class WeldRegistry {
    private final Map<CubicPoint, Set<CubicPoint>> links = new HashMap<>();

    public void registerWeld(CubicPoint a, CubicPoint b) {
        links.computeIfAbsent(a, k -> new HashSet<>()).add(b);
        links.computeIfAbsent(b, k -> new HashSet<>()).add(a);
    }

    public Set<CubicPoint> getLinked(CubicPoint p) {
        Set<CubicPoint> r = links.get(p);
        return r != null ? Collections.unmodifiableSet(r) : Collections.emptySet();
    }

    public void unregisterPoint(CubicPoint p) {
        Set<CubicPoint> linked = links.remove(p);
        if (linked != null) {
            for (CubicPoint o : linked) {
                Set<CubicPoint> s = links.get(o);
                if (s != null) {
                    s.remove(p);
                    if (s.isEmpty()) links.remove(o);
                }
            }
        }
    }

    /** Remove the link between a and b only, leaving each point's other links intact. */
    public void unregisterLink(CubicPoint a, CubicPoint b) {
        Set<CubicPoint> sa = links.get(a);
        if (sa != null) { sa.remove(b); if (sa.isEmpty()) links.remove(a); }
        Set<CubicPoint> sb = links.get(b);
        if (sb != null) { sb.remove(a); if (sb.isEmpty()) links.remove(b); }
    }

    public void clear() { links.clear(); }

    /**
     * Returns the full link map for snapshot capture.
     * Each entry maps a CubicPoint to the set of points it is welded to.
     */
    public java.util.Set<java.util.Map.Entry<CubicPoint, Set<CubicPoint>>> getEntries() {
        return Collections.unmodifiableSet(links.entrySet());
    }
}
