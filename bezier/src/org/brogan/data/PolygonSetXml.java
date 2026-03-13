package org.brogan.data;

import java.awt.geom.Point2D;
import java.io.File;
import java.util.List;

import org.brogan.util.BString;
import org.brogan.bezier.*;

import nu.xom.Attribute;
import nu.xom.Element;
import nu.xom.Elements;

import org.brogan.ui.*;

public class PolygonSetXml extends XmlManager {
	
	private String name;
	private int shapeType;
	private CubicCurvePolygonManager polyManager;
	private double scaleX;
	private double scaleY;
	private double rotationAngle;
	private double transX;
	private double transY;

	
	public PolygonSetXml(String dtdPath) {
		super("polygonSet", "polygonSet.dtd", dtdPath);
	}
	
	public void createNewXml(String n, String sT, CubicCurvePolygonManager polyManager, CubicCurvePanel ccP, double sX, double sY, double rA, double tX, double tY) {
		
		String temp;
		
		Element name = new Element("name");

		String nom = BString.splitDiscardSecondHalf(n, "__");

		name.appendChild(nom);
		super.getRoot().appendChild(name);
		
		Element shapeType = new Element("shapeType");
		shapeType.appendChild(sT);
		super.getRoot().appendChild(shapeType);
		
		CubicCurvePolygon[] polys = polyManager.getPolygons().getArrayofCubicCurvePolygons();
		for (int i = 0; i< polys.length;i++) {
			Element polygon = new Element("polygon");
			if (!polyManager.isClosedAt(i)) {
				polygon.addAttribute(new Attribute("isClosed", "false"));
			}
			CubicCurvePolygon poly = polys[i];
			CubicCurve[] curves = poly.getArrayofCubicCurves();
			for (int c = 0; c < curves.length; c++) {
				Element curve = new Element("curve");
				CubicPoint[] points = curves[c].getPoints();
				
				//NORMALISATION
				polyManager.normalisePoints(points, ccP.getBezier().getGridWidth(), ccP.getBezier().getGridHeight());
				
				for (int p = 0; p < points.length; p++) {
					Element point = new Element("point");
					
					//Added Feb 2002
					//get the bezierDrawPanel grid offset value (20 needs to be converted to .02, which requires 1000 as divisor)
					Double offsetAmount = (Double)(ccP.getBezier().getEdgeOffset()/1000.0);//the small offset between edge of drawing panel and the actual grid (usually 20)

					Point2D.Double offset = polyManager.adjustForOffset(new Point2D.Double(points[p].getPos().x, points[p].getPos().y), offsetAmount);
					
					Point2D.Double simpler = polyManager.simplifyPointValue(new Point2D.Double(offset.x, offset.y));
					
					//then just add them to the xml
					point.addAttribute(new Attribute ("x", Double.toString(simpler.x)));
					point.addAttribute(new Attribute ("y", Double.toString(simpler.y)));
					
					//older code just added points as internally represented, which were always wrong by the edge offset in bezierDrawPanel
					//point.addAttribute(new Attribute ("x", Double.toString(points[p].getPos().x)));
					//point.addAttribute(new Attribute ("y", Double.toString(points[p].getPos().y)));
					curve.appendChild(point);
				}	
				polygon.appendChild(curve);
				
				//DENORMALISATION
				polyManager.deNormalisePoints(points, ccP.getBezier().getGridWidth(), ccP.getBezier().getGridHeight());
			}
			super.getRoot().appendChild(polygon);
		}
		
		Element scaleX = new Element("scaleX");
		temp = ""+sX;
		scaleX.appendChild(temp);
		super.getRoot().appendChild(scaleX);
		
		Element scaleY = new Element("scaleY");
		temp = ""+sY;
		scaleY.appendChild(temp);
		super.getRoot().appendChild(scaleY);
		
		Element rotationAngle = new Element("rotationAngle");
		temp = ""+rA;
		rotationAngle.appendChild(temp);
		super.getRoot().appendChild(rotationAngle);
		
		Element transX = new Element("transX");
		temp = ""+tX;
		transX.appendChild(temp);
		super.getRoot().appendChild(transX);
		
		Element transY = new Element("transY");
		temp = ""+tY;
		transY.appendChild(temp);
		super.getRoot().appendChild(transY);
		
		//printXmlValues();
		//saveResult(super.getRoot());
		String xmlFilePath = super.getXmlFilePath();
		System.out.println("xmlFilePath: "+ xmlFilePath);
		super.setXml_doc();
		saveXMLToFile(super.getXml_doc(), xmlFilePath);
	}
	/**
	 * for debugging (but may not be necessary???)
	 * see save function in XmlManager
	 */
	/**
	public void storeXmlValues() {
		Elements all = super.getTopLevelElements();
		//System.out.println("all size: "+ all.size());
		System.out.println("");
		System.out.println("start cubicCurve xml..............");
		
		//title
		Element name_element = all.get(0);
		name = getValueOfElement(name_element);
		System.out.println("name: "+ name);
		
		//shapeType
		Element shapeType_element = all.get(1);
		String s = getValueOfElement(shapeType_element);
		
		//UPDATE NEEDED____________________________________________________________________________________________________________
		//shapeType = BShape.getShapeTypeIntValue(s);
		System.out.println("shapeType: "+ s);
		
		//polyPoints
		Element polyPoints_element = all.get(2);
		Elements polyPoints_elements = polyPoints_element.getChildElements();
		int len = polyPoints_elements.size();
		//System.out.println("CubicCurveXml, storeXmlValues, polyPoints length: "+len);
		polyPoints = new Point2D.Double[len];
		for (int i = 0;i<len;i++) {
			Element polyPoint = polyPoints_elements.get(i);
			Elements xy_elements = polyPoint.getChildElements();
			Element x_element = xy_elements.get(0);
			Element y_element = xy_elements.get(1);
			String x_string = getValueOfElement(x_element);
			String y_string = getValueOfElement(y_element);
			Double x_double = Double.valueOf(x_string);
			Double y_double = Double.valueOf(y_string);
			double x = x_double.doubleValue();
			double y = y_double.doubleValue();
			polyPoints[i] = new Point2D.Double(x, y);
			System.out.println("     polyPoint "+i+" x: "+x+"  y: "+y);
		}
		
		//scaleX
		Element scaleX_element = all.get(3);
		String scaleX_string = getValueOfElement(scaleX_element);
		Double scaleX_double = Double.valueOf(scaleX_string);
		scaleX = scaleX_double.doubleValue();
		System.out.println("scaleX: "+ scaleX);
		
		//scaleY
		Element scaleY_element = all.get(4);
		String scaleY_string = getValueOfElement(scaleY_element);
		Double scaleY_double = Double.valueOf(scaleY_string);
		scaleY = scaleY_double.doubleValue();
		System.out.println("scaleY: "+ scaleY);
		
		//rotationAngle
		Element rotationAngle_element = all.get(5);
		String rotationAngle_string = getValueOfElement(rotationAngle_element);
		Double rotationAngle_double = Double.valueOf(rotationAngle_string);
		rotationAngle = rotationAngle_double.doubleValue();
		System.out.println("rotationAngle: "+ rotationAngle);
		
		//transX
		Element transX_element = all.get(6);
		String transX_string = getValueOfElement(transX_element);
		Double transX_double = Double.valueOf(transX_string);
		transX = transX_double.doubleValue();
		System.out.println("transX: "+ transX);
		
		//transY
		Element transY_element = all.get(7);
		String transY_string = getValueOfElement(transY_element);
		Double transY_double = Double.valueOf(transY_string);
		transY = transY_double.doubleValue();
		System.out.println("transY: "+ transY);
		
		
		System.out.println("end cubicCurve xml..................\n");
		System.out.println("");
		
	}
	*/
	
