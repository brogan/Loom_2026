error id: 879268F15D4C817C3CAFE190B4ADD8BD
jar:file://<HOME>/Library/Caches/Coursier/v1/https/repo1.maven.org/maven2/org/scala-lang/scala-library/2.12.20/scala-library-2.12.20-sources.jar!/scala/collection/mutable/ArrayBuffer.scala
### scala.MatchError: 22 (of class java.lang.Integer)

occurred in the presentation compiler.



action parameters:
uri: jar:file://<HOME>/Library/Caches/Coursier/v1/https/repo1.maven.org/maven2/org/scala-lang/scala-library/2.12.20/scala-library-2.12.20-sources.jar!/scala/collection/mutable/ArrayBuffer.scala
text:
```scala
/*
 * Scala (https://www.scala-lang.org)
 *
 * Copyright EPFL and Lightbend, Inc.
 *
 * Licensed under Apache License 2.0
 * (http://www.apache.org/licenses/LICENSE-2.0).
 *
 * See the NOTICE file distributed with this work for
 * additional information regarding copyright ownership.
 */

package scala
package collection
package mutable

import generic._
import parallel.mutable.ParArray

/** An implementation of the `Buffer` class using an array to
 *  represent the assembled sequence internally. Append, update and random
 *  access take constant time (amortized time). Prepends and removes are
 *  linear in the buffer size.
 *
 *  @author  Matthias Zenger
 *  @author  Martin Odersky
 *  @since   1
 *  @see [[http://docs.scala-lang.org/overviews/collections/concrete-mutable-collection-classes.html#array-buffers "Scala's Collection Library overview"]]
 *  section on `Array Buffers` for more information.

 *
 *  @tparam A    the type of this arraybuffer's elements.
 *
 *  @define Coll `mutable.ArrayBuffer`
 *  @define coll array buffer
 *  @define thatinfo the class of the returned collection. In the standard library configuration,
 *    `That` is always `ArrayBuffer[B]` because an implicit of type `CanBuildFrom[ArrayBuffer, B, ArrayBuffer[B]]`
 *    is defined in object `ArrayBuffer`.
 *  @define bfinfo an implicit value of class `CanBuildFrom` which determines the
 *    result class `That` from the current representation type `Repr`
 *    and the new element type `B`. This is usually the `canBuildFrom` value
 *    defined in object `ArrayBuffer`.
 *  @define orderDependent
 *  @define orderDependentFold
 *  @define mayNotTerminateInf
 *  @define willNotTerminateInf
 */
@SerialVersionUID(1529165946227428979L)
class ArrayBuffer[A](override protected val initialSize: Int)
  extends AbstractBuffer[A]
     with Buffer[A]
     with GenericTraversableTemplate[A, ArrayBuffer]
     with BufferLike[A, ArrayBuffer[A]]
     with IndexedSeqOptimized[A, ArrayBuffer[A]]
     with Builder[A, ArrayBuffer[A]]
     with ResizableArray[A]
     with CustomParallelizable[A, ParArray[A]]
     with Serializable {

  override def companion: GenericCompanion[ArrayBuffer] = ArrayBuffer

  import scala.collection.Traversable

  def this() = this(16)

  def clear() { reduceToSize(0) }

  override def sizeHint(len: Int) {
    if (len > size && len >= 1) {
      val newarray = new Array[AnyRef](len)
      java.lang.System.arraycopy(array, 0, newarray, 0, size0)
      array = newarray
    }
  }

  override def par = ParArray.handoff[A](array.asInstanceOf[Array[A]], size)

  /** Appends a single element to this buffer and returns
   *  the identity of the buffer. It takes constant amortized time.
   *
   *  @param elem  the element to append.
   *  @return      the updated buffer.
   */
  def +=(elem: A): this.type = {
    ensureSize(size0 + 1)
    array(size0) = elem.asInstanceOf[AnyRef]
    size0 += 1
    this
  }

  /** Appends a number of elements provided by a traversable object.
   *  The identity of the buffer is returned.
   *
   *  @param xs    the traversable object.
   *  @return      the updated buffer.
   */
  override def ++=(xs: TraversableOnce[A]): this.type = xs match {
    case v: scala.collection.IndexedSeqLike[_, _] =>
      val n = v.length
      ensureSize(size0 + n)
      v.copyToArray(array.asInstanceOf[scala.Array[Any]], size0, n)
      size0 += n
      this
    case _ =>
      super.++=(xs)
  }

  /** Prepends a single element to this buffer and returns
   *  the identity of the buffer. It takes time linear in
   *  the buffer size.
   *
   *  @param elem  the element to prepend.
   *  @return      the updated buffer.
   */
  def +=:(elem: A): this.type = {
    ensureSize(size0 + 1)
    copy(0, 1, size0)
    array(0) = elem.asInstanceOf[AnyRef]
    size0 += 1
    this
  }

  /** Prepends a number of elements provided by a traversable object.
   *  The identity of the buffer is returned.
   *
   *  @param xs    the traversable object.
   *  @return      the updated buffer.
   */
  override def ++=:(xs: TraversableOnce[A]): this.type = { insertAll(0, xs.toTraversable); this }

  /** Inserts new elements at the index `n`. Opposed to method
   *  `update`, this method will not replace an element with a new
   *  one. Instead, it will insert a new element at index `n`.
   *
   *  @param n     the index where a new element will be inserted.
   *  @param seq   the traversable object providing all elements to insert.
   *  @throws IndexOutOfBoundsException if `n` is out of bounds.
   */
  def insertAll(n: Int, seq: Traversable[A]) {
    if (n < 0 || n > size0) throw new IndexOutOfBoundsException(n.toString)
    val len = seq.size
    val newSize = size0 + len
    ensureSize(newSize)

    copy(n, n + len, size0 - n)
    seq.copyToArray(array.asInstanceOf[Array[Any]], n)
    size0 = newSize
  }

  /** Removes the element on a given index position. It takes time linear in
   *  the buffer size.
   *
   *  @param n       the index which refers to the first element to remove.
   *  @param count   the number of elements to remove.
   *  @throws   IndexOutOfBoundsException if the index `n` is not in the valid range
   *            `0 <= n <= length - count` (with `count > 0`).
   *  @throws   IllegalArgumentException if `count < 0`.
   */
  override def remove(n: Int, count: Int) {
    if (count < 0) throw new IllegalArgumentException("removing negative number of elements: " + count.toString)
    else if (count == 0) return  // Did nothing
    if (n < 0 || n > size0 - count) throw new IndexOutOfBoundsException("at " + n.toString + " deleting " + count.toString)
    copy(n + count, n, size0 - (n + count))
    reduceToSize(size0 - count)
  }

  /** Removes the element at a given index position.
   *
   *  @param n  the index which refers to the element to delete.
   *  @return   the element that was formerly at position `n`.
   */
  def remove(n: Int): A = {
    val result = apply(n)
    remove(n, 1)
    result
  }

  def result: ArrayBuffer[A] = this

  /** Defines the prefix of the string representation.
   */
  override def stringPrefix: String = "ArrayBuffer"

}

/** Factory object for the `ArrayBuffer` class.
 *
 *  $factoryInfo
 *  @define coll array buffer
 *  @define Coll `ArrayBuffer`
 */
object ArrayBuffer extends SeqFactory[ArrayBuffer] {
  /** $genericCanBuildFromInfo */
  implicit def canBuildFrom[A]: CanBuildFrom[Coll, A, ArrayBuffer[A]] = ReusableCBF.asInstanceOf[GenericCanBuildFrom[A]]
  def newBuilder[A]: Builder[A, ArrayBuffer[A]] = new ArrayBuffer[A]
}


```


