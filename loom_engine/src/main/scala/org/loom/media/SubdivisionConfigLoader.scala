package org.loom.media

import scala.xml.*
import java.io.File
import org.loom.geometry.*
import org.loom.utility.{Transform2D, Range, RangeXY}
import org.loom.transform.*

/**
 * Loads SubdivisionParamsSetCollection from subdivision.xml configuration files.
 */
object SubdivisionConfigLoader {

  def load(filePath: String): SubdivisionParamsSetCollection = {
    val file = File(filePath)
    if (!file.exists()) {
      println(s"Warning: Subdivision config file not found: $filePath")
      return SubdivisionParamsSetCollection()
    }

    try {
      val xml = XML.loadFile(filePath)
      parseSubdivisionConfig(xml)
    } catch {
      case e: Exception =>
        println(s"Error loading subdivision config from $filePath: ${e.getMessage}")
        SubdivisionParamsSetCollection()
    }
  }

  def loadFromString(xmlContent: String): SubdivisionParamsSetCollection = {
    try {
      val xml = XML.loadString(xmlContent)
      parseSubdivisionConfig(xml)
    } catch {
      case e: Exception =>
        println(s"Error parsing subdivision config XML: ${e.getMessage}")
        SubdivisionParamsSetCollection()
    }
  }

  private def parseSubdivisionConfig(root: Elem): SubdivisionParamsSetCollection = {
    val collection = SubdivisionParamsSetCollection()

    (root \\ "SubdivisionParamsSet").foreach { setNode =>
      val paramsSet = parseSubdivisionParamsSet(setNode)
      collection.add(paramsSet)
    }

    collection
  }

  private def parseSubdivisionParamsSet(node: Node): SubdivisionParamsSet = {
    val name = (node \ "@name").text match {
      case "" => "default"
      case n => n
    }

    val paramsSet = SubdivisionParamsSet(name)

    (node \ "SubdivisionParams").foreach { paramNode =>
      val params = parseSubdivisionParams(paramNode)
      paramsSet.add(params)
    }

    paramsSet
  }

