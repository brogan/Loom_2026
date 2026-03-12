/*
 * Created on Jul 10, 2005
 */
package org.brogan.data;

import nu.xom.*;

import java.util.*;
import java.io.*;

/**
 * description: xml manager
 * @author brogan
 * @version
 */
public class XmlManager {
	
	private Document xml_doc;
	private String xmlFilePath;
	private String dtdName;
	private String dtdFilePath;
	private Element root;
	private String rootElementName;
	/**
	 * XmlManagerData constructor
	 *
	 */
	public XmlManager(String rootElementName, String dtdName, String dtdFP){
		root = new Element(rootElementName);
		this.rootElementName = rootElementName;
		this.dtdName = dtdName;
		System.out.println(" XmlManager constructor, dtdName: " + dtdName);
		this.dtdFilePath = dtdFP;
		System.out.println(" XmlManager constructor, dtdFilePath: " + dtdFilePath);
	}
	/**
	 * createNewXml
	 * @param pD ProjectData
	 */
	
	private void printResult(Element root) {
		Document doc = new Document (root);
		String result = doc.toXML();
		System.out.println("XmlManager printResult: " + result.toString());
	}
	
	
	public void saveResult(Element root){
		Document doc = new Document (root);
		DocType docType = new DocType(rootElementName, dtdName);
		doc.insertChild(docType, 0);
		System.out.println(doc.toXML());
		try {
		    Serializer serializer = new Serializer(System.out, "ISO-8859-1");
		    serializer.setIndent(4);
		    serializer.setMaxLength(100);
		    serializer.write(doc);
		} catch (IOException ex) {
			System.err.println(ex);
		}
		
	}
	/**
	 * saveXMLToFile
	 * @param doc document
	 * @param fileName file name
	 */
	public void saveXMLToFile(Document doc, String fileName) {
		System.out.println("XmlManager, saveXMLToFile, dtdFilePath: " + (dtdFilePath + File.separator + dtdName));
		//DocType docType = new DocType(rootElementName, "../../../resources/dtd/" + dtdName);
		DocType docType = new DocType(rootElementName, dtdFilePath + "/" + dtdName);
		//DocType docType = new DocType("cubicCurve", "../../../resources/dtd/cubicCurve.dtd");
		if (doc!=null  && doc.getDocType()==null) {
			doc.insertChild(docType, 0);
		} else {
			System.out.println("doc = null");
		}
		System.out.println(doc.toXML());
		System.out.println("saving xml file: "+ doc.toString()+ "fileName: "+fileName);

        try {

            System.out.println("Saving to File " + fileName);

            File outfile = new File(fileName);

            FileOutputStream fos = new FileOutputStream(outfile);

            Serializer output = new Serializer(fos, "ISO-8859-1");

            output.setIndent(4);

            output.write(doc);

        } catch (FileNotFoundException fnfe) {

            System.out.println("File Not Found");

            fnfe.printStackTrace();

            System.exit(-1);

        } catch (UnsupportedEncodingException uee) {

            System.out.println("unsupported Exception");

            uee.printStackTrace();

            System.exit(-1);

        } catch (IOException ioe) {

            System.out.println("IO Exception");

            ioe.printStackTrace();

            System.exit(-1);

        }
	}
	/**
	 * loadXml
	 * @param f file
	 * @return true if loaded
	 */
	public boolean loadXml(File filey){
		System.out.println("XmlManager.loadXml: " + filey.getPath());
		try {
			Builder parser = new Builder(true);
			xml_doc = parser.build(filey);
			root = xml_doc.getRootElement();
			System.out.println("loaded xml");
			//for debugging
			//storeXmlValues();
			return true;
		} catch (ValidityException ex) {
			System.out.println(ex.getMessage());
			System.out.println(" at line " + ex.getLineNumber() + ", column " + ex.getColumnNumber());
			return false;
		} catch (ParsingException ex){
			System.err.println("malformed xml");
			return false;
		} catch (IOException ex) {
			System.err.println("can't find file");
			return false;
		}
	}
	//*****************
	/**
	 * setXmlFilePath - other objects get the Xml file path to work out their own path
	 */
	public void setXmlFilePath(String pathy) {
		//System.out.println("XmlManager: xmlFilePath: "+ pathy);
		xmlFilePath = pathy;
	}
	/**
	 * getXmlFilePath - other objects get the Xml file path to work out their own path
	 * @return xmlFilePath
	 */
	public String getXmlFilePath() {
		return xmlFilePath;
	}
	//vital private accessor methods
	private Elements getChildren (Element e, String name){
		return e.getChildElements(name);
	}
	private String getAttribute(Element e, String att) {
		return e.getAttributeValue(att);
	}
	
	///////
	
	public Elements getTopLevelElements() {
		return root.getChildElements();
	}
	public Elements getChildElements(Elements es, int elements_index) {
		Element e = es.get(elements_index);
		return e.getChildElements();
	}
	public String getValueOfElement(Element e) {
		return e.getValue();
	}
	
	/**
	 * prints values of PolygonSetXml - should be there, not here, because not generic (can't print values of any xml file)
	 * have moved to cubic curve panel where load button is


	public void printValues() {
		
		System.out.println("..................................");
		
		Elements polys = root.getChildElements("polygon");
		System.out.println("NUMBER OF POLYGONS: " + polys.size());
		for (int p=0;p<polys.size();p++) {
			Element poly = (Element) polys.get(p);
			System.out.println("  POLYGON: " + p);
			for (int c=0;c<poly.getChildCount();c++) {
				Elements curves = poly.getChildElements();
				System.out.println("    CURVES " + c + " (number of curves: " + curves.size() + ")");
				for (int j=0;j<curves.size();j++) {
					Element curve = curves.get(j);
					System.out.println("      CURVE: " + j);
					Elements points = curve.getChildElements();
					System.out.println("        NUMBER OF POINTS: " + points.size());
					for (int n=0;n<points.size();n++) {
						System.out.println("          POINT " + n + ": x: " + (points.get(n).getAttributeValue("x")) + "  y: " + (points.get(n).getAttributeValue("y")));
					}
				}
			}
			
		}
		System.out.println("!!!END POLYGONS:");
		
		System.out.println("..................................");
		
	}
	*/
	
	/**
	 * @return the root
	 */
	public Element getRoot() {
		return root;
	}
	
	/**
	 * 
	 */
	public void setXml_doc() {
		//root = (Element)root.copy();
		xml_doc = new Document (root);
	}
	
	/**
	 * @return the xml_doc
	 */
	public Document getXml_doc() {
		return xml_doc;
	}
	/**
	 * reset root to new element just prior to creating new xml in classes that extend this one
	 * required only in configuration xml to avoid multipleParentException - strange!!!!
	 */
	public void resetRoot() {
		root = new Element(rootElementName);
	}
	
	
}
