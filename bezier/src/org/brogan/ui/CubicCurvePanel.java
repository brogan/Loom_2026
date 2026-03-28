package org.brogan.ui;

import org.brogan.data.*;
import org.brogan.bezier.*;
import org.brogan.bezier.CubicCurveManager;

import java.util.List;
import java.util.stream.Collectors;

import javax.swing.*;
import javax.swing.event.ChangeEvent;
import javax.swing.event.ChangeListener;

import org.brogan.ui.BJSlider;
import org.brogan.ui.ImportImagesPanel;
import org.brogan.util.BPath;
import org.brogan.util.BString;
import org.brogan.util.Swing;
import org.brogan.util.Transform;

import nu.xom.*;

import java.awt.BorderLayout;
import java.awt.Color;
import java.awt.Dimension;
import java.awt.GridLayout;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.awt.event.MouseEvent;
import java.awt.event.MouseListener;
import java.awt.geom.Point2D;
import java.io.File;

public class CubicCurvePanel extends JPanel implements MouseListener, ChangeListener {

	/** Rotation axis modes — queried by BezierDrawPanel.rotate() */
	public static final int ROTATE_LOCAL    = 0; // each polygon around its own centre
	public static final int ROTATE_COMMON   = 1; // all targets around their shared centre
	public static final int ROTATE_ABSOLUTE = 2; // around the absolute grid centre

	/** Scale axis modes — queried by BezierDrawPanel.scaleXY() */
	public static final int SCALE_XY = 0;
	public static final int SCALE_X  = 1;
	public static final int SCALE_Y  = 2;

	private final JFileChooser chooser = new JFileChooser();
	private final ExtensionFileFilter filter = new ExtensionFileFilter();

	private CubicCurveFrame curveFrame;

	private PolygonSetXml polygonXml;

	private boolean editing;//when edit button selected in drawersPanel
	private boolean valuesSaved;
	private boolean cloning;
	private boolean valuesEntered;//values have been entered
	private String originalName;

	private BezierDrawPanel bezier;
	private JPanel drawPanel;
	private int currentCanvasSize;
	private JTextField polySetFile, name, scaleX, scaleY, rotationAngle;
	private JCheckBox editAnchorPoints, editControlPoints;
	private JRadioButton rotateLocal, rotateCommon, rotateAbsolute;
	private JRadioButton scaleAxisXY, scaleAxisX, scaleAxisY;
	private BJSlider scaleSlider;
	private BJSlider rotateSlider;
	private boolean mouseReleased;


	private ImportImagesPanel refImagePanel;

	public CubicCurvePanel(CubicCurveFrame cF) {
		this(cF, null, BezierDrawPanel.WIDTH);
	}

	public CubicCurvePanel(CubicCurveFrame cF, ImportImagesPanel refPanel) {
		this(cF, refPanel, BezierDrawPanel.WIDTH);
	}

	public CubicCurvePanel(CubicCurveFrame cF, ImportImagesPanel refPanel, int initialCanvasSize) {

		chooser.setFileSelectionMode(JFileChooser.FILES_ONLY);
		filter.addExtension("xml");
		filter.setDescription("xml files");

		curveFrame = cF;
		refImagePanel = refPanel;
		editing = false;
		valuesSaved = false;
		cloning = false;
		valuesEntered = false;
		mouseReleased = false;
		currentCanvasSize = initialCanvasSize;

		createLayout();
	}

	public void stateChanged(ChangeEvent e) {
		if (!mouseReleased) {
			if (e.getSource() == scaleSlider) {
				bezier.scaleXY(scaleSlider.getValue());
			} else if (e.getSource() == rotateSlider) {
				double degrees = rotateSlider.getValue() * 1.8; // maps [-100,100] → [-180°,180°]
				bezier.rotate(degrees);
			}
		}
	}

