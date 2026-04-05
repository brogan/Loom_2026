package org.loom.scene

import scala.collection.mutable.ArrayBuffer
import org.loom.utility._

/**
 * Defines a set of one or more renderers and manages the logic of how they are selected.
 * This gets accessed in Sprite2D & Sprite3D in the draw cycle
 */

class RendererSet(val name: String) {
	
	val rendererSet: ArrayBuffer[Renderer] = new ArrayBuffer[Renderer]
	var currentRenderer: Renderer = null
	var selectedIndex: Int = 0
	var preferredRendererIndex: Int = 0//the one most likely to chosen for rendering when randomIndexChange is true
	var preferredProbability: Double = 100//the associated percentage probability that preferred renderer will be chosen

	var staticRendering: Boolean = true//no sequenced or random changing of renderers, no altering rendering parameters

	var modifyInternalParameters: Boolean = false//randomises the parameters within an individual renderer
	var frozen: Boolean = false // when true, updateRenderer skips parameter changes (for global pause)

	//mutually exclusive
	var sequenceIndexChange: Boolean = false//accesses renderers in sequence from first to last and repeat - can then have subsequent modified parameters
	var randomIndexChange: Boolean = false//selects a random renderer - can then have subsequent modified parameters
	var allRenderersActive: Boolean = false//draws the shape once with every renderer in the set each draw cycle



	override def toString(): String = {
		var s: String = "RENDERER SET" + "\n"
		for(i <- 0 until rendererSet.length) {
			s += rendererSet(i).toString
		}
		s
	}
    //convenience method to allow renderers to modify their internal parameters
	def modifyRenderers(): Unit = {
		staticRendering = false
		modifyInternalParameters = true
	}
    //convenience method for accessing renderers in sequence: preferred renderer index, preferred probability
	def sequenceRendererSet(preferred: Int, prob: Double): Unit = {
		staticRendering = false
		preferredRendererIndex = preferred
		preferredProbability = prob
		sequenceIndexChange = true
		randomIndexChange = false
	}

	//convenience method for running all renderers every draw cycle
	def allRenderersMode(): Unit = {
		staticRendering = false
		allRenderersActive = true
		sequenceIndexChange = false
		randomIndexChange = false
	}

	//convenience method for acccessing renderers randomly: preferred renderer index, preferred probability
	def randomRendererSet(preferred: String, prob: Double): Unit = {
		staticRendering = false
		preferredRendererIndex = getRendererIndex(preferred)
		preferredProbability = prob
		randomIndexChange = true
		sequenceIndexChange = false
	}

	def updateRenderer(scale: Int): Unit = {

		if (rendererSet.length > 0) {
			currentRenderer = rendererSet(selectedIndex)
			if (!staticRendering && modifyInternalParameters && !frozen) {
				currentRenderer.update(scale)//change parameters in single renderer depending upon its modification settings
			}
		}
	}

//this gets called in drawing sprite2D for each poly draw
	def getRenderer(): Renderer = {

		if (rendererSet.length > 0) {
			if (rendererSet.length == 1) {
				currentRenderer = rendererSet(selectedIndex)
			} else {
				if (staticRendering) {
					currentRenderer = rendererSet(selectedIndex)
				} else {
					if (sequenceIndexChange) {
						currentRenderer = getNextRenderer()
					} else if (randomIndexChange) {
						currentRenderer = getRandomRendererConsideringPreferredRenderer()
					}

				}

			}
		} else {
			println(s"[Loom] Warning: RendererSet '$name' has no renderers — getRenderer() returning null")
		}
		currentRenderer

	}

	def add(renderer: Renderer): Unit = {
		rendererSet += renderer
	}

	def setPreferredRenderer(n:String): Unit = {
		if (rendererSet.length > 0) {
			for(i <- 0 until rendererSet.length) {
				if (rendererSet(i).name == n) {
					preferredRendererIndex = i
				}
			}
		} else {
			println("Renderer Set contains no renderers so cannot set preferred rendeerer")
		}
	}
	def setPreferredRenderer(index: Int): Unit = {
		if (index > -1 && index <  rendererSet.length) {
			preferredRendererIndex = index
		} else {
			println("Renderer Set specified preferred Renderer index is out of bounds")
		}
	}

	def remove(n: String): Unit = {
		val r: Renderer = getRenderer(n)
		if (rendererSet.length > 0) {
			if (r != null) {
				rendererSet -= r
			} else {
				println("Renderer Set can't remove specified renderer (contains no such named renderer)")
			}
		} else {
			println("Renderer Set contains no renderers so nothing to remove")
		}
	}

	def setCurrentRenderer(n:String): Unit = {
		if (rendererSet.length > 0) {
			for(i <- 0 until rendererSet.length) {
				if (rendererSet(i).name == n) {
					currentRenderer = rendererSet(i)
					selectedIndex = i
				} 
			}
		} else {
			println("Renderer Set contains no renderers so cannot set current rendeerer")
		}
	}

