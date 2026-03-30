package org.brogan.ui;

import java.awt.BorderLayout;
import java.awt.Dimension;
import java.awt.GraphicsEnvironment;
import java.awt.Image;
import java.awt.Point;
import java.awt.Rectangle;
import java.awt.Toolkit;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.awt.event.ComponentAdapter;
import java.awt.event.ComponentEvent;
import java.awt.event.KeyEvent;
import java.awt.event.WindowEvent;
import java.awt.event.WindowListener;
import java.io.IOException;
import java.net.URI;
import java.net.URL;


import javax.swing.*;

import org.brogan.bezier.BezierDrawPanel;
import org.brogan.bezier.BezierToolBarPanel;

import org.brogan.data.ProjectManager;

import java.io.File;


public class CubicCurveFrame extends JFrame implements WindowListener{
	
	public static final int DEFAULT_WIDTH = 1348;
	public static final int DEFAULT_HEIGHT = 1380;
	/** Approximate height consumed by toolbar + fixed panels + frame chrome. */
	private static final int FIXED_OVERHEAD = 344;

	private static ProjectManager projectManager;
	private final String projectsDirectoryName = "resources";
	private final String projectName = "bezier";

	private int initialCanvasSize = BezierDrawPanel.WIDTH;

	private CubicCurvePanel curvePanel;
	private BezierToolBarPanel toolBarPanel;
	private ImportImagesPanel referenceImagePanel;
	private LayerPanel layerPanel;

	public CubicCurveFrame() {
		this(null, null, null, false);
	}

	public CubicCurveFrame(String saveDirPath, String loadFilePath, String nameValue, boolean pointSelect) {
		Toolkit kit = Toolkit.getDefaultToolkit();
		initialCanvasSize = computeInitialCanvasSize();
		setSize(DEFAULT_WIDTH, initialCanvasSize + FIXED_OVERHEAD);
		setLocation(new Point(320,0));
		java.net.URL iconUrl = getClass().getResource("/resources/icons/icon.png");
		Image img = (iconUrl != null) ? kit.getImage(iconUrl) : kit.getImage("resources/icons/icon.png");
		setIconImage(img);
		setTitle("Create/Edit One or More Cubic Bezier Curves");
		createLayout();
		setJMenuBar(createMenuBar());
		this.addWindowListener(this);
		this.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
		this.addComponentListener(new ComponentAdapter() {
			public void componentResized(ComponentEvent e) {
				if (curvePanel != null) {
					int newCanvas = computeCanvasFromHeight(getHeight());
					curvePanel.setCanvasSize(newCanvas);
				}
			}
		});

		// New project: set create-polygon mode BEFORE the window is shown
		// so the correct button is highlighted from the very first frame.
		if (loadFilePath == null && !pointSelect) {
			toolBarPanel.activatePolygonMode();
		}

		this.setVisible(true);

		if (saveDirPath != null) {
			projectManager = new ProjectManager(this, saveDirPath);
		} else {
			projectManager = new ProjectManager(this);
		}

		drawBezier();

		boolean loadedPointSet = false;
		if (loadFilePath != null) {
			File loadFile = new File(loadFilePath);
			if (loadFile.exists()) {
				System.out.println("CubicCurveFrame: auto-loading " + loadFilePath);
				if (loadFilePath.endsWith(".layers.xml")) {
					curvePanel.loadLayerSet(loadFile);
					layerPanel.refreshTable();
				} else {
					String rootName = peekRootElementName(loadFile);
					if ("openCurveSet".equals(rootName)) {
						curvePanel.loadOpenCurveSet(loadFile);
					} else if ("pointSet".equals(rootName)) {
						curvePanel.loadPointSet(loadFile);
						loadedPointSet = true;
					} else if ("ovalSet".equals(rootName)) {
						curvePanel.loadOvalSet(loadFile);
					} else {
						curvePanel.loadPolygonSet(loadFile);
					}
				}
			} else {
				System.out.println("CubicCurveFrame: load file not found: " + loadFilePath);
			}
		}

		if (nameValue != null) {
			curvePanel.setNameField(nameValue);
		}

		// Edit projects: set mode AFTER loading so polygon count is correct.
		// --point-select (morph editing)        → Point Selection Mode
		// --load of a pointSet                  → Point Placement Mode
		// --load without --point-select         → Polygon Selection Mode
		if (pointSelect) {
			toolBarPanel.activatePointSelectionMode();
		} else if (loadedPointSet) {
			toolBarPanel.activatePointMode();
		} else if (loadFilePath != null) {
			toolBarPanel.activatePolygonSelectionMode();
		}
	}
	public ProjectManager getProjectManager() { return projectManager; }

