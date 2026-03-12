package org.brogan.util;

import java.awt.geom.*;

public class Formulas {
	
	/**
	 * Calculate double percentage
	 * @param score
	 * @param total
	 * @return
	 */
	public static double percentage(double score, double total) {
		return ((score/total)*100);
	}
	/**
	 * Calculate hypotenuse
	 * @param start
	 * @param dest
	 * @return
	 */
	public static double hypotenuse(Point2D.Double start, Point2D.Double dest) {
		double diffX = Math.abs(dest.x-start.x);
		//System.out.println("diffX: "+diffX);
		double diffY = Math.abs(dest.y-start.y);
		//System.out.println("diffY: "+diffY);
		double h = (Math.sqrt((diffX*diffX)+(diffY*diffY)));
		//System.out.println("hypotenuse: "+h);
		return h;
	}
	/**
	 * gets the difference between a start and a destination position
	 * @param start
	 * @param dest
	 * @return
	 */
	public static Point2D.Double diffXY(Point2D.Double start, Point2D.Double dest) {
		double diffX = dest.x-start.x;
		double diffY = dest.y-start.y;
		return new Point2D.Double(diffX, diffY);
	}
	/**
	 * adds a specified difference amount to a point
	 * @param start
	 * @param diff
	 * @return
	 */
	public static Point2D.Double addDiff(Point2D.Double start, Point2D.Double diff) {
		return new Point2D.Double(start.x + diff.x, start.y + diff.y);
	}
	   /**
	    * Linear Interpolation 2D
	    * @param a first point
	    * @param b second point
	    * @param t linear interpolation value (.75 is 75% along line that connects a and b)
	    */
	public static Point2D.Double lerp(Point2D.Double a, Point2D.Double b, double t) {
		   double destX = a.x + (b.x - a.x) * t;
		   double destY = a.y + (b.y - a.y) * t;
		   return new Point2D.Double (destX, destY);
	}
	
	/**
	    * Get interpolated point on a bezier curve
	    * Get interpolated point between anchor 1 and control point 1 (M1)
	    * and then between control point 1 and control point 2 (M2)and then finally between
	    * control point 2 and anchor point 2. (M3)
	    * Now calculate the interpolated points between these three new points.(M1-M2) = M4, (M2-M3)= M5
	    * Finally calculate the interpolated point between these two points and this
	    * gives you the point on the curve (M6).
	    * t is typically.5 because halfway points are needed, but may not be if midpoints randomised, so can be any value (usually between 0-1)
	    * see: http://www.cubic.org/docs/bezier.htm
	    */
	public static Point2D.Double bezierPoint(Point2D.Double a1, Point2D.Double c1, Point2D.Double c2, Point2D.Double a2, double t) {
		Point2D.Double M1 = lerp(a1, c1, t);//M1 - point between anchor point 1 and control point 1
		Point2D.Double M2 = lerp(c1, c2, t);//M2 - point between control point 1 and control point 2 
		Point2D.Double M3 = lerp(c2, a2, t);//M3 - point between control point 2 and anchor point 2
		Point2D.Double M4 = lerp(M1, M2, t);//M4 - point between M1 & M2
		Point2D.Double M5 = lerp(M2, M3, t);//M5 - point between M2 & M3
	    return lerp(M4, M5, t);//M6 - point between M4 & M5, which should intersect with curve
	   }
	
	 public static int circularIndex(int n, int tot) {
			  int r = n;
			  if (n > tot-1) {
			  	   r = n % tot;//get the modulus remainder
			   } else if (n < 0) {
			  	   r = tot - (Math.abs(n) % tot);
			   }
			   return r;
	}
	/**
	* Gets average of an array of Point2D.Double values
	* returns Point2D.Double
	*/
		   public static Point2D.Double average(Point2D.Double[] points) {
			   Point2D.Double p = new Point2D.Double(0,0);
			   for (int i=0; i < points.length; i++) {
			  	   p.x += points[i].x;
			  	   p.y += points[i].y;
			   }
			   p.x = p.x/points.length;
			   p.y = p.y/points.length;
			   return p;
		   }

}

