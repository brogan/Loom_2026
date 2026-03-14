package org.brogan.data;

import java.awt.geom.Point2D;
import java.io.File;
import java.io.FileOutputStream;
import java.util.List;

import org.brogan.util.BString;
import org.brogan.bezier.*;

import nu.xom.Attribute;
import nu.xom.Document;
import nu.xom.Element;
import nu.xom.Serializer;

import org.brogan.ui.*;

/**
 * Saves a set of open curves as an <openCurveSet> XML file.
 * Only managers where getIsClosed() == false are written.
 * Inner structure mirrors PolygonSetXml but uses <openCurve> instead of <polygon>.
 */
public class OpenCurveSetXml extends XmlManager {

	public OpenCurveSetXml(String dtdPath) {
		super("openCurveSet", "openCurveSet.dtd", dtdPath);
	}

	public void createNewXml(String n, List<CubicCurveManager> managers,
	                          CubicCurvePanel ccP, double sX, double sY, double rA, double tX, double tY) {
		String temp;

		Element name = new Element("name");
		String nom = BString.splitDiscardSecondHalf(n, "__");
		name.appendChild(nom);
		super.getRoot().appendChild(name);

		Element shapeType = new Element("shapeType");
		shapeType.appendChild("CUBIC_CURVE");
		super.getRoot().appendChild(shapeType);

		CubicCurvePolygonManager polyManager = ccP.getBezier().getPolygonManager();

		for (CubicCurveManager mgr : managers) {
			if (mgr.getIsClosed()) continue; // skip closed polygons

			CubicCurvePolygon poly = mgr.getCurves();
			CubicCurve[] curves = poly.getArrayofCubicCurves();
			Element openCurve = new Element("openCurve");

			for (int c = 0; c < curves.length; c++) {
				Element curve = new Element("curve");
				CubicPoint[] points = curves[c].getPoints();
				polyManager.normalisePoints(points, ccP.getBezier().getGridWidth(), ccP.getBezier().getGridHeight());

				for (int p = 0; p < points.length; p++) {
					Element point = new Element("point");
					Double offsetAmount = (Double)(ccP.getBezier().getEdgeOffset() / 1000.0);
					Point2D.Double offset = polyManager.adjustForOffset(
						new Point2D.Double(points[p].getPos().x, points[p].getPos().y), offsetAmount);
					Point2D.Double simpler = polyManager.simplifyPointValue(new Point2D.Double(offset.x, offset.y));
					point.addAttribute(new Attribute("x", Double.toString(simpler.x)));
					point.addAttribute(new Attribute("y", Double.toString(simpler.y)));
					curve.appendChild(point);
				}
				openCurve.appendChild(curve);
				polyManager.deNormalisePoints(points, ccP.getBezier().getGridWidth(), ccP.getBezier().getGridHeight());
			}
			super.getRoot().appendChild(openCurve);
		}

		Element scaleX = new Element("scaleX"); temp = "" + sX; scaleX.appendChild(temp); super.getRoot().appendChild(scaleX);
		Element scaleY = new Element("scaleY"); temp = "" + sY; scaleY.appendChild(temp); super.getRoot().appendChild(scaleY);
		Element rotationAngle = new Element("rotationAngle"); temp = "" + rA; rotationAngle.appendChild(temp); super.getRoot().appendChild(rotationAngle);
		Element transX = new Element("transX"); temp = "" + tX; transX.appendChild(temp); super.getRoot().appendChild(transX);
		Element transY = new Element("transY"); temp = "" + tY; transY.appendChild(temp); super.getRoot().appendChild(transY);

		String xmlFilePath = super.getXmlFilePath();
		System.out.println("OpenCurveSetXml xmlFilePath: " + xmlFilePath);
		super.setXml_doc();
		// Write without DOCTYPE — open curve sets are loaded with non-validating
		// parser and there is no openCurveSet.dtd in project directories.
		try {
			FileOutputStream fos = new FileOutputStream(new File(xmlFilePath));
			Serializer output = new Serializer(fos, "ISO-8859-1");
			output.setIndent(4);
			output.write(super.getXml_doc());
		} catch (Exception e) {
			System.err.println("OpenCurveSetXml: failed to save: " + e.getMessage());
			e.printStackTrace();
		}
	}
}
