package org.brogan.bezier;

import java.awt.*;
import java.awt.geom.*;

public class DragOval {
  
  private CubicPoint cubicPoint;
  private Point2D.Double dim;
  private Color fillCol;
  private Color selectedCol;
  private Color deselectedCol;
  private Color strokeCol;
  private float strokeWeight;
  
  public DragOval() {
  }
  
  public DragOval(Color c, Color cS, CubicPoint cP) {
      cubicPoint = cP;
      dim = new Point2D.Double(10,10);
      fillCol = c;
      deselectedCol = c;
      selectedCol = cS;
      strokeCol = new Color(0,0,0);
  }
  public void draw(Graphics2D g2D) {
      g2D.setColor(fillCol);
      Ellipse2D.Double ellipse = new Ellipse2D.Double(cubicPoint.getPos().x-(dim.x/2), cubicPoint.getPos().y-(dim.y/2), dim.x, dim.y);
      g2D.fill(ellipse);
      
      g2D.setStroke(new BasicStroke(strokeWeight));
      g2D.setColor(strokeCol);
      g2D.draw(ellipse);
  }

  public double getWidth() {
      return dim.x;
  }
  public void setSelected () {
	  fillCol = selectedCol;
	  dim = new Point2D.Double(14,14);
  }
  public void setDeselected () {
	  fillCol = deselectedCol;
	  dim = new Point2D.Double(10,10);
  }
  
}
