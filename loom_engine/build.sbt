ThisBuild / version := "0.1.0-SNAPSHOT"

ThisBuild / scalaVersion := "3.7.3"

ThisBuild / scalafixDependencies ++= Seq(
  "com.github.xuwei-k" %% "scalafix-rules" % "1.0.0"
)

lazy val root = (project in file("."))
  .settings(
    name := "Loom_2025_373_migration",

    // Fork the application into its own JVM so it gets a clean heap
    // separate from SBT's class-loading overhead.
    fork := true,

    // JVM flags for the forked application process.
    // G1GC + large region size handles the humongous allocations that the
    // high quality-multiple renderer makes (e.g. 8320×8320×4 ≈ 277 MB buffers).
    // GCLockerRetryAllocationCount raises the default (2) so Java2D's JNI
    // critical sections don't abort large allocations mid-render.
    javaOptions ++= Seq(
      "-Xms2G",
      "-Xmx12G",
      "-XX:+UseG1GC",
      "-XX:G1HeapRegionSize=32m",         // 32 MB regions → 277 MB object fits in ~9 regions
      "-XX:+UnlockDiagnosticVMOptions",   // required before diagnostic flags
      "-XX:GCLockerRetryAllocationCount=100", // was 2; give GC time to release JNI locks
      "-XX:MaxGCPauseMillis=500",          // relax pause target; throughput > latency here
      "-XX:InitiatingHeapOccupancyPercent=25", // start concurrent GC earlier for headroom
      "-XX:+AlwaysPreTouch",              // pre-commit heap pages; avoids OS latency mid-render
    ),
  )

libraryDependencies ++= Seq(
  "org.scala-lang.modules" %% "scala-swing" % "3.0.0",
  "org.scala-lang.modules" %% "scala-xml" % "2.2.0",
)

dependencyOverrides ++= Seq(
  elems = "org.scala-lang.modules" %% "scala-xml"   % "2.2.0",
  "org.scala-lang.modules" %% "scala-swing" % "3.0.0"
)

ThisBuild / scalacOptions ++= Seq(
  "-Wunused:all",         // Identify unused code
  "-deprecation",
  "-feature"
)

