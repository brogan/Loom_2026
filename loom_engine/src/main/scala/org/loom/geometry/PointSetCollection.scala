package org.loom.geometry

import scala.collection.mutable.ListBuffer

class PointSetCollection() {
  val collection: ListBuffer[PointSet] = new ListBuffer[PointSet]()

  def add(s: PointSet): Unit = collection += s

  def getSet(name: String): PointSet =
    collection.find(_.name == name).getOrElse(null)
}
