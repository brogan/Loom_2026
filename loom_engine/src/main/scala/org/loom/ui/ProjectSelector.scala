package org.loom.ui

import javax.swing.*
import java.awt.*
import java.awt.event.*
import org.loom.config.{ProjectConfigManager, ProjectPaths}

/**
 * Swing-based project selector dialog.
 * Allows users to select a projects directory and load a project.
 */
class ProjectSelector extends JFrame("Loom - Project Selector") {

  private var onProjectLoaded: () => Unit = () => {}

  private val directoryField = JTextField(40)
  private val projectCombo = JComboBox[String]()
  private val statusLabel = JLabel("Select a project to load")
  private val loadButton = JButton("Load Project")
  private val newProjectButton = JButton("New Project")
  private val browseButton = JButton("Browse...")

  init()

  private def init(): Unit = {
    setDefaultCloseOperation(WindowConstants.EXIT_ON_CLOSE)
    setResizable(false)

    val mainPanel = JPanel(BorderLayout(10, 10))
    mainPanel.setBorder(BorderFactory.createEmptyBorder(15, 15, 15, 15))

    // Directory panel
    val dirPanel = JPanel(BorderLayout(5, 0))
    dirPanel.setBorder(BorderFactory.createTitledBorder("Projects Directory"))
    directoryField.setEditable(false)
    directoryField.setText(ProjectConfigManager.projectsDirectory)
    dirPanel.add(directoryField, BorderLayout.CENTER)
    dirPanel.add(browseButton, BorderLayout.EAST)

    // Project selection panel
    val projectPanel = JPanel(BorderLayout(5, 5))
    projectPanel.setBorder(BorderFactory.createTitledBorder("Project"))

    val comboPanel = JPanel(BorderLayout(5, 0))
    projectCombo.setPreferredSize(Dimension(300, 25))
    comboPanel.add(JLabel("Select: "), BorderLayout.WEST)
    comboPanel.add(projectCombo, BorderLayout.CENTER)
    comboPanel.add(newProjectButton, BorderLayout.EAST)

    projectPanel.add(comboPanel, BorderLayout.NORTH)

    // Button panel
    val buttonPanel = JPanel(FlowLayout(FlowLayout.RIGHT))
    loadButton.setEnabled(false)
    buttonPanel.add(loadButton)

    // Status panel
    val statusPanel = JPanel(BorderLayout())
    statusPanel.setBorder(BorderFactory.createEmptyBorder(10, 0, 0, 0))
    statusLabel.setForeground(Color.DARK_GRAY)
    statusPanel.add(statusLabel, BorderLayout.CENTER)

    // Layout
    val topPanel = JPanel()
    topPanel.setLayout(BoxLayout(topPanel, BoxLayout.Y_AXIS))
    topPanel.add(dirPanel)
    topPanel.add(Box.createVerticalStrut(10))
    topPanel.add(projectPanel)

    mainPanel.add(topPanel, BorderLayout.NORTH)
    mainPanel.add(statusPanel, BorderLayout.CENTER)
    mainPanel.add(buttonPanel, BorderLayout.SOUTH)

    setContentPane(mainPanel)

    // Event handlers
    browseButton.addActionListener((_: ActionEvent) => browseDirectory())
    newProjectButton.addActionListener((_: ActionEvent) => createNewProject())
    loadButton.addActionListener((_: ActionEvent) => loadSelectedProject())

    projectCombo.addActionListener((_: ActionEvent) =>
      loadButton.setEnabled(projectCombo.getSelectedItem != null)
    )

    // Double-click to load
    projectCombo.addMouseListener(new MouseAdapter {
      override def mouseClicked(e: MouseEvent): Unit = {
        if (e.getClickCount == 2 && projectCombo.getSelectedItem != null) {
          loadSelectedProject()
        }
      }
    })

    // Initial population
    refreshProjectList()

    pack()
    setLocationRelativeTo(null)
  }

  def setOnProjectLoaded(callback: () => Unit): Unit = {
    onProjectLoaded = callback
  }

