package org.brogan.util;

public class BString {
	
	/**
	 * Takes a String such as "dog_name_001"
	 * and returns all but the last item (so "dog_name")
	 * @param s the input String
	 * @param the reg ex String split term
	 * @return
	 */
	public static String splitDiscardLastItem(String s, String splitter) {
		String[] sA = s.split(splitter);
		String n = "";
		for (int i = 0; i < sA.length-1; i++) {
			if (i < sA.length-2) {
				n += sA[i] + "_";
			} else {
				n += sA[i];
			}
		}
		return n;
	}
	/**
	 * Takes a string with a definite singular splitting point and returns the first half
	 * or the whole string if the splitter regex is not present
	 * @param s
	 * @param splitter
	 * @return
	 */
	public static String splitDiscardSecondHalf(String s, String splitter) {
		return (s.split(splitter))[0];
	}
	public static boolean isLastItemDigit(String s, String splitter) {
		String[] sA = s.split(splitter);
		String lastItem = sA[sA.length - 1];
		char lastChar = (lastItem.charAt(lastItem.length()-1));
		if (Character.isDigit(lastChar)) {
			return true;
		}
		return false;
	}
	/**
	 * Takes an input String such as "dog.jpg"
	 * and returns the name without the extension
	 * name must incorporate only a single period (because we split around this)
	 * @param s the input String
	 * @return the String without extension
	 */
	public static String removeExtension(String s) {
		String[] sA = s.split(".");
		return sA[0];
	}

}
