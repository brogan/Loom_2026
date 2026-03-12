package org.loom.config

import java.awt.Color

/**
 * Global configuration for a Loom project.
 * Contains canvas size, rendering modes, and other global settings.
 */
case class GlobalConfig(
  name: String = "Untitled",
  width: Int = 1080,
  height: Int = 1080,
  qualityMultiple: Int = 1,
  scaleImage: Boolean = false,
  animating: Boolean = false,
  drawBackgroundOnce: Boolean = true,
  fullscreen: Boolean = false,
  borderColor: Color = Color.BLACK,
  backgroundColor: Color = Color.WHITE,
  overlayColor: Color = Color.BLACK,
  backgroundImagePath: String = "",
  threeD: Boolean = false,
  cameraViewAngle: Int = 120,
  subdividing: Boolean = true
) {
  override def toString: String =
    s"""GlobalConfig:
       |  name: $name
       |  width: $width, height: $height
       |  qualityMultiple: $qualityMultiple
       |  scaleImage: $scaleImage
       |  animating: $animating
       |  drawBackgroundOnce: $drawBackgroundOnce
       |  fullscreen: $fullscreen
       |  borderColor: $borderColor
       |  backgroundColor: $backgroundColor
       |  overlayColor: $overlayColor
       |  backgroundImagePath: $backgroundImagePath
       |  threeD: $threeD
       |  cameraViewAngle: $cameraViewAngle
       |  subdividing: $subdividing""".stripMargin
}

object GlobalConfig {
  def default: GlobalConfig = GlobalConfig()
}
