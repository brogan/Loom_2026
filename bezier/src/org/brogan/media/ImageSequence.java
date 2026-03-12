package org.brogan.media;

import org.brogan.ui.ExtensionFileFilter;
import java.awt.Image;
import java.awt.image.BufferedImage;
import java.io.File;

public class ImageSequence {
	
	private final ExtensionFileFilter filter = new ExtensionFileFilter();
	
	private int totImages;
	private float imIncrement;
	private float imIncCount;
	private int imCount;
	private String dir;
	private String prefix;
	private String extn;
	
	public ImageSequence(File d, float inc) {
		setFilterExtns();
		dir = d.getPath();
		imIncCount = 0;
		imCount = 0;
		String[] allFiles = d.list();
		setTotalImages(allFiles);
		prefix = getPrefix(allFiles);
		String[] allFiles2 = d.list();
		extn = getExtn(allFiles2);
		imIncrement = inc;
	}
	
	public BufferedImage getImage() {
		String filePath = getFilePath();
		Image image = ImageLoader.loadImage(filePath);
		incrementImage();
		return ((BufferedImage) image);
	}
	
	private void incrementImage() {
		if (imIncCount<totImages-imIncrement) {
			imIncCount+=imIncrement;
		} else {
			imIncCount = 0;
		}
		imCount = ((Float)imIncCount).intValue();
		System.out.println("imCount: "+imCount);
	}
	
	private void setTotalImages(String[] allFiles) {
		for (int i = 0;i<allFiles.length;i++){
			if (filter.accept(new File(allFiles[i]))) {
				totImages++;
			} else {
				System.out.println("not an image in ImageSequence setTotalImages");
			}
		}
	}
	
	public String getFilePath() {
		String fileName = dir + File.separator;
		System.out.println("ImageSequence, getFilePath, filePath: " + fileName);
		System.out.println("ImageSequence, getFilePath, prefix: " + prefix);
		if (imCount<10) {
			fileName += prefix + "00000" + imCount + "." + extn;
    	} else if (imCount>9 && imCount<100) {
    		fileName += prefix + "0000" + imCount +"."+ extn;
    	} else if (imCount>99 && imCount<1000) {
    		fileName += prefix + "000" + imCount + "." + extn;
    	} else if (imCount>999 && imCount<10000) {
    		fileName += prefix + "00" + imCount + "." + extn;
    	} else if (imCount>9999 && imCount<100000) {
    		fileName += prefix + "0" + imCount + "." + extn;
    	} else if (imCount>99999 && imCount<1000000){
    		fileName += prefix + imCount + "." + extn;
    	} else {
    		fileName = "too_many_images";
    		System.out.println("more than 9999999 images in the sequence!!!");
    	}
		return fileName;
	}
	
	private void setFilterExtns() {
		filter.addExtension("jpeg");
		filter.setDescription("jpeg files");
		filter.addExtension("JPEG");
		filter.setDescription("JPEG files");
		filter.addExtension("jpg");
		filter.setDescription("jpg files");
		filter.addExtension("JPG");
		filter.setDescription("JPG files");
		filter.addExtension("png");
		filter.setDescription("png files");
		filter.addExtension("PNG");
		filter.setDescription("PNG files");
	}
	
	private String getPrefix(String[] allFiles) {
		for (int i=0;i<allFiles.length;i++) {
			if (filter.accept(new File(allFiles[i]))) {
				String[] paths = allFiles[i].split(File.pathSeparator);
				String [] name = paths[paths.length-1].split("_");
				return (name[0]+"_");
			}
		}
		return "no images so no prefix in ImageSequence getExtn";
	}
	
	private String getExtn(String[] allFiles) {
		for (int i=0;i<allFiles.length;i++) {
			if (filter.accept(new File(allFiles[i]))) {
				String[] subName = allFiles[i].split("\\.");
				//System.out.println("the file: " +allFiles[i]);
				return subName[1];
			}
		}
		return "no images so no extension in ImageSequence getExtn";
	}
	
	

}
