package org.loom.geometry

/** A named set of ovals, each stored as Polygon2D(List(Vector2D(cx,cy), Vector2D(cx+rx, cy+ry)), OVAL_POLYGON). */
class OvalSet(val ovals: List[Polygon2D], val name: String)
