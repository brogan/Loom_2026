package org.loom.utility

/**
 * Easing functions for keyframe animation.
 * Ported from Robert Penner's easing equations.
 *
 * Each function takes: t (current time), s (start value), c (change), d (duration)
 * and returns the eased value.
 */
/**
 * Easing type identifiers. Use EasingType.valueOf(name) to look up by string.
 */
object EasingType {
  val LINEAR = "LINEAR"
  val EASE_IN_QUAD = "EASE_IN_QUAD"
  val EASE_OUT_QUAD = "EASE_OUT_QUAD"
  val EASE_IN_OUT_QUAD = "EASE_IN_OUT_QUAD"
  val EASE_OUT_IN_QUAD = "EASE_OUT_IN_QUAD"
  val EASE_IN_CUBIC = "EASE_IN_CUBIC"
  val EASE_OUT_CUBIC = "EASE_OUT_CUBIC"
  val EASE_IN_OUT_CUBIC = "EASE_IN_OUT_CUBIC"
  val EASE_OUT_IN_CUBIC = "EASE_OUT_IN_CUBIC"
  val EASE_IN_QUART = "EASE_IN_QUART"
  val EASE_OUT_QUART = "EASE_OUT_QUART"
  val EASE_IN_OUT_QUART = "EASE_IN_OUT_QUART"
  val EASE_OUT_IN_QUART = "EASE_OUT_IN_QUART"
  val EASE_IN_QUINT = "EASE_IN_QUINT"
  val EASE_OUT_QUINT = "EASE_OUT_QUINT"
  val EASE_IN_OUT_QUINT = "EASE_IN_OUT_QUINT"
  val EASE_OUT_IN_QUINT = "EASE_OUT_IN_QUINT"
  val EASE_IN_SINE = "EASE_IN_SINE"
  val EASE_OUT_SINE = "EASE_OUT_SINE"
  val EASE_IN_OUT_SINE = "EASE_IN_OUT_SINE"
  val EASE_OUT_IN_SINE = "EASE_OUT_IN_SINE"
  val EASE_IN_EXPO = "EASE_IN_EXPO"
  val EASE_OUT_EXPO = "EASE_OUT_EXPO"
  val EASE_IN_OUT_EXPO = "EASE_IN_OUT_EXPO"
  val EASE_OUT_IN_EXPO = "EASE_OUT_IN_EXPO"
  val EASE_IN_CIRC = "EASE_IN_CIRC"
  val EASE_OUT_CIRC = "EASE_OUT_CIRC"
  val EASE_IN_OUT_CIRC = "EASE_IN_OUT_CIRC"
  val EASE_OUT_IN_CIRC = "EASE_OUT_IN_CIRC"
  val EASE_IN_ELASTIC = "EASE_IN_ELASTIC"
  val EASE_OUT_ELASTIC = "EASE_OUT_ELASTIC"
  val EASE_IN_OUT_ELASTIC = "EASE_IN_OUT_ELASTIC"
  val EASE_OUT_IN_ELASTIC = "EASE_OUT_IN_ELASTIC"
  val EASE_IN_BACK = "EASE_IN_BACK"
  val EASE_OUT_BACK = "EASE_OUT_BACK"
  val EASE_IN_OUT_BACK = "EASE_IN_OUT_BACK"
  val EASE_OUT_IN_BACK = "EASE_OUT_IN_BACK"
  val EASE_IN_BOUNCE = "EASE_IN_BOUNCE"
  val EASE_OUT_BOUNCE = "EASE_OUT_BOUNCE"
  val EASE_IN_OUT_BOUNCE = "EASE_IN_OUT_BOUNCE"
  val EASE_OUT_IN_BOUNCE = "EASE_OUT_IN_BOUNCE"

  def valueOf(name: String): String = name
}

object Easing {

  private val PI = Math.PI
  private val TWO_PI = 2.0 * PI
  private val HALF_PI = PI / 2.0
  private val BACK_S = 1.70158

