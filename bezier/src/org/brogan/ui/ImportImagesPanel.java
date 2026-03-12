package org.brogan.ui;

import java.awt.Color;
import java.awt.Dimension;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.File;

import javax.swing.*;

import org.brogan.ui.ExtensionFileFilter;
import org.brogan.util.BPath;
import org.brogan.util.Swing;
import org.brogan.media.*;

public class ImportImagesPanel extends JPanel implements ActionListener{
	
    private static final int REFERENCE = 3;
	private CubicCurveFrame curveFrame;
	private final JFileChooser chooser = new JFileChooser();
	private final ExtensionFileFilter filter = new ExtensionFileFilter();
	
	private JButton referenceImageBrowse;
	private JTextField referenceImagePathField;

	private File referenceImageFile;
	private boolean referenceImage;
	
	
	/**
	 * Full-width constructor — uses the frame's default width.
	 */
	public ImportImagesPanel(CubicCurveFrame cF) {
		this(cF, cF.DEFAULT_WIDTH - 36);
	}

	/**
	 * Compact constructor — caller specifies the inner panel width so this
	 * section can share a row with other controls.
	 */
	public ImportImagesPanel(CubicCurveFrame cF, int innerPanelWidth) {
		curveFrame = cF;

		chooser.setFileSelectionMode(JFileChooser.FILES_ONLY);

		filter.addExtension("gif");  filter.setDescription("gif files");
		filter.addExtension("GIF");  filter.setDescription("GIF files");
		filter.addExtension("jpeg"); filter.setDescription("jpeg files");
		filter.addExtension("JPEG"); filter.setDescription("JPEG files");
		filter.addExtension("jpg");  filter.setDescription("jpg files");
		filter.addExtension("JPG");  filter.setDescription("JPG files");
		filter.addExtension("png");  filter.setDescription("png files");
		filter.addExtension("PNG");  filter.setDescription("PNG files");

		createLayout(innerPanelWidth);
	}

	private void createLayout(int innerPanelWidth) {

		this.setLayout(new BoxLayout(this, BoxLayout.PAGE_AXIS));
		int h  = 24;
		int bW = 80;

		referenceImagePathField = new JTextField("Reference Image Path");
		// Fill the available width: panel minus browse button and some padding
		Swing.setSize(referenceImagePathField, innerPanelWidth - bW - 20, h);

		referenceImageBrowse = new JButton("Browse");
		Swing.setSize(referenceImageBrowse, bW, h);
		referenceImageBrowse.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				setImportFile(referenceImagePathField, ImportImagesPanel.REFERENCE);
			}
		});

		JPanel referenceImagePanel = new JPanel();
		Swing.setSize(referenceImagePanel, innerPanelWidth, 54);
		referenceImagePanel.add(referenceImagePathField);
		referenceImagePanel.add(referenceImageBrowse);
		referenceImagePanel.setBorder(BorderFactory.createCompoundBorder(
			BorderFactory.createTitledBorder("Reference Image"),
			BorderFactory.createEmptyBorder(2, 2, 2, 2)));

		this.add(referenceImagePanel);

		resetChooserCurrentDirectory();
	}
	private void updateValues() {
		//send message to drawPanel.....
	}
	/**
	 * called from IconDrawManager constructor
	 * @return
	 */
	public ImageManager getImageManager() {
		return new ImageManager(this);
	}

	
	//called from import browse button
	private void setImportFile(JTextField displayPathField, int type) {
		String projectsDirectoryName = curveFrame.getProjectsDirectoryName();
		String projectName = curveFrame.getProjectName();
		String stillImagePath;
		String still = "";
		String fileSep = BPath.getFileSeparator();
		resetChooserCurrentDirectory();
		if (!projectName.equals("")) {//if project IS named 
			still = chooser.getCurrentDirectory() + fileSep + projectName + fileSep + "images" + fileSep + "stills";
			System.out.println("ImportImagesPanel, " + still);
			File fullPath = new File(still);
			if (fullPath.isDirectory()) {//and if project directory exists
				stillImagePath = fileSep + projectName + fileSep + "images" + fileSep + "stills";;
				System.out.println("ImportImagesPanel, stillImagePath: " + stillImagePath);
			} else {
				stillImagePath = "";
				System.out.println("ImportImagesPanel, stillImagePath: " + stillImagePath);
			}
		} else {
			stillImagePath = "";
			System.out.println("ImportImagesPanel, still is not a directory: " + still);
		}
		
		
		chooser.setCurrentDirectory(new File(BPath.getHomeDirectory() + fileSep + projectsDirectoryName + stillImagePath));
		
		//show dialog and
//		//wait for appropriate dialog input
		int result = chooser.showOpenDialog(this);
		//check that a selection has been made and not cancelled
		if (chooser.getSelectedFile()!=null) {
			referenceImageFile = chooser.getSelectedFile();
			displayPathField.setText(referenceImageFile.getPath());
			if (filter.accept(referenceImageFile)) {
				System.out.println("importImagesPanel: IS a reference image!!!!");
				System.out.println("importImagesPanel: imFile path: " + referenceImageFile.getPath());
				setReferenceImage();
			} else {
				System.out.println("importImagesPanel: not an image");
				JOptionPane.showMessageDialog(this, "You must select an image.");
			}
		}
	}
	
	
	
	/**
	 * checks to see if directory contains at least one image
	 * does not check for proper file names!!!!!!!!!!!!
	 * @param allFiles
	 * @return
	 */
	private boolean containsImages(String[] allFiles) {
		for (int i=0;i<allFiles.length;i++) {
			if (filter.accept(new File(allFiles[i]))) {
				return true;
			}
		}
		return false;
		
	}
	
	public void actionPerformed(ActionEvent e) {
		if (e.getActionCommand().equals("referenceImage")) {
			if (referenceImageFile != null) {
				System.out.println("importImagesPanel, actionPerformed: referenceImageFile path: " + referenceImageFile.getPath());
				setReferenceImage();
			}
		} 
		System.out.println("ImportImagesPanel, actionPerformed, e.getActionCommand()"+ e.getActionCommand());
	}

	/**
	 * @return the referenceImageFile
	 */
	public File getReferenceImageFile() {
		File f = new File(Swing.getFieldStringValue(referenceImagePathField));
		if (f != null) {
			return f;
		}
		return null;
	}

	/**
	 * set reference image text field path
	 */
	public void setReferenceImagePath(String p) {
		String rebuiltPath = curveFrame.getProjectsDirectoryName();
		referenceImagePathField.setText(rebuiltPath);
		referenceImageFile = new File(rebuiltPath);
	}

	/**
	 * @return the referenceImage
	 */
	public boolean isReferenceImage() {
		return referenceImage;
	}

	/**
	 * @param referenceImage the referenceImage to set
	 */
	public void setReferenceImage() {		
		curveFrame.getCurvePanel().getBezier().displayReferenceImage();
	}
	
	private void resetChooserCurrentDirectory() {
		String projectsDirectoryName = curveFrame.getProjectsDirectoryName();
		chooser.setCurrentDirectory(new File(BPath.getHomeDirectory() + BPath.getFileSeparator() + projectsDirectoryName));
	}


}
