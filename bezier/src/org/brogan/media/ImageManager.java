package org.brogan.media;

import org.brogan.ui.*;
import java.awt.Image;
import java.awt.image.BufferedImage;
import java.io.File;

public class ImageManager {
	
	private ImportImagesPanel imPanel;
	private BufferedImage im;
	
	private boolean singleImage;
	private boolean sequence;
	
	private ImageSequence seq;
	
	
	public ImageManager(ImportImagesPanel p) {
		imPanel = p;

	}
	
	public BufferedImage getImage() {
		if (singleImage) {
			return im;
		} else {
			if (seq!=null) {
				im = seq.getImage();//sequence object handles incrementing
				return im;
			}
			return null;
		}
	}
	
	
	
}
