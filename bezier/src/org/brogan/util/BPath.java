package org.brogan.util;

import java.io.File;

public class BPath {
	
	/**
	 * 
	 * @return home directory
	 */
	public static String getHomeDirectory() {
		return System.getProperty("user.home");
	}
	/**
	 * 
	 */
	public static String getUserDirectory() {
		return System.getProperty("user.dir");
	}
	/**
	 * 
	 * @return system specific file separator
	 */
	public static String getFileSeparator() {
		return System.getProperty("file.separator");
	}
	
	/**
	 * Takes a system specific absolute path
	 * and returns the same path for the current operating system.
	 * Must also supply the top level known directory name.
	 * Everything from this directory down should be identical
	 * on any system except for the system specific file separator.
	 * Everything above this directory is calculated on the basis of the path
	 * to the user's home directory
	 * @param p
	 * @return
	 */
	public static String getRebuiltPath(String p, String topLevelProjectDirectory) {
		//find the char index of "u" in "um_projects"
		int index = p.indexOf(topLevelProjectDirectory);
		if (index > -1) {
			//get the system specific original file separator (one short of the "u")
			char fileSepChar = p.charAt(index-1);
			String fileSep = new String(""+fileSepChar);
			System.out.println("fileSep: " + fileSep);
			//get the project relative path substring
			String sub = p.substring(index);
			System.out.println("sub: " + sub);
			//make into an array and split with original system specific separator
			String[] projectRelativeArray;
			projectRelativeArray = sub.split((fileSep+fileSep));//necessary in regex with escape character
			/**
			 * Not necessary on linux despite different file separator
			 *if the original fileSeparator in the saved path equals the current one for this system
			if (fileSep.equals(BPath.getFileSeparator())) {
				projectRelativeArray = sub.split((fileSep+fileSep));//necessary in regex with escape character
			} else {
				projectRelativeArray = sub.split((fileSep+fileSep));//a different system file separator
			}
			*/
			//get the current system path
			String systemPath = BPath.getHomeDirectory();
			//need then to rebuild the path with the current system specific file separator
			//this enables project to be moved to another system - as long as they are in the um-projects directory
			//all should be ok
			String fullPath = systemPath + BPath.getFileSeparator();
			for (int i = 0; i < projectRelativeArray.length; i++) {
				if (i < projectRelativeArray.length-1) {
					fullPath+=projectRelativeArray[i] + BPath.getFileSeparator();
				} else {
					fullPath+=projectRelativeArray[i];
				}
				System.out.println("projectRelativeArray[i]: "+ projectRelativeArray[i]);
			}
			System.out.println("");
			System.out.println("^^^^^^^^^^^^^^^^^^^^^^^^ImportImagesPanel, setImagePath, substring: "+fullPath);
			System.out.println("");
			return fullPath;
		}
		return "";
		
	}

}
