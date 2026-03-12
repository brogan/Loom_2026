package org.brogan.util;

import java.awt.geom.*;

public final class Transform {
	
	//FLOAT
	
	public static Point2D.Float translate(Point2D.Float origPos, Point2D.Float trans) {
		return new Point2D.Float(origPos.x+trans.x, origPos.y+trans.y);
	}
	public static Point2D.Float scale(Point2D.Float origPos, Point2D.Float scale) {
		return new Point2D.Float(origPos.x*scale.x, origPos.y*scale.y);
	}
	public static Point2D.Float rotate(Point2D.Float origPos, float angle) {
		angle = degreesToRadians(angle);
		float cosOfAngle = (float)Math.cos(angle);
		float sinOfAngle = (float)Math.sin(angle);
		
		float rotX = ((origPos.x * cosOfAngle) - (origPos.y * sinOfAngle));
	    float rotY = ((origPos.x * sinOfAngle) + (origPos.y * cosOfAngle));

	    //System.out.println("");
	    //System.out.println("Transform, rotX: " + rotX);
	    //System.out.println("Transform, rotY: " + rotY);
	    
		return new Point2D.Float(rotX, rotY);
	}
	public static float radiansToDegrees(float radians) {
			return (float)(radians * (180/Math.PI));
		}
	public static float degreesToRadians(float degrees) {
		return (float)(degrees * (Math.PI/180));
	}

	
	
	//DOUBLE
	
	
	public static Point2D.Double translate(Point2D.Double origPos, Point2D.Double trans) {
		return new Point2D.Double(origPos.x+trans.x, origPos.y+trans.y);
	}
	public static Point2D.Double scale(Point2D.Double origPos, Point2D.Double scale) {
		return new Point2D.Double(origPos.x*scale.x, origPos.y*scale.y);
	}
	public static Point2D.Double rotate(Point2D.Double origPos, double angle) {
		angle = degreesToRadians(angle);
		double cosOfAngle = Math.cos(angle);
		double sinOfAngle = Math.sin(angle);
		
		double rotX = ((origPos.x * cosOfAngle) - (origPos.y * sinOfAngle));
	    double rotY = ((origPos.x * sinOfAngle) + (origPos.y * cosOfAngle));

	    //System.out.println("");
	    //System.out.println("Transform, rotX: " + rotX);
	    //System.out.println("Transform, rotY: " + rotY);
	    
		return new Point2D.Double(rotX, rotY);
	}
	
	public static double radiansToDegrees(double radians) {
		return (double)(radians * (180/Math.PI));
	}
	public static double degreesToRadians(double degrees) {
		return (double)(degrees * (Math.PI/180));
	}

}
