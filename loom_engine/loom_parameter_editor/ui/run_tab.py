"""
Run tab for launching and controlling the Loom Scala/Swift application.

Process controls (▶ ⏸ ⏹) live in a separate control_bar widget that
MainWindow places in the top-right corner of the QTabWidget, level with
the tab labels.  This tab retains Drawing Settings, Capture Controls,
path configuration, and the output console.
"""
import os
import re
from pathlib import Path
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QPushButton, QLabel,
    QPlainTextEdit, QCheckBox, QLineEdit, QFileDialog, QGroupBox, QSpinBox,
    QFrame
)
from PySide6.QtCore import Signal, QProcess, QProcessEnvironment, Qt
from PySide6.QtGui import QShortcut, QKeySequence


class RunTab(QWidget):
    """Tab for launching Loom, triggering reload, and capturing output."""

    save_requested = Signal()
    loom_app_path_changed = Signal(str)

    DEFAULT_LOOM_PATH = "/Users/broganbunt/Loom_2026/loom_engine"

    def __init__(self, save_callback=None, parent=None):
        super().__init__(parent)
        self._project_dir = None
        self._project_name = None
        self._save_callback = save_callback
        self._loom_path = self.DEFAULT_LOOM_PATH
        self._loom_app_path = "/Users/broganbunt/Loom_2026/loom_swift"
        self._engine = "scala"
        self._process = None
        self._last_render_type: str = ""

        # Build the detached control bar first so it can be placed in the
        # QTabWidget corner by MainWindow before this tab is fully shown.
        self._control_bar = self._build_control_bar()
        self._init_ui()

    # ── Control bar (placed in QTabWidget corner by MainWindow) ───────────────

    @property
    def control_bar(self) -> QWidget:
        return self._control_bar

    def _build_control_bar(self) -> QWidget:
        """Media-style process controls for the tab-bar corner."""
        bar = QWidget()
        bar.setObjectName("processControlBar")
        layout = QHBoxLayout(bar)
        layout.setContentsMargins(8, 2, 12, 2)
        layout.setSpacing(4)

        btn_style = (
            "QPushButton {"
            "  font-size: 13px; padding: 0px 7px;"
            "  min-width: 26px; min-height: 20px;"
            "  border: 1px solid #606060; border-radius: 4px;"
            "  background: #484848; color: #e8e8e8;"
            "}"
            "QPushButton:hover  { background: #585858; }"
            "QPushButton:pressed { background: #383838; }"
            "QPushButton:disabled { color: #707070; border-color: #505050; background: #3c3c3c; }"
            "QPushButton:checked  { background: #7a3030; color: #ffcccc; }"
        )

        self._play_btn = QPushButton("▶")
        self._play_btn.setToolTip("Run Loom  (or Reload if already running)")
        self._play_btn.setStyleSheet(btn_style)
        self._play_btn.clicked.connect(self._on_play)
        layout.addWidget(self._play_btn)

        self._pause_btn = QPushButton("⏸")
        self._pause_btn.setToolTip("Pause / Resume animation")
        self._pause_btn.setCheckable(True)
        self._pause_btn.setChecked(False)
        self._pause_btn.setEnabled(False)
        self._pause_btn.setStyleSheet(btn_style)
        self._pause_btn.clicked.connect(self._on_pause_toggled)
        layout.addWidget(self._pause_btn)

        self._stop_btn = QPushButton("⏹")
        self._stop_btn.setToolTip("Stop Loom")
        self._stop_btn.setEnabled(False)
        self._stop_btn.setStyleSheet(btn_style)
        self._stop_btn.clicked.connect(self._on_stop)
        layout.addWidget(self._stop_btn)

        sep = QFrame()
        sep.setFrameShape(QFrame.Shape.VLine)
        sep.setFrameShadow(QFrame.Shadow.Sunken)
        sep.setFixedWidth(8)
        layout.addWidget(sep)

        self._frame_label = QLabel("— / —")
        self._frame_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._frame_label.setStyleSheet(
            "font-family: monospace; font-size: 11px; color: #cccccc;"
            "background: #2e2e2e; padding: 2px 8px;"
            "border: 1px solid #555; border-radius: 3px; min-width: 72px;"
        )
        layout.addWidget(self._frame_label)

        sep2 = QFrame()
        sep2.setFrameShape(QFrame.Shape.VLine)
        sep2.setFrameShadow(QFrame.Shadow.Sunken)
        sep2.setFixedWidth(8)
        layout.addWidget(sep2)

        self._status_label = QLabel("Stopped")
        self._status_label.setStyleSheet(
            "font-size: 11px; font-weight: bold; color: #888888; min-width: 80px;"
        )
        layout.addWidget(self._status_label)

        return bar

    # ── Tab UI ─────────────────────────────────────────────────────────────────

    def _init_ui(self):
        layout = QVBoxLayout(self)

        # ── Drawing Settings ──────────────────────────────────────────────
        drawing_group = QGroupBox("Drawing Settings")
        drawing_layout = QFormLayout(drawing_group)

        row1 = QHBoxLayout()
        self._quality_spin = QSpinBox()
        self._quality_spin.setRange(1, 8)
        self._quality_spin.setValue(1)
        self._quality_spin.setToolTip(
            "Render at this multiple of canvas size (2 = 2× resolution)"
        )
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
        self._draw_bg_once_check.setToolTip(
            "When animating, draw the background only once (first frame) or every frame"
        )
        row2.addWidget(self._draw_bg_once_check)
        row2.addStretch()
        drawing_layout.addRow("", row2)

        layout.addWidget(drawing_group)

        # ── Capture Controls ──────────────────────────────────────────────
        capture_group = QGroupBox("Capture Controls")
        capture_layout = QVBoxLayout(capture_group)

        btn_row = QHBoxLayout()
        self._still_btn = QPushButton("Save Still  [F9]")
        self._still_btn.clicked.connect(self._on_capture_still)
        btn_row.addWidget(self._still_btn)

        self._renders_btn = QPushButton("Renders")
        self._renders_btn.setToolTip("Open the renders folder in Finder")
        self._renders_btn.clicked.connect(self._on_open_renders)
        btn_row.addWidget(self._renders_btn)

        self._video_btn = QPushButton("Save Animation  [F10]")
        self._video_btn.clicked.connect(self._on_capture_video)
        btn_row.addWidget(self._video_btn)

        QShortcut(QKeySequence("F9"),  self, activated=self._on_capture_still)
        QShortcut(QKeySequence("F10"), self, activated=self._on_capture_video)

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

        autosave_row = QHBoxLayout()
        self._auto_save_cb = QCheckBox("Auto-save before run/reload")
        self._auto_save_cb.setChecked(True)
        autosave_row.addWidget(self._auto_save_cb)
        autosave_row.addStretch()
        capture_layout.addLayout(autosave_row)

        layout.addWidget(capture_group)

        # ── Loom path setting (Scala engine) ──────────────────────────────
        self._scala_path_widget = QWidget()
        scala_path_row = QHBoxLayout(self._scala_path_widget)
        scala_path_row.setContentsMargins(0, 0, 0, 0)
        scala_path_row.addWidget(QLabel("Loom SBT path:"))
        self._loom_path_edit = QLineEdit(self._loom_path)
        self._loom_path_edit.editingFinished.connect(self._on_loom_path_changed)
        scala_path_row.addWidget(self._loom_path_edit)
        layout.addWidget(self._scala_path_widget)

        # ── LoomApp path setting (Swift engine) ───────────────────────────
        self._swift_path_widget = QWidget()
        swift_path_row = QHBoxLayout(self._swift_path_widget)
        swift_path_row.setContentsMargins(0, 0, 0, 0)
        swift_path_row.addWidget(QLabel("Loom Swift path:"))
        self._loom_app_path_edit = QLineEdit(self._loom_app_path)
        self._loom_app_path_edit.setPlaceholderText("Path to loom_swift source directory…")
        self._loom_app_path_edit.editingFinished.connect(self._on_loom_app_path_changed)
        swift_path_row.addWidget(self._loom_app_path_edit)
        browse_app_btn = QPushButton("Browse…")
        browse_app_btn.clicked.connect(self._on_browse_loom_app)
        swift_path_row.addWidget(browse_app_btn)
        self._swift_path_widget.setVisible(False)
        layout.addWidget(self._swift_path_widget)

        # ── Output console ────────────────────────────────────────────────
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

    # ── Engine public API ─────────────────────────────────────────────────────

    def set_engine(self, engine: str) -> None:
        self._engine = engine
        is_swift = engine == "swift"
        self._scala_path_widget.setVisible(not is_swift)
        self._swift_path_widget.setVisible(is_swift)
        tip = "Run LoomApp  (or Reload if already running)" if is_swift \
              else "Run Loom  (or Reload if already running)"
        self._play_btn.setToolTip(tip)

    def set_loom_app_path(self, path: str) -> None:
        self._loom_app_path = path
        self._loom_app_path_edit.setText(path)

    def get_loom_app_path(self) -> str:
        return self._loom_app_path

    # ── Public API ────────────────────────────────────────────────────────────

    def set_project_dir(self, path: str):
        old_dir = self._project_dir
        self._project_dir = path
        self._project_name = os.path.basename(path) if path else None
        if path:
            default_render = os.path.join(path, "renders")
            current_dest = self._render_dest_edit.text().strip()
            if not current_dest:
                self._render_dest_edit.setText(default_render)
            elif old_dir:
                old_default = os.path.join(old_dir, "renders")
                if os.path.normpath(current_dest) == os.path.normpath(old_default):
                    self._render_dest_edit.setText(default_render)

    def set_save_callback(self, callback):
        self._save_callback = callback

    # ── Drawing settings public API ───────────────────────────────────────────

    def set_drawing_settings(self, quality: int, scale_image: bool,
                             animating: bool, draw_bg_once: bool) -> None:
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

    # ── Control-bar state helpers ─────────────────────────────────────────────

    def _set_running_state(self, label: str, color: str):
        self._status_label.setText(label)
        self._status_label.setStyleSheet(
            f"font-size: 11px; font-weight: bold; color: {color}; min-width: 80px;"
        )

    def _is_process_running(self) -> bool:
        return bool(self._process and
                    self._process.state() != QProcess.ProcessState.NotRunning)

    # ── Process management ────────────────────────────────────────────────────

    def _do_save_if_needed(self) -> bool:
        if self._auto_save_cb.isChecked():
            if self._save_callback:
                return self._save_callback()
            else:
                self.save_requested.emit()
                return True
        return True

    def _on_play(self):
        """▶ — Run if engine is not running; Reload if it is."""
        if self._is_process_running():
            self._on_reload()
        else:
            self._on_run()

    def _on_run(self):
        if self._engine == "swift":
            self._on_run_swift()
        else:
            self._on_run_scala()

    def _on_run_swift(self):
        if self._is_process_running():
            self._append_output("[Editor] LoomApp is already running.\n")
            return
        if not self._project_dir:
            self._append_output("[Editor] No project loaded. Open or create a project first.\n")
            return
        swift_dir = self._loom_app_path.strip()
        if not swift_dir or not os.path.isdir(swift_dir):
            self._append_output("[Editor] Loom Swift path not set or invalid.\n")
            return
        if not self._do_save_if_needed():
            self._append_output("[Editor] Save failed. Aborting launch.\n")
            return

        self._process = QProcess(self)
        self._process.setWorkingDirectory(swift_dir)
        self._process.readyReadStandardOutput.connect(self._read_stdout)
        self._process.readyReadStandardError.connect(self._read_stderr)
        self._process.finished.connect(self._on_process_finished)
        self._process.errorOccurred.connect(self._on_process_error)
        env = QProcessEnvironment.systemEnvironment()
        self._process.setProcessEnvironment(env)

        shell_cmd = f'swift run LoomApp -- --project "{self._project_dir}"'
        self._append_output(f"[Editor] Launching: {shell_cmd}\n")
        self._append_output(f"[Editor] Working dir: {swift_dir}\n")
        self._append_output("[Editor] (First run compiles — this may take a minute)\n")
        self._process.start("/bin/zsh", ["-l", "-c", shell_cmd])
        self._set_running_state("Running", "#4488ff")
        self._stop_btn.setEnabled(True)
        self._pause_btn.setEnabled(True)
        self._clear_pause()

    def _on_run_scala(self):
        if self._is_process_running():
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
        env = QProcessEnvironment.systemEnvironment()
        self._process.setProcessEnvironment(env)

        shell_cmd = f'sbt "run --project {self._project_name}"'
        self._append_output(f"[Editor] Launching: {shell_cmd}\n")
        self._append_output(f"[Editor] Working dir: {self._loom_path}\n")
        self._process.start("/bin/zsh", ["-l", "-c", shell_cmd])
        self._set_running_state("Running", "#44cc44")
        self._stop_btn.setEnabled(True)
        self._pause_btn.setEnabled(True)
        self._frame_label.setText("— / —")
        self._clear_pause()

    def _on_stop(self):
        if self._is_process_running():
            self._append_output("[Editor] Stopping Loom...\n")
            self._process.terminate()
            if not self._process.waitForFinished(3000):
                self._process.kill()
                self._append_output("[Editor] Loom killed.\n")

    def _on_process_finished(self, exit_code, exit_status):
        self._append_output(f"[Editor] Loom exited (code {exit_code}).\n")
        self._set_running_state("Stopped", "#888888")
        self._stop_btn.setEnabled(False)
        self._pause_btn.setEnabled(False)
        self._pause_btn.setChecked(False)
        self._frame_label.setText("— / —")

    def _on_process_error(self, error):
        error_msgs = {
            QProcess.ProcessError.FailedToStart: "Failed to start",
            QProcess.ProcessError.Crashed:       "Crashed",
            QProcess.ProcessError.Timedout:      "Timed out",
            QProcess.ProcessError.WriteError:    "Write error",
            QProcess.ProcessError.ReadError:     "Read error",
        }
        self._append_output(
            f"[Editor] Process error: {error_msgs.get(error, f'Unknown ({error})')}\n"
        )

    def _read_stdout(self):
        if self._process:
            text = bytes(self._process.readAllStandardOutput()).decode("utf-8", errors="replace")
            self._append_output(text)

    def _read_stderr(self):
        if self._process:
            text = bytes(self._process.readAllStandardError()).decode("utf-8", errors="replace")
            self._append_output(text)

    def _append_output(self, text: str):
        self._console.moveCursor(self._console.textCursor().MoveOperation.End)
        self._console.insertPlainText(text)
        self._console.moveCursor(self._console.textCursor().MoveOperation.End)
        self._parse_frame_count(text)

    _FRAME_RE = re.compile(r'[Ff]rame[:\s]+(\d+)\s*/\s*(\d+)')
    _FRAME1_RE = re.compile(r'[Ff]rame[:\s]+(\d+)')

    def _parse_frame_count(self, text: str):
        """Update frame counter from engine stdout (best-effort)."""
        m = self._FRAME_RE.search(text)
        if m:
            self._frame_label.setText(f"{m.group(1)} / {m.group(2)}")
            return
        m = self._FRAME1_RE.search(text)
        if m:
            existing = self._frame_label.text()
            total = existing.split('/')[1].strip() if '/' in existing else '—'
            self._frame_label.setText(f"{m.group(1)} / {total}")

    # ── Sentinel file protocol ────────────────────────────────────────────────

    def _write_sentinel(self, filename: str, content: str = "") -> bool:
        if not self._project_dir:
            self._append_output("[Editor] No project directory set.\n")
            return False
        try:
            with open(os.path.join(self._project_dir, filename), "w") as f:
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
            self._set_running_state("Reloading…", "#ffaa44")
            from PySide6.QtCore import QTimer
            QTimer.singleShot(2000, self._restore_status_after_reload)

    def _restore_status_after_reload(self):
        if self._is_process_running():
            color = "#4488ff" if self._engine == "swift" else "#44cc44"
            self._set_running_state("Running", color)
        else:
            self._set_running_state("Stopped", "#888888")

    def _on_capture_still(self):
        if not self._project_dir:
            self._append_output("[Editor] No project loaded.\n")
            return
        self._last_render_type = "stills"
        self._write_render_path_if_needed()
        if self._write_sentinel(".capture_still"):
            self._append_output("[Editor] Capture still signal sent.\n")

    def _on_capture_video(self):
        if not self._project_dir:
            self._append_output("[Editor] No project loaded.\n")
            return
        self._last_render_type = "animations"
        self._write_render_path_if_needed()
        if self._write_sentinel(".capture_video"):
            self._append_output("[Editor] Capture video toggle signal sent.\n")

    def _on_open_renders(self):
        if not self._project_dir:
            self._append_output("[Editor] No project loaded.\n")
            return
        render_dest = self._render_dest_edit.text().strip()
        base = render_dest if render_dest else os.path.join(self._project_dir, "renders")
        path = os.path.join(base, self._last_render_type) if self._last_render_type else base
        if not os.path.isdir(path):
            os.makedirs(path, exist_ok=True)
        import subprocess
        subprocess.Popen(["open", path])

    def _clear_pause(self):
        self._pause_btn.setChecked(False)
        if self._project_dir:
            pause_file = os.path.join(self._project_dir, ".pause")
            if os.path.exists(pause_file):
                os.remove(pause_file)

    def _on_pause_toggled(self, checked):
        if not self._project_dir:
            self._append_output("[Editor] No project loaded.\n")
            return
        if checked:
            if self._write_sentinel(".pause"):
                self._append_output("[Editor] Animation paused.\n")
                self._set_running_state("Paused", "#ffaa44")
        else:
            pause_file = os.path.join(self._project_dir, ".pause")
            if os.path.exists(pause_file):
                os.remove(pause_file)
            self._append_output("[Editor] Animation resumed.\n")
            color = "#4488ff" if self._engine == "swift" else "#44cc44"
            self._set_running_state("Running", color)

    # ── Render destination ────────────────────────────────────────────────────

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
        render_dest = self._render_dest_edit.text().strip()
        if render_dest and self._project_dir:
            default_render = os.path.join(self._project_dir, "renders")
            if os.path.normpath(render_dest) != os.path.normpath(default_render):
                self._write_sentinel(".render_path", render_dest)
            else:
                render_path_file = os.path.join(self._project_dir, ".render_path")
                if os.path.exists(render_path_file):
                    os.remove(render_path_file)

    # ── Path settings ─────────────────────────────────────────────────────────

    def _on_loom_path_changed(self):
        self._loom_path = self._loom_path_edit.text().strip()

    def _on_loom_app_path_changed(self):
        self._loom_app_path = self._loom_app_path_edit.text().strip()
        self.loom_app_path_changed.emit(self._loom_app_path)

    def _on_browse_loom_app(self):
        start = self._loom_app_path or os.path.expanduser("~")
        path = QFileDialog.getExistingDirectory(
            self, "Select Loom Swift Source Directory", start)
        if path:
            self._loom_app_path = path
            self._loom_app_path_edit.setText(path)
            self.loom_app_path_changed.emit(path)
