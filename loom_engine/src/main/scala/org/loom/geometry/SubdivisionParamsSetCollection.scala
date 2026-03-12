package org.loom.geometry

import scala.collection.mutable.ListBuffer

//A SubdivisionParamsSetCollection holds a collection of subdivision parameters sets, which in turn holds a number of subdivision parameters
//A shape and its associated sprite have a set of subdivision parameters
//Collections enable multiple shape/sprites with different subdivision parameter sets
//Sets are named, as are individual subdivision parameters, but the collection is singular and does not need its own name

class SubdivisionParamsSetCollection () {

	val collection: ListBuffer[SubdivisionParamsSet] = new ListBuffer[SubdivisionParamsSet]

	def add(paramsSet: SubdivisionParamsSet): Unit = {
		collection += paramsSet
	}

	def getParamsSet(n: String): SubdivisionParamsSet = {

		var s: SubdivisionParamsSet = null
		if (collection.length > 0) {
			
			for (paramsSet <- collection) {
				if (paramsSet.name == n) {
					s = paramsSet
				}
			}

		} else {
			println("SubdivisionParamsSetCollection is empty so can't get any subdivision params set")
		}
		s

		
	}
}