package org.brogan.bezier;

import java.awt.Color;
import java.awt.Graphics;
import java.awt.Graphics2D;

/**
 * GridAxes
 * @author brogan bunt
 *
 */

public class GridAxes {
	
	private int gridWidth;
	private int gridHeight;
	private int edgeOffset;
	private int[][] verts;
	private int[][] horiz;
	private Color oddAxes;
	private Color evenAxes;
	private boolean displayGridAxes;
	
	/**
	 * 
	 * @param width (width of grid, assumed to be square)
	 * @param numDivs (or number of axes)
	 * @param edgeOff (x and y offset value, again assumed to be equal)
	 * @param c color
	 */
	public GridAxes(int width, int numDivs, int edgeOff, Color odd, Color even) {
		gridWidth = width;
		gridHeight = width;
		edgeOffset = edgeOff;
		oddAxes = odd;
		evenAxes = even;
		displayGridAxes = true;
		
		int xInc = gridWidth/numDivs;
		int yInc = gridHeight/numDivs; //square
		
		verts = new int[numDivs + 1][2];
		horiz = new int[numDivs + 1][2];
		
		int x = 0;
		int y = 0;
		for (int i = 0; i < numDivs + 1; i++) {
			verts[i] = new int[2];
			verts[i][0] = x + edgeOffset;
			verts[i][1] = x+gridHeight+edgeOffset;
			x += xInc;
			
			horiz[i] = new int[2];
			horiz[i][0] = y + edgeOffset;
			horiz[i][1] = y+gridWidth + edgeOffset;
			y += yInc;
		}
	}
	/**
	 * 
	 * @param g (Graphics)
	 */
	public void draw(Graphics g) {
		if (displayGridAxes) {
			Graphics2D g2D = (Graphics2D)g;
			for (int i = 0; i < verts.length; i++) {
				if (i % 2 != 0) {
					g2D.setColor(evenAxes);
				} else {
					g2D.setColor(oddAxes);
				}
				g2D.drawLine(verts[i][0], edgeOffset, verts[i][0], gridWidth + edgeOffset);
				g2D.drawLine(edgeOffset, horiz[i][0], gridWidth + edgeOffset, horiz[i][0]);
			}
		}
	}
	/**
	 * @return the verts
	 */
	public int[][] getVerts() {
		return verts;
	}
	/**
	 * @return the horiz
	 */
	public int[][] getHoriz() {
		return horiz;
	}
	/**
	 * toggle grid axes display
	 */
	public void toggleGridAxesDisplay() {
		displayGridAxes = !displayGridAxes;
	}

}
