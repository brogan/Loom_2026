/**
 * 
 */
package org.brogan.bezier;

import java.awt.*;
/**
 * add one sentence class summary here add class description here
 * 
 * @author brogan
 * @version 1.0, Jul 19, 2006
 */
public class Grid {

	private int rows;// number of rows
	private int cols;// number of columns
	private int startX;// the initial x coordinate
	private int startY;// the initial y coordinate
	private int squareWidth;// the width of each square
	private int squareHeight;// the height of each square
	private int xOffset;// the horizontal distance to offset each square in the grid
	private int yOffset;// the vertical distance to offset each square in the grid
	private Square[] squares;// the array of squares
	private boolean displayGrid;

	public Grid(int r, int c, int x, int y, int w, int h, int xO, int yO) {
		rows = r;
		cols = c;
		startX = x;
		startY = y;
		squareWidth = w;
		squareHeight = h;
		xOffset = xO;
		yOffset = yO;
		displayGrid = true;
		squares = new Square[rows * cols];// creates a new empty array of squares of the specified size
		createSquares();// calls an internal method to fill the square array with square objects
	}

	// private method to create new grid of square objects
	private void createSquares() {
		long ranSeed = System.currentTimeMillis();
		int count = 0;// a local variable storing our total count as we loop through the array of squares
		// the following section of code contains two repeat loops
		// the columns repeat loop is nested within the rows repeat loop
		// so we move through the array of squares one row at a time and address
		// each column position within each row
		for (int r = 0; r < rows; r++) {// loop through the rows
			for (int c = 0; c < cols; c++) {// loop through the columns current squareX = startX + columns * the sum of squareWidth and xOffset
				int squareX = startX + (c * (squareWidth + xOffset));
				// current squareY = startY + rows * the sum of squareHeight and yOffset
				int squareY = startY + (r * (squareHeight + yOffset));
				ranSeed+=20;
				squares[count] = new Square(squareX, squareY, squareWidth, squareHeight, ranSeed);
				count++;// add one to the count value (so move to the next square in the array)
			}
		}
	}
	public void update() {
		long ranSeed = System.currentTimeMillis();
		int count = 0;
		for (int r = 0; r < rows; r++) {// loop through rows
			for (int c = 0; c < cols; c++) {// loop through columns
				ranSeed+=20;
				//System.out.println("update square");
				squares[count].update(ranSeed);// tell each square in the square array to draw
				count++;
			}
		}
	}

	// publicly accessible method (called from draw method in main sketch)
	// which in turn calls the draw method in each grid square
	public void draw(Graphics g) {
		if (displayGrid) {
			int count = 0;
			//draw non-axes grid squares
			for (int r = 0; r < rows; r++) {// loop through rows
				for (int c = 0; c < cols; c++) {// loop through columns
					//System.out.println("draw square");
					squares[count].draw(g);// tell each square in the square array to draw
					count++;
				}
			}
		}
	}
	/**
	 * 
	 * @return horizontal coordinates (left & right)
	 */
	public int[][] getHoriz() {
		int[][] horiz = new int[cols+1][2];
		for (int i = 0; i < cols+1; i++) {
			horiz[i][0] = ((i*squareWidth))+xOffset+startX;
			horiz[i][1] = ((cols*squareWidth))+xOffset+startX;
		}
		return horiz;
	}
	/**
	 * 
	 * @return vertical coordinates (top & bottom)
	 */
	public int[][] getVerts() {
		int[][] verts = new int[rows+1][2];
		for (int i = 0; i < rows+1; i++) {
			verts[i][0] = ((i*(squareHeight)))+yOffset+startY;
			verts[i][1] = ((rows*(squareHeight)))+yOffset+startY;
		}
		return verts;
	}

	/**
	 * @return the squares
	 */
	public Square[] getSquares() {
		return squares;
	}
	/**
	 * 
	 */
	public void toggleGridDisplay() {
		displayGrid = !displayGrid;
	}

}