	/**
	 * Overload that saves only the polygons in the provided list (for per-layer export).
	 */
	public void createNewXml(String n, String sT, List<CubicCurveManager> managers,
	                          CubicCurvePanel ccP, double sX, double sY, double rA, double tX, double tY) {
		String temp;

		Element name = new Element("name");
		String nom = BString.splitDiscardSecondHalf(n, "__");
		name.appendChild(nom);
		super.getRoot().appendChild(name);

		Element shapeType = new Element("shapeType");
		shapeType.appendChild(sT);
		super.getRoot().appendChild(shapeType);

		CubicCurvePolygonManager polyManager = ccP.getBezier().getPolygonManager();

		for (CubicCurveManager mgr : managers) {
			CubicCurvePolygon poly = mgr.getCurves();
			CubicCurve[] curves = poly.getArrayofCubicCurves();
			Element polygon = new Element("polygon");
			if (!mgr.getIsClosed()) {
				polygon.addAttribute(new Attribute("isClosed", "false"));
			}
			for (int c = 0; c < curves.length; c++) {
				Element curve = new Element("curve");
				CubicPoint[] points = curves[c].getPoints();
				polyManager.normalisePoints(points, ccP.getBezier().getGridWidth(), ccP.getBezier().getGridHeight());
				for (int p = 0; p < points.length; p++) {
					Element point = new Element("point");
					Double offsetAmount = (Double)(ccP.getBezier().getEdgeOffset() / 1000.0);
					Point2D.Double offset = polyManager.adjustForOffset(new Point2D.Double(points[p].getPos().x, points[p].getPos().y), offsetAmount);
					Point2D.Double simpler = polyManager.simplifyPointValue(new Point2D.Double(offset.x, offset.y));
					point.addAttribute(new Attribute("x", Double.toString(simpler.x)));
					point.addAttribute(new Attribute("y", Double.toString(simpler.y)));
					curve.appendChild(point);
				}
				polygon.appendChild(curve);
				polyManager.deNormalisePoints(points, ccP.getBezier().getGridWidth(), ccP.getBezier().getGridHeight());
			}
			super.getRoot().appendChild(polygon);
		}

		Element scaleX = new Element("scaleX"); temp = "" + sX; scaleX.appendChild(temp); super.getRoot().appendChild(scaleX);
		Element scaleY = new Element("scaleY"); temp = "" + sY; scaleY.appendChild(temp); super.getRoot().appendChild(scaleY);
		Element rotationAngle = new Element("rotationAngle"); temp = "" + rA; rotationAngle.appendChild(temp); super.getRoot().appendChild(rotationAngle);
		Element transX = new Element("transX"); temp = "" + tX; transX.appendChild(temp); super.getRoot().appendChild(transX);
		Element transY = new Element("transY"); temp = "" + tY; transY.appendChild(temp); super.getRoot().appendChild(transY);

		String xmlFilePath = super.getXmlFilePath();
		System.out.println("xmlFilePath: " + xmlFilePath);
		super.setXml_doc();
		saveXMLToFile(super.getXml_doc(), xmlFilePath);
	}

	/**
	 * @return the name
	 */
	public String getName() {
		return name;
	}

	/**
	 * @return the shapeType
	 */
	public int getShapeType() {
		return shapeType;
	}

	/**
	 * @return the polyPoints
	 */
	public CubicCurvePolygonManager getPolyManager() {
		return polyManager;
	}

	/**
	 * @return the scaleX
	 */
	public double getScaleX() {
		return scaleX;
	}

	/**
	 * @return the scaleY
	 */
	public double getScaleY() {
		return scaleY;
	}

	/**
	 * @return the rotationAngle
	 */
	public double getRotationAngle() {
		return rotationAngle;
	}

	/**
	 * @return the transX
	 */
	public double getTransX() {
		return transX;
	}

	/**
	 * @return the transY
	 */
	public double getTransY() {
		return transY;
	}

}
