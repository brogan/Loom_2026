package org.loom.transform

import org.loom.geometry._


class PointsTransform() {
	
}

object PointsTransform {

	/**
	 * bulgeOrPucker works with exterior control points, shifting them out or in depending upon whether bulging or puckering is selected.
	 * Where the bezier middle point cooincides with the actual middle point of line (so no curving) then bulging and puckering applied
	 * depending upon settings (and via calulation of perpendicular vectors)
	 * 
	 * 
	 */

	 def transformPoints(polyArray: Array[Polygon2D], subP: SubdivisionParams, centreIndex: Int, sidesTotal: Int, numSidesPerPoly: Int): Unit = {

	 	//val pTP_flags: Map[String, Boolean] = subP.polysTransformPoints_flags// - was used below but no longer needed

	 	val probability: Double = subP.pTP_probability

	 	if (probability > 0) {

	 		for (transform <- subP.pTP_transformSet) {
	 			transform.transform(polyArray, centreIndex, subP.subdivisionType, sidesTotal, numSidesPerPoly)//sidesTotal in original unsubdivided poly, number of sides in subdividided poly (3 or 4 currently)
	 		}
	 		
	 	}

	 }
}


