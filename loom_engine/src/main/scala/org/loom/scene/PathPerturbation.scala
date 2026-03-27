package org.loom.scene

import org.loom.geometry.{PolygonType, Vector2D}
import org.loom.utility.Formulas

/**
 * Configuration for meandering-path perturbation of brush strokes.
 * When enabled, each edge is rendered along a perturbed path rather than the
 * original Bezier/line geometry, producing hand-drawn or scribbled aesthetics.
 */
class MeanderConfig(
  var enabled:                  Boolean,
  var amplitude:                Double,   // max perpendicular displacement (canvas px)
  var frequency:                Double,   // noise control-points per px of segment length
  var samples:                  Int,      // sample points along each segment
  var seed:                     Int,      // 0 = auto from edge identity; >0 = user seed
  var animated:                 Boolean,  // shift noise phase per frame (FULL_PATH only)
  var animSpeed:                Double,   // noise phase offset per frame when animated
  var scaleAlongPath:           Boolean,  // modulate stamp size along perturbed path
  var scaleAlongPathFrequency:  Double,   // noise frequency for size envelope
  var scaleAlongPathRange:      Double    // fraction of scaleMin..scaleMax to oscillate
)

object MeanderConfig {
  def default(): MeanderConfig = new MeanderConfig(
    enabled                 = false,
    amplitude               = 8.0,
    frequency               = 0.03,
    samples                 = 24,
    seed                    = 0,
    animated                = false,
    animSpeed               = 0.01,
    scaleAlongPath          = false,
    scaleAlongPathFrequency = 0.05,
    scaleAlongPathRange     = 0.4
  )
}

/**
 * A perturbed path computed from one BrushEdge.
 * Stores displaced sample points as a Catmull-Rom chain for smooth evaluation.
 * pts(0) and pts(N) are the original unperturbed anchor points.
 */
class PerturbedPath(
  private val pts:      Array[Vector2D],
  private val scaleEnv: Array[Double],   // scale value at each sample point
  val length:           Double
) {
  private val n = pts.length - 1  // number of segments (= config.samples)

  /** Evaluate position, tangent angle, and scale at parameter t in [0, 1]. */
  def evaluate(t: Double): (Vector2D, Double, Double) = {
    val tc  = math.max(0.0, math.min(1.0, t))
    val pos = tc * n
    val seg = math.min(pos.toInt, n - 1)
    val lt  = pos - seg

    val p0 = pts(math.max(0, seg - 1))
    val p1 = pts(seg)
    val p2 = pts(seg + 1)
    val p3 = pts(math.min(n, seg + 2))

    val position = crPoint(p0, p1, p2, p3, lt)
    val tangent  = crTangent(p0, p1, p2, p3, lt)
    val angle    = math.atan2(tangent.y, tangent.x)

    val sA    = scaleEnv(seg)
    val sB    = scaleEnv(seg + 1)
    val scale = sA + (sB - sA) * lt

    (position, angle, scale)
  }

  private def crPoint(p0: Vector2D, p1: Vector2D, p2: Vector2D, p3: Vector2D, t: Double): Vector2D = {
    val t2 = t * t; val t3 = t2 * t
    val x = 0.5 * ((2*p1.x) + (-p0.x+p2.x)*t + (2*p0.x-5*p1.x+4*p2.x-p3.x)*t2 + (-p0.x+3*p1.x-3*p2.x+p3.x)*t3)
    val y = 0.5 * ((2*p1.y) + (-p0.y+p2.y)*t + (2*p0.y-5*p1.y+4*p2.y-p3.y)*t2 + (-p0.y+3*p1.y-3*p2.y+p3.y)*t3)
    Vector2D(x, y)
  }

  private def crTangent(p0: Vector2D, p1: Vector2D, p2: Vector2D, p3: Vector2D, t: Double): Vector2D = {
    val t2 = t * t
    val dx = 0.5 * ((-p0.x+p2.x) + 2*(2*p0.x-5*p1.x+4*p2.x-p3.x)*t + 3*(-p0.x+3*p1.x-3*p2.x+p3.x)*t2)
    val dy = 0.5 * ((-p0.y+p2.y) + 2*(2*p0.y-5*p1.y+4*p2.y-p3.y)*t + 3*(-p0.y+3*p1.y-3*p2.y+p3.y)*t2)
    val len = math.sqrt(dx*dx + dy*dy)
    if (len < 1e-9) Vector2D(1.0, 0.0) else Vector2D(dx / len, dy / len)
  }
}

/**
 * Computes a PerturbedPath for a given BrushEdge and MeanderConfig.
 */
object PathPerturbation {