  /**
   * Compute an eased value.
   * @param t current time (0 to d)
   * @param s start value
   * @param c change in value (end - start)
   * @param d duration
   * @param easing the easing type
   * @return eased value
   */
  def ease(t: Double, s: Double, c: Double, d: Double, easing: String): Double = {
    if (d == 0) return s + c
    easing match {
      case "LINEAR"              => linear(t, s, c, d)
      case "EASE_IN_QUAD"        => easeInQuad(t, s, c, d)
      case "EASE_OUT_QUAD"       => easeOutQuad(t, s, c, d)
      case "EASE_IN_OUT_QUAD"    => easeInOutQuad(t, s, c, d)
      case "EASE_OUT_IN_QUAD"    => easeOutIn(t, s, c, d, easeOutQuad, easeInQuad)
      case "EASE_IN_CUBIC"       => easeInCubic(t, s, c, d)
      case "EASE_OUT_CUBIC"      => easeOutCubic(t, s, c, d)
      case "EASE_IN_OUT_CUBIC"   => easeInOutCubic(t, s, c, d)
      case "EASE_OUT_IN_CUBIC"   => easeOutIn(t, s, c, d, easeOutCubic, easeInCubic)
      case "EASE_IN_QUART"       => easeInQuart(t, s, c, d)
      case "EASE_OUT_QUART"      => easeOutQuart(t, s, c, d)
      case "EASE_IN_OUT_QUART"   => easeInOutQuart(t, s, c, d)
      case "EASE_OUT_IN_QUART"   => easeOutIn(t, s, c, d, easeOutQuart, easeInQuart)
      case "EASE_IN_QUINT"       => easeInQuint(t, s, c, d)
      case "EASE_OUT_QUINT"      => easeOutQuint(t, s, c, d)
      case "EASE_IN_OUT_QUINT"   => easeInOutQuint(t, s, c, d)
      case "EASE_OUT_IN_QUINT"   => easeOutIn(t, s, c, d, easeOutQuint, easeInQuint)
      case "EASE_IN_SINE"        => easeInSine(t, s, c, d)
      case "EASE_OUT_SINE"       => easeOutSine(t, s, c, d)
      case "EASE_IN_OUT_SINE"    => easeInOutSine(t, s, c, d)
      case "EASE_OUT_IN_SINE"    => easeOutIn(t, s, c, d, easeOutSine, easeInSine)
      case "EASE_IN_EXPO"        => easeInExpo(t, s, c, d)
      case "EASE_OUT_EXPO"       => easeOutExpo(t, s, c, d)
      case "EASE_IN_OUT_EXPO"    => easeInOutExpo(t, s, c, d)
      case "EASE_OUT_IN_EXPO"    => easeOutIn(t, s, c, d, easeOutExpo, easeInExpo)
      case "EASE_IN_CIRC"        => easeInCirc(t, s, c, d)
      case "EASE_OUT_CIRC"       => easeOutCirc(t, s, c, d)
      case "EASE_IN_OUT_CIRC"    => easeInOutCirc(t, s, c, d)
      case "EASE_OUT_IN_CIRC"    => easeOutIn(t, s, c, d, easeOutCirc, easeInCirc)
      case "EASE_IN_ELASTIC"     => easeInElastic(t, s, c, d)
      case "EASE_OUT_ELASTIC"    => easeOutElastic(t, s, c, d)
      case "EASE_IN_OUT_ELASTIC" => easeInOutElastic(t, s, c, d)
      case "EASE_OUT_IN_ELASTIC" => easeOutIn(t, s, c, d, easeOutElastic, easeInElastic)
      case "EASE_IN_BACK"        => easeInBack(t, s, c, d)
      case "EASE_OUT_BACK"       => easeOutBack(t, s, c, d)
      case "EASE_IN_OUT_BACK"    => easeInOutBack(t, s, c, d)
      case "EASE_OUT_IN_BACK"    => easeOutIn(t, s, c, d, easeOutBack, easeInBack)
      case "EASE_IN_BOUNCE"      => easeInBounce(t, s, c, d)
      case "EASE_OUT_BOUNCE"     => easeOutBounce(t, s, c, d)
      case "EASE_IN_OUT_BOUNCE"  => easeInOutBounce(t, s, c, d)
      case "EASE_OUT_IN_BOUNCE"  => easeOutIn(t, s, c, d, easeOutBounce, easeInBounce)
      case _                     => linear(t, s, c, d) // default fallback
    }
  }