	private void createLayout() {

		this.setLayout(new BoxLayout(this, BoxLayout.PAGE_AXIS));
		int w = 60;
		int h = 24;
		
		JLabel fileLabel, nameLabel;

		fileLabel = new JLabel("File");
		nameLabel = new JLabel("Name");

		editAnchorPoints = new JCheckBox("Anchor");
		editAnchorPoints.setSelected(true);
		editControlPoints = new JCheckBox("Control");
		editControlPoints.setSelected(true);

		Swing.setSize(fileLabel, w, h);
		nameLabel.setHorizontalAlignment(SwingConstants.RIGHT);
		Swing.setSize(nameLabel, w, h);
		nameLabel.setHorizontalAlignment(SwingConstants.RIGHT);

		//polySetFile
		polySetFile = new JTextField("");
		Swing.setSize(polySetFile, w*5, h);
		name = new JTextField("");
		Swing.setSize(name, w*3, h);

		// These fields are hidden from the UI but still read by exportToUserDir() for XML export
		scaleX = new JTextField("1");
		scaleY = new JTextField("1");
		rotationAngle = new JTextField("0");
		
		JButton loadButton = new JButton("Load");
		Swing.setSize(loadButton, w*2, h);
		
		loadButton.addActionListener(new
				ActionListener () {
			public void actionPerformed(ActionEvent e) {
				String fileSep = BPath.getFileSeparator();
				File polySetXml;
				ProjectManager projectManager = curveFrame.getProjectManager();
				String polygonSetFilePath = projectManager.getPolygonSetFilePath();
				chooser.setCurrentDirectory(new File(polygonSetFilePath));

				//show dialog and
				//						//wait for appropriate dialog input
				int result = chooser.showOpenDialog(bezier);
				//check that a selection has been made and not cancelled
				if (chooser.getSelectedFile()!=null) {

					polySetXml = chooser.getSelectedFile();
					polySetFile.setText(polySetXml.getPath());
					if (filter.accept(polySetXml)) {
						System.out.println("CubicCurvePanel: loading polygon set xml: " + polySetXml.getAbsolutePath());
						loadPolygonSet(polySetXml);
					} else {
						System.out.println("CubicCurvePanel: not xml");
						JOptionPane.showMessageDialog(bezier, "You must select an xml file.");
					}
				}
			}
		});
		
		JButton enterButton = new JButton("Save");
		Swing.setSize(enterButton, w*2, h);
		
		enterButton.addActionListener(new
				ActionListener () {
					public void actionPerformed(ActionEvent e){
						enterValues();
						exportToUserDir();
						// Save open curves if any exist
						CubicCurvePolygonManager pm = bezier.getPolygonManager();
						boolean hasOpen = false;
						for (int i = 0; i < pm.getPolygonCount(); i++) {
							if (!pm.getManager(i).getIsClosed()) { hasOpen = true; break; }
						}
						if (hasOpen) saveAsOpenCurveSet();
					}
				});
		
		
		JPanel namePanel = new JPanel();
		Swing.setSize(namePanel, CubicCurveFrame.DEFAULT_WIDTH-8, 54);
		namePanel.add(fileLabel);
		namePanel.add(polySetFile);
		namePanel.add(loadButton);
		namePanel.add(nameLabel);
		namePanel.add(name);
		namePanel.add(enterButton);
		namePanel.setBorder(BorderFactory.createCompoundBorder(BorderFactory.createTitledBorder("Load File: Save"), BorderFactory.createEmptyBorder(2,2,2,2)));
		
		drawPanel = new JPanel();
		Swing.setSize(drawPanel, CubicCurveFrame.DEFAULT_WIDTH-8, currentCanvasSize);
		bezier = new BezierDrawPanel(this, curveFrame, new Color(0,0,0));
		bezier.setFocusable(true);
		bezier.requestFocus();
		Swing.setSize(bezier, currentCanvasSize, currentCanvasSize);
		drawPanel.add(bezier);
		
		
		//drawPanel.setBorder(BorderFactory.createCompoundBorder(BorderFactory.createTitledBorder("Bezier Draw"), BorderFactory.createEmptyBorder(2,2,2,2)));
		
		JPanel editPanel = new JPanel();
		Swing.setSize(editPanel, CubicCurveFrame.DEFAULT_WIDTH-8, 64);

		JPanel editModePanel = new JPanel();
		Swing.setSize(editModePanel, 290, 54);
		editModePanel.add(editAnchorPoints);
		editModePanel.add(editControlPoints);
		editModePanel.setBorder(BorderFactory.createCompoundBorder(BorderFactory.createTitledBorder("Edit Mode (Point Selection)"), BorderFactory.createEmptyBorder(2,2,2,2)));

		scaleAxisXY = new JRadioButton("XY", true);
		scaleAxisX  = new JRadioButton("X",  false);
		scaleAxisY  = new JRadioButton("Y",  false);
		ButtonGroup scaleAxisGroup = new ButtonGroup();
		scaleAxisGroup.add(scaleAxisXY);
		scaleAxisGroup.add(scaleAxisX);
		scaleAxisGroup.add(scaleAxisY);
		JPanel scaleAxisPanel = new JPanel();
		Swing.setSize(scaleAxisPanel, 210, 54);
		scaleAxisPanel.add(scaleAxisXY);
		scaleAxisPanel.add(scaleAxisX);
		scaleAxisPanel.add(scaleAxisY);
		scaleAxisPanel.setBorder(BorderFactory.createCompoundBorder(BorderFactory.createTitledBorder("Scale Axis"), BorderFactory.createEmptyBorder(2,2,2,2)));

		rotateLocal    = new JRadioButton("Local",    true);
		rotateCommon   = new JRadioButton("Common",   false);
		rotateAbsolute = new JRadioButton("Absolute", false);
		ButtonGroup rotateAxisGroup = new ButtonGroup();
		rotateAxisGroup.add(rotateLocal);
		rotateAxisGroup.add(rotateCommon);
		rotateAxisGroup.add(rotateAbsolute);

		JPanel rotationAxisPanel = new JPanel();
		Swing.setSize(rotationAxisPanel, 510, 54);
		rotationAxisPanel.add(rotateLocal);
		rotationAxisPanel.add(rotateCommon);
		rotationAxisPanel.add(rotateAbsolute);
		rotationAxisPanel.setBorder(BorderFactory.createCompoundBorder(BorderFactory.createTitledBorder("Rotation Axis"), BorderFactory.createEmptyBorder(2,2,2,2)));

		editPanel.add(editModePanel);
		editPanel.add(scaleAxisPanel);
		editPanel.add(rotationAxisPanel);
		
		JPanel sliderPanel = new JPanel(new GridLayout(1, 2, 10, 0));
		Swing.setSize(sliderPanel, CubicCurveFrame.DEFAULT_WIDTH - 8, 90);

		scaleSlider = new BJSlider(-100, 100, 0, "Scale");
		scaleSlider.addChangeListener(this);
		scaleSlider.addMouseListener(this);
		JPanel scalePanel = new JPanel(new BorderLayout(0, 2));
		scalePanel.add(new JLabel("Scale", SwingConstants.CENTER), BorderLayout.NORTH);
		scalePanel.add(scaleSlider, BorderLayout.CENTER);

		rotateSlider = new BJSlider(-100, 100, 0, "Rotation");
		rotateSlider.addChangeListener(this);
		rotateSlider.addMouseListener(this);
		JPanel rotatePanel = new JPanel(new BorderLayout(0, 2));
		rotatePanel.add(new JLabel("Rotation", SwingConstants.CENTER), BorderLayout.NORTH);
		rotatePanel.add(rotateSlider, BorderLayout.CENTER);

		sliderPanel.add(scalePanel);
		sliderPanel.add(rotatePanel);
		sliderPanel.setBorder(BorderFactory.createCompoundBorder(
			BorderFactory.createTitledBorder("Transform"),
			BorderFactory.createEmptyBorder(2, 2, 2, 2)));

		JButton importSvgButton = new JButton("Import SVG");
		Swing.setSize(importSvgButton, w * 3, h);
		importSvgButton.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				importFromSvg();
			}
		});
		JPanel svgPanel = new JPanel();
		Swing.setSize(svgPanel, 240, 54);
		svgPanel.add(importSvgButton);
		svgPanel.setBorder(BorderFactory.createCompoundBorder(
			BorderFactory.createTitledBorder("SVG"),
			BorderFactory.createEmptyBorder(2, 2, 2, 2)));

		// Place the SVG button and reference image section side-by-side in one row
		JPanel topRow = new JPanel();
		topRow.setLayout(new BoxLayout(topRow, BoxLayout.LINE_AXIS));
		Swing.setSize(topRow, CubicCurveFrame.DEFAULT_WIDTH - 8, 54);
		topRow.add(svgPanel);
		if (refImagePanel != null) {
			topRow.add(refImagePanel);
		}

		this.add(namePanel);
		this.add(topRow);
		this.add(drawPanel);
		this.add(editPanel);
		this.add(sliderPanel);
		
		
	}
	/**
	 * COMMENTED CODE BELOW NEEDS UPDATING - HOW TO MANAGE SHAPE CREATOR AND UIFRAME
	 * ______________________________________________________________________________________________________________________________
	 */

	public void enterValues() {
		
		CubicCurvePolygonManager polygonManager = bezier.getPolygonManager();

		//note that normalisation now occurs from exportToUserDir and then createXMl in PolygonSetXml

		String n = Swing.getFieldStringValue(name);
		double sX = Swing.getFieldDoubleValue(scaleX);
		double sY = Swing.getFieldDoubleValue(scaleY);
		double rotA = Swing.getFieldDoubleValue(rotationAngle);

		if (editing && !cloning) {
			System.out.println("CubicCurvePanel enterValues calling editCubicCurve in editing mode");
			//ShapeCreator.editCubicCurve(originalName, n, allPoints, sX, sY, rotA, uiFrame);
		} else if (!valuesSaved){//new
			System.out.println("CubicCurvePanel enterValues calling createCubicCurve - first time saved");
			//ShapeCreator.createCubicCurve(n, allPoints, sX, sY, rotA, uiFrame);
			valuesSaved = true;//so subsequent calls to enter save edited values
		} else {
			System.out.println("CubicCurvePanel enterValues calling editCubicCurve - subsequent save");
			originalName = n;
			//ShapeCreator.editCubicCurve(originalName, n, allPoints, sX, sY, rotA, uiFrame);
		}
		
		//COMMENT JUST WHILE FIXING XML SAVING 
		//uiFrame.getDrawersPanel().updateCombos();
		//exportToUserDir();
		valuesEntered = true;

	}
	/**
	 * exports shape as xml to user dir
	 */
	
	private static String toFilename(String s) {
		return s.trim()
			.replaceAll("\\s+", "_")
			.replaceAll("[^a-zA-Z0-9_\\-]", "")
			.toLowerCase();
	}

	public void exportToUserDir() {
		if (!valuesEntered) {
			enterValues();
		}
		CubicCurvePolygonManager polygonManager = bezier.getPolygonManager();
		LayerManager lm = bezier.getLayerManager();

		String overall = Swing.getFieldStringValue(name);
		double sX  = Swing.getFieldDoubleValue(scaleX);
		double sY  = Swing.getFieldDoubleValue(scaleY);
		double rotA = Swing.getFieldDoubleValue(rotationAngle);

		String dtdPath = "../dtd";

		ProjectManager projectManager = curveFrame.getProjectManager();
		String polygonSetFilePath = projectManager.getPolygonSetFilePath();
		File polygonSetDir = new File(polygonSetFilePath);
		String svgDirPath = new File(polygonSetDir.getParent(), "svgs").getAbsolutePath();

		String overallFn = toFilename(overall);
		boolean anySaved = false;

		for (Layer layer : lm.getLayers()) {
			List<CubicCurveManager> managers = polygonManager.getManagersForLayer(layer.getId());
			if (managers.isEmpty()) continue;

			String layerFn = overallFn + "_" + toFilename(layer.getName());
			String xmlPath = polygonSetFilePath + File.separator + layerFn + ".xml";

			polygonXml = new PolygonSetXml(dtdPath);
			polygonXml.setXmlFilePath(xmlPath);
			polygonXml.createNewXml(layerFn, "CUBIC_CURVE", managers, this, sX, sY, rotA, 0.5, 0.5);

			BezierSvgExporter.save(managers, svgDirPath, layerFn);
			anySaved = true;
		}

		// If no layers had polygons, fall back to saving everything as one file
		if (!anySaved) {
			String filePath = polygonSetFilePath + File.separator + overallFn + ".xml";
			polygonXml = new PolygonSetXml(dtdPath);
			polygonXml.setXmlFilePath(filePath);
			polygonXml.createNewXml(overall, "CUBIC_CURVE", polygonManager, this, sX, sY, rotA, 0.5, 0.5);
			BezierSvgExporter.save(polygonManager, svgDirPath, overallFn);
		} else {
			// Save the layer manifest
			LayerSetXml.save(lm, overall, polygonSetFilePath);
		}

		// Save discrete points (if any) to the pointSets directory
		java.util.List<java.awt.geom.Point2D.Double> points = bezier.getPoints();
		if (!points.isEmpty()) {
			File pointSetsDir = new File(new File(polygonSetFilePath).getParent(), "pointSets");
			pointSetsDir.mkdirs();
			String pointsFn = overallFn + "_points";
			String pointsXmlPath = pointSetsDir.getAbsolutePath() + File.separator + pointsFn + ".xml";
			org.brogan.data.PointSetXml pointsXml = new org.brogan.data.PointSetXml(dtdPath);
			pointsXml.setXmlFilePath(pointsXmlPath);
			pointsXml.createNewXml(pointsFn, points, this, sX, sY, rotA, 0.5, 0.5);
			System.out.println("CubicCurvePanel: saved point set to " + pointsXmlPath);
		}
		// Save ovals (if any) to the ovalSets directory
		java.util.List<OvalManager> ovals = bezier.getOvals();
		if (!ovals.isEmpty()) {
			File ovalSetsDir = new File(new File(polygonSetFilePath).getParent(), "ovalSets");
			ovalSetsDir.mkdirs();
			String ovalsFn = overallFn + "_ovals";
			String ovalsXmlPath = ovalSetsDir.getAbsolutePath() + File.separator + ovalsFn + ".xml";
			org.brogan.data.OvalSetXml ovalsXml = new org.brogan.data.OvalSetXml();
			ovalsXml.setXmlFilePath(ovalsXmlPath);
			ovalsXml.createNewXml(ovalsFn, ovals);
			System.out.println("CubicCurvePanel: saved oval set to " + ovalsXmlPath);
		}
	}

	/**
	 * Open a file chooser for the adjacent "svgs" directory and import the
	 * selected SVG file, adding its paths to the current canvas geometry.
	 */
	private void importFromSvg() {
		ProjectManager projectManager = curveFrame.getProjectManager();
		String polygonSetFilePath = projectManager.getPolygonSetFilePath();
		File polygonSetDir = new File(polygonSetFilePath);
		File svgDir = new File(polygonSetDir.getParent(), "svgs");

		JFileChooser svgChooser = new JFileChooser();
		svgChooser.setCurrentDirectory(svgDir.exists() ? svgDir : polygonSetDir);
		svgChooser.setFileSelectionMode(JFileChooser.FILES_ONLY);
		svgChooser.setFileFilter(new javax.swing.filechooser.FileNameExtensionFilter("SVG files", "svg"));

		int result = svgChooser.showOpenDialog(bezier);
		if (result == JFileChooser.APPROVE_OPTION && svgChooser.getSelectedFile() != null) {
			File svgFile = svgChooser.getSelectedFile();
			bezier.takeUndoSnapshot();
			BezierSvgImporter.importSvg(svgFile, bezier.getPolygonManager(), bezier.getStrokeColor());
		}
	}
	/**
	 * Save all open (non-closed) managers as an openCurveSet XML to the curveSets directory.
	 */
	public void saveAsOpenCurveSet() {
		if (!valuesEntered) {
			enterValues();
		}
		CubicCurvePolygonManager polygonManager = bezier.getPolygonManager();
		String overall = Swing.getFieldStringValue(name);
		double sX  = Swing.getFieldDoubleValue(scaleX);
		double sY  = Swing.getFieldDoubleValue(scaleY);
		double rotA = Swing.getFieldDoubleValue(rotationAngle);

		String dtdPath = "../dtd";
		ProjectManager projectManager = curveFrame.getProjectManager();
		String polygonSetFilePath = projectManager.getPolygonSetFilePath();
		File polygonSetDir = new File(polygonSetFilePath);
		File curveSetsDir = new File(polygonSetDir.getParent(), "curveSets");
		curveSetsDir.mkdirs();

		String overallFn = toFilename(overall);
		String xmlPath = curveSetsDir.getAbsolutePath() + File.separator + overallFn + ".xml";
		String svgDirPath = new File(polygonSetDir.getParent(), "svgs").getAbsolutePath();

		// Collect only open managers
		java.util.List<CubicCurveManager> openManagers = new java.util.ArrayList<>();
		int count = polygonManager.getPolygonCount();
		for (int i = 0; i < count; i++) {
			CubicCurveManager mgr = polygonManager.getManager(i);
			if (!mgr.getIsClosed()) {
				openManagers.add(mgr);
			}
		}

		OpenCurveSetXml xml = new OpenCurveSetXml(dtdPath);
		xml.setXmlFilePath(xmlPath);
		xml.createNewXml(overallFn, openManagers, this, sX, sY, rotA, 0.5, 0.5);
		BezierSvgExporter.save(openManagers, svgDirPath, overallFn);
		System.out.println("CubicCurvePanel: saved open curve set to " + xmlPath);
	}

	/**
	 * Save all discrete points as a pointSet XML to the pointSets directory.
	 */
	public void saveAsPointSet() {
		java.util.List<java.awt.geom.Point2D.Double> points = bezier.getPoints();
		if (points.isEmpty()) {
			javax.swing.JOptionPane.showMessageDialog(this, "No points to save. Enable Point Mode and click on the canvas first.",
				"No Points", javax.swing.JOptionPane.INFORMATION_MESSAGE);
			return;
		}
		if (!valuesEntered) {
			enterValues();
		}
		String overall = Swing.getFieldStringValue(name);
		double sX  = Swing.getFieldDoubleValue(scaleX);
		double sY  = Swing.getFieldDoubleValue(scaleY);
		double rotA = Swing.getFieldDoubleValue(rotationAngle);

		String dtdPath = "../dtd";
		ProjectManager projectManager = curveFrame.getProjectManager();
		String polygonSetFilePath = projectManager.getPolygonSetFilePath();
		File polygonSetDir = new File(polygonSetFilePath);
		File pointSetsDir = new File(polygonSetDir.getParent(), "pointSets");
		pointSetsDir.mkdirs();

		String overallFn = toFilename(overall);
		String xmlPath = pointSetsDir.getAbsolutePath() + File.separator + overallFn + ".xml";

		org.brogan.data.PointSetXml xml = new org.brogan.data.PointSetXml(dtdPath);
		xml.setXmlFilePath(xmlPath);
		xml.createNewXml(overallFn, points, this, sX, sY, rotA, 0.5, 0.5);
		System.out.println("CubicCurvePanel: saved point set to " + xmlPath);
	}

	/**
	 * Load a pointSet XML file, replacing current points and clearing curves.
	 */
	public void loadPointSet(File f) {
		bezier.getPolygonManager().clearManagers();
		bezier.clearPoints();
		nu.xom.Document doc;
		try {
			org.xml.sax.XMLReader xr = org.xml.sax.helpers.XMLReaderFactory.createXMLReader();
			try { xr.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false); } catch (Exception ignore) {}
			nu.xom.Builder parser = new nu.xom.Builder(xr);
			doc = parser.build(f);
		} catch (Exception ex) {
			System.out.println("CubicCurvePanel: failed to parse pointSet: " + ex.getMessage());
			return;
		}
		nu.xom.Element root = doc.getRootElement();
		bezier.appendPointSet(root);
		nu.xom.Element nameEl = root.getFirstChildElement("name");
		if (nameEl != null && !nameEl.getValue().trim().isEmpty()) {
			name.setText(nameEl.getValue().trim());
		}
		System.out.println("CubicCurvePanel: loaded point set from " + f.getName());
	}

	/**
	 * Load an openCurveSet XML file, replacing the current canvas geometry.
	 */
	public void loadOpenCurveSet(File f) {
		bezier.getPolygonManager().clearManagers();
		Document doc;
		try {
			org.xml.sax.XMLReader xr = org.xml.sax.helpers.XMLReaderFactory.createXMLReader();
			try { xr.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false); } catch (Exception ignore) {}
			Builder parser = new Builder(xr);
			doc = parser.build(f);
		} catch (Exception ex) {
			System.out.println("CubicCurvePanel: failed to parse openCurveSet: " + ex.getMessage());
			return;
		}
		Element root = doc.getRootElement();
		bezier.appendOpenCurveSet(root);
		bezier.denormaliseAllPoints();
		Element nameEl = root.getFirstChildElement("name");
		if (nameEl != null && !nameEl.getValue().trim().isEmpty()) {
			name.setText(nameEl.getValue().trim());
		}
		System.out.println("CubicCurvePanel: loaded open curve set from " + f.getName());
	}

	/**
	 * Save all ovals as an ovalSet XML to the ovalSets directory.
	 */
	public void saveAsOvalSet() {
		java.util.List<OvalManager> ovals = bezier.getOvals();
		if (ovals.isEmpty()) {
			javax.swing.JOptionPane.showMessageDialog(this, "No ovals to save.",
				"No Ovals", javax.swing.JOptionPane.INFORMATION_MESSAGE);
			return;
		}
		if (!valuesEntered) {
			enterValues();
		}
		String overall = Swing.getFieldStringValue(name);

		ProjectManager projectManager = curveFrame.getProjectManager();
		String polygonSetFilePath = projectManager.getPolygonSetFilePath();
		File polygonSetDir = new File(polygonSetFilePath);
		File ovalSetsDir = new File(polygonSetDir.getParent(), "ovalSets");
		ovalSetsDir.mkdirs();

		String overallFn = toFilename(overall);
		String xmlPath = ovalSetsDir.getAbsolutePath() + File.separator + overallFn + ".xml";

		org.brogan.data.OvalSetXml xml = new org.brogan.data.OvalSetXml();
		xml.setXmlFilePath(xmlPath);
		xml.createNewXml(overallFn, ovals);
		System.out.println("CubicCurvePanel: saved oval set to " + xmlPath);
	}

	/**
	 * Load an ovalSet XML file, replacing current ovals.
	 */
	public void loadOvalSet(File f) {
		bezier.clearOvals();
		Document doc;
		try {
			org.xml.sax.XMLReader xr = org.xml.sax.helpers.XMLReaderFactory.createXMLReader();
			try { xr.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false); } catch (Exception ignore) {}
			Builder parser = new Builder(xr);
			doc = parser.build(f);
		} catch (Exception ex) {
			System.out.println("CubicCurvePanel: failed to parse ovalSet: " + ex.getMessage());
			return;
		}
		Element root = doc.getRootElement();
		bezier.appendOvalSet(root);
		Element nameEl = root.getFirstChildElement("name");
		if (nameEl != null && !nameEl.getValue().trim().isEmpty()) {
			name.setText(nameEl.getValue().trim());
		}
		System.out.println("CubicCurvePanel: loaded oval set from " + f.getName());
	}

	/**
	 *
	 */
	public void loadPolygonSet(File polySetXml) {
		
		CubicCurvePolygonManager polygonManager = bezier.getPolygonManager();

		String dtdPath = "../dtd";

		XmlManager xmlManager = new XmlManager(polySetXml.getName(), "polygonSet.dtd", dtdPath);
		
		xmlManager.loadXml(polySetXml);
		
		//for debugging purposes
		printLoadedXmlValues(xmlManager.getRoot());
		
		bezier.setPolygonSet(xmlManager.getRoot());

		// Populate the name field from the loaded XML so the set can be re-saved easily
		Element nameEl = xmlManager.getRoot().getFirstChildElement("name");
		if (nameEl != null && !nameEl.getValue().trim().isEmpty()) {
			name.setText(nameEl.getValue().trim());
		}

		System.out.println("CubicCurvePanel, xml loaded");
		System.out.println("______");
		
		//curveManager.readjustForOffset(-.01);
		//polygonManager.readjustForOffset(((double)(-bezier.getEdgeOffset()/2))/1000);
		//polygonManager.readjustForOffset(((double)(-bezier.getEdgeOffset()/2)/1000));
		//polygonManager.readjustForOffset(((double)(-bezier.getEdgeOffset()/2)));
		
	}
	/**
	 * Load a full multi-layer set from a .layers.xml manifest.
	 * Clears all existing geometry, creates one Layer per manifest entry,
	 * loads each layer's polygon XML, then denormalises once at the end.
	 */
	public void loadLayerSet(File layersXmlFile) {
		// 1. Clear existing geometry
		bezier.getPolygonManager().clearManagers();

		// 2. Parse .layers.xml with a non-validating parser (no DOCTYPE needed)
		Document doc;
		try {
			Builder parser = new Builder(false);
			doc = parser.build(layersXmlFile);
		} catch (Exception ex) {
			System.out.println("CubicCurvePanel: failed to parse layers manifest: " + ex.getMessage());
			return;
		}

		Element root = doc.getRootElement();

		// 3. Populate name field from <overallName>
		Element overallNameEl = root.getFirstChildElement("overallName");
		if (overallNameEl != null && !overallNameEl.getValue().trim().isEmpty()) {
			name.setText(overallNameEl.getValue().trim());
		}

		// 4. Create layers and load polygons
		LayerManager lm = bezier.getLayerManager();
		Elements layerEls = root.getChildElements("layer");
		boolean firstLayer = true;

		for (int i = 0; i < layerEls.size(); i++) {
			Element layerEl  = layerEls.get(i);
			Element nameEl   = layerEl.getFirstChildElement("name");
			Element fileEl   = layerEl.getFirstChildElement("file");
			Element visEl    = layerEl.getFirstChildElement("visible");
			if (nameEl == null || fileEl == null) continue;

			String  layerName     = nameEl.getValue().trim();
			String  layerFilename = fileEl.getValue().trim();
			boolean visible       = visEl == null || !"false".equals(visEl.getValue().trim());

			// Reuse the initial "Layer 1" for the first entry; create new layers for the rest
			Layer layer;
			if (firstLayer) {
				layer = lm.getActiveLayer();
				lm.renameLayer(layer.getId(), layerName);
				firstLayer = false;
			} else {
				layer = lm.createLayer(layerName);
			}
			layer.setVisible(visible);
			lm.setActiveLayerId(layer.getId());
			bezier.getPolygonManager().syncActiveDrawingManagerLayer();

			// Load the layer's polygon XML (no DTD validation — headers are stripped)
			File layerFile = new File(layersXmlFile.getParent(), layerFilename);
			if (layerFile.exists()) {
				try {
					Builder layerParser = new Builder(false);
					Document layerDoc   = layerParser.build(layerFile);
					bezier.appendPolygonSet(layerDoc.getRootElement());
				} catch (Exception ex) {
					System.out.println("CubicCurvePanel: failed to load layer '"
						+ layerName + "': " + ex.getMessage());
				}
			} else {
				System.out.println("CubicCurvePanel: layer file not found: "
					+ layerFile.getAbsolutePath());
			}
		}

		// 5. Denormalise all loaded polygons in a single pass
		bezier.denormaliseAllPoints();

		// 6. Activate the first layer
		if (!lm.getLayers().isEmpty()) {
			lm.setActiveLayerId(lm.getLayers().get(0).getId());
			bezier.getPolygonManager().syncActiveDrawingManagerLayer();
		}

		System.out.println("CubicCurvePanel: loaded layer set from " + layersXmlFile.getName());
	}

	/**
	 * Set the name text field value (used by CLI --name argument).
	 */
	public void setNameField(String n) {
		name.setText(n);
	}
	/**
	 * printLoadedXmlValues
	 * @param root
	 * print out the loaded PolygonSet xml values
	 */
	public void printLoadedXmlValues(Element root) {
		
		System.out.println("..................................");
		
		Elements polys = root.getChildElements("polygon");
		System.out.println("NUMBER OF POLYGONS: " + polys.size());
		for (int p=0;p<polys.size();p++) {
			Element poly = (Element) polys.get(p);
			System.out.println("  POLYGON: " + p);
			Elements curves = poly.getChildElements();
			int totCurves = curves.size();
			System.out.println("      totCurves: " + totCurves);
			for (int c=0;c<totCurves;c++) {
				System.out.println("      CURVE: " + c);
				Element curve = curves.get(c);
				Elements points = curve.getChildElements();
				System.out.println("        NUMBER OF POINTS: " + points.size());
				for (int n=0;n<points.size();n++) {
					System.out.println("          POINT " + n + ": x: " + (points.get(n).getAttributeValue("x")) + "  y: " + (points.get(n).getAttributeValue("y")));
				}
			}

		}
		
		/**
		Elements polys = root.getChildElements("polygon");
		System.out.println("NUMBER OF POLYGONS: " + polys.size());
		for (int p=0;p<polys.size();p++) {
			Element poly = (Element) polys.get(p);
			System.out.println("  POLYGON: " + p);
			for (int c=0;c<poly.getChildCount();c++) {
				Elements curves = poly.getChildElements();
				System.out.println("    CURVES " + c + " (number of curves: " + curves.size() + ")");
				for (int j=0;j<curves.size();j++) {
					Element curve = curves.get(j);
					System.out.println("      CURVE: " + j);
					Elements points = curve.getChildElements();
					System.out.println("        NUMBER OF POINTS: " + points.size());
					for (int n=0;n<points.size();n++) {
						System.out.println("          POINT " + n + ": x: " + (points.get(n).getAttributeValue("x")) + "  y: " + (points.get(n).getAttributeValue("y")));
					}
				}
			}
			
		}
		*/
		System.out.println("!!!END POLYGONS:");
		
		System.out.println("..................................");
		
	}
	/**
	 * 
	 */
	public void cloneCubicCurve() {

		cloning = true;
		enterValues();

		String n = Swing.getFieldStringValue(name);
		CubicCurveFrame f = new CubicCurveFrame();
		
		//HOW TO UPDATE?______________________________________________________________________________________________________________________________
		//ShapeParamsLibrary shapeLib = uiFrame.getShapeParamsAsLibrary();  
		//ShapeParams thisCurve = shapeLib.getShapeParamsByName(n).cloneShapeParams();
		//f.getCubicCurvePanel().setValues(thisCurve);
	}
	/**
	 * called when editing Cubic Curve
	 * from edit curve button in DrawersPanel
	 * @param s
	 */
	/**
	 * UPDATE NEEDED_______________________________________________________________________________________________________________________________
	 * @return
	 
	public void setValues(ShapeParams sP) {
		ShapeParams s = sP.cloneShapeParams();
		if (!cloning) {
			editing = true;
		} else {
			editing = false;
		}
		String n = s.getName();
		if (n.contains("__")) {
			originalName = BString.splitDiscardLastItem(n, "__");
		} else {
			originalName = n;
		}
		
		
		name.setText(originalName);
		Point2D.Double[] points = s.getPolyPoints();
		
		double[] initInfo = s.getInitInfo();
		double sX = initInfo[0];
		double sY = initInfo[1];
		double rotA = initInfo[2];
		
		//invert scale x values if less than or greater than 1
		if (sX==1) {
			//sX stays the same
		} else if (sX<1) {
			sX = sX/1;//so .5 becomes 2, etc.
		} else {//sX greater than 1
			sX = 1/sX;
		}
		//invert scale y values if less than or greater than 1
		if (sY==1) {
			//sY stays the same
		} else if (sY<1) {
			sY = sY/1;//so .5 becomes 2, etc.
		} else {//sY greater than 1
			sY = 1/sY;
		}
		Point2D.Double scale = new Point2D.Double(sX, sY);
		rotA += -rotA;//invert rotation
		Point2D.Double trans = new Point2D.Double(-.5, -.5);//serves to position at center of square
		
		Point2D.Double rotOffset = new Point2D.Double(0, 0);
		
		for (int g = 0; g<points.length; g++) {
			points [g] = Transform.scale(points [g], scale);
			points [g] = Transform.rotate(points [g], rotA);
			points [g] = Transform.translate(points [g], trans);
			CubicCurves.deNormalise(points[g]);
		}
		bezier.getCurveManager().setAllPoints(points, bezier.getStrokeColor());

		scaleX.setText(""+initInfo[0]);
		scaleY.setText(""+initInfo[1]);
		rotationAngle.setText(""+initInfo[2]);

	}
	*/
	
	/**
	 * Returns the currently selected rotation axis mode.
	 * Used by BezierDrawPanel.rotate() to determine the pivot point.
	 */
	public int getRotationAxisMode() {
		if (rotateCommon.isSelected())   return ROTATE_COMMON;
		if (rotateAbsolute.isSelected()) return ROTATE_ABSOLUTE;
		return ROTATE_LOCAL;
	}

	/**
	 * Returns the currently selected scale axis mode.
	 * Used by BezierDrawPanel.scaleXY() to determine which axes to scale.
	 */
	public int getScaleAxisMode() {
		if (scaleAxisX.isSelected()) return SCALE_X;
		if (scaleAxisY.isSelected()) return SCALE_Y;
		return SCALE_XY;
	}

	/*
	 * called from BezierDrawPanel
	 * to manage cubic curve editing (allows anchor points to be edited)
	 */
	public boolean isEditAnchorPoints() {
		return editAnchorPoints.isSelected();
	}
	/*
	 * called from BezierDrawPanel
	 * to manage cubic curve editing (allows control points to be edited)
	 */
	public boolean isEditControlPoints() {
		return editControlPoints.isSelected();
	}
	//@Override
	public void mouseClicked(MouseEvent arg0) {
		// TODO Auto-generated method stub
		
	}
	//@Override
	public void mouseEntered(MouseEvent arg0) {
		// TODO Auto-generated method stub
		
	}
	//@Override
	public void mouseExited(MouseEvent arg0) {
		// TODO Auto-generated method stub
		
	}
	//@Override
	public void mousePressed(MouseEvent arg0) {
		mouseReleased = false;
		
	}
	//@Override
	public void mouseReleased(MouseEvent arg0) {
		mouseReleased = true;
		bezier.setOrigPosOfAllPointsToModifiedPos();
		scaleSlider.setValue(0);
		rotateSlider.setValue(0);
		mouseReleased = false;
	}
	/**
	 * Resize the drawing canvas to a new square size.
	 * Called by CubicCurveFrame when the window is resized.
	 */
	public void setCanvasSize(int size) {
		if (size == currentCanvasSize) return;
		currentCanvasSize = size;
		Swing.setSize(drawPanel, CubicCurveFrame.DEFAULT_WIDTH - 8, size);
		Swing.setSize(bezier, size, size);
		revalidate();
		repaint();
	}

	/** Combined preferred height of all fixed-height panels (excludes the drawing canvas). */
	public int getFixedPanelHeight() {
		// namePanel(54) + topRow(54) + editPanel(64) + sliderPanel(90)
		return 262;
	}

	/**
	 * @return the bezier
	 */
	public BezierDrawPanel getBezier() {
		return bezier;
	}
	


}
