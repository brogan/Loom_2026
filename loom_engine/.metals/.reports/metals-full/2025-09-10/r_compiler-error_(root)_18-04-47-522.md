error id: A90497D6FD608F7C3248CF5CB7123C34
file://<WORKSPACE>/src/main/scala/org/loom/utility/Transform3D.scala
### scala.MatchError: 22 (of class java.lang.Integer)

occurred in the presentation compiler.



action parameters:
uri: file://<WORKSPACE>/src/main/scala/org/loom/utility/Transform3D.scala
text:
```scala
/**
Transform3D provides translation, scaling and rotation code for Vector3Ds
*/

package org.loom.utility

import org.loom.geometry._

object Transform3D {

   /**
   translate (move) a 3D position (Vector3D) via a translation vector (Vector3D)
   @param origPos the original position
   @param trans the translation vector
   */
   def translate(origPos: Vector3D, trans: Vector3D): Vector3D = {
      new Vector3D(origPos.x+trans.x, origPos.y+trans.y, origPos.z+trans.z)
   }
   /**
   scale a 3D point (Vector3D) via a scaling factor (Vector3D)
   @param origPos the 3D point
   @param scale the scaling factor
   */
   def scale(origPos: Vector3D, scale: Vector3D): Vector3D = {
      new Vector3D(origPos.x*scale.x, origPos.y*scale.y, origPos.z*scale.z)
   }

   //X AXIS ROTATION
   /**
   rotate a 3D point (Vector3D) via an angle on x axis
   @param origPos the 3D point
   @param angle the rotation angle on x axis
   */
   def rotateX(origPos: Vector3D, ang: Double): Vector3D = {
      val ratios: Vector2D = getCosSin(ang)
      val rotY: Double = ((origPos.y * ratios.x) - (origPos.z * ratios.y))
      val rotZ: Double = ((origPos.y * ratios.y) + (origPos.z * ratios.x))
      new Vector3D(origPos.x, rotY, rotZ)
   }
   /**
   rotate a 3D point (Vector3D) via an angle on x axis
   in relation to the difference from a parent position (defined by spriteOffset)
   @param origPos the 3D point
   @param angle the rotation angle on x axis
   @param spriteOffset the distance from the parent position (and axis of rotation).
   This is the inverse magnitude vector of the difference between the child and 
   the parent.  So if child is at (4,0,0) and parent is at (0,0,0), the vector we
   need is (-4,0,0).  Calculate by subtracting the child from the parent.
   */
   def rotateX(origPos: Vector3D, ang: Double, spriteOffset: Vector3D): Vector3D = {
      val ratios: Vector2D = getCosSin(ang)
      val rotY: Double = (((origPos.y + spriteOffset.y) * ratios.x) - ((origPos.z + spriteOffset.z) * ratios.y))
      val rotZ: Double = (((origPos.y + spriteOffset.y) * ratios.y) + ((origPos.z + spriteOffset.z) * ratios.x))
      new Vector3D(origPos.x, rotY, rotZ)
   }
   /**
   rotate a 3D point (Vector3D) via an angle on x axis with precalculated cos sin ratios
   @param origPos the 3D point
   @param ratios precalculated cos and sin ratios stored in Vector2D
   */
   def rotateX(origPos: Vector3D, ratios: Vector2D): Vector3D = {
      val rotY: Double = ((origPos.y * ratios.x) - (origPos.z * ratios.y))
      val rotZ: Double = ((origPos.y * ratios.y) + (origPos.z * ratios.x))
      new Vector3D(origPos.x, rotY, rotZ)
   }
   /**
   rotate a 3D point (Vector3D) via an angle on x axis with precalculated cos sin ratios
   in relation to the difference from a parent position (defined by spriteOffset)
   @param origPos the 3D point
   @param ratios precalculated cos and sin ratios stored in Vector2D
   @param spriteOffset the distance from the parent position (and axis of rotation).
   This is the inverse magnitude vector of the difference between the child and 
   the parent.  So if child is at (4,0,0) and parent is at (0,0,0), the vector we
   need is (-4,0,0).  Calculate by subtracting the child from the parent.
   */
   def rotateX(origPos: Vector3D, ratios: Vector2D, spriteOffset: Vector3D): Vector3D = {
      val rotY: Double = (((origPos.y + spriteOffset.y) * ratios.x) - ((origPos.z + spriteOffset.z) * ratios.y))
      val rotZ: Double = (((origPos.y + spriteOffset.y) * ratios.y) + ((origPos.z + spriteOffset.z) * ratios.x))
      new Vector3D(origPos.x, rotY, rotZ)
   }


   //Y AXIS ROTATION
   /**
   rotate a 3D point (Vector3D) via an angle on y axis
   @param origPos the 3D point
   @param angle the rotation angle on y axis
   */
   def rotateY(origPos: Vector3D, ang: Double): Vector3D = {
      val ratios: Vector2D = getCosSin(ang)
      val rotX: Double = ((origPos.x * ratios.x) + (origPos.z * ratios.y))
      val rotZ: Double = ((origPos.x * -ratios.y) + (origPos.z * ratios.x))
      new Vector3D(rotX, origPos.y, rotZ)
   }
   /**
   rotate a 3D point (Vector3D) via an angle on y axis
   in relation to the difference from a parent position (defined by spriteOffset)
   @param origPos the 3D point
   @param angle the rotation angle on y axis
   @param spriteOffset the distance from the parent position (and axis of rotation).
   This is the inverse magnitude vector of the difference between the child and 
   the parent.  So if child is at (4,0,0) and parent is at (0,0,0), the vector we
   need is (-4,0,0).  Calculate by subtracting the child from the parent.
   */
   def rotateY(origPos: Vector3D, ang: Double, spriteOffset: Vector3D): Vector3D = {
      val ratios: Vector2D = getCosSin(ang)
      val rotX: Double = (((origPos.x + spriteOffset.x) * ratios.x) + ((origPos.z + spriteOffset.z) * ratios.y))
      val rotZ: Double = (((origPos.x + spriteOffset.x) * -ratios.y) + ((origPos.z + spriteOffset.z) * ratios.x))
      new Vector3D(rotX, origPos.y, rotZ)
   }
   /**
   rotate a 3D point (Vector3D) via an angle on y axis with precalculated cos sin ratios
   @param origPos the 3D point
   @param ratios precalculated cos and sin ratios stored in Vector2D
   */
   def rotateY(origPos: Vector3D, ratios: Vector2D): Vector3D = {
      val rotX: Double = ((origPos.x * ratios.x) + (origPos.z * ratios.y))
      val rotZ: Double = ((origPos.x * -ratios.y) + (origPos.z * ratios.x))
      new Vector3D(rotX, origPos.y, rotZ)
   }
   /**
   rotate a 3D point (Vector3D) via an angle on y axis with precalculated cos sin ratios
   in relation to the difference from a parent position (defined by spriteOffset)
   @param origPos the 3D point
   @param ratios precalculated cos and sin ratios stored in Vector2D
   @param spriteOffset the distance from the parent position (and axis of rotation).
   This is the inverse magnitude vector of the difference between the child and 
   the parent.  So if child is at (4,0,0) and parent is at (0,0,0), the vector we
   need is (-4,0,0).  Calculate by subtracting the child from the parent.
   */
   def rotateY(origPos: Vector3D, ratios: Vector2D, spriteOffset: Vector3D): Vector3D = {
      val rotX: Double = (((origPos.x + spriteOffset.x) * ratios.x) + ((origPos.z + spriteOffset.z) * ratios.y))
      val rotZ: Double = (((origPos.x + spriteOffset.x) * -ratios.y) + ((origPos.z + spriteOffset.z) * ratios.x))
      new Vector3D(rotX, origPos.y, rotZ)
   }

   //Z AXIS ROTATION
   /**
   rotate a 3D point (Vector3D) via an angle on z axis
   @param origPos the 3D point
   @param angle the rotation angle on z axis
   */
   def rotateZ(origPos: Vector3D, ang: Double): Vector3D = {
      val ratios: Vector2D = getCosSin(ang)
      val rotX: Double = ((origPos.x * ratios.x) - (origPos.y * ratios.y))
      val rotY: Double = ((origPos.x * ratios.y) + (origPos.y * ratios.x))
      new Vector3D(rotX, rotY, origPos.z)
   }
   /**
   rotate a 3D point (Vector3D) via an angle on z axis
   in relation to the difference from a parent position (defined by spriteOffset)
   @param origPos the 3D point
   @param angle the rotation angle on z axis
   @param spriteOffset the distance from the parent position (and axis of rotation).
   This is the inverse magnitude vector of the difference between the child and 
   the parent.  So if child is at (4,0,0) and parent is at (0,0,0), the vector we
   need is (-4,0,0).  Calculate by subtracting the child from the parent.
   */
   def rotateZ(origPos: Vector3D, ang: Double, spriteOffset: Vector3D): Vector3D = {
      val ratios: Vector2D = getCosSin(ang)
      val rotX: Double = (((origPos.x + spriteOffset.x) * ratios.x) - ((origPos.y + spriteOffset.y) * ratios.y))
      val rotY: Double = (((origPos.x + spriteOffset.x) * ratios.y) + ((origPos.y + spriteOffset.y) * ratios.x))
      new Vector3D(rotX, rotY, origPos.z)
   }
   /**
   rotate a 3D point (Vector3D) via an angle on z axis with precalculated cos sin ratios
   @param origPos the 3D point
   @param ratios precalculated cos and sin ratios stored in Vector2D
   */
   def rotateZ(origPos: Vector3D, ratios: Vector2D): Vector3D = {
      val rotX: Double = ((origPos.x * ratios.x) - (origPos.y * ratios.y))
      val rotY: Double = ((origPos.x * ratios.y) + (origPos.y * ratios.x))
      new Vector3D(rotX, rotY, origPos.z)
   }
   /**
   rotate a 3D point (Vector3D) via an angle on z axis with precalculated cos sin ratios
   in relation to the difference from a parent position (defined by spriteOffset)
   @param origPos the 3D point
   @param ratios precalculated cos and sin ratios stored in Vector2D
   @param spriteOffset the distance from the parent position (and axis of rotation).
   This is the inverse magnitude vector of the difference between the child and 
   the parent.  So if child is at (4,0,0) and parent is at (0,0,0), the vector we
   need is (-4,0,0).  Calculate by subtracting the child from the parent.
   */
   def rotateZ(origPos: Vector3D, ratios: Vector2D, spriteOffset: Vector3D): Vector3D = {
      val rotX: Double = (((origPos.x + spriteOffset.x) * ratios.x) - ((origPos.y + spriteOffset.y) * ratios.y))
      val rotY: Double = (((origPos.x + spriteOffset.x) * ratios.y) + ((origPos.y + spriteOffset.y) * ratios.x))
      new Vector3D(rotX, rotY, origPos.z)
   }


   /**
   Calculates Cos and Sin ratios and stores in a Vector2D - x for Cos and y for Sin
   @param ang angle of rotation
   */
   def getCosSin(ang: Double): Vector2D = {
      val angle = Formulas.degreesToRadians(ang)
      val cosOfAngle: Double = math.cos(angle)
      val sinOfAngle: Double = math.sin(angle)
      new Vector2D(cosOfAngle, sinOfAngle)
   }

}

```


