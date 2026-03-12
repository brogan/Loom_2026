/**
 * 
 */
package org.brogan.bezier;
import java.awt.*;
import java.util.*;

/**
 * add one sentence class summary here add class description here
 * 
 * @author brogan
 * @version 1.0, Jul 19, 2006
 */
public class Square {

	private int myX;// x coordinate
	private int myY;// y coordinate
	private int myWidth;// width
	private int myHeight;// height
	private Color color;

	// constructor method for the square
	public Square(int x, int y, int w, int h, long rS) {
		myX = x;
		myY = y;
		myWidth = w;
		myHeight = h;
		color = new Color(200,200,200);
	}
	public void update(long r) {
		//
	}

	// draws method for the square (actually draws a rectangle!)
	public void draw(Graphics g) {
		Graphics2D g2D = (Graphics2D)g;
		g2D.setColor(color);
		g2D.drawRect(myX, myY, myWidth, myHeight);
	}
	/**
	 * @return the myX
	 */
	public int getMyX() {
		return myX;
	}
	/**
	 * @return the myY
	 */
	public int getMyY() {
		return myY;
	}
}
