package org.loom.media

import java.awt.GraphicsEnvironment


object Text {
	
	/**
	 * printFonts
	 * prints available system fonts
	 */
	
	def printFonts(): Unit = {
		val f: Array[String] = getFontFamilyNames()
		f.foreach(println)
	}
	
	def getFontFamilyNames(): Array[String] = {
		val e = GraphicsEnvironment.getLocalGraphicsEnvironment()
		e.getAvailableFontFamilyNames()
	}
	
	/**
	 * takes a body of text and returns an array of lines of length determined by specified number of characters
	 * @param text String
	 * @param lineCharLength Int number of characters in a line
	 * @return array of line Strings
	 */
    def getTextAsLineArray (text: String, lineCharLength: Int): Array[String] = {
       val blanks: Array[Int] = getBlankIndexes(text)
       getLines(text, blanks, lineCharLength)
    }
	
    /**
	 * takes a body of text and prints to the console an array of lines of length determined by specified number of characters
	 * @param text String
	 * @param lineCharLength Int number of characters in a line
	 */
	def printText(text: String, lineCharLength: Int): Unit = {
       val blanks: Array[Int] = getBlankIndexes(text)
       val lines: Array[String] = getLines(text, blanks, lineCharLength)
       for (i <- 0 until lines.length) {
          if (lines(i) != null) println(lines(i))
       }
    }

   def getLines(text: String, blanks: Array[Int], lineLength: Int): Array[String] = {
      val lines: Array[String] = new Array[String]((text.length/lineLength) + 1)
      var currLine: Int = 0
      var currCharStartIndex: Int = 0
      for (i <- 0 until blanks.length) {
         if (blanks(i) > (currCharStartIndex + lineLength)) {
            lines(currLine) = text.substring(currCharStartIndex, blanks(i))
            currLine += 1
            currCharStartIndex = blanks(i)+1
         }
      }
      lines(currLine) = text.substring(currCharStartIndex, (text.length))
      lines
   }

   def getBlankIndexes(t: String): Array[Int] = {
      val totalBlanks: Int = getTotalBlanks(t)
      val blanks: Array[Int] = new Array[Int](totalBlanks)
      var index: Int = -1
      for(i <- 0 until t.length) if (t.charAt(i).equals(' ')) { index += 1; blanks(index) = i}
      blanks
   }

   def getTotalBlanks(t: String): Int = {
      var count: Int = 0
      for(i <- 0 until t.length) if (t.charAt(i).equals(' ')) count += 1
      count
   }
	
}