presentation compiler configuration:
Scala version: 2.12.20
Classpath:
<WORKSPACE>/.bloop/root/bloop-bsp-clients-classes/classes-Metals-kywpr2wZTnK8_E1DYvw48w== [exists ], <HOME>/Library/Caches/bloop/semanticdb/com.sourcegraph.semanticdb-javac.0.11.0/semanticdb-javac-0.11.0.jar [exists ], <WORKSPACE>/lib/scala-xml_2.11-1.0.2.jar [exists ], <WORKSPACE>/lib/scala-library.jar [exists ], <WORKSPACE>/lib/rxtxSerial.dll [exists ], <WORKSPACE>/lib/RXTXcomm.jar [exists ], <WORKSPACE>/lib/akka-actor.jar [exists ], <WORKSPACE>/lib/librxtxSerial.jnilib [exists ], <WORKSPACE>/lib/Easing.jar [exists ], <WORKSPACE>/lib/scala-xml_2.12-1.1.0.jar [exists ], <WORKSPACE>/lib/librxtxSerial.so [exists ], <HOME>/.sbt/boot/scala-2.12.20/lib/scala-library.jar [exists ], <HOME>/Library/Caches/Coursier/v1/https/repo1.maven.org/maven2/org/scala-lang/modules/scala-swing_2.12/3.0.0/scala-swing_2.12-3.0.0.jar [exists ], <HOME>/Library/Caches/Coursier/v1/https/repo1.maven.org/maven2/org/scala-lang/modules/scala-xml_2.12/1.3.0/scala-xml_2.12-1.3.0.jar [exists ]
Options:
-Yrangepos -Xplugin-require:semanticdb




