package org.loom.geometry

import scala.collection.mutable.ListBuffer

class SubdivisionParamsSet (val name: String) {

	val set: ListBuffer[SubdivisionParams] = new ListBuffer[SubdivisionParams]

	def add(params: SubdivisionParams): Unit = {
		set += params
	}

	def getParams(n: String): SubdivisionParams = {

		var p: SubdivisionParams = null
		if (set.length > 0) {
			
			for (params <- set) {
				if (params.name == n) {
					p = params
				}
			}

		} else {
			println("SubdivisionParamsSet is empty so can't get any subdivision params")
		}
		p

		
	}

	def getParams(index: Int): SubdivisionParams = {

		var p: SubdivisionParams = null
		if (set.length > 0) {
			
			p = set(index)

		} else {
			println("SubdivisionParamsSet is empty so can't get any subdivision params")
		}
		p

		
	}

	def toList(): List[SubdivisionParams] = {
		set.toList
	}
}