	/**
	 * Compute the initial canvas size so the full window fits on the current screen.
	 * The result is clamped between 200 px (minimum) and BezierDrawPanel.WIDTH (1040 px).
	 */
	private int computeInitialCanvasSize() {
		Rectangle maxBounds = GraphicsEnvironment.getLocalGraphicsEnvironment().getMaximumWindowBounds();
		int available = maxBounds.height - FIXED_OVERHEAD;
		return Math.max(200, Math.min(BezierDrawPanel.WIDTH, available));
	}

	/**
	 * Compute the canvas size that fits inside a frame of the given total height.
	 */
	private int computeCanvasFromHeight(int frameHeight) {
		int available = frameHeight - FIXED_OVERHEAD;
		return Math.max(200, Math.min(BezierDrawPanel.WIDTH, available));
	}

	public void drawBezier() {
		curvePanel.getBezier().start();
	}
	private void createLayout() {
		// Reference image panel must be created before CubicCurvePanel so it
		// can be placed alongside the SVG section inside the curve panel.
		// Width: total row width minus the SVG section (240 px) minus layer panel (280 px) minus gaps.
		referenceImagePanel = new ImportImagesPanel(this, DEFAULT_WIDTH - 8 - 240 - 10 - 280);

		curvePanel = new CubicCurvePanel(this, referenceImagePanel, initialCanvasSize);

		toolBarPanel = new BezierToolBarPanel(curvePanel.getBezier());
		toolBarPanel.setSize(new Dimension(DEFAULT_WIDTH - 60, 32));
		toolBarPanel.add(toolBarPanel.getToolBar(), BorderLayout.PAGE_START);
		this.getContentPane().add(toolBarPanel, BorderLayout.NORTH);

		layerPanel = new LayerPanel(curvePanel.getBezier().getLayerManager(), curvePanel.getBezier());
		this.getContentPane().add(layerPanel, BorderLayout.WEST);

		this.getContentPane().add(curvePanel, BorderLayout.CENTER);
		// referenceImagePanel is now embedded inside curvePanel — not added here
	}
	public CubicCurvePanel getCubicCurvePanel() {
		return curvePanel;
	}
	