#### Error stacktrace:

```
scala.reflect.internal.pickling.UnPickler$Scan.readType(UnPickler.scala:406)
	scala.reflect.internal.pickling.UnPickler$Scan.$anonfun$readTypeRef$1(UnPickler.scala:654)
	scala.reflect.internal.pickling.UnPickler$Scan.at(UnPickler.scala:188)
	scala.reflect.internal.pickling.UnPickler$Scan.readTypeRef(UnPickler.scala:654)
	scala.reflect.internal.pickling.UnPickler$Scan.readType(UnPickler.scala:416)
	scala.reflect.internal.pickling.UnPickler$Scan.$anonfun$readTypeRef$1(UnPickler.scala:654)
	scala.reflect.internal.pickling.UnPickler$Scan.at(UnPickler.scala:188)
	scala.reflect.internal.pickling.UnPickler$Scan.readTypeRef(UnPickler.scala:654)
	scala.reflect.internal.pickling.UnPickler$Scan.readType(UnPickler.scala:417)
	scala.reflect.internal.pickling.UnPickler$Scan$LazyTypeRef.$anonfun$completeInternal$1(UnPickler.scala:722)
	scala.reflect.internal.pickling.UnPickler$Scan.at(UnPickler.scala:188)
	scala.reflect.internal.pickling.UnPickler$Scan$LazyTypeRef.completeInternal(UnPickler.scala:722)
	scala.reflect.internal.pickling.UnPickler$Scan$LazyTypeRef.complete(UnPickler.scala:749)
	scala.reflect.internal.Symbols$Symbol.completeInfo(Symbols.scala:1542)
	scala.reflect.internal.Symbols$Symbol.info(Symbols.scala:1514)
	scala.reflect.internal.Symbols$Symbol.initialize(Symbols.scala:1698)
	scala.tools.nsc.interactive.Global.$anonfun$forceSymbolsUsedByParser$1(Global.scala:1374)
	scala.collection.immutable.HashSet$HashSet1.foreach(HashSet.scala:335)
	scala.collection.immutable.HashSet$HashTrieSet.foreach(HashSet.scala:1111)
	scala.collection.immutable.HashSet$HashTrieSet.foreach(HashSet.scala:1111)
	scala.tools.nsc.interactive.Global.forceSymbolsUsedByParser(Global.scala:1374)
	scala.tools.nsc.interactive.Global.<init>(Global.scala:1377)
	scala.meta.internal.pc.MetalsGlobal.<init>(MetalsGlobal.scala:49)
	scala.meta.internal.pc.ScalaPresentationCompiler.newCompiler(ScalaPresentationCompiler.scala:627)
	scala.meta.internal.pc.ScalaPresentationCompiler.$anonfun$compilerAccess$1(ScalaPresentationCompiler.scala:147)
	scala.meta.internal.pc.CompilerAccess.loadCompiler(CompilerAccess.scala:40)
	scala.meta.internal.pc.CompilerAccess.retryWithCleanCompiler(CompilerAccess.scala:182)
	scala.meta.internal.pc.CompilerAccess.$anonfun$withSharedCompiler$1(CompilerAccess.scala:155)
	scala.Option.map(Option.scala:230)
	scala.meta.internal.pc.CompilerAccess.withSharedCompiler(CompilerAccess.scala:154)
	scala.meta.internal.pc.CompilerAccess.$anonfun$withInterruptableCompiler$1(CompilerAccess.scala:92)
	scala.meta.internal.pc.CompilerAccess.$anonfun$onCompilerJobQueue$1(CompilerAccess.scala:209)
	scala.meta.internal.pc.CompilerJobQueue$Job.run(CompilerJobQueue.scala:152)
	java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1136)
	java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:635)
	java.base/java.lang.Thread.run(Thread.java:833)
```
#### Short summary: 

scala.MatchError: 22 (of class java.lang.Integer)