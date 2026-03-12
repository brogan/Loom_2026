package org.brogan.data;

import org.brogan.bezier.Layer;
import org.brogan.bezier.LayerManager;
import nu.xom.Element;

import java.io.File;

/**
 * Writes a manifest XML file listing all layers and their exported file names.
 * Root element: layerSet.  File name: {overallName}.layers.xml
 */
public class LayerSetXml extends XmlManager {

    public LayerSetXml() {
        super("layerSet", "polygonSet.dtd", "../dtd");
    }

    /**
     * Save a layers manifest alongside the per-layer XML files.
     *
     * @param lm           the LayerManager to read layer info from
     * @param overallName  the overall shape name (e.g. "My Shape")
     * @param dirPath      directory where per-layer XMLs were saved
     */
    public static void save(LayerManager lm, String overallName, String dirPath) {
        LayerSetXml xml = new LayerSetXml();

        String overallFn = toFilename(overallName);

        Element nameEl = new Element("overallName");
        nameEl.appendChild(overallName);
        xml.getRoot().appendChild(nameEl);

        for (Layer layer : lm.getLayers()) {
            String layerFn = overallFn + "_" + toFilename(layer.getName());
            Element layerEl = new Element("layer");
            Element nameChild = new Element("name");
            nameChild.appendChild(layer.getName());
            Element fileChild = new Element("file");
            fileChild.appendChild(layerFn + ".xml");
            Element visChild = new Element("visible");
            visChild.appendChild(Boolean.toString(layer.isVisible()));
            layerEl.appendChild(nameChild);
            layerEl.appendChild(fileChild);
            layerEl.appendChild(visChild);
            xml.getRoot().appendChild(layerEl);
        }

        String outPath = dirPath + File.separator + overallFn + ".layers.xml";
        xml.setXmlFilePath(outPath);
        xml.setXml_doc();
        xml.saveXMLToFile(xml.getXml_doc(), outPath);
        System.out.println("LayerSetXml: saved " + outPath);
    }

    public static String toFilename(String s) {
        return s.trim()
                .replaceAll("\\s+", "_")
                .replaceAll("[^a-zA-Z0-9_\\-]", "")
                .toLowerCase();
    }
}