  private def parseSubdivisionParams(node: Node): SubdivisionParams = {
    val name = (node \ "@name").text match {
      case "" => "default"
      case n => n
    }

    val params = SubdivisionParams(name)

    // Basic properties
    params.subdivisionType = parseSubdivisionType((node \ "SubdivisionType").text)
    params.visibilityRule = parseVisibilityRule((node \ "VisibilityRule").text)
    params.ranMiddle = getBoolOrDefault(node, "RanMiddle", false)
    params.ranDiv = getDoubleOrDefault(node, "RanDiv", 100.0)

    // Line ratios (values 0.0-1.0, e.g., 0.5 = 50%)
    (node \ "LineRatios").headOption.foreach { lr =>
      val x = (lr \ "@x").text match { case "" => 0.5; case s => s.toDouble }
      val y = (lr \ "@y").text match { case "" => 0.5; case s => s.toDouble }
      params.lineRatios = Vector2D(x, y)
    }

    // Control point ratios (values 0.0-1.0)
    (node \ "ControlPointRatios").headOption.foreach { cpr =>
      val x = (cpr \ "@x").text match { case "" => 0.25; case s => s.toDouble }
      val y = (cpr \ "@y").text match { case "" => 0.75; case s => s.toDouble }
      params.controlPointRatios = Vector2D(x, y)
    }

    // Inset transform
    (node \ "InsetTransform").headOption.foreach { it =>
      val trans = parseTranslation(it \ "Translation")
      val scale = parseScale(it \ "Scale")
      val rot = parseRotation(it \ "Rotation")
      params.insetTransform = Transform2D(trans, scale, rot)
    }

    // Continuous
    params.continuous = getBoolOrDefault(node, "Continuous", true)

    // Polys transform
    params.polysTransform = getBoolOrDefault(node, "PolysTransform", false)
    params.polysTranformWhole = getBoolOrDefault(node, "PolysTransformWhole", false)

    // PTW settings
    params.pTW_randomTranslation = getBoolOrDefault(node, "PTW_RandomTranslation", false)
    params.pTW_randomScale = getBoolOrDefault(node, "PTW_RandomScale", false)
    params.pTW_randomRotation = getBoolOrDefault(node, "PTW_RandomRotation", false)
    params.pTW_commonCentre = getBoolOrDefault(node, "PTW_CommonCentre", false)
    params.pTW_probability = getDoubleOrDefault(node, "PTW_Probability", 100.0)

    // PTW Transform
    (node \ "PTW_Transform").headOption.foreach { ptwt =>
      val trans = parseTranslation(ptwt \ "Translation")
      val scale = parseScale(ptwt \ "Scale")
      val rot = parseRotation(ptwt \ "Rotation")
      params.pTW_transform = Transform2D(trans, scale, rot)
    }

    params.pTW_randomCentreDivisor = getDoubleOrDefault(node, "PTW_RandomCentreDivisor", 100.0)

    // PTW Random ranges
    (node \ "PTW_RandomTranslationRange").headOption.foreach { rtr =>
      val xMin = ((rtr \ "X" \ "@min").text match { case "" => 0.0; case s => s.toDouble })
      val xMax = ((rtr \ "X" \ "@max").text match { case "" => 0.0; case s => s.toDouble })
      val yMin = ((rtr \ "Y" \ "@min").text match { case "" => 0.0; case s => s.toDouble })
      val yMax = ((rtr \ "Y" \ "@max").text match { case "" => 0.0; case s => s.toDouble })
      params.pTW_randomTranslationRange = new RangeXY(new Range(xMin, xMax), new Range(yMin, yMax))
    }

    (node \ "PTW_RandomScaleRange").headOption.foreach { rsr =>
      val xMin = ((rsr \ "X" \ "@min").text match { case "" => 1.0; case s => s.toDouble })
      val xMax = ((rsr \ "X" \ "@max").text match { case "" => 1.0; case s => s.toDouble })
      val yMin = ((rsr \ "Y" \ "@min").text match { case "" => 1.0; case s => s.toDouble })
      val yMax = ((rsr \ "Y" \ "@max").text match { case "" => 1.0; case s => s.toDouble })
      params.pTW_randomScaleRange = new RangeXY(new Range(xMin, xMax), new Range(yMin, yMax))
    }

    (node \ "PTW_RandomRotationRange").headOption.foreach { rrr =>
      val min = (rrr \ "@min").text match { case "" => 0.0; case s => s.toDouble }
      val max = (rrr \ "@max").text match { case "" => 0.0; case s => s.toDouble }
      params.pTW_randomRotationRange = new Range(min, max)
    }

    // Polys transform points
    params.polysTransformPoints = getBoolOrDefault(node, "PolysTransformPoints", false)
    params.pTP_probability = getDoubleOrDefault(node, "PTP_Probability", 100.0)

    // TransformSet (ExteriorAnchors, CentralAnchors, etc.)
    (node \ "TransformSet").headOption.foreach { tsNode =>
      parseTransformSet(tsNode, params)
    }

    params
  }

