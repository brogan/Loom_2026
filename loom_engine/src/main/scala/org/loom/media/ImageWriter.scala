package org.loom.media

import org.loom.scaffold.Capture

import java.awt.image.BufferedImage
import java.io.File
import java.io.IOException

import javax.imageio.ImageIO

/**
 * ImageWriter
 * For writing still and sequence images to file
 * @author brogan
 *
 */
object ImageWriter {

	var writeType: String = "png"
	
	/**
	 * Save image
	 * @param buffer the BufferedImage to save
	 * @param path the save path
	 */
	def saveImage(buffer: BufferedImage): Unit = {
		val imFile: File = new File(Capture.writePath + Capture.extension)
		val hasAlpha: Boolean = buffer.getColorModel().hasAlpha()
		println("buffer alpha in ImageWriter: "+hasAlpha)
		writeImageToFile(buffer, imFile)
	}  
	
	def writeImageToFile (im: BufferedImage, file: File): Unit = {	
		try {
			ImageIO.write(im, writeType, file);
		} catch {
			case _: IOException => println("saving image not working");
		}
	}
	/**
	 * set the format to write images with (jpg, png, tiff)
	 */
	def setWriteType(format: String): Unit = {
		val formats: Array[String]  = ImageIO.getWriterFormatNames()
		for (i <- 0 until formats.length) {
			//println("write format: "+formats(i));
			if (formats(i).equals(format)) {
				writeType = format;
			}
		}
	}
	
}