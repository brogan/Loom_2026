
package org.brogan.bezier;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.geom.Point2D;
import java.util.ArrayList;

public class CubicCurvePolygonSet {
	
	private ArrayList polys;
	
	public CubicCurvePolygonSet(int initSize) {
	      polys = new ArrayList(initSize);
	  }

	  
	  public void draw(Graphics2D g2D) {
		  CubicCurvePolygon[] cA = getArrayofCubicCurvePolygons();
	      for (int i = 0; i<cA.length; i++) {
	        cA[i].draw(g2D);
	      }
	  }

	  public void clearPolygonSet() {polys = new ArrayList(100); }
	  
	  public int getPolygonTotal() {
	      return (polys.size());
	  }
	  
	  public void addPolygon(CubicCurvePolygon c) {
	      polys.add(c);
	      System.out.println("CubicCurvePolygonSet, polygon count: "+ polys.size());
	  }
	  
	  public CubicCurvePolygon getPolygon(int index) {
	      return ((CubicCurvePolygon)polys.get(index));
	  }
	  
	  public void removePolygon(int index) {
	      polys.remove(index);
	  }
	  public CubicCurvePolygon[] getArrayofCubicCurvePolygons() {
		  Object a[] = polys.toArray();
		  CubicCurvePolygon[] cA = new CubicCurvePolygon[a.length];
		  for (int i =0; i<cA.length; i++) {
			  cA[i] = (CubicCurvePolygon)a[i];
		  }
		  return cA;
	  }
	  /**
	   * @param strokeCol the strokeCol to set
	   */
	  public void setStrokeCol(Color strokeCol) {
		  Object a[] = polys.toArray();
		  CubicCurvePolygon[] cA = new CubicCurvePolygon[a.length];
		  for (int i =0; i<cA.length; i++) {
			  cA[i].setStrokeCol(strokeCol);
		  }
	  }
	  public Point2D.Double[] getArrayOfPoints() {
		  ArrayList allPoints = new ArrayList();
		  Object a[] = polys.toArray();
		  CubicCurvePolygon[] cA = new CubicCurvePolygon[a.length];
		  for (int i =0; i<cA.length; i++) {
			  Point2D.Double [] ps = cA[i].getArrayOfPoints();
			  for (int j =0; j<ps.length; j++) {
				  allPoints.add(ps[j]);
			  }
		  }
		  int tot = allPoints.size();
		  Point2D.Double[] aP = new Point2D.Double[tot];
		  for (int i =0; i<tot; i++) {
			  aP[i] = (Point2D.Double)allPoints.get(i);
		  }
		  return aP;
		  
	  }
	  
	  public void setPolygon(int index, CubicCurvePolygon ccP) {
		  polys.set(index, ccP);
	  }

}


