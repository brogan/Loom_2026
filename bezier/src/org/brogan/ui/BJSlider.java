package org.brogan.ui;

import javax.swing.*;

public class BJSlider extends JSlider {
	
	private String name;
	BJSliderListener listener;
	
	public BJSlider(int min, int max, int def, String n) {
		super(min, max, def);
		name = n;
		//BJSliderListener listener = new BJSliderListener(this);
	}

	/**
	 * @return the name
	 */
	public String getName() {
		return name;
	}
	/**
	 * 
	 */
	public void sliderReleased() {
		System.out.println("BJSlider released");
	}

}