  // Out-In helper: first half uses easeOut, second half uses easeIn
  private def easeOutIn(t: Double, s: Double, c: Double, d: Double,
                        outFn: (Double, Double, Double, Double) => Double,
                        inFn: (Double, Double, Double, Double) => Double): Double = {
    if t < d / 2 then outFn(t * 2, s, c / 2, d)
    else inFn(t * 2 - d, s + c / 2, c / 2, d)
  }

  // Linear
  private def linear(t: Double, s: Double, c: Double, d: Double): Double =
    c * t / d + s

  // Quadratic
  private def easeInQuad(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / d
    c * tn * tn + s
  }

  private def easeOutQuad(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / d
    s - c * tn * (tn - 2)
  }

  private def easeInOutQuad(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / (d / 2)
    if tn < 1 then c / 2 * tn * tn + s
    else {
      val tn1 = tn - 1
      s - c / 2 * (tn1 * (tn1 - 2) - 1)
    }
  }

  // Cubic
  private def easeInCubic(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / d
    c * tn * tn * tn + s
  }

  private def easeOutCubic(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / d - 1
    c * (tn * tn * tn + 1) + s
  }

  private def easeInOutCubic(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / (d / 2)
    if tn < 1 then c / 2 * tn * tn * tn + s
    else {
      val tn1 = tn - 2
      c / 2 * (tn1 * tn1 * tn1 + 2) + s
    }
  }

  // Quartic
  private def easeInQuart(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / d
    c * tn * tn * tn * tn + s
  }

  private def easeOutQuart(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / d - 1
    s - c * (tn * tn * tn * tn - 1)
  }

  private def easeInOutQuart(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / (d / 2)
    if tn < 1 then c / 2 * tn * tn * tn * tn + s
    else {
      val tn1 = tn - 2
      s - c / 2 * (tn1 * tn1 * tn1 * tn1 - 2)
    }
  }

  // Quintic
  private def easeInQuint(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / d
    c * tn * tn * tn * tn * tn + s
  }

  private def easeOutQuint(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / d - 1
    c * (tn * tn * tn * tn * tn + 1) + s
  }

  private def easeInOutQuint(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / (d / 2)
    if tn < 1 then c / 2 * tn * tn * tn * tn * tn + s
    else {
      val tn1 = tn - 2
      c / 2 * (tn1 * tn1 * tn1 * tn1 * tn1 + 2) + s
    }
  }

  // Sine
  private def easeInSine(t: Double, s: Double, c: Double, d: Double): Double =
    s + c - c * Math.cos(t / d * HALF_PI)

  private def easeOutSine(t: Double, s: Double, c: Double, d: Double): Double =
    c * Math.sin(t / d * HALF_PI) + s

  private def easeInOutSine(t: Double, s: Double, c: Double, d: Double): Double =
    s - c / 2 * (Math.cos(PI * t / d) - 1)

  // Exponential
  private def easeInExpo(t: Double, s: Double, c: Double, d: Double): Double = {
    if t == 0 then s
    else c * Math.pow(2, 10 * (t / d - 1)) + s
  }

  private def easeOutExpo(t: Double, s: Double, c: Double, d: Double): Double = {
    if t == d then s + c
    else c * (1 - Math.pow(2, -10 * t / d)) + s
  }

  private def easeInOutExpo(t: Double, s: Double, c: Double, d: Double): Double = {
    if t == 0 then return s
    if t == d then return s + c
    val tn = t / (d / 2)
    if tn < 1 then c / 2 * Math.pow(2, 10 * (tn - 1)) + s
    else c / 2 * (2 - Math.pow(2, -10 * (tn - 1))) + s
  }

