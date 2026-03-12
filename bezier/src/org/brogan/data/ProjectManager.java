/*
 * Created on Jul 23, 2005
 */
package org.brogan.data;

import org.apache.commons.io.FileUtils;
import org.brogan.util.BPath;
import org.brogan.util.BString;

import org.brogan.ui.CubicCurveFrame;


import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.PrintWriter;
import java.nio.file.Files;


/**
 * description: coordinates overall processes - loading, settings, etc.
 * @author brogan
 * @version
 * 
 */
public class ProjectManager {

	private CubicCurveFrame cubicCurveFrame;
	private String projectsDirectoryName;
	private String projectDirectoryPath;
	private String polygonSetFilePath;
	private String projectName;
	private boolean projectOpen;

	private String polygonSetXml = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n" +
			"<!DOCTYPE polygonSet SYSTEM \"../dtd/polygonSet.dtd\">\n" +
			"<polygonSet>\n" +
			"    <name>h</name>\n" +
			"    <shapeType>CUBIC_CURVE</shapeType>\n" +
			"    <polygon>\n" +
			"        <curve>\n" +
			"            <point x=\"-0.34\" y=\"-0.16\"/>\n" +
			"            <point x=\"-0.22\" y=\"-0.21\"/>\n" +
			"            <point x=\"-0.09\" y=\"-0.25\"/>\n" +
			"            <point x=\"0.02\" y=\"-0.3\"/>\n" +
			"        </curve>\n" +
			"        <curve>\n" +
			"            <point x=\"0.02\" y=\"-0.3\"/>\n" +
			"            <point x=\"0.07\" y=\"-0.18\"/>\n" +
			"            <point x=\"0.13\" y=\"-0.06\"/>\n" +
			"            <point x=\"0.18\" y=\"0.05\"/>\n" +
			"        </curve>\n" +
			"        <curve>\n" +
			"            <point x=\"0.18\" y=\"0.05\"/>\n" +
			"            <point x=\"0.06\" y=\"0.1\"/>\n" +
			"            <point x=\"-0.05\" y=\"0.16\"/>\n" +
			"            <point x=\"-0.17\" y=\"0.21\"/>\n" +
			"        </curve>\n" +
			"        <curve>\n" +
			"            <point x=\"-0.17\" y=\"0.21\"/>\n" +
			"            <point x=\"-0.23\" y=\"0.08\"/>\n" +
			"            <point x=\"-0.29\" y=\"-0.03\"/>\n" +
			"            <point x=\"-0.34\" y=\"-0.16\"/>\n" +
			"        </curve>\n" +
			"    </polygon>\n" +
			"    <scaleX>1.0</scaleX>\n" +
			"    <scaleY>1.0</scaleY>\n" +
			"    <rotationAngle>0.0</rotationAngle>\n" +
			"    <transX>0.5</transX>\n" +
			"    <transY>0.5</transY>\n" +
			"</polygonSet>";
	/**
	 * ProjectManager constructor
	 */
	public ProjectManager(CubicCurveFrame f) {
		cubicCurveFrame = f;
		projectsDirectoryName = "bezier_projects";
		projectDirectoryPath = null;
        polygonSetFilePath = null;
		projectOpen = false;
		createProjectsDirectory(); //if needed (not already created)
	}

	/**
	 * Constructor with custom save directory for polygon sets.
	 * When customSaveDir is non-null, polygon sets are saved there
	 * instead of the default ~/bezier_projects/polygonSet/ directory.
	 */
	public ProjectManager(CubicCurveFrame f, String customSaveDir) {
		cubicCurveFrame = f;
		projectsDirectoryName = "bezier_projects";
		projectDirectoryPath = null;
		polygonSetFilePath = null;
		projectOpen = false;

		if (customSaveDir != null) {
			File customDir = new File(customSaveDir);
			if (!customDir.isDirectory()) {
				customDir.mkdirs();
			}
			polygonSetFilePath = customDir.getAbsolutePath();
			// Still create the default projects directory for other resources
			createProjectsDirectory();
			// Override polygonSetFilePath after createProjectsDirectory
			polygonSetFilePath = customDir.getAbsolutePath();
			System.out.println("pM: Using custom save dir: " + polygonSetFilePath);
		} else {
			createProjectsDirectory();
		}
	}

	/**
	 * create overall projects directory for all projects
	 * and polygonSet directory within it
	 */
	public void createProjectsDirectory()  {
		//create um_projects directory in user home directory if does not exist
		File h = new File(BPath.getHomeDirectory() + BPath.getFileSeparator() + projectsDirectoryName);
		if (!h.isDirectory()) {
			h.mkdir();//create directory if it does not exist
		}
		String filePath = h.getAbsolutePath();
		projectDirectoryPath = filePath;
		File pS = new File(filePath + BPath.getFileSeparator() + "polygonSet");
		if (!pS.isDirectory()) {
			pS.mkdir();//create directory if it does not exist
		}
		polygonSetFilePath = pS.getAbsolutePath();

		File dtd = new File(filePath + BPath.getFileSeparator() + "dtd");
		if (!dtd.isDirectory()) {
			dtd.mkdir();//create directory if it does not exist
		}

		System.out.println("pM: Get createProjectsDirectory: "+polygonSetFilePath);
    }

	public void setProjectName(String n) {
		projectName = n;
	}

	/**
	 * getProjectDirectoryPath
	 * @return projectDirectoryPath
	 */
	public String getProjectDirectoryPath() {
		System.out.println("pM: Get projectFilePath: "+projectDirectoryPath);
		return projectDirectoryPath;
	}

	/**
	 * getPolygonSetFilePath
	 * @return polygonSetFilePath
	 */
	public String getPolygonSetFilePath() {
		System.out.println("pM: Get polygonSetFilePath: "+polygonSetFilePath);
		return polygonSetFilePath;
	}

	/**
	 * @return the projectsDirectoryName
	 */
	public String getProjectsDirectoryName() {
		return projectsDirectoryName;
	}

	
}