  /**
   * Parse TransformSet containing ExteriorAnchors, CentralAnchors, etc.
   * Creates new transform objects with the correct enabled state and replaces
   * the defaults in SubdivisionParams.
   */
  private def parseTransformSet(tsNode: Node, params: SubdivisionParams): Unit = {

    (tsNode \ "ExteriorAnchors").headOption.foreach { eaNode =>
      val enabled = (eaNode \ "@enabled").text.toLowerCase == "true"
      val ea = new ExteriorAnchors(enabled)

      ea.probability = getDoubleOrDefault(eaNode, "Probability", 100.0)
      ea.spikeFactor = getDoubleOrDefault(eaNode, "SpikeFactor", -0.3)

      // WhichSpike: ALL, CORNERS, MIDDLES
      (eaNode \ "WhichSpike").headOption.foreach { ws =>
        ws.text.trim.toUpperCase match {
          case "ALL" => ea.setWhichSpike(ExteriorAnchors.ALL)
          case "CORNERS" => ea.setWhichSpike(ExteriorAnchors.CORNERS)
          case "MIDDLES" => ea.setWhichSpike(ExteriorAnchors.MIDDLES)
          case _ =>
        }
      }

      // SpikeType: SYMMETRICAL, RIGHT, LEFT, RANDOM
      (eaNode \ "SpikeType").headOption.foreach { st =>
        st.text.trim.toUpperCase match {
          case "SYMMETRICAL" => ea.setSpikeType(ExteriorAnchors.SYMMETRICAL)
          case "RIGHT" => ea.setSpikeType(ExteriorAnchors.RIGHT)
          case "LEFT" => ea.setSpikeType(ExteriorAnchors.LEFT)
          case "RANDOM" => ea.setSpikeType(ExteriorAnchors.RANDOM)
          case _ =>
        }
      }

      // SpikeAxis: XY, X, Y
      (eaNode \ "SpikeAxis").headOption.foreach { sa =>
        sa.text.trim.toUpperCase match {
          case "XY" => ea.setSpikeAxis(ExteriorAnchors.SPIKE_XY)
          case "X" => ea.setSpikeAxis(ExteriorAnchors.SPIKE_X)
          case "Y" => ea.setSpikeAxis(ExteriorAnchors.SPIKE_Y)
          case _ =>
        }
      }

      ea.randomSpike = getBoolOrDefault(eaNode, "RandomSpike", false)
      (eaNode \ "RandomSpikeFactor").headOption.foreach { rsf =>
        val min = (rsf \ "@min").text match { case "" => -0.2; case s => s.toDouble }
        val max = (rsf \ "@max").text match { case "" => 0.2; case s => s.toDouble }
        ea.randomSpikeFactor = new Range(min, max)
      }

      ea.cpsFollow = getBoolOrDefault(eaNode, "CpsFollow", false)
      ea.cpsFollowMultiplier = getDoubleOrDefault(eaNode, "CpsFollowMultiplier", 2.0)
      ea.randomCPsFollow = getBoolOrDefault(eaNode, "RandomCpsFollow", false)
      (eaNode \ "RandomCpsFollowRange").headOption.foreach { rcf =>
        val min = (rcf \ "@min").text match { case "" => -1.5; case s => s.toDouble }
        val max = (rcf \ "@max").text match { case "" => 1.5; case s => s.toDouble }
        ea.randomCPsFollowMultiplier = new Range(min, max)
      }

      ea.cpsSqueeze = getBoolOrDefault(eaNode, "CpsSqueeze", false)
      ea.cpsSqueezeFactor = getDoubleOrDefault(eaNode, "CpsSqueezeFactor", -0.2)
      ea.randomCPsSqueeze = getBoolOrDefault(eaNode, "RandomCpsSqueeze", false)
      (eaNode \ "RandomCpsSqueezeRange").headOption.foreach { rcs =>
        val min = (rcs \ "@min").text match { case "" => -0.5; case s => s.toDouble }
        val max = (rcs \ "@max").text match { case "" => 0.5; case s => s.toDouble }
        ea.randomCPsSqueezeFactor = new Range(min, max)
      }

      // Replace in params
      params.exteriorAnchors = ea
      params.transformSet(0) = ea
    }

    (tsNode \ "CentralAnchors").headOption.foreach { caNode =>
      val enabled = (caNode \ "@enabled").text.toLowerCase == "true"
      val ca = new CentralAnchors(enabled)

      ca.probability = getDoubleOrDefault(caNode, "Probability", 100.0)
      ca.tearFactor = getDoubleOrDefault(caNode, "TearFactor", 0.2)

      // TearAxis: XY, X, Y, RANDOM
      (caNode \ "TearAxis").headOption.foreach { ta =>
        ta.text.trim.toUpperCase match {
          case "XY" => ca.setTearAxis(CentralAnchors.TEAR_XY)
          case "X" => ca.setTearAxis(CentralAnchors.TEAR_X)
          case "Y" => ca.setTearAxis(CentralAnchors.TEAR_Y)
          case "RANDOM" => ca.setTearAxis(CentralAnchors.RANDOM_TEAR_AXIS)
          case _ =>
        }
      }

      // TearDirection: DIAGONAL, LEFT, RIGHT, RANDOM
      (caNode \ "TearDirection").headOption.foreach { td =>
        td.text.trim.toUpperCase match {
          case "DIAGONAL" => ca.setTearDirection(CentralAnchors.TEAR_DIAGONAL)
          case "LEFT" => ca.setTearDirection(CentralAnchors.TEAR_LEFT)
          case "RIGHT" => ca.setTearDirection(CentralAnchors.TEAR_RIGHT)
          case "RANDOM" => ca.setTearDirection(CentralAnchors.RANDOM_TEAR_DIRECTION)
          case _ =>
        }
      }

      ca.randomTear = getBoolOrDefault(caNode, "RandomTear", false)
      (caNode \ "RandomTearFactor").headOption.foreach { rtf =>
        val min = (rtf \ "@min").text match { case "" => -0.2; case s => s.toDouble }
        val max = (rtf \ "@max").text match { case "" => 0.2; case s => s.toDouble }
        ca.randomTearFactor = new Range(min, max)
      }

      ca.cpsFollow = getBoolOrDefault(caNode, "CpsFollow", false)
      ca.cpsFollowMultiplier = getDoubleOrDefault(caNode, "CpsFollowMultiplier", -7.0)
      ca.randomCPsFollow = getBoolOrDefault(caNode, "RandomCpsFollow", false)
      (caNode \ "RandomCpsFollowRange").headOption.foreach { rcf =>
        val min = (rcf \ "@min").text match { case "" => -1.5; case s => s.toDouble }
        val max = (rcf \ "@max").text match { case "" => 1.5; case s => s.toDouble }
        ca.randomCPsFollowMultiplier = new Range(min, max)
      }

      ca.allPointsFollowCentre = getBoolOrDefault(caNode, "AllPointsFollow", false)
      ca.invertedFollowCentre = getBoolOrDefault(caNode, "InvertedFollow", false)

      // Replace in params
      params.centralAnchors = ca
      params.transformSet(1) = ca
    }

    (tsNode \ "AnchorsLinkedToCentre").headOption.foreach { alcNode =>
      val enabled = (alcNode \ "@enabled").text.toLowerCase == "true"
      val alc = new AnchorsLinkedToCentre(enabled)

      alc.probability = getDoubleOrDefault(alcNode, "Probability", 100.0)
      alc.tearFactor = getDoubleOrDefault(alcNode, "TearFactor", 0.45)
      alc.randomTear = getBoolOrDefault(alcNode, "RandomTear", false)
      (alcNode \ "RandomTearFactor").headOption.foreach { rtf =>
        val min = (rtf \ "@min").text match { case "" => -0.2; case s => s.toDouble }
        val max = (rtf \ "@max").text match { case "" => 0.2; case s => s.toDouble }
        alc.randomTearFactor = new Range(min, max)
      }

      alc.cpsFollow = getBoolOrDefault(alcNode, "CpsFollow", true)
      alc.cpsFollowMultiplier = getDoubleOrDefault(alcNode, "CpsFollowMultiplier", 1.0)
      alc.randomCPsFollow = getBoolOrDefault(alcNode, "RandomCpsFollow", false)
      (alcNode \ "RandomCpsFollowRange").headOption.foreach { rcf =>
        val min = (rcf \ "@min").text match { case "" => -1.5; case s => s.toDouble }
        val max = (rcf \ "@max").text match { case "" => 1.5; case s => s.toDouble }
        alc.randomCPsFollowMultiplier = new Range(min, max)
      }

      // Replace in params
      params.anchorsLinkedToCentre = alc
      params.transformSet(2) = alc
    }

    (tsNode \ "OuterControlPoints").headOption.foreach { ocpNode =>
      val enabled = (ocpNode \ "@enabled").text.toLowerCase == "true"
      val ocp = new OuterControlPoints(enabled)

      ocp.probability = getDoubleOrDefault(ocpNode, "Probability", 100.0)
      ocp.lineSideRatio = new Vector2D(
        getDoubleOrDefault(ocpNode, "LineRatioX", 0.33),
        getDoubleOrDefault(ocpNode, "LineRatioY", 0.66)
      )
      ocp.randomLineRatio = getBoolOrDefault(ocpNode, "RandomLineRatio", false)
      (ocpNode \ "RandomLineRatioInner").headOption.foreach { r =>
        val min = (r \ "@min").text match { case "" => 0.1; case s => s.toDouble }
        val max = (r \ "@max").text match { case "" => 0.5; case s => s.toDouble }
        ocp.randomLineRatioA = new Range(min, max)
      }
      (ocpNode \ "RandomLineRatioOuter").headOption.foreach { r =>
        val min = (r \ "@min").text match { case "" => 0.5; case s => s.toDouble }
        val max = (r \ "@max").text match { case "" => 0.9; case s => s.toDouble }
        ocp.randomLineRatioB = new Range(min, max)
      }

      // Curve mode: PERPENDICULAR (default) or FROM_CENTRE
      (ocpNode \ "CurveMode").headOption.foreach { cm =>
        cm.text.trim.toUpperCase match {
          case "FROM_CENTRE" => ocp.curveFromCentre = true
          case _ => ocp.curveFromCentre = false
        }
      }

      // Curve type
      (ocpNode \ "CurveType").headOption.foreach { ct =>
        ct.text.trim.toUpperCase match {
          case "PUFF" => ocp.curveType = OuterControlPoints.PUFF
          case "PINCH" => ocp.curveType = OuterControlPoints.PINCH
          case "PUFF_PINCH_PUFF_PINCH" => ocp.curveType = OuterControlPoints.PUFF_PINCH_PUFF_PINCH
          case "PUFF_PINCH_PINCH_PUFF" => ocp.curveType = OuterControlPoints.PUFF_PINCH_PINCH_PUFF
          case "PINCH_PUFF_PUFF_PINCH" => ocp.curveType = OuterControlPoints.PINCH_PUFF_PUFF_PINCH
          case "PINCH_PUFF_PINCH_PUFF" => ocp.curveType = OuterControlPoints.PINCH_PUFF_PINCH_PUFF
          case _ =>
        }
      }

      ocp.curveMultiplier = new Range(
        getDoubleOrDefault(ocpNode, "CurveMultiplierMin", 1.0),
        getDoubleOrDefault(ocpNode, "CurveMultiplierMax", 3.0)
      )
      ocp.randomMultiplier = getBoolOrDefault(ocpNode, "RandomMultiplier", false)
      (ocpNode \ "RandomCurveMultiplier").headOption.foreach { r =>
        val min = (r \ "@min").text match { case "" => 0.5; case s => s.toDouble }
        val max = (r \ "@max").text match { case "" => 3.0; case s => s.toDouble }
        ocp.randomCurveMultiplier = new Range(min, max)
      }

      ocp.curveFromCentreRatio = new Vector2D(
        getDoubleOrDefault(ocpNode, "CurveFromCentreRatioX", 0.2),
        getDoubleOrDefault(ocpNode, "CurveFromCentreRatioY", -0.5)
      )
      ocp.ranCurveFromCentre = getBoolOrDefault(ocpNode, "RandomFromCentre", false)
      (ocpNode \ "RandomFromCentreA").headOption.foreach { r =>
        val min = (r \ "@min").text match { case "" => -1.0; case s => s.toDouble }
        val max = (r \ "@max").text match { case "" => 1.0; case s => s.toDouble }
        ocp.ranCurveFromCentreRatioA = new Range(min, max)
      }
      (ocpNode \ "RandomFromCentreB").headOption.foreach { r =>
        val min = (r \ "@min").text match { case "" => -1.0; case s => s.toDouble }
        val max = (r \ "@max").text match { case "" => 1.0; case s => s.toDouble }
        ocp.ranCurveFromCentreRatioB = new Range(min, max)
      }

      // Replace in params
      params.outerControlPoints = ocp
      params.transformSet(3) = ocp
    }

    (tsNode \ "InnerControlPoints").headOption.foreach { icpNode =>
      val enabled = (icpNode \ "@enabled").text.toLowerCase == "true"
      val icp = new InnerControlPoints(enabled)

      icp.probability = getDoubleOrDefault(icpNode, "Probability", 100.0)

      // Replace in params
      params.innerControlPoints = icp
      params.transformSet(4) = icp
    }

    // Rebuild the transform array used at runtime
    params.pTP_transformSet = params.transformSet.toArray
  }


