/**
 * Reads and Writes text files
 * Here is how to call:
 * TextReaderWriter.writeTextFile("cats are crazy", new File("a.txt"))//file parameter
 * val tex: String = TextReaderWriter.readTextFile("a.txt")//path String parameter
 * val t: String = TextReaderWriter.readTextFile(new File("a.txt"))//file parameter
 */
package org.loom.media

import java.io._

object TextReaderWriter {
    /**
     * read a text file
     * @param path
     * @return String
     */
    def readTextFile(path: String): String = {
        scala.io.Source.fromFile(path).mkString
    }
    
    /**
     * read a text file
     * @param File
     * @return String
     */

    def readTextFile(f: File): String = {
	    var readText: String = ""
	    try {
		    val in: BufferedReader = new BufferedReader(new FileReader(f))
		    var line: String = in.readLine()
		    while (line != null) {
		        readText += line;
                line = in.readLine()
		    }
	    } catch  {
		    case ex: IOException => println(ex);
	    }
	    //println("readText: "+readText)
        readText
   }

   /**
    * write a text file
    * @param String to write
    * @param file to write to
    */
   def writeTextFile(s: String, f: File): Unit = {

	try {
		val out: PrintWriter = new PrintWriter(new BufferedWriter(new FileWriter(f)))
		out.write(s)
                out.close
	} catch  {
		case ex: IOException => println(ex);
	}

   }

}

