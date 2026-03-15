package org.brogan.scaffold;

import java.io.*;
import java.nio.file.*;
import java.text.SimpleDateFormat;
import java.util.Date;

/**
 * Captures unhandled exceptions and writes dated error reports to
 * logs/ in the Bezier working directory (beside the jar).
 *
 * Install once at startup via BezierErrorLogger.install().
 */
public class BezierErrorLogger {

    private static final String LOG_DIR = "logs";
    private static PrintStream logStream;

    public static void install() {
        try {
            Path dir = Paths.get(LOG_DIR);
            Files.createDirectories(dir);

            String timestamp = new SimpleDateFormat("yyyy-MM-dd_HH-mm-ss").format(new Date());
            File logFile = dir.resolve("bezier_" + timestamp + ".log").toFile();

            logStream = new PrintStream(new FileOutputStream(logFile, true), true);

            // Write session header
            logStream.println("=== Bezier session started: " + new Date() + " ===");
            logStream.flush();

            // Redirect System.err to the log file (catches printStackTrace output)
            System.setErr(new PrintStream(new TeeOutputStream(System.err, logStream), true));

            // Catch any thread that throws an uncaught exception
            Thread.setDefaultUncaughtExceptionHandler((thread, ex) -> {
                String ts = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date());
                PrintStream out = logStream != null ? logStream : System.err;
                out.println("\n=== UNCAUGHT EXCEPTION [" + ts + "] thread=" + thread.getName() + " ===");
                ex.printStackTrace(out);
                out.flush();
                // Also show a dialog so the user knows something went wrong
                javax.swing.SwingUtilities.invokeLater(() -> {
                    javax.swing.JOptionPane.showMessageDialog(null,
                        "An unexpected error occurred and has been saved to:\n" + logFile.getAbsolutePath(),
                        "Bezier Error",
                        javax.swing.JOptionPane.ERROR_MESSAGE);
                });
            });

        } catch (Exception e) {
            System.err.println("BezierErrorLogger: could not initialise log file: " + e.getMessage());
        }
    }

    /** Write a message to the log (and System.err which is now tee'd). */
    public static void log(String message) {
        String ts = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date());
        System.err.println("[" + ts + "] " + message);
    }

    /** Write an exception with context message to the log. */
    public static void log(String context, Throwable t) {
        String ts = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date());
        PrintStream out = logStream != null ? logStream : System.err;
        out.println("\n=== ERROR [" + ts + "] " + context + " ===");
        t.printStackTrace(out);
        out.flush();
    }

    // ── Helper: writes to two streams simultaneously ───────────────────────
    private static class TeeOutputStream extends OutputStream {
        private final OutputStream a, b;
        TeeOutputStream(OutputStream a, OutputStream b) { this.a = a; this.b = b; }
        @Override public void write(int c) throws IOException { a.write(c); b.write(c); }
        @Override public void write(byte[] buf, int off, int len) throws IOException {
            a.write(buf, off, len); b.write(buf, off, len);
        }
        @Override public void flush() throws IOException { a.flush(); b.flush(); }
    }
}
