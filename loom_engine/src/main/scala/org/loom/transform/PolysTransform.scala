package org.loom.transform

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._


class PolysTransform() {
	
}

object PolysTransform {

    def transform(polys: Array[Polygon2D], @unused subdivObj: Subdivision, subP: SubdivisionParams): Unit = {
    	
    	if (subP.pTW_probability > 0) {
    		for (i <- 0 until polys.length) {
    		   val happens: Boolean = Randomise.probabilityResult(subP.pTW_probability)
    		   if (happens) {
    		   		transformPoly(polys(i), subP)	
    		   }
    		}

		} else {

			println("PolysTransform - not all or some")

		} 
    }


    def transformPoly(poly: Polygon2D, subP: SubdivisionParams): Unit = {

    	val centre: Vector2D = Formulas.average(poly.points)//get the centre of the polygon as average of all points

		val adjustedTransform: Transform2D = new Transform2D(new Vector2D(0,0), new Vector2D(1,1), new Vector2D(0,0))

		if (subP.pTW_randomTranslation)  {

			adjustedTransform.translation.x = Randomise.range(subP.pTW_randomTranslationRange.x.min, subP.pTW_randomTranslationRange.x.max)
			adjustedTransform.translation.y = Randomise.range(subP.pTW_randomTranslationRange.y.min, subP.pTW_randomTranslationRange.y.max)
			subP.pTW_transform.translation.x = adjustedTransform.translation.x
			subP.pTW_transform.translation.y = adjustedTransform.translation.y

		}
		if (subP.pTW_randomScale) {

			adjustedTransform.scale.x = Randomise.range(subP.pTW_randomScaleRange.x.min, subP.pTW_randomScaleRange.x.max)
			adjustedTransform.scale.y = Randomise.range(subP.pTW_randomScaleRange.y.min, subP.pTW_randomScaleRange.y.max)
			subP.pTW_transform.scale.x = adjustedTransform.scale.x
			subP.pTW_transform.scale.y = adjustedTransform.scale.y
			
		}
		if (subP.pTW_randomRotation) {

			adjustedTransform.rotation.x = Randomise.range(subP.pTW_randomRotationRange.min, subP.pTW_randomRotationRange.max)
			subP.pTW_transform.rotation.x = adjustedTransform.rotation.x//only the x value is relevant for rotation
			
		}

		if (subP.pTW_commonCentre) {//If common centre is true	
				
			poly.transform(subP.pTW_transform)

		} else {//not a common centre, so we will get tearing

			val newCentre: Vector2D = poly.randomiseMiddle(centre, poly.points(0), subP.pTW_randomCentreDivisor)

			poly.transformAroundOffset(subP.pTW_transform, newCentre)

		}

    }

}