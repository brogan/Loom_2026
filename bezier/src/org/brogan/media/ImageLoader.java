package org.brogan.media;


import java.awt.*;
import java.io.File;
import java.io.IOException;

import javax.imageio.ImageIO;

public final class ImageLoader {
	
	/**
	 * load and return the image
	 * returns null if load fails
	 * @param String filePath
	 */
	public static final Image loadImage(String filePath) {
		System.out.println("ImageLoader, filePath: "+filePath);
		try {
			Image image = ImageIO.read(new File(filePath));
			System.out.println("image loaded");
			return image;
		} catch (IOException e) {
			e.printStackTrace();
		}
		return null;
	}
}