  // Circular
  private def easeInCirc(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / d
    s - c * (Math.sqrt(1 - tn * tn) - 1)
  }

  private def easeOutCirc(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / d - 1
    c * Math.sqrt(1 - tn * tn) + s
  }

  private def easeInOutCirc(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / (d / 2)
    if tn < 1 then s - c / 2 * (Math.sqrt(1 - tn * tn) - 1)
    else {
      val tn1 = tn - 2
      c / 2 * (Math.sqrt(1 - tn1 * tn1) + 1) + s
    }
  }

  // Elastic
  private def easeInElastic(t: Double, s: Double, c: Double, d: Double): Double = {
    if t == 0 then return s
    val tn = t / d
    if tn == 1 then return s + c
    val p = d * 0.3
    val g = p / 4
    val tn1 = tn - 1
    s - c * Math.pow(2, 10 * tn1) * Math.sin((tn1 * d - g) * TWO_PI / p)
  }

  private def easeOutElastic(t: Double, s: Double, c: Double, d: Double): Double = {
    if t == 0 then return s
    val tn = t / d
    if tn == 1 then return s + c
    val p = d * 0.3
    val g = p / 4
    c * Math.pow(2, -10 * tn) * Math.sin((tn * d - g) * TWO_PI / p) + c + s
  }

  private def easeInOutElastic(t: Double, s: Double, c: Double, d: Double): Double = {
    if t == 0 then return s
    val tn = t / (d / 2)
    if tn == 2 then return s + c
    val p = d * 0.45
    val g = p / 4
    if tn < 1 then {
      val tn1 = tn - 1
      s - 0.5 * c * Math.pow(2, 10 * tn1) * Math.sin((tn1 * d - g) * TWO_PI / p)
    } else {
      val tn1 = tn - 1
      c * Math.pow(2, -10 * tn1) * Math.sin((tn1 * d - g) * TWO_PI / p) * 0.5 + c + s
    }
  }

  // Back
  private def easeInBack(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / d
    c * tn * tn * ((BACK_S + 1) * tn - BACK_S) + s
  }

  private def easeOutBack(t: Double, s: Double, c: Double, d: Double): Double = {
    val tn = t / d - 1
    c * (tn * tn * ((BACK_S + 1) * tn + BACK_S) + 1) + s
  }

  private def easeInOutBack(t: Double, s: Double, c: Double, d: Double): Double = {
    val ss = BACK_S * 1.525
    val tn = t / (d / 2)
    if tn < 1 then c / 2 * (tn * tn * ((ss + 1) * tn - ss)) + s
    else {
      val tn1 = tn - 2
      c / 2 * (tn1 * tn1 * ((ss + 1) * tn1 + ss) + 2) + s
    }
  }

  // Bounce
  private def easeOutBounce(t: Double, s: Double, c: Double, d: Double): Double = {
    var tn = t / d
    if tn < 1.0 / 2.75 then
      c * (7.5625 * tn * tn) + s
    else if tn < 2.0 / 2.75 then {
      tn -= 1.5 / 2.75
      c * (7.5625 * tn * tn + 0.75) + s
    } else if tn < 2.5 / 2.75 then {
      tn -= 2.25 / 2.75
      c * (7.5625 * tn * tn + 0.9375) + s
    } else {
      tn -= 2.625 / 2.75
      c * (7.5625 * tn * tn + 0.984375) + s
    }
  }

  private def easeInBounce(t: Double, s: Double, c: Double, d: Double): Double =
    c - easeOutBounce(d - t, 0, c, d) + s

  private def easeInOutBounce(t: Double, s: Double, c: Double, d: Double): Double = {
    if (t < d / 2) easeInBounce(t * 2, 0, c, d) * 0.5 + s
    else easeOutBounce(t * 2 - d, 0, c, d) * 0.5 + c * 0.5 + s
  }
}
