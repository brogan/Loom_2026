package org.brogan.bezier;

import java.awt.*;
import java.awt.geom.*;

public class CubicPoint {
	  
    public static final int ANCHOR_POINT = 0;
    public static final int CONTROL_POINT = 1;
  
    private int type;
    private Point2D.Double origPos;
    private Point2D.Double pos;
    private Point2D.Double origScale;
    private Point2D.Double scale;
    private Point2D.Double origRotation;
    private Point2D.Double rotation;
    private Point2D.Double currentPos;//at the start of any drag move
    private DragOval oval;
    private boolean ovalDrawing;
    private boolean selected;
    private boolean selectable;
    
    private CubicPoint slave;//another CubicPoint that is tied to this one
    
    private Color anchorFill;
    private Color controlFill;
    private Color anchorSelectedFill;
    private Color controlSelectedFill;

    public CubicPoint(Point2D.Double p, int t) {
	    	origPos = new Point2D.Double(p.x, p.y);
	    	pos = new Point2D.Double(p.x, p.y);
	    	scale = new Point2D.Double(1.0, 1.0);
	    	origScale = new Point2D.Double(1.0, 1.0);
	    	rotation = new Point2D.Double(0, 0);
	    	origRotation = new Point2D.Double(0, 0);
	    	type = t;
	    	anchorFill = new Color(0,230,50, 100);
	    	anchorSelectedFill = new Color(230,250,0,200);
	    	controlFill = new Color(230,50,0, 50);
	    	controlSelectedFill = new Color(230,100,0,200);
	    	if (type == ANCHOR_POINT) {
	    		oval = new DragOval(anchorFill, anchorSelectedFill, this);
	    	} else {
	    		oval = new DragOval(controlFill, controlSelectedFill, this);
	    	}
	    	ovalDrawing = true;
	    	selected = false;
	    	currentPos = new Point2D.Double(0,0);
    }
    public void draw(Graphics2D g2D) {
	    	if (ovalDrawing) {
	    		oval.draw(g2D);
	    	}
    }
    
    public void drag(Point2D.Double p) {
      System.out.println("dragging cubic point");
      pos = p;
      if (slave!=null) {
    	System.out.println("dragging slave");
        slave.drag(p);
      }
    }
    
    public Point2D.Double getPos() {
      return pos;
    }
    public DragOval getOval() {
      return oval;
    }
    public void setSlave(CubicPoint s) {
      System.out.println("setting slave in CubicPoint: "+s.getClass());
      slave = s;
      if (slave==null) {
    	  System.out.println("slave is null in CubicPoint");
      } else {
    	  System.out.println("slave is NOT null in CubicPoint");
      }
    }
    public void switchOvalDrawing() {
      ovalDrawing = !ovalDrawing;
    }
	/**
	 * @return the type
	 */
	public int getType() {
		return type;
	}
	/**
	 * @return the currentPos
	 */
	public Point2D.Double getCurrentPos() {
		return currentPos;
	}
	/**stores the current position
	 * when mouse is first pressed (prior to dragging)
	 * @param currentPos the currentPos to set
	 */
	public void setCurrentPos() {
		this.currentPos.x = getPos().x;
		this.currentPos.y = getPos().y;
	}
	/**
	 * @param pos the pos to set
	 */
	public void setPos(Point2D.Double pos) {
		this.pos = pos;
	}
	/**
	 * @return the origPos
	 */
	public Point2D.Double getOrigPos() {
		return origPos;
	}
	/**
	 * sets the orig pos to the current pos when mouse released on slider
	 */
	public void setOrigPosToPos() {
		origPos.x = pos.x;
		origPos.y = pos.y;
	}
	/**
	 * @return the origScale
	 */
	public Point2D.Double getOrigScale() {
		return origScale;
	}
	/**
	 * @param origScale the origScale to set
	 */
	public void setOrigScaleToScale() {
		origScale.x = scale.x;
		origScale.y = scale.y;
	}
	/**
	 * @return the origRotation
	 */
	public Point2D.Double getOrigRotation() {
		return origRotation;
	}
	/**
	 * @param origRotation the origRotation to set
	 */
	public void setOrigRotationToRotation() {
		origRotation.x = rotation.x;
		origRotation.y = rotation.y;
	}
	/**
	 * @return the scale
	 */
	public Point2D.Double getScale() {
		return scale;
	}
	/**
	 * @return the rotation
	 */
	public Point2D.Double getRotation() {
		return rotation;
	}
	/**
	 * @param scale the scale to set
	 */
	public void setScale(Point2D.Double scale) {
		this.scale = scale;
	}
	/**
	 * @param rotation the rotation to set
	 */
	public void setRotation(Point2D.Double rotation) {
		this.rotation = rotation;
	}
	public void toggleSelected() {
		if (!selected) {
			oval.setSelected();
			selected = true;
		} else {
			oval.setDeselected();
			selected = false;
		}
	}
	public boolean isSelected() {
		return selected;
	}
 
  
}
