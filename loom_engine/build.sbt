ThisBuild / version := "0.1.0-SNAPSHOT"

ThisBuild / scalaVersion := "3.7.3"

ThisBuild / scalafixDependencies ++= Seq(
  "com.github.xuwei-k" %% "scalafix-rules" % "1.0.0"
)

lazy val root = (project in file("."))
  .settings(
    name := "Loom_2025_373_migration",
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

