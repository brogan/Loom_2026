package org.loom.geometry

import scala.collection.mutable.ListBuffer

class OpenCurveSetCollection() {

  val collection: ListBuffer[OpenCurveSet] = new ListBuffer[OpenCurveSet]()

  def add(s: OpenCurveSet): Unit = collection += s

  def getSet(name: String): OpenCurveSet =
    collection.find(_.name == name).getOrElse(null)
}
