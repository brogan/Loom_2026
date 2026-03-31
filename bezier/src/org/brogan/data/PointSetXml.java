package org.brogan.data;

import java.awt.geom.Point2D;
import java.util.List;
import java.util.ArrayList;

import org.brogan.bezier.*;
import org.brogan.ui.*;

import nu.xom.Attribute;
import nu.xom.Element;

/**
 * Saves a set of discrete points as a <pointSet> XML file.
 * Coordinates use the same normalisation pipeline as PolygonSetXml / OpenCurveSetXml.
 */
public class PointSetXml extends XmlManager {

	public PointSetXml(String dtdPath) {
		super("pointSet", "pointSet.dtd", dtdPath);
	}

	/**
	 * Build and save the XML.
	 * @param n          Name for the pointSet
	 * @param points     Pixel-space Point2D.Double coordinates from BezierDrawPanel
	 * @param pressures  Per-point pressure values (parallel to points); may be null or shorter
	 * @param ccP        CubicCurvePanel (used to query grid/offset dimensions)
	 * @param sX         scaleX
	 * @param sY         scaleY
	 * @param rA         rotationAngle
	 * @param tX         transX
	 * @param tY         transY
	 */
	public void createNewXml(String n, List<Point2D.Double> points, List<Float> pressures,
	                          CubicCurvePanel ccP, double sX, double sY, double rA, double tX, double tY) {

		BezierDrawPanel bezier = ccP.getBezier();
		int gridWidth  = bezier.getGridWidth();
		int gridHeight = bezier.getGridHeight();
		double offsetAmount = bezier.getEdgeOffset() / 1000.0;

		// <name>
		Element name = new Element("name");
		name.appendChild(n);
		super.getRoot().appendChild(name);

		// One <point> per discrete point
		for (int i = 0; i < points.size(); i++) {
			Point2D.Double pt = points.get(i);
			// 1. normalise to [-0.5, 0.5]
			double nX = (pt.x / (double) gridWidth)  - 0.5;
			double nY = (pt.y / (double) gridHeight) - 0.5;
			// 2. adjust for edge offset
			double aX = nX - offsetAmount;
			double aY = nY - offsetAmount;
			// 3. round to 2 decimal places
			double sX2 = Math.round(aX * 100) / 100.0;
			double sY2 = Math.round(aY * 100) / 100.0;

			Element pointEl = new Element("point");
			pointEl.addAttribute(new Attribute("x", Double.toString(sX2)));
			pointEl.addAttribute(new Attribute("y", Double.toString(sY2)));
			// Write pressure only when it differs from the default
			float pr = (pressures != null && i < pressures.size()) ? pressures.get(i) : 1.0f;
			if (pr != 1.0f) {
				pointEl.addAttribute(new Attribute("pressure", String.format("%.3f", pr)));
			}
			super.getRoot().appendChild(pointEl);
		}

		// Transform elements
		Element scaleXEl = new Element("scaleX");       scaleXEl.appendChild("" + sX);       super.getRoot().appendChild(scaleXEl);
		Element scaleYEl = new Element("scaleY");       scaleYEl.appendChild("" + sY);       super.getRoot().appendChild(scaleYEl);
		Element rotAEl   = new Element("rotationAngle"); rotAEl.appendChild("" + rA);         super.getRoot().appendChild(rotAEl);
		Element transXEl = new Element("transX");       transXEl.appendChild("" + tX);       super.getRoot().appendChild(transXEl);
		Element transYEl = new Element("transY");       transYEl.appendChild("" + tY);       super.getRoot().appendChild(transYEl);

		String xmlFilePath = super.getXmlFilePath();
		System.out.println("PointSetXml xmlFilePath: " + xmlFilePath);
		super.setXml_doc();
		saveXMLToFile(super.getXml_doc(), xmlFilePath);
	}
}