  private def browseDirectory(): Unit = {
    val chooser = JFileChooser(ProjectConfigManager.projectsDirectory)
    chooser.setDialogTitle("Select Projects Directory")
    chooser.setFileSelectionMode(JFileChooser.DIRECTORIES_ONLY)
    chooser.setAcceptAllFileFilterUsed(false)

    if (chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION) {
      val selectedDir = chooser.getSelectedFile.getAbsolutePath
      ProjectConfigManager.projectsDirectory = selectedDir
      directoryField.setText(selectedDir)
      refreshProjectList()
      setStatus("Changed projects directory")
    }
  }

  private def createNewProject(): Unit = {
    val projectName = JOptionPane.showInputDialog(
      this,
      "Enter project name:",
      "New Project",
      JOptionPane.PLAIN_MESSAGE
    )

    if (projectName != null && projectName.trim.nonEmpty) {
      val cleanName = projectName.trim.replaceAll("[^a-zA-Z0-9_-]", "_")
      if (ProjectConfigManager.createProject(cleanName)) {
        refreshProjectList()
        projectCombo.setSelectedItem(cleanName)
        setStatus(s"Created project: $cleanName")
      } else {
        JOptionPane.showMessageDialog(
          this,
          s"Failed to create project '$cleanName'",
          "Error",
          JOptionPane.ERROR_MESSAGE
        )
      }
    }
  }

  private def loadSelectedProject(): Unit = {
    val selectedProject = projectCombo.getSelectedItem.asInstanceOf[String]
    if (selectedProject != null && selectedProject.nonEmpty) {
      setStatus(s"Loading project: $selectedProject...")
      loadButton.setEnabled(false)

      SwingUtilities.invokeLater(() => {
        if (ProjectConfigManager.loadProject(selectedProject)) {
          setStatus(s"Loaded: $selectedProject")
          dispose()
          onProjectLoaded()
        } else {
          setStatus(s"Failed to load: $selectedProject")
          loadButton.setEnabled(true)
          JOptionPane.showMessageDialog(
            this,
            s"Failed to load project '$selectedProject'",
            "Error",
            JOptionPane.ERROR_MESSAGE
          )
        }
      })
    }
  }

  private def refreshProjectList(): Unit = {
    projectCombo.removeAllItems()
    val projects = ProjectConfigManager.listProjects
    projects.foreach(projectCombo.addItem)

    val lastProject = ProjectPaths.lastProject
    if (lastProject.nonEmpty && projects.contains(lastProject)) {
      projectCombo.setSelectedItem(lastProject)
    }

    loadButton.setEnabled(projectCombo.getSelectedItem != null)

    if (projects.isEmpty) {
      setStatus("No projects found. Create a new project to get started.")
    } else {
      setStatus(s"${projects.size} project(s) found")
    }
  }

  private def setStatus(message: String): Unit = {
    statusLabel.setText(message)
  }
}


object ProjectSelector {

  def show(onLoaded: () => Unit): Unit = {
    SwingUtilities.invokeLater(() => {
      try {
        UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName)
      } catch {
        case _: Exception => // Ignore, use default L&F
      }

      val selector = ProjectSelector()
      selector.setOnProjectLoaded(onLoaded)
      selector.setVisible(true)
    })
  }

  def selectProject(): String = {
    var selectedProject = ""
    val latch = java.util.concurrent.CountDownLatch(1)

    SwingUtilities.invokeLater(() => {
      try {
        UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName)
      } catch {
        case _: Exception =>
      }

      val selector = ProjectSelector()
      selector.setDefaultCloseOperation(WindowConstants.DISPOSE_ON_CLOSE)
      selector.setOnProjectLoaded(() => {
        selectedProject = ProjectConfigManager.currentProject
        latch.countDown()
      })
      selector.addWindowListener(new WindowAdapter {
        override def windowClosed(e: WindowEvent): Unit = {
          latch.countDown()
        }
      })
      selector.setVisible(true)
    })

    latch.await()
    selectedProject
  }
}
