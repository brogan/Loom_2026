package org.brogan.bezier;

import java.awt.*;
import java.awt.geom.*;
import java.util.ArrayList;

public class CubicCurvePolygon {
	  
	  private ArrayList curves;
	  
	  public CubicCurvePolygon(int initSize) {
	      curves = new ArrayList(initSize);
	  }
	  
	  public void draw(Graphics2D g2D) {
	      CubicCurve[] cA = getArrayofCubicCurves();
	      for (int i = 0; i<cA.length; i++) {
	        cA[i].draw(g2D);
	      }
	  }
	  
	  public int getCubicCurveTotal() {
		  //System.out.println("CubicCurvePolygon, getCubicCurveTotal, curves count: "+ curves.size());
	      return curves.size();
	  }
	  
	  public void addCurve(CubicCurve c) {
	      curves.add(c);
	      //System.out.println("CubicCurvePolygon, addCurve, curves count: "+ curves.size());
	  }
	  
	  public CubicCurve getCurve(int index) {
		  System.out.println("...CubicCurvePolygon, getCurve, index: " + index + "    curves count: "+ curves.size());
	      return ((CubicCurve)curves.get(index));
	  }
	  
	  public void removeCurve(int index) {
	      curves.remove(index);
	  }
	  public ArrayList getCurves() {
		  return curves;
	  }
	  
	  public CubicCurve[] getArrayofCubicCurves() {
		  Object a[] = curves.toArray();
		  CubicCurve[] cA = new CubicCurve[a.length];
		  for (int i =0; i<cA.length; i++) {
			  cA[i] = (CubicCurve)a[i];
		  }
		  return cA;
	  }
	  public Point2D.Double[] getArrayOfPoints() {
	     CubicCurve[] cA = getArrayofCubicCurves();
	     int totCurves = getCubicCurveTotal();
	     int totPoints = totCurves * 4;//each curve stores 4 points
	     Point2D.Double[] points = new Point2D.Double[totPoints];
	     int count = 0;
	     for (int i = 0; i<totCurves;i++) {
	       for (int p = 0; p<4;p++) {
	    	   Point2D.Double currPoint = cA[i].getPoint(p).getPos();
	    	   points[count] = new Point2D.Double(currPoint.x, currPoint.y);
	    	   normalisePoint(points[count]);
	    	   count++;
	       }
	     }
	     printAllPoints(points);
	     return points;
	  }
	  /**
	   * normalisePoint
	   * @param p
	   */
	  private void normalisePoint(Point2D.Double p) {
		  double x = p.x;
		  double y = p.y;
		  x = (x-(BezierDrawPanel.WIDTH/2))/BezierDrawPanel.GRIDWIDTH;
		  y = (y-(BezierDrawPanel.HEIGHT/2))/BezierDrawPanel.GRIDWIDTH;
		  p.x = x;
		  p.y = y;
	  }
	  /**
	   * for editing - returns points to bezier draw proportions
	   * @param p point
	   */
	  public static void deNormalise (Point2D.Double p) {
		  double x = p.x;
		  double y = p.y;
		  x = (x * BezierDrawPanel.GRIDWIDTH) + BezierDrawPanel.WIDTH/2;
		  y = (y * BezierDrawPanel.GRIDWIDTH) + BezierDrawPanel.HEIGHT/2;
		  p.x = x;
		  p.y = y;
	  }
	  /**
	   * print out entire polygon
	   * @param points
	   */
	  public void printAllPoints(Point2D.Double[] points) {
	      int count = 0;
	      System.out.println("CubicCurvePolygon:");
	      for (int i = 0; i<points.length/4;i++) {
	        String curvePoints = "curve "+ i+"  points: ";
	        for (int p = 0; p<4; p++) {
	          if (p<3) {
	            curvePoints += (points[count].x + ", " + points[count].y + " :  ");
	          } else {
	            curvePoints += (points[count].x + ", " + points[count].y);
	            System.out.println(curvePoints);
	            System.out.println("");
	          }
	          count++;
	        }
	      }
	  }
	  /**
	   * @param strokeCol the strokeCol to set
	   */
	  public void setStrokeCol(Color strokeCol) {
		  Object a[] = curves.toArray();
		  CubicCurve[] cA = new CubicCurve[a.length];
		  for (int i =0; i<cA.length; i++) {
			  cA[i].setStrokeCol(strokeCol);
		  }
	  }
	  
	  public void setCurve(int index, CubicCurve cC) {
		  curves.set(index, cC);
	  }

	  
	}
