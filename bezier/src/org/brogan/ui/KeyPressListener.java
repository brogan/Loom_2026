/*
 * Created on Aug 7, 2005
 */
package org.brogan.ui;

import java.awt.event.*;

import javax.swing.Action;

import org.brogan.bezier.BezierDrawPanel;

/**
 * description: monitors key events
 * @author brogan
 * @version
 * 
 */
public class KeyPressListener implements KeyListener {
	
	private BezierDrawPanel bezierDrawPanel;
	
	public KeyPressListener(BezierDrawPanel bDP) {
		System.out.println("New KeyPresses");
		bezierDrawPanel = bDP;
	}
	
	public void keyPressed(KeyEvent e) {
		int keyCode = e.getKeyCode();
		//System.out.println("Key code:" + keyCode);
		if (keyCode == KeyEvent.VK_SHIFT) {
			//System.out.println("shift key pressed");
			//bezierDrawPanel.setShiftKey(true);
		} else if (keyCode == KeyEvent.VK_CONTROL) {
			//bezierDrawPanel.setControlKey(true);
		}
		
		if (keyCode == KeyEvent.VK_SPACE) {
			System.out.println("space bar pressed");
		} 
		
		if (keyCode == KeyEvent.VK_N){
			//bezierDrawPanel.getNewProject();
		} else if (keyCode == KeyEvent.VK_O){
			//bezierDrawPanel.openProject();
		} else if (keyCode == KeyEvent.VK_S) {
			//bezierDrawPanel.saveCurrentProject();
		} /**
		else if (keyCode == KeyEvent.VK_D) {
			bezierDrawPanel.setInteractionMode(InteractionMode.DRAWING);
		} else if (keyCode == KeyEvent.VK_I) {
			bezierDrawPanel.setInteractionMode(InteractionMode.IMAGE_DRAWING);
		} else if (keyCode == KeyEvent.VK_E) {
			bezierDrawPanel.setInteractionMode(InteractionMode.ERASING);
		} else if (keyCode == KeyEvent.VK_A) {
			bezierDrawPanel.setInteractionMode(InteractionMode.SELECTING);
		} else if (keyCode == KeyEvent.VK_B) {
			bezierDrawPanel.setInteractionMode(InteractionMode.DESELECTING);
		} else if (keyCode == KeyEvent.VK_P) {
			bezierDrawPanel.switchHighlightAxesVisibility();
		} else if (keyCode == KeyEvent.VK_L) {
			bezierDrawPanel.switchGridVisibility();
		} else if (keyCode == KeyEvent.VK_X) {
			bezierDrawPanel.cut();
		} else if (keyCode == KeyEvent.VK_C) {
			bezierDrawPanel.copy();
		} else if (keyCode == KeyEvent.VK_V) {
			bezierDrawPanel.paste();
		} else if (keyCode == KeyEvent.VK_R) {
			bezierDrawPanel.invertSelection();
		} else if (keyCode == KeyEvent.VK_1) {
			bezierDrawPanel.invertFillColor();
		} else if (keyCode == KeyEvent.VK_2) {
			bezierDrawPanel.invertStrokeColor();
		} else if (keyCode == KeyEvent.VK_3) {
			bezierDrawPanel.invertFillAlpha();
		} else if (keyCode == KeyEvent.VK_4) {
			bezierDrawPanel.invertStrokeAlpha();
		} else if (keyCode == KeyEvent.VK_LEFT) {
			bezierDrawPanel.shiftSquaresLeft();
		} else if (keyCode == KeyEvent.VK_RIGHT) {
			bezierDrawPanel.shiftSquaresRight();
		} else if (keyCode == KeyEvent.VK_UP) {
			bezierDrawPanel.shiftSquaresUp();
		} else if (keyCode == KeyEvent.VK_DOWN) {
			bezierDrawPanel.shiftSquaresDown();
		} else if (keyCode == KeyEvent.VK_Y) {
			bezierDrawPanel.flipHorizontal();
		} else if (keyCode == KeyEvent.VK_U) {
			bezierDrawPanel.flipVertical();
		} else if (keyCode == KeyEvent.VK_J) {
			bezierDrawPanel.mirrorHorizontal();
		} else if (keyCode == KeyEvent.VK_K) {
			bezierDrawPanel.mirrorVertical();
		} else if (keyCode == KeyEvent.VK_PERIOD) {
			bezierDrawPanel.rotateRight();
		} else if (keyCode == KeyEvent.VK_COMMA) {
			bezierDrawPanel.rotateLeft();
		} else if (keyCode == KeyEvent.VK_G) {
			bezierDrawPanel.cloneRotateRight();
		} else if (keyCode == KeyEvent.VK_F) {
			bezierDrawPanel.cloneRotateLeft();
		} else if (keyCode == KeyEvent.VK_W) {
			bezierDrawPanel.clearGrid();
		} else if (keyCode == KeyEvent.VK_H) {
			bezierDrawPanel.getHelp();
		} else if (keyCode == KeyEvent.VK_Z) {
			//bezierDrawPanel.undo();
		} else if (keyCode == KeyEvent.VK_T) {
			//bezierDrawPanel.redo();
		}
		*/

		
	}
	
	public void keyTyped(KeyEvent e) {
		char keyChar = e.getKeyChar();
		//System.out.println("Key char:" + keyChar);
		if (keyChar=='n') {
			System.out.println("n pressed");
		}
	}
	
	public void keyReleased(KeyEvent e) {
		int keyCode = e.getKeyCode();
		if (keyCode == KeyEvent.VK_SHIFT) {
			//bezierDrawPanel.setShiftKey(false);
		} else if (keyCode == KeyEvent.VK_CONTROL) {
			//bezierDrawPanel.setControlKey(false);
		};
	}


}
