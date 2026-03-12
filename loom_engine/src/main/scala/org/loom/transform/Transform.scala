package org.loom.transform

import org.loom.geometry._


abstract class Transform(val transforming: Boolean) {

	def transform(polys: Array[Polygon2D], centreIndex: Int, subdivisionType: Int, sidesTotal: Int, numSidesPerPoly: Int): Unit = {

	}

}
