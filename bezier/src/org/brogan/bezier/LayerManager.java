package org.brogan.bezier;

import java.util.ArrayList;
import java.util.List;

public class LayerManager {

    private final List<Layer> layers = new ArrayList<>();
    private int activeLayerId;

    public LayerManager() {
        Layer first = new Layer("Layer 1");
        layers.add(first);
        activeLayerId = first.getId();
    }

    public Layer createLayer(String name) {
        Layer l = new Layer(name);
        layers.add(l);
        return l;
    }

    /** Returns false if this is the last layer (refuse to delete). */
    public boolean deleteLayer(int id) {
        if (layers.size() <= 1) return false;
        layers.removeIf(l -> l.getId() == id);
        // If we deleted the active layer, make the first remaining layer active
        if (activeLayerId == id) {
            activeLayerId = layers.get(0).getId();
        }
        return true;
    }

    public void renameLayer(int id, String name) {
        Layer l = getLayerById(id);
        if (l != null) l.setName(name);
    }

    /**
     * Duplicate a layer: creates a new layer named "LayerName copy" and
     * deep-copies all polygons belonging to that layer via addDuplicateOf.
     * Returns the new layer (the caller should set it active and refresh UI).
     */
    public Layer duplicateLayer(int id, CubicCurvePolygonManager pm) {
        Layer src = getLayerById(id);
        if (src == null) return null;
        Layer dup = createLayer(src.getName() + " copy");
        int dupId = dup.getId();
        int count = pm.getPolygonCount();
        List<CubicCurveManager> toCopy = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            CubicCurveManager m = pm.getManager(i);
            if (m.getLayerId() == id) toCopy.add(m);
        }
        for (CubicCurveManager m : toCopy) {
            CubicCurveManager copy = pm.addDuplicateOf(m, 0, 0);
            copy.setLayerId(dupId);
        }
        return dup;
    }

    public void moveLayerUp(int id) {
        int idx = indexOf(id);
        if (idx > 0) {
            Layer tmp = layers.get(idx - 1);
            layers.set(idx - 1, layers.get(idx));
            layers.set(idx, tmp);
        }
    }

    public void moveLayerDown(int id) {
        int idx = indexOf(id);
        if (idx >= 0 && idx < layers.size() - 1) {
            Layer tmp = layers.get(idx + 1);
            layers.set(idx + 1, layers.get(idx));
            layers.set(idx, tmp);
        }
    }

    public void    setActiveLayerId(int id)  { activeLayerId = id; }
    public int     getActiveLayerId()        { return activeLayerId; }
    public Layer   getActiveLayer()          { return getLayerById(activeLayerId); }
    public List<Layer> getLayers()           { return layers; }

    public Layer getLayerById(int id) {
        for (Layer l : layers) if (l.getId() == id) return l;
        return null;
    }

    private int indexOf(int id) {
        for (int i = 0; i < layers.size(); i++) {
            if (layers.get(i).getId() == id) return i;
        }
        return -1;
    }
}
