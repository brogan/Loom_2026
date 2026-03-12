"""
Run tab for launching and controlling the Loom Scala application.
"""
import os
from pathlib import Path
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QPushButton, QLabel,
    QPlainTextEdit, QCheckBox, QLineEdit, QFileDialog, QGroupBox, QSpinBox
)
from PyQt6.QtCore import pyqtSignal, QProcess, QProcessEnvironment


class RunTab(QWidget):
    """Tab for launching Loom, triggering reload, and capturing output."""

    # Signal emitted when we need the main window to save before run/reload
    save_requested = pyqtSignal()

    # Default path to the Loom Scala project
    DEFAULT_LOOM_PATH = "/Users/broganbunt/Loom_2026/loom_engine"

    def __init__(self, save_callback=None, parent=None):
        super().__init__(parent)
        self._project_dir = None
        self._project_name = None
        self._save_callback = save_callback
        self._loom_path = self.DEFAULT_LOOM_PATH
        self._process = None

        self._init_ui()

    def _init_ui(self):
        layout = QVBoxLayout(self)

        # --- Drawing Settings (moved from Global tab) ---
        drawing_group = QGroupBox("Drawing Settings")
        drawing_layout = QFormLayout(drawing_group)

        row1 = QHBoxLayout()
        self._quality_spin = QSpinBox()
        self._quality_spin.setRange(1, 8)
        self._quality_spin.setValue(1)
        self._quality_spin.setToolTip("Render at this multiple of canvas size (2 = 2× resolution)")
        row1.addWidget(QLabel("Quality Multiple:"))
        row1.addWidget(self._quality_spin)

        self._scale_image_check = QCheckBox("Scale Image")
        self._scale_image_check.setToolTip(
            "Scale all pixel-based values (stroke width, point size,\n"
            "animation translation ranges, speed factors, keyframe positions)\n"
            "by the quality multiple for consistent output across resolutions"
        )
        row1.addWidget(self._scale_image_check)
        row1.addStretch()
        drawing_layout.addRow("", row1)

        row2 = QHBoxLayout()
        self._animating_check = QCheckBox("Animating")
        self._animating_check.setToolTip("Run the draw loop continuously (animation mode)")
        row2.addWidget(self._animating_check)

        self._draw_bg_once_check = QCheckBox("Draw Background Once")
        self._draw_bg_once_check.setChecked(True)
        self._draw_bg_once_check.setToolTip("When animating, draw the background only once (first frame) or every frame")
        row2.addWidget(self._draw_bg_once_check)
        row2.addStretch()
        drawing_layout.addRow("", row2)

        layout.addWidget(drawing_group)

        # --- Process controls ---
        process_group = QGroupBox("Process Controls")
        process_layout = QHBoxLayout(process_group)

        self._run_btn = QPushButton("Run Loom")
        self._run_btn.clicked.connect(self._on_run)
        process_layout.addWidget(self._run_btn)

        self._reload_btn = QPushButton("Reload")
        self._reload_btn.clicked.connect(self._on_reload)
        process_layout.addWidget(self._reload_btn)

        self._stop_btn = QPushButton("Stop Loom")
        self._stop_btn.setEnabled(False)
        self._stop_btn.clicked.connect(self._on_stop)
        process_layout.addWidget(self._stop_btn)

        self._auto_save_cb = QCheckBox("Auto-save before run/reload")
        self._auto_save_cb.setChecked(True)
        process_layout.addWidget(self._auto_save_cb)

        self._status_label = QLabel("Not running")
        self._status_label.setStyleSheet("font-weight: bold;")
        process_layout.addWidget(self._status_label)

        self._pause_btn = QPushButton("Pause")
        self._pause_btn.setCheckable(True)
        self._pause_btn.setChecked(False)
        self._pause_btn.setToolTip("Pause/resume animation in running Loom instance")
        self._pause_btn.clicked.connect(self._on_pause_toggled)
        self._pause_btn.setStyleSheet("QPushButton:checked { background-color: #d32f2f; color: white; }")
        process_layout.addWidget(self._pause_btn)

        process_layout.addStretch()
        layout.addWidget(process_group)

        # --- Capture controls ---
        capture_group = QGroupBox("Capture Controls")
        capture_layout = QVBoxLayout(capture_group)

        btn_row = QHBoxLayout()
        self._still_btn = QPushButton("Save Still")
        self._still_btn.clicked.connect(self._on_capture_still)
        btn_row.addWidget(self._still_btn)

        self._video_btn = QPushButton("Save Animation")
        self._video_btn.clicked.connect(self._on_capture_video)
        btn_row.addWidget(self._video_btn)

        btn_row.addStretch()
        capture_layout.addLayout(btn_row)

        dest_row = QHBoxLayout()
        dest_row.addWidget(QLabel("Render destination:"))
        self._render_dest_edit = QLineEdit()
        self._render_dest_edit.setPlaceholderText("<project_dir>/renders/")
        self._render_dest_edit.editingFinished.connect(self._on_render_dest_changed)
        dest_row.addWidget(self._render_dest_edit)

        browse_btn = QPushButton("Browse...")
        browse_btn.clicked.connect(self._browse_render_dest)
        dest_row.addWidget(browse_btn)
        capture_layout.addLayout(dest_row)

        layout.addWidget(capture_group)

        # --- Loom path setting ---
        path_row = QHBoxLayout()
        path_row.addWidget(QLabel("Loom SBT path:"))
        self._loom_path_edit = QLineEdit(self._loom_path)
        self._loom_path_edit.editingFinished.connect(self._on_loom_path_changed)
        path_row.addWidget(self._loom_path_edit)
        layout.addLayout(path_row)

        # --- Output console ---
        console_group = QGroupBox("Loom Output")
        console_layout = QVBoxLayout(console_group)

        self._console = QPlainTextEdit()
        self._console.setReadOnly(True)
        self._console.setMaximumBlockCount(5000)
        console_layout.addWidget(self._console)

        clear_btn = QPushButton("Clear")
        clear_btn.clicked.connect(self._console.clear)
        console_layout.addWidget(clear_btn)

        layout.addWidget(console_group, stretch=1)

    # --- Public API ---

    def set_project_dir(self, path: str):
        """Called by MainWindow when a project is loaded/created."""
        old_dir = self._project_dir
        self._project_dir = path
        self._project_name = os.path.basename(path) if path else None
        # Update render destination when project dir changes
        if path:
            default_render = os.path.join(path, "renders")
            current_dest = self._render_dest_edit.text().strip()
            if not current_dest:
                # Field is empty — set to new default
                self._render_dest_edit.setText(default_render)
            elif old_dir:
                # If the current destination was the old project's default renders dir,
                # update it to the new project's renders dir
                old_default = os.path.join(old_dir, "renders")
                if os.path.normpath(current_dest) == os.path.normpath(old_default):
                    self._render_dest_edit.setText(default_render)

    def set_save_callback(self, callback):
        """Set the callback to invoke for saving before run/reload."""
        self._save_callback = callback

    # --- Drawing settings public API ---

    def set_drawing_settings(self, quality: int, scale_image: bool, animating: bool, draw_bg_once: bool) -> None:
        """Set drawing settings (called by MainWindow on project load)."""
        self._quality_spin.setValue(quality)
        self._scale_image_check.setChecked(scale_image)
        self._animating_check.setChecked(animating)
        self._draw_bg_once_check.setChecked(draw_bg_once)

    def get_quality_multiple(self) -> int:
        return self._quality_spin.value()

    def get_scale_image(self) -> bool:
        return self._scale_image_check.isChecked()

    def get_animating(self) -> bool:
        return self._animating_check.isChecked()

    def get_draw_bg_once(self) -> bool:
        return self._draw_bg_once_check.isChecked()

    # --- Process management ---

    def _do_save_if_needed(self) -> bool:
        """Auto-save if checkbox is checked. Returns True if OK to proceed."""
        if self._auto_save_cb.isChecked():
            if self._save_callback:
                return self._save_callback()
            else:
                self.save_requested.emit()
                return True  # signal-based, assume success
        return True

    def _on_run(self):
        if self._process and self._process.state() != QProcess.ProcessState.NotRunning:
            self._append_output("[Editor] Loom is already running.\n")
            return

        if not self._project_name:
            self._append_output("[Editor] No project loaded. Open or create a project first.\n")
            return

        if not self._do_save_if_needed():
            self._append_output("[Editor] Save failed. Aborting launch.\n")
            return

        self._process = QProcess(self)
        self._process.setWorkingDirectory(self._loom_path)
        self._process.readyReadStandardOutput.connect(self._read_stdout)
        self._process.readyReadStandardError.connect(self._read_stderr)
        self._process.finished.connect(self._on_process_finished)
        self._process.errorOccurred.connect(self._on_process_error)

        # Inherit current environment
        env = QProcessEnvironment.systemEnvironment()
        self._process.setProcessEnvironment(env)

        # Launch via shell so PATH from user profile is available
        shell_cmd = f'sbt "run --project {self._project_name}"'
        cmd = "/bin/zsh"
        args = ["-l", "-c", shell_cmd]

        self._append_output(f"[Editor] Launching: {shell_cmd}\n")
        self._append_output(f"[Editor] Working dir: {self._loom_path}\n")

        self._process.start(cmd, args)
        self._status_label.setText("Running")
        self._status_label.setStyleSheet("font-weight: bold; color: green;")
        self._run_btn.setEnabled(False)
        self._stop_btn.setEnabled(True)
        self._clear_pause()

    def _on_stop(self):
        if self._process and self._process.state() != QProcess.ProcessState.NotRunning:
            self._append_output("[Editor] Stopping Loom...\n")
            self._process.terminate()
            if not self._process.waitForFinished(3000):
                self._process.kill()
                self._append_output("[Editor] Loom killed.\n")

    def _on_process_finished(self, exit_code, exit_status):
        self._append_output(f"[Editor] Loom exited (code {exit_code}).\n")
        self._status_label.setText("Not running")
        self._status_label.setStyleSheet("font-weight: bold; color: black;")
        self._run_btn.setEnabled(True)
        self._stop_btn.setEnabled(False)

    def _on_process_error(self, error):
        error_msgs = {
            QProcess.ProcessError.FailedToStart: "Failed to start",
            QProcess.ProcessError.Crashed: "Crashed",
            QProcess.ProcessError.Timedout: "Timed out",
            QProcess.ProcessError.WriteError: "Write error",
            QProcess.ProcessError.ReadError: "Read error",
        }
        msg = error_msgs.get(error, f"Unknown error ({error})")
        self._append_output(f"[Editor] Process error: {msg}\n")

    def _read_stdout(self):
        if self._process:
            data = self._process.readAllStandardOutput()
            text = bytes(data).decode("utf-8", errors="replace")
            self._append_output(text)

    def _read_stderr(self):
        if self._process:
            data = self._process.readAllStandardError()
            text = bytes(data).decode("utf-8", errors="replace")
            self._append_output(text)

    def _append_output(self, text: str):
        self._console.moveCursor(self._console.textCursor().MoveOperation.End)
        self._console.insertPlainText(text)
        self._console.moveCursor(self._console.textCursor().MoveOperation.End)

    # --- Sentinel file protocol ---

    def _write_sentinel(self, filename: str, content: str = ""):
        """Write a sentinel file to the project directory."""
        if not self._project_dir:
            self._append_output(f"[Editor] No project directory set.\n")
            return False
        sentinel_path = os.path.join(self._project_dir, filename)
        try:
            with open(sentinel_path, "w") as f:
                f.write(content)
            return True
        except Exception as e:
            self._append_output(f"[Editor] Failed to write {filename}: {e}\n")
            return False

    def _on_reload(self):
        if not self._project_dir:
            self._append_output("[Editor] No project loaded.\n")
            return

        if not self._do_save_if_needed():
            self._append_output("[Editor] Save failed. Aborting reload.\n")
            return

        self._clear_pause()
        if self._write_sentinel(".reload"):
            self._append_output("[Editor] Reload signal sent.\n")
            self._status_label.setText("Reloading...")
            self._status_label.setStyleSheet("font-weight: bold; color: orange;")
            # Status reverts when Loom deletes the file (we don't track that)
            # Just show it briefly
            from PyQt6.QtCore import QTimer
            QTimer.singleShot(2000, self._restore_status_after_reload)

    def _restore_status_after_reload(self):
        if self._process and self._process.state() != QProcess.ProcessState.NotRunning:
            self._status_label.setText("Running")
            self._status_label.setStyleSheet("font-weight: bold; color: green;")
        else:
            self._status_label.setText("Not running")
            self._status_label.setStyleSheet("font-weight: bold; color: black;")

    def _on_capture_still(self):
        if not self._project_dir:
            self._append_output("[Editor] No project loaded.\n")
            return
        # Write render path if custom
        self._write_render_path_if_needed()
        if self._write_sentinel(".capture_still"):
            self._append_output("[Editor] Capture still signal sent.\n")

    def _on_capture_video(self):
        if not self._project_dir:
            self._append_output("[Editor] No project loaded.\n")
            return
        # Write render path if custom
        self._write_render_path_if_needed()
        if self._write_sentinel(".capture_video"):
            self._append_output("[Editor] Capture video toggle signal sent.\n")

    def _clear_pause(self):
        """Reset pause state: uncheck button and remove .pause sentinel."""
        self._pause_btn.setChecked(False)
        if self._project_dir:
            pause_file = os.path.join(self._project_dir, ".pause")
            if os.path.exists(pause_file):
                os.remove(pause_file)

    def _on_pause_toggled(self, checked):
        """Toggle pause/resume in running Loom instance via .pause sentinel."""
        if not self._project_dir:
            self._append_output("[Editor] No project loaded.\n")
            return
        if checked:
            # Paused = write .pause sentinel
            if self._write_sentinel(".pause"):
                self._append_output("[Editor] Animation paused.\n")
        else:
            # Resumed = remove .pause sentinel
            pause_file = os.path.join(self._project_dir, ".pause")
            if os.path.exists(pause_file):
                os.remove(pause_file)
            self._append_output("[Editor] Animation resumed.\n")

    # --- Render destination ---

    def _browse_render_dest(self):
        current = self._render_dest_edit.text()
        if not current and self._project_dir:
            current = os.path.join(self._project_dir, "renders")
        dir_path = QFileDialog.getExistingDirectory(self, "Select Render Directory", current)
        if dir_path:
            self._render_dest_edit.setText(dir_path)
            self._on_render_dest_changed()

    def _on_render_dest_changed(self):
        self._write_render_path_if_needed()

    def _write_render_path_if_needed(self):
        """Write .render_path sentinel if user has set a custom render destination."""
        render_dest = self._render_dest_edit.text().strip()
        if render_dest and self._project_dir:
            default_render = os.path.join(self._project_dir, "renders")
            # Only write if it differs from the default
            if os.path.normpath(render_dest) != os.path.normpath(default_render):
                self._write_sentinel(".render_path", render_dest)
            else:
                # Remove custom path file if reverting to default
                render_path_file = os.path.join(self._project_dir, ".render_path")
                if os.path.exists(render_path_file):
                    os.remove(render_path_file)

    def _on_loom_path_changed(self):
        self._loom_path = self._loom_path_edit.text().strip()
