package org.loom.geometry

import scala.collection.mutable.ListBuffer

class OvalSetCollection() {
  val collection: ListBuffer[OvalSet] = new ListBuffer[OvalSet]()

  def add(s: OvalSet): Unit = collection += s

  def getSet(name: String): OvalSet =
    collection.find(_.name == name).getOrElse(null)
}