	def setCurrentRenderer(index: Int): Unit = {
		if (index > -1 && index <  rendererSet.length) {
			currentRenderer = rendererSet(index)
			selectedIndex = index
		} else {
			println("Renderer Set specified Renderer index is out of bounds")
		}
	}

	def getRenderer(index: Int): Renderer = {

		var r: Renderer = null
		if (rendererSet.length > 0) {

			r = rendererSet(index)

		} else {
			println("Renderer Set contains no renderers so returning null")
		}
		r
	}

	def getRenderer(n: String): Renderer = {

		var r: Renderer = null
		if (rendererSet.length > 0) {
			for(i <- 0 until rendererSet.length) {
				if (rendererSet(i).name == n) r = rendererSet(i)
			}
			if (r == null) println(s"[Loom] Warning: RendererSet '$name' contains no renderer named '$n'")
		} else {
			println(s"[Loom] Warning: RendererSet '$name' contains no renderers (getRenderer)")
		}
		r
	}

	def getRendererIndex(n: String): Int = {

		var r: Int = -1
		if (rendererSet.length > 0) {

			for(i <- 0 until rendererSet.length) {
				if (rendererSet(i).name == n) {
					r = i
				} else {
					//println("getRendererIndex: Renderer Set contains no such renderer - can't find the specified name")
				}
			}

		} else {
			//println("Renderer Set contains no renderers so returning null")
		}
		if (r == -1) {
			r = 0
			//System.out.println("RendererSet, getRendererIndex not available so index set to 0")
		} 
		//return index
		r
	}

	def getRandomRendererConsideringPreferredRenderer(): Renderer = {

		var r: Renderer = null
		val preferredSelected: Boolean = Randomise.probabilityResult(preferredProbability)
		if (preferredSelected) {
			r = rendererSet(preferredRendererIndex)
		} else {
			r = getRandomRenderer()
		}
		r
	}

//this method includes the preferred renderer so increases probability that it is chosen - may need to fix
	def getRandomRenderer(): Renderer = {

		var r: Renderer = null
		if (rendererSet.length > 0) {

			val max: Int = rendererSet.length-1
			val ran: Int = Randomise.range(0, max)
			r = rendererSet(ran)

		} else {
			println("Renderer Set can't get a random renderer (contains no renderers) so returning null")
		}
		r

	}

	def getNextRenderer(): Renderer = {

		var r: Renderer = null
		if (rendererSet.length > 0) {
			if (selectedIndex < rendererSet.length-1) {
				selectedIndex = selectedIndex + 1
			} else {
				selectedIndex = 0
			}
			r = rendererSet(selectedIndex)

		} else {
			println("Renderer Set can't get next renderer (contains no renderers) so returning null")
		}
		r

	}

	/**

	//need to adjust stroke width on the basis of quality multiple in configuration file
	def multiplyStrokeWidth(multiplier: Float): Unit = {
		if (rendererSet.length > 0) {
			for(i <- 0 until rendererSet.length) {
				rendererSet(i).strokeWidth = rendererSet(i).strokeWidth * multiplier
				rendererSet(i).randomStrokeWidthRange = new Range(rendererSet(i).randomStrokeWidthRange.min * multiplier, rendererSet(i).randomStrokeWidthRange.max * multiplier)
			}
		} else {
			println("Renderer Set contains no renderers so no stroke width to multiply")
		}
	}



	def getRandomisedFilledStrokedRenderer(sWSpecified: Boolean, sWS: Float, sWR: Range, sCSpecified: Boolean, sCS: Color, sCR: Range, sCG: Range, sCB: Range, sCA: Range, fCSpecified: Boolean, fCS: Color, fCR: Range, fCG: Range, fCB: Range, fCA: Range): Renderer = {

		val n: String = "random"
		val ren: Renderer = new Renderer(n, Renderer.FILLED_STROKED, .1f, Renderer.BLACK, Renderer.YELLOW)
		if (sWSpecified) {
			ren.strokeWidth = sWS
		} else {
			val w: Double = Randomise.range(sWR.min, sWR.max)
			ren.strokeWidth = w.toFloat
		}
		if (sCSpecified) {
			ren.strokeColor = sCS
		} else {
			val r: Int = Randomise.range(sCR.min.toInt, sCR.max.toInt)
			val g: Int = Randomise.range(sCG.min.toInt, sCG.max.toInt)
			val b: Int = Randomise.range(sCB.min.toInt, sCB.max.toInt)
			val a: Int = Randomise.range(sCA.min.toInt, sCA.max.toInt)
			ren.strokeColor = new Color(r, g, b, a)
		}
		if (fCSpecified) {
			ren.fillColor = fCS
		} else {
			val r: Int = Randomise.range(fCR.min.toInt, fCR.max.toInt)
			val g: Int = Randomise.range(fCG.min.toInt, fCG.max.toInt)
			val b: Int = Randomise.range(fCB.min.toInt, fCB.max.toInt)
			val a: Int = Randomise.range(fCA.min.toInt, fCA.max.toInt)
			ren.fillColor = new Color(r, g, b, a)
		}
		ren

	}

	*/





}