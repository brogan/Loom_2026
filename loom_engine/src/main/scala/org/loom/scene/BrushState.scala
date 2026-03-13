package org.loom.scene

import org.loom.geometry.{Polygon2D, PolygonType, Vector2D}
import org.loom.utility.Formulas
import scala.collection.mutable

/**
 * Represents a single unique edge extracted from the polygon mesh.
 * For LINE_POLYGON: points has 2 elements (start, end).
 * For SPLINE_POLYGON: points has 4 elements (anchor1, control1, control2, anchor2).
 */
class BrushEdge(
  val edgeType: Int,
  val points: Array[Vector2D],
  val length: Double
) {
  override def toString: String = s"BrushEdge(type=$edgeType, pts=${points.length}, len=$length)"
}

/**
 * An agent that progressively draws a portion of the edges.
 */
class BrushAgent(
  var edgeStartIndex: Int,
  var edgeEndIndex: Int,
  var currentEdgeIndex: Int,
  var currentStampT: Double,
  var completed: Boolean,
  var direction: Int // 1=forward, -1=backward (for ping-pong)
)

/**
 * Holds the deduplicated edge list and progressive reveal state for a sprite.
 */
class BrushState {

  var edges: Array[BrushEdge] = Array.empty
  var agents: Array[BrushAgent] = Array.empty
  var initialized: Boolean = false
  var totalLength: Double = 0.0

  /**
   * Extract unique edges from a list of visible polygons.
   * Deduplicates shared edges using canonical vertex-position keys.
   */
  def initializeFromPolys(polys: List[Polygon2D]): Unit = {
    val edgeList = mutable.ArrayBuffer[BrushEdge]()
    val seen = mutable.Set[String]()
    val epsilon = 0.01

    def roundKey(v: Vector2D): String = {
      val rx = (math.round(v.x / epsilon) * epsilon)
      val ry = (math.round(v.y / epsilon) * epsilon)
      f"$rx%.2f,$ry%.2f"
    }

    def canonicalKey(a: Vector2D, b: Vector2D): String = {
      val ka = roundKey(a)
      val kb = roundKey(b)
      if (ka < kb) s"$ka-$kb" else s"$kb-$ka"
    }

    for (poly <- polys) {
      if (!poly.visible) () // skip invisible
      else if (poly.polyType == PolygonType.LINE_POLYGON) {
        val pts = poly.points
        val n = pts.length
        for (i <- 0 until n) {
          val p1 = pts(i)
          val p2 = pts((i + 1) % n)
          val key = canonicalKey(p1, p2)
          if (!seen.contains(key)) {
            seen += key
            val length = Formulas.hypotenuse(p1, p2)
            edgeList += new BrushEdge(PolygonType.LINE_POLYGON, Array(p1, p2), length)
          }
        }
      } else if (poly.polyType == PolygonType.SPLINE_POLYGON || poly.polyType == PolygonType.OPEN_SPLINE_POLYGON) {
        val pts = poly.points
        for (i <- 0 until poly.sidesTotal) {
          val a1 = pts(i * 4)
          val c1 = pts(i * 4 + 1)
          val c2 = pts(i * 4 + 2)
          val a2 = pts(i * 4 + 3)
          val key = canonicalKey(a1, a2)
          if (!seen.contains(key)) {
            seen += key
            val length = approximateSplineLength(a1, c1, c2, a2, 10)
            edgeList += new BrushEdge(PolygonType.SPLINE_POLYGON, Array(a1, c1, c2, a2), length)
          }
        }
      }
    }

    edges = edgeList.toArray
    totalLength = edges.map(_.length).sum
    initialized = true
  }

  /**
   * Create progressive reveal agents that divide edges among N agents.
   */
  def createAgents(agentCount: Int): Unit = {
    if (edges.isEmpty) return
    val count = math.max(1, agentCount)
    val edgesPerAgent = math.max(1, edges.length / count)

    agents = Array.tabulate(count) { i =>
      val start = i * edgesPerAgent
      val end = if (i == count - 1) edges.length - 1 else math.min((i + 1) * edgesPerAgent - 1, edges.length - 1)
      new BrushAgent(
        edgeStartIndex = start,
        edgeEndIndex = end,
        currentEdgeIndex = start,
        currentStampT = 0.0,
        completed = false,
        direction = 1
      )
    }
  }

  /**
   * Check completion and handle hold/loop/ping-pong.
   */
  def checkCompletion(postCompletionMode: Int): Unit = {
    val allDone = agents.forall(_.completed)
    if (!allDone) return

    postCompletionMode match {
      case BrushConfig.HOLD =>
        // Stay completed — nothing to do
        ()
      case BrushConfig.LOOP =>
        // Reset all agents to start
        for (agent <- agents) {
          agent.currentEdgeIndex = agent.edgeStartIndex
          agent.currentStampT = 0.0
          agent.completed = false
          agent.direction = 1
        }
      case BrushConfig.PING_PONG =>
        // Reverse direction
        for (agent <- agents) {
          agent.direction = -agent.direction
          agent.currentEdgeIndex = if (agent.direction == 1) agent.edgeStartIndex else agent.edgeEndIndex
          agent.currentStampT = if (agent.direction == 1) 0.0 else 1.0
          agent.completed = false
        }
      case _ => ()
    }
  }

  /**
   * Approximate arc length of a cubic bezier by sampling.
   */
  private def approximateSplineLength(a1: Vector2D, c1: Vector2D, c2: Vector2D, a2: Vector2D, samples: Int): Double = {
    var totalLen = 0.0
    var prev = a1
    for (i <- 1 to samples) {
      val t = i.toDouble / samples
      val pt = Formulas.bezierPoint(a1, c1, c2, a2, t)
      totalLen += Formulas.hypotenuse(prev, pt)
      prev = pt
    }
    totalLen
  }
}
