/**
Randomise provides utility methods for getting random numbers in a range
and for randomising arrays
*/

package org.loom.utility

import scala.util.Random

object Randomise {

   // Single shared instance — avoids creating a new Random on every call,
   // which was wasteful and prevented reproducible seeding.
   private val rng = new Random()

   /**
    Calculate a random Double between an inclusive minimum and a maximum. Can handle any mixture of positive and negative numbers, , as long is min is less than max
   @param min
   @param max
   */
   def range(min: Int, max: Int): Int = {
      val lo = math.min(min, max)
      val hi = math.max(min, max)
      val diff: Int = hi - lo
      val ran = (rng.nextInt(diff + 1)) + lo
      //testRandomRange(min, max, ran)//see internal test method below
      ran
   }

   /**
   Calculate a random Double between an inclusive minimum and a maximum. Can handle any mixture of positive and negative numbers, as long is min is less than max
   @param min
   @param max
   */
   def range(min: Double, max: Double): Double = {
      val lo = math.min(min, max)
      val hi = math.max(min, max)
      val diff: Double = hi - lo
      val ran = (rng.nextDouble() * diff) + lo
      //testRandomRange(min, max, ran)//see internal test method below
      ran
   }

   /**
    * testRandomRange (Int)
    * internal test
    * prints random range (Int) output to console
    * @param min minimum value in random range
    * @param max  maximum possible value in random range
    * @param ran calculated random Int
    */
   private def testRandomRange(min: Int, max: Int, ran: Int): Unit = {
      if ((ran > (min-1)) && (ran < (max+1))) {
         println("RANDOMISE.range (Int): " + ran)
      } else {
         println("RANDOMISE.range (Int) OUTSIDE BOUNDS: " + ran)
      }
   }

   /**
    * testRandomRange (Double)
    * prints random range (Double) output to console
    * @param min minimum value in random range
    * @param max  maximum possible value in random range
    * @param ran calculated random Int
    */
   private def testRandomRange(min: Double, max: Double, ran: Double): Unit = {
       if ((ran > min) && (ran < max)) {
         println("RANDOMISE.range (Double): " + ran)
       } else {
         println("RANDOMISE.range (Double) OUTSIDE BOUNDS: " + ran)
       }
   }

   def getRandomisedColorArray(min: Array[Int], max: Array[Int]): Array[Int] = {
      val r: Int = Randomise.range(min(0), max(0))
      val g: Int = Randomise.range(min(1), max(1))
      val b: Int = Randomise.range(min(2), max(2))
      val a: Int = Randomise.range(min(3), max(3))
      Array(r, g, b, a)
   }

   /**
   Randomise an array of Ints
   @param a the array of Ints
   */
   def arrayOfInts(a: Array[Int]): Array[Int] = {
      var oldArray: Array[Int] = a.clone()
      val newArray: Array[Int] = oldArray.clone()
      val ranGen = rng
      for (i <- 0 until a.length) {
         val ran: Int = ranGen.nextInt(oldArray.length)
         newArray(i) = oldArray(ran)
         val oldList = oldArray.toList
         val listy = oldList.filterNot(x => x == newArray(i))
         oldArray = listy.toArray
      }
      newArray
   }

   /**
   Randomise a list of Ints
   @param list the List of Ints
   */
   def listOfInts(list: List[Int]): List[Int] = {
      var oldArray: Array[Int] = list.toArray
      val newArray: Array[Int] = list.toArray
      val ranGen = rng
      for (i <- 0 until list.length) {
         val ran: Int = ranGen.nextInt(oldArray.length)
         newArray(i) = oldArray(ran)
         val oldList = oldArray.toList
         val listy = oldList.filterNot(x => x == newArray(i))
         oldArray = listy.toArray
      }
      newArray.iterator.toList
   }

   /**
   Randomise an array of Doubles
   @param a the array of Doubles
   */
   def arrayOfDoubles(a: Array[Double]): Array[Double] = {
      var oldArray: Array[Double] = a.clone()
      val newArray: Array[Double] = oldArray.clone()
      val ranGen = rng
      for (i <- 0 until a.length) {
         val ran: Int = ranGen.nextInt(oldArray.length)
         newArray(i) = oldArray(ran)
         val oldList = oldArray.toList
         val listy = oldList.filterNot(x => x == newArray(i))
         oldArray = listy.toArray
      }
      newArray
   }

   /**
   Randomise a list of Doubles
   @param list the List of Doubles
   */
   def listOfDoubles(list: List[Double]): List[Double] = {
      var oldArray: Array[Double] = list.toArray
      val newArray: Array[Double] = list.toArray
      val ranGen = rng
      for (i <- 0 until list.length) {
         val ran: Int = ranGen.nextInt(oldArray.length)
         newArray(i) = oldArray(ran)
         val oldList = oldArray.toList
         val listy = oldList.filterNot(x => x == newArray(i))
         oldArray = listy.toArray
      }
      newArray.iterator.toList
   }

   /**
   Randomise an array of Strings
   @param a the array of Strings
   */
   def arrayOfStrings(a: Array[String]): Array[String] = {
      var oldArray: Array[String] = a.clone()
      val newArray: Array[String] = oldArray.clone()
      val ranGen = rng
      for (i <- 0 until a.length) {
         val ran: Int = ranGen.nextInt(oldArray.length)
         newArray(i) = oldArray(ran)
         val oldList = oldArray.toList
         val listy = oldList.filterNot(x => x == newArray(i))
         oldArray = listy.toArray
      }
      newArray
   }

   /**
   Randomise a list of Strings
   @param list the List of Strings
   */
   def listOfStrings(list: List[String]): List[String] = {
      var oldArray: Array[String] = list.toArray
      val newArray: Array[String] = list.toArray
      val ranGen = rng
      for (i <- 0 until list.length) {
         val ran: Int = ranGen.nextInt(oldArray.length)
         newArray(i) = oldArray(ran)
         val oldList = oldArray.toList
         val listy = oldList.filterNot(x => x == newArray(i))
         oldArray = listy.toArray
      }
      newArray.iterator.toList
   }

   /**
    * Given a probability percentage calculate whether something occurs or not
    * @param probability percentage that something will happen
    */

    def probabilityResult(percentage: Double): Boolean = {
      val ran: Double = range(0.0,100.0)
      var result: Boolean = false
      if (ran <= percentage) {
         result = true
      }
      result
    }
   def happens(p: Double): Boolean = {
      probabilityResult(p)

    }

}
