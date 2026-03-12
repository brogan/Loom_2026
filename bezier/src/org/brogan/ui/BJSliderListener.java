package org.brogan.ui;

import javax.swing.event.ChangeEvent;
import javax.swing.event.ChangeListener;

public class BJSliderListener implements ChangeListener {

	private BJSlider slider;
	
	public BJSliderListener(BJSlider c) {
		slider = c;
	}
	
	public void stateChanged(ChangeEvent e) {
		BJSlider source = (BJSlider)e.getSource();
		if (!source.getValueIsAdjusting()) {
			source.sliderReleased();
		}
		source.sliderReleased();
	}

}
