error id: C87F86182D9A27BB5ED2277F062A9C60
file://<WORKSPACE>/Main.scala
### scala.MatchError: 22 (of class java.lang.Integer)

occurred in the presentation compiler.



action parameters:
offset: 9
uri: file://<WORKSPACE>/Main.scala
text:
```scala
object Ma@@

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
	scala.meta.internal.pc.CompilerAccess.$anonfun$withNonInterruptableCompiler$1(CompilerAccess.scala:132)
	scala.meta.internal.pc.CompilerAccess.$anonfun$onCompilerJobQueue$1(CompilerAccess.scala:209)
	scala.meta.internal.pc.CompilerJobQueue$Job.run(CompilerJobQueue.scala:152)
	java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1136)
	java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:635)
	java.base/java.lang.Thread.run(Thread.java:833)
```
#### Short summary: 

scala.MatchError: 22 (of class java.lang.Integer)