  def perturbEdge(
    edge:      BrushEdge,
    config:    MeanderConfig,
    edgeIndex: Int,
    frame:     Int,
    scaleMin:  Double,
    scaleMax:  Double
  ): PerturbedPath = {
    val n = math.max(4, config.samples)

    // Derive a stable per-edge seed; user seed adds variety across edges
    val baseSeed: Long =
      if (config.seed == 0) edgeIndex.toLong * 2654435761L
      else                  (config.seed.toLong + edgeIndex) * 2654435761L

    // Phase offset (0 for consistent, shifts each frame for animated)
    val phase = if (config.animated) (frame * config.animSpeed) % 1.0 else 0.0

    val numNoiseCtrl = math.max(2, (config.frequency * edge.length).toInt)
    val numScaleCtrl = math.max(2, (config.scaleAlongPathFrequency * edge.length).toInt)

    val pts      = new Array[Vector2D](n + 1)
    val scaleEnv = new Array[Double](n + 1)

    for (i <- 0 to n) {
      val t = i.toDouble / n

      val (origPos, origTangent) = sampleEdge(edge, t)

      // Perpendicular displacement — sin(πt) taper forces path back to anchors at both ends
      val taper    = math.sin(math.Pi * t)
      val noiseVal = SmoothNoise.sample(t, numNoiseCtrl, baseSeed, phase)
      val disp     = config.amplitude * noiseVal * taper

      val normalAngle = origTangent + math.Pi / 2.0
      pts(i) = Vector2D(
        origPos.x + disp * math.cos(normalAngle),
        origPos.y + disp * math.sin(normalAngle)
      )

      // Scale envelope: independent noise pass (baseSeed+1 keeps it uncorrelated)
      val scaleNoise  = SmoothNoise.sample(t, numScaleCtrl, baseSeed + 1L, 0.0)
      val envelope    = (scaleNoise + 1.0) / 2.0
      val scaleCenter = (scaleMin + scaleMax) / 2.0
      val halfRange   = (scaleMax - scaleMin) * config.scaleAlongPathRange / 2.0
      scaleEnv(i) = math.max(scaleMin, math.min(scaleMax,
        scaleCenter + (envelope - 0.5) * 2.0 * halfRange))
    }

    var totalLen = 0.0
    for (i <- 0 until n) totalLen += Formulas.hypotenuse(pts(i), pts(i + 1))

    new PerturbedPath(pts, scaleEnv, math.max(totalLen, 0.1))
  }

  private def sampleEdge(edge: BrushEdge, t: Double): (Vector2D, Double) = {
    if (edge.edgeType == PolygonType.LINE_POLYGON) {
      val p1 = edge.points(0); val p2 = edge.points(1)
      (Formulas.lerp(p1, p2, t), math.atan2(p2.y - p1.y, p2.x - p1.x))
    } else {
      val a1 = edge.points(0); val c1 = edge.points(1)
      val c2 = edge.points(2); val a2 = edge.points(3)
      (Formulas.bezierPoint(a1, c1, c2, a2, t), bezierTangentAngle(a1, c1, c2, a2, t))
    }
  }

  private def bezierTangentAngle(a1: Vector2D, c1: Vector2D, c2: Vector2D, a2: Vector2D, t: Double): Double = {
    val mt = 1.0 - t
    val dx = 3*mt*mt*(c1.x-a1.x) + 6*mt*t*(c2.x-c1.x) + 3*t*t*(a2.x-c2.x)
    val dy = 3*mt*mt*(c1.y-a1.y) + 6*mt*t*(c2.y-c1.y) + 3*t*t*(a2.y-c2.y)
    math.atan2(dy, dx)
  }
}

/**
 * 1D smooth noise in [-1, 1].
 * Uses Catmull-Rom interpolation between uniformly-spaced random control values.
 * Same seed always produces the same pattern; phase shifts the sampling position.
 */
object SmoothNoise {
  def sample(x: Double, numCtrl: Int, seed: Long, phase: Double): Double = {
    val n   = math.max(2, numCtrl)
    val rng = new scala.util.Random(seed)
    val v   = Array.fill(n)(rng.nextDouble() * 2.0 - 1.0)

    val xw  = ((x + phase) % 1.0 + 1.0) % 1.0
    val pos = xw * (n - 1)
    val i0  = pos.toInt.min(n - 2)
    val t   = pos - i0

    val va = v(math.max(0, i0 - 1))
    val vb = v(i0)
    val vc = v(i0 + 1)
    val vd = v(math.min(n - 1, i0 + 2))

    val t2     = t * t; val t3 = t2 * t
    val result = 0.5 * ((2*vb) + (-va+vc)*t + (2*va-5*vb+4*vc-vd)*t2 + (-va+3*vb-3*vc+vd)*t3)
    math.max(-1.0, math.min(1.0, result))
  }
}
