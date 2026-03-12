/*
 * Created on Jul 10, 2005
 */
package org.brogan.ui;

import java.util.*;
import java.io.*;
import javax.swing.filechooser.FileFilter;
/**
 * @author brogan (from Horstmann & Cornell, Core Java)
 * @version July 2005
 * description: ensures that only files with proper extension are selected 
 */
public class ExtensionFileFilter extends FileFilter{
	
	private ArrayList extensions = new ArrayList();
	private String ext;
	private String description = "";
	/**
	 * adds file extenstion (with or without starting '.')
	 * @param extension file extension (String)
	 */
	public void addExtension(String extension) {
		if(!extension.startsWith(".")){
			extension="."+extension;
		}
		extensions.add(extension.toLowerCase());
	}
	/**
	 * 
	 * @return ext current extension
	 */
	public String getCurrentExtension(){
		return ext;
	}
	/**
	 * set description
	 * @param d description (String)
	 */
	public void setDescription(String d){
		description = d;
	}
	/**
	 * @return description
	 */
	public String getDescription(){
		return description;
	}
	/**
	 * checks to see if file has appropriate extension
	 * @return boolean
	 */
	public boolean accept(File f) {
		if (f.isDirectory()) {
			return true;
		}
		String name = f.getName().toLowerCase();
		Iterator extensionsIter = extensions.iterator();
		while(extensionsIter.hasNext()){
			String e = extensionsIter.next().toString();
			if(name.endsWith(e)){
				ext = e;
				return true;
			}
		}
		return false;
	}

}
