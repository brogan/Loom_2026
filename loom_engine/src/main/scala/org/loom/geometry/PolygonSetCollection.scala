package org.loom.geometry

import scala.collection.mutable.ListBuffer

class PolygonSetCollection() {

	var collection: ListBuffer[PolygonSet] = new ListBuffer[PolygonSet] 

	def add(polySet: PolygonSet): Unit = {
		collection += polySet
	}

	def getPolySet(n: String): PolygonSet = {

		var pSet: PolygonSet = null
		if (collection.length > 0) {
			
			for (polySet <- collection) {
				if (polySet.name == n) {
					pSet = polySet
				}
			}

		} else {
			println("PolygonSetCollection is empty so can't get any PolygonSet")
		}
		pSet

		
	}
	
}