  private def parseSubdivisionType(typeStr: String): Int = {
    typeStr.toUpperCase match {
      case "TRI" => Subdivision.TRI
      case "QUAD" => Subdivision.QUAD
      case "QUAD_BORD" => Subdivision.QUAD_BORD
      case "QUAD_BORD_ECHO" => Subdivision.QUAD_BORD_ECHO
      case "QUAD_BORD_DOUBLE" => Subdivision.QUAD_BORD_DOUBLE
      case "QUAD_BORD_DOUBLE_ECHO" => Subdivision.QUAD_BORD_DOUBLE_ECHO
      case "TRI_BORD_A" => Subdivision.TRI_BORD_A
      case "TRI_BORD_A_ECHO" => Subdivision.TRI_BORD_A_ECHO
      case "TRI_BORD_B" => Subdivision.TRI_BORD_B
      case "TRI_BORD_B_ECHO" => Subdivision.TRI_BORD_B_ECHO
      case "TRI_STAR" => Subdivision.TRI_STAR
      case "TRI_STAR_FILL" => Subdivision.TRI_STAR_FILL
      case "TRI_BORD_C" => Subdivision.TRI_BORD_C
      case "TRI_BORD_C_ECHO" => Subdivision.TRI_BORD_C_ECHO
      case "SPLIT_VERT" => Subdivision.SPLIT_VERT
      case "SPLIT_HORIZ" => Subdivision.SPLIT_HORIZ
      case "SPLIT_DIAG" => Subdivision.SPLIT_DIAG
      case "ECHO" => Subdivision.ECHO
      case "ECHO_ABS_CENTER" => Subdivision.ECHO_ABS_CENTER
      case _ => Subdivision.QUAD
    }
  }

