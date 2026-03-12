package org.brogan.bezier;

import java.awt.*;
import java.awt.geom.*;

public class CubicCurve {
  
  public final static int ANCHOR_FIRST = 0;
  public final static int ANCHOR_LAST = 1;
  
  private CubicPoint[] points;
  private boolean drawLinesToAnchor;
  private float strokeWeight;
  private Color strokeCol;
  private float anchorLinesWeight;
  private Color anchorLinesCol;
  
  public CubicCurve(Color strokeColor) {
      points = new CubicPoint[4];
      drawLinesToAnchor = true;
      strokeWeight = 2f;
      strokeCol = strokeColor;
      anchorLinesCol = new Color(0,50,230);
      anchorLinesWeight = 1f;
  }
  public void draw(Graphics2D g2D) {
      int pointCount = 0;
      for (int i = 0; i<points.length; i++) {
        if (points[i]!= null) {
          points[i].draw(g2D);
          pointCount++;
        }
      }
      if (pointCount==4) {
    	g2D.setStroke(new BasicStroke(strokeWeight));
        g2D.setColor(strokeCol);
        float a1X = (float)points[0].getPos().x;
        float a1Y = (float)points[0].getPos().y;
        float c1X = (float)points[1].getPos().x;
        float c1Y = (float)points[1].getPos().y;
        float c2X = (float)points[2].getPos().x;
        float c2Y = (float)points[2].getPos().y;
        float a2X = (float)points[3].getPos().x;
        float a2Y = (float)points[3].getPos().y;
        CubicCurve2D.Float curve = new CubicCurve2D.Float(a1X,a1Y,c1X,c1Y,c2X,c2Y,a2X,a2Y);
        g2D.draw(curve);
        
        if (drawLinesToAnchor) {
          g2D.setStroke(new BasicStroke(anchorLinesWeight));
          g2D.setColor(anchorLinesCol);
          Line2D.Float initAnchorLine = new Line2D.Float(c1X, c1Y, a1X, a1Y);
          Line2D.Float endAnchorLine = new Line2D.Float(c2X, c2Y, a2X, a2Y);
          g2D.draw(initAnchorLine);
          g2D.draw(endAnchorLine);
        }
      }
  }
  /**
  public void setAnchorPoint(Point2D.Double point, int anchorType, CubicPoint master) {
      if (anchorType == ANCHOR_FIRST) {
        points[0] = new CubicPoint(point, CubicPoint.ANCHOR_POINT);
        if (master!=null) {
          master.setSlave(points[0]);//first points (after initial point) need to be tied to last anchor point of previous curve
        }
      } else if (anchorType == ANCHOR_LAST) {
        points[3] = new CubicPoint(point, CubicPoint.ANCHOR_POINT);
        if (master!=null) {
          master.setSlave(points[3]);//for closing last point and tying to initial point
        }
      }
  }
  */
  public void setAnchorPoint(Point2D.Double point, int anchorType, CubicPoint master) {
      if (anchorType == ANCHOR_FIRST) {
        //points[0] = new CubicPoint(point, CubicPoint.ANCHOR_POINT);
        if (master!=null) {
            //master.setSlave(points[0]);//first points (after initial point) need to be tied to last anchor point of previous curve
	        	points[0] = master;
        } else {
        		points[0] = new CubicPoint(point, CubicPoint.ANCHOR_POINT);
        }
      } else if (anchorType == ANCHOR_LAST) {
        if (master!=null) {
        		points[3] = master;//for closing last point and tying to initial point
        } else {
        		points[3] = new CubicPoint(point, CubicPoint.ANCHOR_POINT);
        }
      }
  }
  public void setAnchorPoint(CubicPoint master, int anchorType) {
	  
      if (anchorType == ANCHOR_FIRST) {
        points[0] = master;

      } else if (anchorType == ANCHOR_LAST) {
        points[3] = master;

      }
  }
  /**
   * 
   */
  public void setPoint(int index, CubicPoint cP) {
	  //System.out.println("CubicCurve, setPoint, point: " + points[index] + "  weld point: " + cP);
	  points[index] = cP;
  }
  /**
   * for setting individual control points (when editing mode - see setAllPoints in CubicCurveManager
   * @param point
   * @param index
   */
  public void setControlPoint(Point2D.Double point,int index) {
	  points[index] = new CubicPoint(point, CubicPoint.CONTROL_POINT);
  }
  /**
   * calculates intermediate control points when initially placing anchor points
   */
  public void setControlPoints() {
      if (points[0] != null && points[3] != null) {
          double diffX = points[3].getPos().x-points[0].getPos().x;
          double diffY = points[3].getPos().y-points[0].getPos().y;
          double incX = diffX/3;
          double incY = diffY/3;
          points[1] = new CubicPoint(new Point2D.Double(points[0].getPos().x+incX, points[0].getPos().y+incY), CubicPoint.CONTROL_POINT);
          points[2] = new CubicPoint(new Point2D.Double(points[0].getPos().x+(2*incX), points[0].getPos().y+(2*incY)), CubicPoint.CONTROL_POINT);
      } else {
          System.out.println("not all anchor points set");
      }
  }
  
  /**
   * sets position of control points to particular values
   * for loading from xml
   */
  public void setControlPoints(Point2D.Double c1, Point2D.Double c2) {
      if (points[0] != null && points[3] != null) {
          points[1] = new CubicPoint(c1, CubicPoint.CONTROL_POINT);
          points[2] = new CubicPoint(c2, CubicPoint.CONTROL_POINT);
      } else {
          System.out.println("not all anchor points set");
      }
  }
  
  
  
  /**
   * calculates intermediate control points when snap to grid (BezierControlPanel)
   */
  public void resetControlPoints() {
      if (points[0] != null && points[3] != null) {
          double diffX = points[3].getPos().x-points[0].getPos().x;
          double diffY = points[3].getPos().y-points[0].getPos().y;
          double incX = diffX/3;
          double incY = diffY/3;
          points[1].setPos(new Point2D.Double(points[0].getPos().x+incX, points[0].getPos().y+incY));
          points[2].setPos(new Point2D.Double(points[0].getPos().x+(2*incX), points[0].getPos().y+(2*incY)));
      } else {
          System.out.println("not all anchor points set");
      }
  }
  
  public CubicPoint[] getPoints() {
      return points;
  }
  
  public CubicPoint getPoint(int index) {
      return points[index];
  }
  public void switchDrawLinesToAnchor() {
      drawLinesToAnchor = !drawLinesToAnchor;
  }
/**
 * @param strokeCol the strokeCol to set
 */
  public void setStrokeCol(Color strokeCol) {
	  this.strokeCol = strokeCol;
  }
  public void setPointPos (int pointIndex, Point2D.Double pos) {
	  points[pointIndex].setPos(pos);
  }
  
  
}
