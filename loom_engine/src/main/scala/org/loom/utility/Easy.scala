package org.loom.utility

/**
 * Easing code - just testing to understand how works 2018
 */

object Easy {
  
  val easeIn: Int = 1
  val easeOut: Int = 2
  
    /**
   * easeIn
   * start slowly and then pick up pace
   * @param time: current time in frames or whatever
   * @param begin: starting x, y or z coordinate
   * @param change: distance to end
   * @param duration: overall duration
   * @param power: 1 = linear, 2 = quad, 3 = cubic, 4 = quart, 5 = quint/strong (exponent level)
   * returns a single point on a single axis
   */

   def easeIn(time: Double, begin: Double, change: Double, duration: Double, power: Int): Double = {
       val per: Double = scala.math.pow(time/duration, power)
       change * per + begin
    }
    /**
   * easeOut
   * start quickly and then slow down
   * @param time: current time in frames or whatever
   * @param begin: starting x, y or z coordinate
   * @param change: distance to end
   * @param duration: overall duration
   * @param power: 1 = linear, 2 = quad, 3 = cubic, 4 = quart, 5 = quint/strong (exponent level)
   * returns a single point on a single axis
   */
  
     def easeOut(time: Double, begin: Double, change: Double, duration: Double, power: Int): Double = {
       val per: Double = 1 - (scala.math.pow((1 - (time/duration)), power))
       change * per + begin
    }
  
  
}