  private def parseVisibilityRule(ruleStr: String): Int = {
    ruleStr.toUpperCase match {
      case "QUADS" => Subdivision.QUADS
      case "TRIS" => Subdivision.TRIS
      case "ALL_BUT_LAST" => Subdivision.ALL_BUT_LAST
      case "ALTERNATE_ODD" => Subdivision.ALTERNATE_ODD
      case "ALTERNATE_EVEN" => Subdivision.ALTERNATE_EVEN
      case "FIRST_HALF" => Subdivision.FIRST_HALF
      case "SECOND_HALF" => Subdivision.SECOND_HALF
      case "EVERY_THIRD" => Subdivision.EVERY_THIRD
      case "EVERY_FOURTH" => Subdivision.EVERY_FOURTH
      case "EVERY_FIFTH" => Subdivision.EVERY_FIFTH
      case "RANDOM_1_2" => Subdivision.RANDOM_1_2
      case "RANDOM_1_3" => Subdivision.RANDOM_1_3
      case "RANDOM_1_5" => Subdivision.RANDOM_1_5
      case "RANDOM_1_7" => Subdivision.RANDOM_1_7
      case "RANDOM_1_10" => Subdivision.RANDOM_1_10
      case _ => Subdivision.ALL
    }
  }

  private def parseTranslation(nodeSeq: NodeSeq): Vector2D = {
    nodeSeq.headOption.map { node =>
      val x = (node \ "@x").text match { case "" => 0.0; case s => s.toDouble }
      val y = (node \ "@y").text match { case "" => 0.0; case s => s.toDouble }
      Vector2D(x, y)
    }.getOrElse(Vector2D(0, 0))
  }

  private def parseScale(nodeSeq: NodeSeq): Vector2D = {
    nodeSeq.headOption.map { node =>
      val x = (node \ "@x").text match { case "" => 1.0; case s => s.toDouble }
      val y = (node \ "@y").text match { case "" => 1.0; case s => s.toDouble }
      Vector2D(x, y)
    }.getOrElse(Vector2D(1.0, 1.0))
  }

  private def parseRotation(nodeSeq: NodeSeq): Vector2D = {
    nodeSeq.headOption.map { node =>
      val x = (node \ "@x").text match { case "" => 0.0; case s => s.toDouble }
      val y = (node \ "@y").text match { case "" => 0.0; case s => s.toDouble }
      Vector2D(x, y)
    }.getOrElse(Vector2D(0, 0))
  }

  private def getBoolOrDefault(node: Node, elem: String, default: Boolean): Boolean = {
    (node \ elem).headOption.map(_.text.trim.toLowerCase == "true").getOrElse(default)
  }

  private def getDoubleOrDefault(node: Node, elem: String, default: Double): Double = {
    try {
      (node \ elem).headOption.map(_.text.trim.toDouble).getOrElse(default)
    } catch {
      case _: NumberFormatException => default
    }
  }
}