presentation compiler configuration:
Scala version: 2.12.20
Classpath:
<HOME>/Scala/Loom_2025_21220_migration/.bloop/root/bloop-bsp-clients-classes/classes-Metals-TrDAliK9S4KuHM6MGfMebA== [exists ], <HOME>/Library/Caches/bloop/semanticdb/com.sourcegraph.semanticdb-javac.0.11.0/semanticdb-javac-0.11.0.jar [exists ], <HOME>/Scala/Loom_2025_21220_migration/lib/scala-xml_2.11-1.0.2.jar [missing ], <HOME>/Scala/Loom_2025_21220_migration/lib/scala-library.jar [exists ], <HOME>/Scala/Loom_2025_21220_migration/lib/rxtxSerial.dll [exists ], <HOME>/Scala/Loom_2025_21220_migration/lib/RXTXcomm.jar [exists ], <HOME>/Scala/Loom_2025_21220_migration/lib/akka-actor.jar [exists ], <HOME>/Scala/Loom_2025_21220_migration/lib/librxtxSerial.jnilib [exists ], <HOME>/Scala/Loom_2025_21220_migration/lib/Easing.jar [exists ], <HOME>/Scala/Loom_2025_21220_migration/lib/scala-xml_2.12-1.1.0.jar [exists ], <HOME>/Scala/Loom_2025_21220_migration/lib/librxtxSerial.so [exists ], <HOME>/.sbt/boot/scala-2.12.20/lib/scala-library.jar [exists ], <HOME>/Library/Caches/Coursier/v1/https/repo1.maven.org/maven2/org/scala-lang/modules/scala-swing_2.12/3.0.0/scala-swing_2.12-3.0.0.jar [exists ], <HOME>/Library/Caches/Coursier/v1/https/repo1.maven.org/maven2/org/scala-lang/modules/scala-xml_2.12/2.2.0/scala-xml_2.12-2.2.0.jar [exists ]
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