	private JMenuBar createMenuBar() {
		JMenuBar menuBar = new JMenuBar();
		int cmd = Toolkit.getDefaultToolkit().getMenuShortcutKeyMaskEx();

		JMenu editMenu = new JMenu("Edit");

		JMenuItem undoItem = new JMenuItem("Undo");
		undoItem.setAccelerator(KeyStroke.getKeyStroke(KeyEvent.VK_Z, cmd));
		undoItem.addActionListener(e -> curvePanel.getBezier().undo());

		JMenuItem selectAllItem = new JMenuItem("Select All");
		selectAllItem.setAccelerator(KeyStroke.getKeyStroke(KeyEvent.VK_A, cmd));
		selectAllItem.addActionListener(e -> curvePanel.getBezier().selectAll());

		JMenuItem deselectAllItem = new JMenuItem("Deselect All");
		deselectAllItem.setAccelerator(KeyStroke.getKeyStroke(KeyEvent.VK_D, cmd));
		deselectAllItem.addActionListener(e -> curvePanel.getBezier().deselectAll());

		JMenuItem copyItem = new JMenuItem("Copy");
		copyItem.setAccelerator(KeyStroke.getKeyStroke(KeyEvent.VK_C, cmd));
		copyItem.addActionListener(e -> curvePanel.getBezier().copySelectedToClipboard());

		JMenuItem pasteItem = new JMenuItem("Paste");
		pasteItem.setAccelerator(KeyStroke.getKeyStroke(KeyEvent.VK_V, cmd));
		pasteItem.addActionListener(e -> curvePanel.getBezier().pasteFromClipboard());

		JMenuItem deleteItem = new JMenuItem("Cut");
		deleteItem.setAccelerator(KeyStroke.getKeyStroke(KeyEvent.VK_X, cmd));
		deleteItem.addActionListener(e -> {
			curvePanel.getBezier().copySelectedToClipboard();
			curvePanel.getBezier().performDelete();
		});

		editMenu.add(undoItem);
		editMenu.addSeparator();
		editMenu.add(selectAllItem);
		editMenu.add(deselectAllItem);
		editMenu.addSeparator();
		editMenu.add(copyItem);
		editMenu.add(pasteItem);
		editMenu.add(deleteItem);
		menuBar.add(editMenu);

		JMenu helpMenu = new JMenu("Help");
		JMenuItem helpItem = new JMenuItem("Bezier Help…");
		helpItem.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent e) {
				showHelp();
			}
		});
		helpMenu.add(helpItem);
		menuBar.add(helpMenu);

		return menuBar;
	}

	private void showHelp() {
		String[][] tabs = {
			{ "Overview & Interface", "/resources/help_overview.html",  "resources/help_overview.html"  },
			{ "Selection Modes",      "/resources/help_selection.html", "resources/help_selection.html" },
			{ "Operations",           "/resources/help_operations.html","resources/help_operations.html"},
			{ "View & Files",         "/resources/help_files.html",     "resources/help_files.html"     },
			{ "Quick Reference",      "/resources/help_reference.html", "resources/help_reference.html" }
		};

		JTabbedPane tabbedPane = new JTabbedPane();

		for (String[] tab : tabs) {
			String title       = tab[0];
			String jarPath     = tab[1];
			String fileFallback= tab[2];

			URL url = getClass().getResource(jarPath);
			if (url == null) {
				java.io.File f = new java.io.File(fileFallback);
				if (f.exists()) {
					try { url = f.toURI().toURL(); } catch (Exception ex) { /* ignore */ }
				}
			}

			JEditorPane pane = new JEditorPane();
			pane.setEditable(false);
			if (url != null) {
				try {
					pane.setPage(url);
				} catch (IOException ex) {
					pane.setContentType("text/plain");
					pane.setText("Could not load: " + ex.getMessage());
				}
			} else {
				pane.setContentType("text/plain");
				pane.setText("Help file not found: " + fileFallback);
			}

			JScrollPane scroll = new JScrollPane(pane);
			scroll.setPreferredSize(new Dimension(820, 620));
			// Scroll to top after page loads
			pane.setCaretPosition(0);
			tabbedPane.addTab(title, scroll);
		}

		JDialog dialog = new JDialog(this, "Bezier Help", false);
		dialog.getContentPane().add(tabbedPane);
		dialog.pack();
		dialog.setLocationRelativeTo(this);
		dialog.setVisible(true);
	}

	public void windowClosed(WindowEvent e) {
		System.out.println("window closed");
	}
	public void windowOpened(WindowEvent e) {
		System.out.println("window opened");
	}
	public void windowClosing(WindowEvent e) {
		System.out.println("window closing");
		curvePanel.getBezier().killDrawThread();
	}
	public void windowActivated(WindowEvent e) {
		
	}
	public void windowDeactivated(WindowEvent e) {
		
	}
	public void windowIconified(WindowEvent e) {
		
	}
	public void windowDeiconified(WindowEvent e) {
		
	}
	/**
	 * Peek at the root element name of an XML file without full validation.
	 * Uses a no-external-DTD reader so missing DTD files don't cause failures.
	 * Returns "" on any error.
	 */
	private String peekRootElementName(File f) {
		try {
			org.xml.sax.XMLReader xr = org.xml.sax.helpers.XMLReaderFactory.createXMLReader();
			try { xr.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false); } catch (Exception ignore) {}
			nu.xom.Builder parser = new nu.xom.Builder(xr);
			nu.xom.Document doc = parser.build(f);
			return doc.getRootElement().getLocalName();
		} catch (Exception ex) {
			return "";
		}
	}

	public ImportImagesPanel getImportImagesPanel() {
		return referenceImagePanel;
	}
	public CubicCurvePanel getCurvePanel() {
		return curvePanel;
	}
	public String getProjectsDirectoryName() {
		return projectsDirectoryName;
	}
	public String getProjectName() {
		return projectName;
	}
}