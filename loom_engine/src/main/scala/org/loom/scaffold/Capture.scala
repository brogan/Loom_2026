package org.loom.scaffold

import org.loom.config.ProjectConfigManager
import java.io._
import scala.util.Try

object Capture {

	var savingStill: Boolean = false
	var savingVideo: Boolean = false
	var savePath: String = ""
    def prefix: String = Config.name + "_"   // def so it always reflects current Config.name
    var fileDirectory: File = null
	var writePath: String = "no capture write path"
    val extension: String = ".png"
    var saveCount: Int = 0

	/**
	 * Find the highest sequential number already present in dir whose filename
	 * matches <prefix><number><extension>. Returns 0 if no matching files exist.
	 */
	private def maxExistingNumber(dir: File, pfx: String): Int = {
		val files = Option(dir.listFiles()).getOrElse(Array.empty[File])
		files.flatMap { f =>
			val name = f.getName
			if (name.startsWith(pfx) && name.endsWith(extension)) {
				val middle = name.substring(pfx.length, name.length - extension.length)
				Try(middle.toInt).toOption
			} else None
		}.maxOption.getOrElse(0)
	}

	/**
	 * Get the render base directory.
	 * Checks for a .render_path file in the project directory first,
	 * then falls back to <projectDir>/renders/
	 */
	private def getRenderBaseDir(): String = {
		val projectPath = ProjectConfigManager.currentProjectPath
		if (projectPath.nonEmpty) {
			// Check for custom render path
			val renderPathFile = new File(projectPath, ".render_path")
			if (renderPathFile.exists()) {
				val customPath = scala.io.Source.fromFile(renderPathFile).mkString.trim
				if (customPath.nonEmpty) return customPath
			}
			// Default: <projectDir>/renders
			projectPath + File.separator + "renders"
		} else {
			// Legacy fallback
			org.loom.media.ProjectFilePath.filePath + File.separator + "sketches" + File.separator + Config.sketchName + File.separator + "captures"
		}
	}

	/**
	 * Capture Still
	 */
	def captureStill(): Unit = {
		val baseDir = getRenderBaseDir()
		fileDirectory = new File(baseDir + File.separator + "stills")
		if (!fileDirectory.isDirectory()) {
			fileDirectory.mkdirs()
		}
		saveCount = maxExistingNumber(fileDirectory, prefix) + 1
		writePath = fileDirectory.toString() + File.separator + prefix + saveCount.toString()
		println(s"[Loom] Capture still → $writePath")
		savingStill = true
		savingVideo = false
	}
	/**
	 * Capture Video
	 */
    def captureVideo(): Unit = {
		val baseDir = getRenderBaseDir()
		fileDirectory = new File(baseDir + File.separator + "animations")
		if (!fileDirectory.isDirectory()) {
			fileDirectory.mkdirs()
		}
		saveCount = maxExistingNumber(fileDirectory, prefix)
		writePath = fileDirectory.toString() + File.separator + prefix + saveCount.toString()
		println(s"[Loom] Capture video → $fileDirectory")
		savingStill = false
		savingVideo = true
	}
    /**
     * called from DrawPanel
     */
    def incrementSaveCount(): Unit = {
    	saveCount += 1
		val baseDir = getRenderBaseDir()
    	fileDirectory = new File(baseDir + File.separator + "animations")
    	writePath = fileDirectory.toString() + File.separator + prefix + saveCount.toString()
    }

}
