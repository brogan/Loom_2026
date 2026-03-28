package org.brogan.data;

import java.io.File;
import java.io.FileOutputStream;
import java.util.List;

import org.brogan.bezier.OvalManager;

import nu.xom.Attribute;
import nu.xom.Document;
import nu.xom.Element;
import nu.xom.Serializer;

/**
 * Saves a list of OvalManagers as an <ovalSet> XML file.
 * Coordinates are normalised to the -0.5..+0.5 space used by all other geometry types:
 *   normalised = (canvas_px - edgeOffset) / gridSize - 0.5
 * where gridSize = 1000 and edgeOffset = 20.
 *
 * File is written without a DOCTYPE — loaded with a non-validating parser.
 */
public class OvalSetXml {

    private static final double GRID = 1000.0;
    private static final double EDGE = 20.0;

    private String xmlFilePath;

    public void setXmlFilePath(String path) { this.xmlFilePath = path; }

    /**
     * Create and save the XML file.
     * @param name       base name (used in <name> element)
     * @param ovals      list of OvalManagers to serialise
     */
    public void createNewXml(String name, List<OvalManager> ovals) {
        Element root = new Element("ovalSet");

        Element nameEl = new Element("name");
        nameEl.appendChild(name);
        root.appendChild(nameEl);

        for (OvalManager oval : ovals) {
            Element ovalEl = new Element("oval");
            ovalEl.addAttribute(new Attribute("cx", fmt(toNorm(oval.getCx()))));
            ovalEl.addAttribute(new Attribute("cy", fmt(toNorm(oval.getCy()))));
            ovalEl.addAttribute(new Attribute("rx", fmt(toNormRadius(oval.getRx()))));
            ovalEl.addAttribute(new Attribute("ry", fmt(toNormRadius(oval.getRy()))));
            root.appendChild(ovalEl);
        }

        Document doc = new Document(root);
        try {
            new File(xmlFilePath).getParentFile().mkdirs();
            FileOutputStream fos = new FileOutputStream(new File(xmlFilePath));
            Serializer out = new Serializer(fos, "UTF-8");
            out.setIndent(4);
            out.write(doc);
            fos.close();
        } catch (Exception e) {
            System.err.println("OvalSetXml: failed to save: " + e.getMessage());
        }
    }

    // ── Coordinate helpers ────────────────────────────────────────────────

    /** Canvas pixel → normalised centre coordinate (-0.5..+0.5). */
    private static double toNorm(double px) {
        return (px - EDGE) / GRID - 0.5;
    }

    /** Canvas pixel radius → normalised radius (0..0.5). */
    private static double toNormRadius(double r) {
        return r / GRID;
    }

    private static String fmt(double v) {
        // Round to 4 decimal places
        return String.format("%.4f", v);
    }
}
