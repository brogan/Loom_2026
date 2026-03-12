package org.loom.scene

import scala.collection.mutable.ArrayBuffer
import org.loom.utility._

/**
 * Stores a libary of renderer sets, which are themselves composed of one or more renderers
 * This is managed at the global MySketch level
 */

class RendererSetLibrary(val name: String) {

    val library: ArrayBuffer[RendererSet] = new ArrayBuffer[RendererSet]
    var currentRendererSet: RendererSet = null
    var selectedIndex: Int = 0
    var preferredRendererSetIndex: Int = 0
    var preferredProbability: Double = 100//the associated percentage probability that preferred renderer will be chosen

    override def toString(): String = {
        var s: String = "RENDERER LIBRARY" + "\n"
        for(i <- library.indices) {
            s += library(i).toString
        }
        s
    }

    def add(rendererSet: RendererSet): Unit = {
        library += rendererSet
    }

    def setPreferredRendererSet(n:String): Unit = {
        if (library.length > 0) {
            for(i <- 0 until library.length) {
                if (library(i).name == n) {
                    preferredRendererSetIndex = i
                }
            }
        } else {
            println("Renderer Library contains no renderer sets so cannot set preferred rendeerer")
        }
    }
    def setPreferredRendererSet(index: Int): Unit = {
        if (index > -1 && index <  library.length) {
            preferredRendererSetIndex = index
        } else {
            println("Renderer Library specified preferred Renderer Set index is out of bounds")
        }
    }

    def remove(n: String): Unit = {
        val r: RendererSet = getRendererSet(n)
        if (library.length > 0) {
            if (r != null) {
                library -= r
            } else {
                println("Renderer Library can't remove specified renderer set (contains no such named renderer set)")
            }
        } else {
            println("Renderer Library contains no renderer sets so nothing to remove")
        }
    }

    def setCurrentRendererSet(n:String): Unit = {
        if (library.length > 0) {
            for(i <- 0 until library.length) {
                if (library(i).name == n) {
                    currentRendererSet = library(i)
                    selectedIndex = i
                }
            }
        } else {
            println("Renderer Library contains no renderer sets so cannot set current rendeerer")
        }
    }

    def setCurrentRendererSet(index: Int): Unit = {
        if (index > -1 && index <  library.length) {
            currentRendererSet = library(index)
            selectedIndex = index
        } else {
            println("Renderer Library: specified Renderer Set index is out of bounds")
        }
    }

    def hasRendererSet(n: String): Boolean =
        library.exists(_.name == n)

    def getRendererSet(index: Int): RendererSet = {

        var r: RendererSet = null
        if (library.length > 0) {

            r = library(index)

        } else {
            println("Renderer Library contains no renderer sets so returning null")
        }
        r
    }

    def getRendererSet(n: String): RendererSet = {

        var r: RendererSet = null
        if (library.length > 0) {
            for(i <- 0 until library.length) {
                if (library(i).name == n) r = library(i)
            }
            if (r == null) println(s"[Loom] Warning: RendererSetLibrary '$name' contains no renderer set named '$n'")
        } else {
            println(s"[Loom] Warning: RendererSetLibrary '$name' contains no renderer sets (getRendererSet)")
        }
        r
    }

    def getRandomRendererSetConsideringPreferredRendererSet(): RendererSet = {

        var r: RendererSet = null
        val preferredSelected: Boolean = Randomise.probabilityResult(preferredProbability)
        if (preferredSelected) {
            r = library(preferredRendererSetIndex)
        } else {
            r = getRandomRendererSet()
        }
        r
    }

    //this method includes the preferred renderer so increases probability that it is chosen - may need to fix
    def getRandomRendererSet(): RendererSet = {

        var r: RendererSet = null
        if (library.length > 0) {

            val max: Int = library.length-1
            val ran: Int = Randomise.range(0, max)
            r = library(ran)

        } else {
            println("Renderer Library can't get a random renderer set (contains no renderer sets) so returning null")
        }
        r

    }

    def getNextRendererSet(): RendererSet = {

        var r: RendererSet = null
        if (library.length > 0) {
            if (selectedIndex < library.length-1) {
                selectedIndex = selectedIndex + 1
            } else {
                selectedIndex = 0
            }
            r = library(selectedIndex)

        } else {
            println("Renderer Library can't get next renderer set (contains no renderer sets) so returning null")
        }
        r

    }

}